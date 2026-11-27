# 课集 Agent 集成实施计划

## 目标与首发范围

教务人员能在 WorkBuddy 或支持 WebMCP 的浏览器 Agent 中，用自然语言查询课集数据、生成排课或课务变更预览，并在课集界面确认写入。两个入口共用 TypeScript 工具契约、业务校验和执行服务，各自读取当前端的本地数据库。桌面采用 Tauri 原生 SQLite，浏览器采用 SQL.js 和 IndexedDB。首发按 WorkBuddy 与课集同机、课集窗口可见、浏览器目标为 Chrome WebMCP 设计。正式课程课表继续通过智能排课页面的既有发布流程发布。浏览器内置 AI 是否实际调用工具，由目标客户端验收决定。

仓库现有 [工具声明](../../../src/domain/agentToolSchemas.ts)、[执行器](../../../src/domain/agentToolExecutor.ts) 和 [单测](../../../tests/unit/domain/agentTools.test.ts)。执行器已接入排课、带班和实际课表算法，但外部参数靠类型断言，部分工具省略 `dryRun` 就写库，自动排课的 `publish` 可以连带发布正式课表。WebMCP 注册函数没有挂到生产入口，Tauri 还缺 MCP 服务。制定计划时，现有 Agent 单测 5 项通过，`tsc --noEmit` 通过。实际客户端连接待验收。

## 1. 先用无业务数据的工具验证两个客户端

