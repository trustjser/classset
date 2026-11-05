# 应用框架与学期日历重设计实施计划

> **For agentic workers:** 本计划由当前会话直接执行；不新增或运行测试，遵守当前会话的测试限制。

**Goal:** 按 `design/DESIGN.md` 重做课集 Flutter 主框架与「学期与日历」页面，支持桌面和窄窗口布局，并保留现有本地数据行为。

**Architecture:** 延续 `MaterialApp` + `FTheme`、Riverpod 和 `SchoolRepository`。全局色彩与圆角统一到设计 token；App shell 由侧栏与工作区顶栏组成；学期页使用响应式双卡片布局；教学日历采用新的月份网格组件，继续调用现有按教学周编辑例外对话框。

**Tech Stack:** Flutter / Dart、Forui 0.27.5、flutter_riverpod、现有 Drift 仓储。

**Spec:** `design/DESIGN.md`、`design/classset-ui-draft.html`、`docs/PRD.md`、`docs/data-schema.md`。

## Global Constraints

- 简体中文为默认界面语言；沿用现有主题、Forui 组件适配器、Riverpod 与 `SchoolRepository`。
- 教学周锚点第 1 周为单周，周数与单双周沿用 `AcademicTerm` 领域模型。
- 每周上课日按学段配置在作息设置中，不在学期与日历页配置。
- 停课/补课沿用 `CalendarException` 的日期、类型、备注和原课日期映射；不直接访问 Drift。
- 响应式布局根据可用宽度选择侧栏与卡片排列，不按设备类型判断。
- 当前会话明确禁止未被用户要求的测试操作；不新增或运行测试。

---

### Task 1: 统一主题并重组 App shell

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `lib/app.dart`

**Interfaces:**
- 保持 `AppSection`、`selectedSectionProvider`、`activeTermIdProvider` 和页面路由行为。
- Shell 继续接收 `databasePath`，并从 `termsProvider` / `activeTermIdProvider` 显示与切换当前学期。

- [x] 将画布、强调蓝、暖灰文字、轻边框、卡片圆角映射为 `AppTheme` 与 Forui tokens。
- [x] 将整体结构改为固定侧栏 + 工作区顶栏 + 可滚动页面内容；顶栏显示学校、学期切换、本地保存状态与帮助。
- [x] 使用 `LayoutBuilder` 按可用宽度在完整侧栏与图标导航栏间切换；保留窄窗口可访问性和提示。

### Task 2: 重做学期设置卡片和页面布局

**Files:**
- Modify: `lib/features/terms/term_page.dart`
- Modify: `lib/features/terms/widgets/term_summary_card.dart`

**Interfaces:**
- 保持 `TermSummaryCard` 的学期编辑/管理/新建回调，并增加可选的作息设置跳转回调。
- `TermPage` 继续由 `termsProvider`、`calendarExceptionsProvider` 驱动加载、空态和错误态。

- [x] 将页面标题、简短说明与“新建学期”主操作按新设计排列。
- [x] 将学期名称、首周日期、周数、单双周模式整理为清楚的设置卡片，并明确编辑入口。
- [x] 增加“上课日按学段在作息设置中维护”说明与导航入口，不在学期页设置周几上课。
- [x] 桌面宽度并排显示学期卡片与日历；空间不足时纵向排列。

### Task 3: 增加月份日历和例外新增入口

**Files:**
- Create: `lib/features/terms/widgets/teaching_calendar_month.dart`
- Modify: `lib/features/terms/term_page.dart`

**Interfaces:**
- 月历组件接收 `AcademicTerm`、`List<CalendarException>`、`ValueChanged<int> onEditWeek`、`VoidCallback onAddException`。
- `TermPage` 通过 `term.teachingWeekOf(date)` 将选中日期映射到现有教学周例外对话框。

- [x] 新建可前后切月的网格，日期格展示教学周/单双周及对应例外状态。
- [x] 点击有效教学日打开该周现有例外编辑器；点击“添加例外”先选学期内日期，再进入同一编辑器。
- [x] 无锚点或非学期教学日禁用例外编辑，并给出可理解的提示。
- [x] 保留现有 `TeachingCalendarTable` 实现供兼容使用，不改动领域模型或数据库 schema。

### Task 4: 格式化并做非测试验证

**Files:**
- Format: 本计划修改的 Dart 文件

- [x] 使用 `dart format` 格式化修改过的 Dart 文件。
- [x] 检查 Flutter/Dart MCP 连接状态；当前无热重载工具，未调用。
- [x] 运行 `flutter analyze` 检查静态错误；不运行测试。

## Self-Review

- 主框架、学期信息、学段作息职责边界、日历导航和例外入口均由 Tasks 1–3 覆盖。
- 学期日期区间字段不在现有领域模型与 PRD schema 中，因此本计划不加入新字段或迁移。
- 现有表格与例外对话框暂不删除；新的月历只投影已有日历数据并复用当前业务回调。
