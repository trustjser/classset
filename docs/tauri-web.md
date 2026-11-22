针对将当前 Flutter + Drift 本地应用 **课集（ClassSet）** 重构为 **Tauri v2（支持 Web 端 + 桌面端双端运行）** 并升级 UI 交互的需求，我结合当前仓库的代码结构（Schema v19、10 大功能模块、`SchoolRepository` 契约及 `design/` 下的原型资产），为您整理了一套完整的工程与交互重构方案。

### 一、 总体技术架构：一套前端 + 双端存储与算力同构

由于课集的核心特性是**纯本地离线优先（SQLite 唯一数据源）**与**高强度排课计算（原 Dart Isolate 求解器）**，为了同时支持 **Tauri 桌面端** 和 **纯浏览器 Web 端（或局域网 Web 部署）**，核心策略是**在 TypeScript 前端抽象统一的 `SchoolRepository` 与 `SchedulerEngine` 接口，并将 Rust 核心逻辑同时编译为 Tauri Native 命令与 WebAssembly (Wasm)**。

```svg
<svg viewBox="0 0 680 280" xmlns="http://www.w3.org/2000/svg">
  <style>
    :root {
      --lumi-ink: light-dark(#000000, #e0e0e0);
      --lumi-muted: light-dark(#5f6368, #9aa0a6);
      --lumi-dim: light-dark(#f2f0f0, #242528);
      --lumi-container: light-dark(#e8e6e6, #2d2f33);
      --lumi-outline: light-dark(#727676, #9a9b9c);
      --lumi-accent-bg: light-dark(#dcf1ff, #192967);
      --lumi-primary: light-dark(#3186ff, #9dd2ff);
      --lumi-sans: 'Google Sans Flex', var(--font-family, 'Google Sans', sans-serif);
      --lumi-mono: 'Google Sans Code', ui-monospace, monospace;
    }
    text { font-weight: 400; stroke: none; }
    .t-l1 { font-family: var(--lumi-sans); font-size: 15px; fill: var(--lumi-ink); }
    .t-l2 { font-family: var(--lumi-mono); font-size: 13px; font-style: italic; fill: var(--lumi-ink); }
    .t-l4 { font-family: var(--lumi-sans); font-size: 13px; fill: var(--lumi-muted); }
    .node-step { fill: var(--lumi-dim); stroke: none; }
    .node-focal { fill: var(--lumi-accent-bg); stroke: var(--lumi-primary); stroke-width: 1.25; }
    .node-store { fill: var(--lumi-container); stroke: var(--lumi-outline); stroke-width: 1; }
    .edge-seg { fill: none; stroke: var(--lumi-ink); stroke-width: 1.3; stroke-linecap: round; stroke-dasharray: 0 4; }
    .edge-arrow { fill: none; stroke: var(--lumi-ink); stroke-width: 1.3; stroke-linecap: round; stroke-dasharray: 0 4; marker-end: url(#lumi-caret); }
  </style>
  <defs>
    <marker id="lumi-caret" viewBox="0 0 10 10" refX="7.5" refY="5" markerUnits="userSpaceOnUse" markerWidth="10" markerHeight="10" orient="auto">
      <path d="M 3 1.2 L 7.5 5 L 3 8.8" fill="none" stroke="var(--lumi-ink)" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round" />
    </marker>
  </defs>

  <rect class="node-focal" x="20" y="100" width="184" height="80" rx="40" />
  <text class="t-l1" x="112" y="131" text-anchor="middle" dominant-baseline="central">React + Tailwind UI</text>
  <text class="t-l4" x="112" y="153" text-anchor="middle" dominant-baseline="central">10 大模块 · 晴空蓝主题</text>

  <line class="edge-arrow" x1="212" y1="140" x2="252" y2="140" />

  <rect class="node-step" x="260" y="100" width="176" height="80" rx="40" />
  <text class="t-l1" x="348" y="131" text-anchor="middle" dominant-baseline="central">平台适配层 Adapter</text>
  <text class="t-l2" x="348" y="153" text-anchor="middle" dominant-baseline="central">SchoolRepository</text>

  <path class="edge-arrow" d="M 444 124 L 460 124 Q 476 124 476 108 L 476 78 Q 476 62 492 62 L 504 62" />
  <path class="edge-arrow" d="M 444 156 L 460 156 Q 476 156 476 172 L 476 202 Q 476 218 492 218 L 504 218" />

  <rect class="node-store" x="512" y="22" width="152" height="80" rx="40" />
  <text class="t-l1" x="588" y="53" text-anchor="middle" dominant-baseline="central">Tauri 桌面端</text>
  <text class="t-l2" x="588" y="75" text-anchor="middle" dominant-baseline="central">Rust + SQLite</text>

  <rect class="node-store" x="512" y="178" width="152" height="80" rx="40" />
  <text class="t-l1" x="588" y="209" text-anchor="middle" dominant-baseline="central">Web 浏览器端</text>
  <text class="t-l2" x="588" y="231" text-anchor="middle" dominant-baseline="central">Wasm + OPFS / HTTP</text>
</svg>
```

