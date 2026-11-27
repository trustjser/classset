# 课集 (ClassSet) 工程开发规范

本文件定义了「课集 (ClassSet)」项目的架构分层、编码约定、测试流程、MCP 能力扩展、PWA 兼容与组件复用规范。项目采用 **Tauri v2 + React 18 + TypeScript + Tailwind CSS v3 + shadcn/ui + SQLite**，同时支持桌面端（Tauri）与浏览器端（Web / PWA）。

> UI 视觉与交互设计规范见 [`design/DESIGN.md`](design/DESIGN.md)；界面改动前请先核对设计 Token、圆角、字号与交互约定。

## 1. 技术栈与运行形态

- **桌面端**：Tauri v2 + WebView + 本地 SQLite（事务封装见 `src/adapter/db/tauriTransaction.ts`），支持本地 Streamable HTTP MCP 服务供外部 AI Agent 接入。
- **Web / PWA 端**：React SPA + `sql.js`（WebAssembly SQLite）+ 浏览器持久化 + Service Worker / Manifest，构建输出至 `websitedist/classsetapp/`（base `/classsetapp/`），支持 Chrome WebMCP。
- **前端核心**：React 18 + TypeScript（`strict: true`）+ Vite 6 + Zustand 5 + Tailwind CSS v3 + Radix UI / shadcn/ui + Lucide Icons + Recharts + SheetJS (`xlsx`)。
- **测试框架**：Vitest 5（jsdom 环境）+ Node test + Rust `cargo test`。

## 2. 目录结构与分层边界

- `src/domain/`：纯领域模型、排课算法、带班匹配、调代课演算、校验逻辑（保持零 React / DOM / DB 依赖）。
- `src/repository/`：`SchoolRepository` 统一数据仓储与持久化调度（事务、版本与修订校验）。
- `src/adapter/db/`：桌面端 Tauri SQLite 与 Web 端 `sql.js` 适配器实现。
- `src/store/`：Zustand 全局应用状态（`useAppStore`）与导航守卫。
- `src/agent/`：AI Agent 统一能力层，包含 `domain/agentToolSchemas.ts`、`domain/agentToolExecutor.ts`、提案队列、桌面 MCP 与 WebMCP 桥接。
- `src/components/ui/`：shadcn/ui 基础原语组件（`Button`、`Dialog`、`Switch`、`Select`、`DatePicker` 等）。
- `src/components/`：跨模块复用的业务外壳与共享组件（如 `AppShell`、`AppearanceDialog`、`PwaInstallAction`、`charts/`）。
- `src/features/`：按业务域划分的功能模块（`terms`、`classes`、`routines`、`subjects`、`teachers`、`scheduling`、`supervision`、`temporaryAdjustments`、`settings`、`setup`、`workbench`）。
- `src/hooks/` 与 `src/lib/`：通用 React Hooks（如 `useStickyToolbar`）与通用交互/工具函数（如 `pointerSelection`、`numberInput`）。
- `src/styles/`：Tailwind 与语义化主题 CSS 变量（亮/暗色、多色板）。
- `website/`：官网静态页与对外发布的 Skill（`website/skills/classset-scheduling/SKILL.md`）。
- `tests/unit/`：Vitest 单元测试，按 `domain`、`repository`、`agent`、`features`、`adapterAndStore` 组织。

### 依赖方向约定

1. **单向依赖**：`features / components` → `store / repository` → `domain`；`agent/domain` → `domain / repository`。
2. **`domain/` 保持纯净**：不在 `src/domain/` 中引入 React、DOM API、`window` 或 Tauri API，保证算法与校验逻辑可在纯 Node / Vitest 下独立测试。
3. **统一通过仓储访问数据**：UI 页面与组件通过 `useAppStore` 或 `schoolRepository` 读写数据，不在组件中直接拼接 SQL 或调用原生存储接口。
4. **不再引入已移除的 Flutter 代码**：原 Flutter 代码已清理，新功能均在 Tauri + TypeScript 架构下演进。

## 3. TDD 开发流程与测试规范