- [ ] 用本机 WorkBuddy 5.11.3 添加测试连接器，通过 `http://127.0.0.1:<port>/mcp` 和 `Authorization: Bearer <token>` 调用返回固定值的测试工具。记录是否支持本机 Streamable HTTP、自定义请求头、`initialize`、`tools/list` 和 `tools/call`。记录版本、配置字段和实际调用证据。腾讯文档支持自定义连接器，本机回环和请求头仍以实际桌面版本为准。[腾讯 WorkBuddy 连接器](https://intl.cloud.tencent.com/zh/document/product/1316/84494) · [MCP 传输规范](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [ ] 如果该 WorkBuddy 版本无法直连回环 HTTP，验证它能否启动本地 `stdio` MCP 进程。通过时随桌面安装包提供一个 Rust `classset-mcp` 程序，在 `stdio` 上服务 WorkBuddy 并代理到同一个本机 MCP 地址，连接令牌通过子进程环境传入。代理只转发 MCP 调用，部署时验证 macOS 和 Windows 安装路径及启动方式。两种接法都失败时，继续共享执行层和 Web 端，桌面标记为客户端不兼容，直到有真实成功调用。
- [ ] 用本机 Chrome 158 在 localhost 开启 WebMCP 测试，实际注册 `document.modelContext` 工具。分别验证 DevTools 看得到并可执行工具，以及目标浏览器 Agent 能从自然语言触发该工具。记录浏览器版本、Agent、账号条件、所需开关和调用证据。对正式 HTTPS 站点按当时 Chrome 支持状态配置 Origin Trial。只有 DevTools 调通时，发布说明标为「WebMCP 调试可用」，等待目标 Agent 验证后再宣称浏览器内置 AI 可操作。[Chrome WebMCP](https://developer.chrome.com/docs/ai/webmcp) · [Imperative API](https://developer.chrome.com/docs/ai/webmcp/imperative-api)

## 2. 收敛为两端共用的工具契约和执行入口

- [ ] 保留现有 10 个业务工具名。`agentToolSchemas.ts` 作为唯一工具目录，记录输入、说明和只读标记，去掉它对执行器的反向导出。运行时用 Ajv 校验真实传入的 `unknown`，拒绝未知字段、错误枚举、无效实际日期和缺失的分支参数。提前校验输入体积、数组上限、日期查询最长 31 天，以及学期、班级、教师、课节和岗位的归属。沿用现有步骤门控，并返回用户能理解的原因。两个适配器都从同一目录生成公开定义。
- [ ] 新建 `src/agent/agentService.ts`，统一提供 `listTools()`、`callTool(name, args, context)`、`confirmProposal(id)`、`rejectProposal(id)`。外部适配器只绑定发现与调用。`context` 由应用填写渠道、连接代次和取消信号。外部请求不能指定这些值。统一结果状态为 `ok`、`preview`、`awaiting_confirmation`、`committed`、`rejected`、`expired`、`error`。稳定错误码覆盖 `INVALID_ARGUMENT`、`TERM_NOT_FOUND`、`GATE_BLOCKED`、`RECONCILIATION_REQUIRED`、`CONFLICT`、`STALE_PREVIEW`、`STORAGE_UNAVAILABLE`、`BUSY`、`NOT_READY` 和 `UNKNOWN_OUTCOME`。错误包含简体中文消息和下一步提示，日志使用关联 ID，不返回 SQL、堆栈或本地路径。
- [ ] 增加只读 `classset_get_action_status`，接收随机 `actionId`，供同一接入渠道和授权代次短轮询最终状态。写入工具立即返回预览摘要和 `actionId`，无需保持 MCP 请求等待用户。状态有效期内接受查询，过期返回 `expired`。关闭集成或退出后清除待确认提案。已开始提交但响应丢失时，客户端先查询状态或重新读取业务数据。查不到时显示 `UNKNOWN_OUTCOME`，避免自动再提交。
- [ ] 查询默认使用当前学期，显式学期必须存在，写入限定于课集当前学期。`get_context_and_gates` 默认返回学期标识和门控摘要，按需返回字典。`query_actual_timetable` 返回受日期与对象筛选限制的结果、正式课表状态、业务 ID 及必要显示名称。大结果返回下一页游标。连接开启时说明教师姓名、课表等结果会交给所选客户端处理，诊断日志只存工具名、渠道、状态和耗时。

```ts
type AgentResult =
  | { status: 'ok' | 'preview'; data: JsonValue }
  | { status: 'awaiting_confirmation'; actionId: string; expiresAt: string; data: JsonValue }
  | { status: 'committed' | 'rejected' | 'expired'; actionId: string; data?: JsonValue }
  | { status: 'error'; code: AgentErrorCode; message: string; requestId: string; nextStep?: string };
```

`JsonValue` 限定为可序列化的 JSON 数据，`expiresAt` 使用 ISO 8601。业务日期使用 `YYYY-MM-DD`。查询分页使用稳定排序后的不透明游标，游标绑定查询条件及结果版本，数据变化时从第一页重新查询。Agent 可将查询得到的业务 ID 用作后续调用参数。工具说明提供一条查询、一条预览和一条查询确认状态的示例。

## 3. 打通预览、确认、事务和界面刷新

`Agent 调用 → 校验与计算 → 应用内预览 → 用户确认 → 校验数据版本并提交 → 刷新对应工作台 → Agent 查询结果`

| 工具组 | 预览和写入行为 |
| --- | --- |
| 查询学期与门控、实际课表 | 直接返回结构化结果。实际课表沿用正式课表、校历和已生效调代课的计算规则，并区分缺少正式课表与合法空结果。 |
| 配置排课规则 | 先生成教师预设、科目预设、硬条件及偏好的前后差异，确认后批量原子写入。已有草稿时沿用协调基线，界面显示旧课表并引导查看协调。 |
| 自动排课、移动或互换课节 | 仅操作草稿。沿用现有 Worker、预检、锁定与安放检查。展示移动、互换、暂放和未排项。存在待协调基线时返回 `RECONCILIATION_REQUIRED`，引导走既有协调预览与确认。公开 schema 移除 `publish`。 |
| 批量创建带班岗位、自动分配 | 预览新增岗位、改派、未分配项与冲突，沿用岗位校验和分配规则。确认后保存带班草稿、匹配偏好及教师限制中本次涉及的变更。 |
| 发布带班版本 | 复用既有发布日期预览，展示缺岗、替换的未来版本及课表变化。用户确认后执行现有发布校验并提交。 |
| 应用、取消调代课 | 复用实际课表预览和调代课记录，展示日期、课程、人员、冲突和被跳过的日期。取消时定位当前学期内的原记录并预览回退影响。 |

- [ ] 拆分执行器中混合读写的方法，每项操作产出结构化差异、规范化参数和数据版本。外部请求只会生成预览。统一为 8 个写入工具提供 `dryRun`。`true` 只试算，省略或设为 `false` 时创建待确认提案。UI 保存路径消费经校验的原预览，自动排课结果含生成时的课节、种子和报告。用测试断言所有写入工具的外部调用阶段零写库。
- [ ] 从 `App` 和 `AppShell` 接入初始化后的 Agent 设置与「待确认操作」界面。两端设置默认关闭，Desktop 开关仅在当前运行会话有效，Web 开关在当前标签页会话有效。提案单次使用，默认 10 分钟有效，绑定学期、渠道、授权代次和受影响数据版本。显示来源、学期、关键差异和冲突，双击确认只提交一次。切换学期、导入或清空数据、断开渠道时作废待确认操作。切换学期期间暂停创建新提案，工作台有未保存表单或正在运行求解时，使用现有编辑守卫避免覆盖。
- [ ] 在 `SchoolRepository` 提取事务内可复用的读写方法。确认阶段用同一事务重新检查学期及相关数据版本，命中变化时返回 `STALE_PREVIEW`，由用户重新查看新预览。排课输入版本包含规则、实际参与的课节和协调基线。带班和调代课版本包含草稿或正式快照、适用日期和现有调整。当前 `configureScheduleRules` 的多次保存合并至同一个事务，含必要的协调基线创建；应用现有的 `saveScheduleDraft`、`previewSupervisionPublish` 和临时调整事务逻辑时，复用事务客户端，避免嵌套开启事务。注入中途失败，证明整批回滚。
- [ ] Web 端浏览器适配器目前只串行化单标签页请求，普通数据库保存还可能吞掉 IndexedDB 持久化错误。为 Agent 写入增加严格持久化路径。保留 `school.sqlite.v19` 的现有二进制记录，在同一 IndexedDB 读写事务维护旁路版本键，升级后的所有快照写入、备份恢复和清空使用版本比较后写入。旧标签页如果改动原二进制但没更新版本键，也在写入前比较持久镜像并报告冲突。Agent 成功以 IndexedDB 事务完成为准，失败恢复原内存库；内存降级模式只允许读取。跨标签页更新后重新加载数据并作废陈旧提案。启用 Web 写入前要求关闭仍运行旧版应用的标签页，发布验收包含旧 Service Worker 更新后重开标签页。
- [ ] 提交成功后调用 `useAppStore.refreshTermData(termId)` 刷新门控和历史，再更新按学期作用的工作台数据版本，让排课、带班和临时调整重载各自维护的快照。提交与刷新分别报告。刷新失败时保留 `committed`，界面显示「已保存，刷新失败」并提供刷新操作。

## 4. 接入桌面 MCP 和浏览器 WebMCP

- [ ] Tauri 在 `src-tauri/src/agent_mcp.rs` 使用官方 Rust MCP SDK 实现 `/mcp`，按第 1 步记录的主机能力接入。只绑定 `127.0.0.1`，启动时分配可用端口，校验实际 Host，拒绝不允许的 Origin，所有请求校验随机令牌。应用启用时生成令牌，随连接关闭或重置撤销。配置由用户从课集设置复制，包含本机地址和授权头。服务限制请求体和在途数。Rust 通过限定主窗口的 Tauri Channel 下发带内部请求 ID 的工具调用，主窗口通过专用 command 完成响应。Rust 保存请求关联和通道代次，前端使用共享服务完成校验，仓储是唯一业务写入路径。[官方 Rust MCP SDK](https://rust.sdk.modelcontextprotocol.io/)
- [ ] MCP SDK 负责协议握手、发现、调用与结果包装。令牌未通过时返回 HTTP 鉴权错误。工具业务失败通过 `isError` 和结构化错误返回，普通预览、等待确认和已拒绝状态可以继续查询。初始化未完成、前端通道断开、连接关闭或主窗口隐藏返回 `NOT_READY`，并作废未确认提案。当前 Tauri 点击关闭只是隐藏窗口，按窗口可见性检查处理。设置页提供重连操作。清理重复或超时请求、迟到响应和进程退出留下的等待项。取消发生在提交开始前时作废相关未完成操作。提交一旦开始，按事务最终结果更新状态。
- [ ] Web 在 `src/agent/webMcpAdapter.ts` 注册，优先 `document.modelContext`，只有确认试点环境仍需旧声明时兼容 `navigator.modelContext`。以 `registerTool` 能力检测决定支持状态，顶层应用、仓储初始化完成且用户主动开启后注册。用 `AbortController` 配对卸载，覆盖 StrictMode 重挂载、切换学期、关闭集成和部分注册失败。回调读取当前应用状态，接收浏览器传入的取消信号。支持时调用 `waitForToolsUntil`，以浏览器支持的可序列化返回值提供工具结果。无 WebMCP 时照常使用课集，并在设置里显示浏览器能力状态。生产部署只从实际 `/classsetapp/` 页面注册工具。[Chrome WebMCP Imperative API](https://developer.chrome.com/docs/ai/webmcp/imperative-api)

## 5. 验收与发布顺序

- [ ] 每阶段先补对应的失败用例，再实现并重跑。契约测试查询与工具枚举、无效日期、非法分支参数、跨学期 ID、未知字段、门控和结果截断。事务测试覆盖取消、过期、重复点击、导入后失效、过期预览、失败回滚、并发和超时后查询。浏览器测试增加双标签页读写和 IndexedDB 写入失败。适配器测试对比同名工具的 schema 与业务错误结果，覆盖 WebMCP 注册清理和 MCP 鉴权、超时和断链。
- [ ] 使用同一份演示库，在已安装的桌面包和部署后的 HTTPS 网页分别验收，记录实际调用参数、预览差异、确认状态和可见课表。先跑查询当前学期与查询某班本周实际课表。再跑「草稿排课并移动一节课」「生成带班草稿并按生效日发布」「预览无冲突代课、确认、撤销」。每条抽查拒绝时数据不变，确认后当前界面立即反映变化，重启或刷新后结果仍可查到。额外验证规则确认后出现协调入口，旧课表持续可见且受保护，正式课程快照保持只读。
- [ ] 执行 `./node_modules/.bin/vitest run tests/unit/domain/agentTools.test.ts`、`npm run build`、`npm run build:web` 和 `npm test`。使用 MCP Inspector 验证协议链路，再分别用 WorkBuddy 对话和目标浏览器 Agent 对话验证自然语言触发。记录测试通过数、客户端版本、开关、预期行为和实际证据。按「双端只读联通 → 草稿预览和确认写入 → 带班发布与调代课」推进，上一阶段的客户端与实际数据流都通过后开放下一阶段。连接异常时可关闭对应渠道并继续使用日常课务功能。