| 架构分层 | 技术选型（推荐方案） | 对应原 Flutter 模块 | 双端运行机制（Desktop vs Web） |
| --- | --- | --- | --- |
| **前端视图与组件** | React 18 + TypeScript + Vite + Tailwind CSS v3 + Radix UI (shadcn/ui) | `lib/features/*`、`forui` + `material_ui` | 桌面端与 Web 端 **100% 共享同一套前端代码**，完美复用 `design/*.html` 中的 20+ 个 Tailwind 原型设计资产 |
| **状态与数据流** | TanStack Query + Zustand | `flutter_riverpod` (`StreamProvider` / `StateProvider`) | Zustand 管理当前学期 (`activeTermId`)、草稿拦截器 (`DraftNavigationGuard`) 与视图焦点；TanStack Query 负责表数据订阅与乐观更新 |
| **数据持久层** | Drizzle ORM + SQLite (Schema v19) | `drift` + `sqlite3_flutter_libs` (`school.sqlite`) | **桌面端**：通过 `@tauri-apps/plugin-sql` 或 Rust `rusqlite` 读写本机 `school.sqlite`；**Web 端**：支持 `wa-sqlite` (OPFS 浏览器本地持久化) 或连接局域网/云端 REST API |
| **排课求解引擎** | Rust 核心 Crate (`classset-core`) | `lib/domain/scheduling/course_scheduler.dart` + `Isolate` | 将排课算法与冲突校验用 Rust 编写为独立包：桌面端通过 Tauri Async Command 多线程运行并推送进度事件；Web 端通过 `wasm-pack` 编译在 Web Worker 中运行 |
| **文件与表格导出** | SheetJS / ExcelJS + 平台文件适配器 | `excel` + `file_selector` | 桌面端调用 `@tauri-apps/plugin-dialog` 与 `plugin-fs` 直接写入路径；Web 端自动降级为 `<input type="file">` 与浏览器 Blob 下载 |

---

### 二、 UI 与交互重构方案：从「分页表单」升级为「高密度桌面工作台」

保留 `design/DESIGN.md` 确立的「晴空蓝 / 海盐青 / 云白墨灰」明暗双主题体系**与严格的业务约束（如**步骤级联锁定、**课集调整记录页不设「当前学期」教学周上下翻牌**），同时利用 Web CSS Grid / Sticky / 键盘快捷键的优势，对核心交互进行 5 项体验升级：

#### 1. 导航框架与步骤级联体验升级

* **保留并强化级联门控（`步骤级联限制`）**：左侧栏延续「工作台 → 基础设置（学期/班级/作息/场室）→ 排课准备（科目节数/教师任课）→ 课表与课务（排课/带班/调代课）」的解锁链条。重构后，置灰项不仅支持悬浮 Tooltip 提示原因，点击置灰菜单时还能在当前前置步骤高亮闪烁「待完成的最后一项任务卡片」，消除迷失感。
* **全局命令面板（`Cmd/Ctrl + K`）**：新增桌面级快捷搜索框，支持一键跳转任意班级课表、检索教师姓名看任课、或快速触发「导出 Excel」「新建带班岗位」。
* **草稿防丢与顶部状态胶囊**：将原侧栏底部的「本地数据 · 最近保存时间」升级为顶部工具栏右侧的实时保存状态胶囊；当处于作息、科目、带班草稿编辑态时，顶部自动浮现醒目的「未保存草稿 · 预览差异 / 保存 (`Cmd+S`)」内联工具条，减少弹窗打断。