1. **红-绿-重构节奏**：新增领域算法、校验规则、Repository 方法、Agent Tool 或复杂页面交互时，优先在 `tests/unit/` 编写失败用例，再实现最小可行代码使测试通过，最后整理结构。
2. **先排查业务代码，不盲目改绿测试**：遇到单测失败时，先核对生产代码是否存在逻辑缺陷；只有在确认业务需求或交互机制已明确演进（例如从 `window.confirm` 升级为应用内导航守卫弹窗）时，才同步更新测试断言并说明原因。
3. **分层测试要求**：
   - `domain/`：覆盖输入输出边界、冲突判定、单双周计算、排课求解与校验。
   - `agent/`：每个 MCP Tool 覆盖 `dryRun` 预览、真实写入（含提案确认与自动写入）、级联门控校验与异常参数拦截。
   - `features/`：覆盖关键表单校验、指针/键盘框选、弹窗流程与导航守卫交互。
4. **如实报告运行情况**：若当前环境无法运行 `vitest` / `tsc` / `cargo test`，应在结果中说明未执行，不把未执行的检查描述为已通过。

## 4. MCP 与 AI Agent 能力同步规范

1. **统一 Schema 与执行器**：所有工具定义在 `src/agent/domain/agentToolSchemas.ts`，执行逻辑实现在 `src/agent/domain/agentToolExecutor.ts`。桌面端（Streamable HTTP MCP）与浏览器端（WebMCP）共用同一套实现。
2. **写入安全与预览机制**：
   - 写入类工具均需支持 `dryRun` 预览，并返回结构化 `notes` 摘要。
   - 写入执行通过 `schoolRepository.withAgentWrite` 与修订号校验保护；「自动写入（免人工确认）」仅在开启 MCP / WebMCP 时允许配置。
3. **新增或扩展功能同步清单**：
   - `src/agent/domain/agentToolSchemas.ts`（JSON Schema 与参数描述）
   - `src/agent/domain/agentToolExecutor.ts`（`prepare*` 预览、`apply` 落库与 `getNavSectionAvailability` 门控校验）
   - `src/agent/agentService.ts`（注册到 `prepareTools` 与错误映射）
   - `src/features/settings/AgentPendingOperations.tsx`（待确认预览描述）
   - `website/skills/classset-scheduling/SKILL.md` 与 `.workbuddy/skills/classset-scheduling/SKILL.md`
   - `tests/unit/domain/agentTools.test.ts` 与 `tests/unit/agent/agentService.test.ts`

## 5. PWA 与跨端（Tauri + Web）兼容规范

1. **运行时能力隔离**：通过 `isTauriDesktop()` 与 `databaseAdapter` 屏蔽桌面 SQLite 与 Web `sql.js` 差异。仅桌面端可用的能力（本地 HTTP MCP Server、原生文件对话框等）需在浏览器端平滑降级或隐藏。
2. **PWA 构建与子路径兼容**：
   - Web 应用通过 `npm run build:web` 输出至 `websitedist/classsetapp/`（`--base=/classsetapp/`）；官网与 Skill 资源通过 `tools/build-website.mjs` 复制到 `websitedist/`。
   - 静态资源引用需兼容 `/classsetapp/` 子路径（使用 Vite 模块导入或 `import.meta.env.BASE_URL`）。
   - `website/skills/` 下的 `SKILL.md` 保持固定规范路径，不经过 hash 重命名。
3. **跨平台打包注意**：Tauri Windows `.msi` 构建时，若 `productName` 包含中文，需在 `tauri.conf.json` 中配置 `bundle.windows.wix.language: "zh-CN"`（避免 WiX 默认 1252 码页报错 `LGHT0311`），或改用 NSIS 打包。

## 6. 组件划分、沉淀与复用规范