#### 2. 二维矩阵交互：框选涂抹（Drag-to-Paint）与快捷键

* **作息免任课矩阵 & 科目/教师预排网格**：原 Flutter 端依赖逐格单击或右键菜单。重构为 Web/Tauri 后，引入**鼠标按住拖拽涂抹（Paint Selection）**与**Shift 区间框选**：
* 顶部提供画笔工具条（如：`必排`、`优先`、`禁排`、`自习`、`教研`），选中画笔后在「星期 × 节次」网格上直接拖拽即可批量填充。
* 范围树（全校 / 学段 / 年级 / 班级）位于左侧固定面板，继承自上级范围的格子以斜纹微标展示「继承自年级/学段」，鼠标悬停即可一键「在此班级覆盖」。



#### 3. 排课与课表工作台：主副双视图联动（Split-View Workbench）

* **同屏对照调课**：在「排课与课表」页面支持开启**左右或上下分屏视图**——左侧为「班级课表」，右侧同步锁定显示当前选中课程对应的「任课教师课表」与「暂放课节池（Unplaced Pool）」。
* **智能落位高亮（Magnetic Drop Zones）**：当拖拽某节课程或点击某个课节准备移动时，整个课表网格实时计算硬条件与教师时间冲突：
* **绿色呼吸边框**：完全无冲突、且符合连堂/进度偏好；
* **琥珀色边框**：可互换（Swap）但会打破教师软偏好（悬停直接预览互换后的两张课表变化）；
* **红色斜纹禁区**：教师撞课、公共场室满额或免任课禁排，悬停直接浮现冲突归因（如：`张老师在 三(2)班 已有语文课`）。



#### 4. 带班安排（`带班安排`）与批量岗位弹窗重构

* **多视图无缝切换**：将您 `design/classset-duty-arrangement-redesign.html` 与 `create-post-redesign.html` 的高保真设计直接转化为 React 组件：
* 顶部视图切换器支持「按周网格」「按班级」「按教师」三视图切换，带有鲜明的年级色彩区分与草稿修订号保护。
* **创建带班岗位弹窗**：严格对齐 `h-9` 全局配置控件（活动类型、人员规则），左侧三级班级范围树 + 右侧节次选择矩阵 + 连堂/合班开关同屏联动，底部实时汇总将生成的岗位数量。



#### 5. 调代课与调整记录页面（`调代课`）

* **自然日日历联动 + 历史时间轴**：
* 在调代课工作区，点击课表单元格直接弹出轻量级浮动面板（Popover）选择「代课」「调课」「互换」或「带班替班」，自动过滤出该时段空闲的同科教师。
* 在**课集调整记录页面**，严格遵循已确认规范——**去除「当前学期」教学周上下翻牌控件**，改用清晰的状态筛选（生效中 / 已撤销）与检索栏，直接呈现每一次调代课与替班的前后对比快照及一键撤销入口。



---

### 三、 渐进式重构与迁移实施路径

为了确保现有的 **SQLite Schema v19 数据完全兼容**（老用户的 `school.sqlite` 可直接无缝打开），建议按以下 5 个阶段推进：

1. **搭建 Monorepo 与 Tauri v2 + Web 双端底座:** 阶段 1 · 基础设施与设计系统落地.
初始化 `pnpm` 工作区（或单仓双入口），配置 Vite + React + TypeScript + Tailwind CSS v3 与 Tauri v2 (`src-tauri`)。将 `design/DESIGN.md` 中的三套主题（晴空蓝、海盐青、云白墨灰）与 10 种稳定散列科目色封装为 CSS Variables 与 Tailwind 主题 Token。