### 三层组件架构
1. **基础原语层（`src/components/ui/`）**：基于 shadcn/ui + Radix UI，将组件视为项目自有源码维护；只负责基础视觉、变体（`cva`）、ARIA 无障碍与受控/非受控接口，不引入 `useAppStore` 或具体业务术语。
2. **共享业务组件层（`src/components/`、`src/components/charts/`）**：沉淀跨 2 个及以上功能模块复用的业务组件（如 `AppShell`、`AppearanceDialog`、`SchoolNameDialog`、`PwaInstallAction`、`TeacherWorkloadChart`）。重型图表或低频弹窗使用 `React.lazy` + `Suspense` 按需加载。
3. **领域功能层（`src/features/<feature>/`）**：放置页面容器、领域表格/矩阵、专属弹窗及纯 TS 逻辑模块（推荐按 `FeaturePage.tsx` + `featureLogic.ts` + `FeatureDialog.tsx` 拆分，计算与校验逻辑优先抽离到 `*Logic.ts` 以便单测）。

### 组件沉淀与复用准则
- **多处出现即沉淀**：同一 UI 结构或交互逻辑在 2 个以上模块出现时（如矩阵框选/长按 `useSelectionPress`、吸顶工具栏 `useStickyToolbar`、数字草稿输入 `numericInputDraftReducer`），统一沉淀至 `src/lib/`、`src/hooks/` 或 `src/components/`，避免复制粘贴后行为分叉。
- **组合优于巨型 Props**：封装共享组件时优先采用子组件插槽与组合（如 `DialogHeader` / `DialogFooter`、`children`），避免单个组件堆积过多互斥布尔开关。
- **控制单文件复杂度**：单个页面组件过大或包含多个独立弹窗时，按职责拆分为子组件与纯逻辑文件。

## 7. Tauri + TypeScript + shadcn/ui 编码最佳实践

### TypeScript 规范
- 严格遵守 `tsconfig.json`（`strict: true`、`noUnusedLocals`、`noUnusedParameters`、`noFallthroughCasesInSwitch`）。
- 避免新增 `any`（优先用 `unknown` + 类型守卫）；对易被 `.map()` / `.filter()` 收窄的数组显式标注实体类型（如 `const teachers: Teacher[] = ...`）。
- 使用 `@/` 路径别名引用 `src/` 下模块。

### React 状态与交互规范
- **未保存草稿保护**：带有本地草稿态的页面（科目节数、作息设置、教师预排、带班安排等）统一接入 `useAppStore.getState().setNavigationGuard(...)` 并在卸载时清理。
- **指针、键盘与触屏兼容**：
  - 矩阵/网格类交互同时兼容鼠标框选与触屏长按拖拽（复用 `src/lib/pointerSelection.ts`）。
  - 选中态支持点击界面其他区域自动取消选中，但需排除按住 `Shift` / `Ctrl` / `Meta` 的追加选中，并避免误伤批量操作栏、快捷菜单及关联弹窗。
  - 浮动菜单使用 `createPortal(..., document.body)` 避免被容器 `overflow` 裁剪，支持 `Escape` 关闭与视口边界钳制。
- **异步竞态防护**：切换学期或页面时校验请求时效（如 `active` 标记或修订号），卸载时清理 Worker、定时器与全局事件监听。

### shadcn/ui 与样式规范
- **语义化 Token 优先**：使用 `bg-surface`、`bg-canvas`、`text-ink`、`text-ink-secondary`、`border-border`、`bg-selection`、`text-primary`、`text-destructive` 等语义化类名，不写死十六进制色值以保证亮/暗色与多色板正常切换。
- **无障碍与键盘可达性**：保留 `aria-label`、`aria-labelledby`、`role` 与 `focus-visible:ring-2`；纯图标按钮提供 `aria-label`，装饰图标标记 `aria-hidden="true"`。
- **界面文案**：面向用户的标题、提示、报错与按钮文案默认使用自然简洁的简体中文。

## 8. 常用命令

```bash
npx tsc --noEmit
npx vitest run
npm run build
npm run build:site
npm run tauri:dev
npm run tauri:build
```

## 9. UI 规范

界面视觉与交互细节以 [`design/DESIGN.md`](design/DESIGN.md) 为准。