2. **构建兼容 Schema v19 的双端 SQLite 仓储层:** 阶段 2 · 零数据丢失无缝迁移.
在 Rust / TypeScript 侧原样对齐 `docs/data-schema.md` 中的 28 张表与 v1～v19 迁移脚本。实现 `SchoolRepository` TS 接口：桌面端通过 Tauri SQL 插件直连本机 `class_set/school.sqlite`；Web 端通过 SQLite Wasm (OPFS) 或后端接口驱动，确保桌面端与 Web 端可互相导入导出 `.sqlite` 备份文件。


3. **还原应用外壳与基础设置模块:** 阶段 3 · 步骤级联与作息/科目/教师模块.
迁移应用主框架（侧边栏级联锁定、学期选择器、草稿离开守卫 `DraftNavigationGuard`）。直接利用 `design/` 目录下的 HTML 原型资产，快速落地「创建向导」「学期与日历」「班级与学段」「作息设置」「公共场室」「科目节数」「教师任课」模块，并加入拖拽涂抹矩阵交互。


4. **移植 Rust 排课求解器与双端 Worker:** 阶段 4 · 核心算法与排课工作台.
将 `lib/domain/scheduling/` 下的排课问题构建器（`ProblemBuilder`）、硬条件校验、软偏好评分与启发式求解器（`CourseScheduler`）迁移至 Rust 独立 Crate `classset-solver`。桌面端通过 Tauri Command 异步调用并流式推送 `ScheduleProgress`；Web 端编译为 Wasm 在 Web Worker 中调用，配合前端分屏调课工作台与冲突热力图完成闭环。


5. **落地带班安排、调代课与跨端打包 CI:** 阶段 5 · 课务闭环与自动化构建.
完成「带班安排」（含版本生效日快照与批量建岗弹窗）与「调代课」（含无教学周翻牌的调整记录页）模块，接入 Excel 导入导出能力。最后更新 `.github/workflows/build.yml`，一条流水线同时产出 macOS / Windows / Linux 桌面安装包（体积预计从 Flutter 的 ~45MB 降至 ~8MB）与静态 Web 部署包。


---

### 四、 推荐的新项目目录结构

您可以选择在当前仓库新建 `tauri-app/` 子目录并行开发（方便随时对照 `lib/domain/` 下的 Dart 领域逻辑），或切换新分支直接重构：

```text
paike_a/
├── packages/
│   └── solver-wasm/            # 编译自 Rust 的 Web 端排课求解器 Wasm 包
├── src/                        # React + TS 前端源码 (Web 与 Tauri 桌面端 100% 共用)
│   ├── adapter/                # 平台适配层 (Tauri Native vs Web Browser)
│   │   ├── db/                 # Tauri SQLite Adapter & Web wa-sqlite/API Adapter
│   │   ├── fs/                 # 桌面原生文件对话框 vs 浏览器下载适配器
│   │   └── solver/             # Tauri IPC Solver vs Web Worker Wasm Solver
│   ├── domain/                 # 领域模型与纯函数校验 (对齐原 lib/domain/models)
│   ├── repository/             # SchoolRepository 接口定义与 SQL 实现
│   ├── components/             # 公共 UI 组件 (MatrixPainter, ScopeTree, AppDialog)
│   ├── features/               # 10 大业务模块 (workbench, terms, classes, routines...)
│   └── styles/                 # 晴空蓝/海盐青/云白墨灰 CSS Tokens 与科目色散列
├── src-tauri/                  # Tauri v2 Rust 桌面端与核心库
│   ├── crates/
│   │   └── classset-solver/    # 纯 Rust 排课求解引擎 (同时供 Tauri 与 Wasm 编译)
│   ├── migrations/             # SQLite Schema v19 完整建表与迁移 SQL
│   └── src/                    # Tauri 窗口外观控制、原生菜单、SQLite 事务命令
└── design/                     # 现有的 20+ 个 HTML/Tailwind 设计规范与交互样张

```