# 学期与日历 Forui 控件统一实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 学期与日历中的表单单选、文本输入、日期选择、按钮、弹窗和弹出菜单统一使用 Forui 组件，同时保留 TDesign 样式和业务行为。

**Architecture:** 共享适配组件位于 `lib/core/widgets/app_components.dart`，封装 Forui 0.27.5 API 与 TDesign 样式；业务页面通过共享适配器传递日期值、可选范围、校验和回调。学期与日历功能不直接使用 Material 表单、按钮、日期选择器、dialog route 或手写 tappable 控件。

**Tech Stack:** Flutter、Dart、Forui 0.27.5、flutter_test。

**Spec:** 用户在当前会话提出的 Forui 组件统一要求；页面行为依据 `docs/PRD.md` 和当前会话提供的设计稿。

## Global Constraints

- 延续现有 TDesign 字号、色值、边距、边界校验、日期格式和可访问语义。
- 继续使用 Riverpod、`SchoolRepository` 和 Drift，页面不直接访问数据库。
- 不引入新版本依赖；将已锁定的 `material_ui 1.6.0` 提升为直接依赖，用于 Forui 暴露的 Material `InputBorder` 类型。
- 修改 `lib/**/*.dart` 后按仓库 Flutter 热重载规则执行可用的 MCP 操作；若工具未连接，如实说明。
- 先写回归测试并确认失败，再实现最小改动；完成后运行 `flutter test` 和 `flutter analyze`。

---

### Task 1: 单选与日期共享适配器

**Files:**
- Modify: `lib/core/widgets/app_components.dart`
- Test: `test/term_widgets_test.dart`
- Test: `test/dialog_test.dart`

**Interfaces:**
- `AppRadioOption<T>`、`AppRadioIndicator<T>` 保留已有 API，内部改用 Forui `FRadio`。
- `AppDateField` 以 `DateTime? value`、`DateTime startDate/endDate`、`String hint`、`String Function(DateTime) format` 和 `ValueChanged<DateTime?> onChanged` 接入 Forui `FDateField.calendar`。
- `AppTextFormField` 保持为 Forui `FTextFormField` 的 TDesign 适配器；表单使用它而非 Material `TextFormField`。

- [x] **Step 1: 测试当前学期 radio/date 表单控件由 Forui 提供**

在 `test/term_widgets_test.dart` 渲染 `AppRadioOption<String>` 和 `AppDateField`，断言树内分别存在 `FRadio`、`FDateField`，点击 radio 后值变为 `clone`，点日期后 `onChanged` 收到选中日期；日期弹层内的 `FGridCalendarControl.start/end` 等于传入边界。

- [x] **Step 2: 运行测试确认旧自绘控件导致断言失败**

Run: `flutter test test/term_widgets_test.dart`
Expected: Forui `FRadio`、`FDateField` 和控制器边界断言失败。

- [x] **Step 3: 将 app radio 和 date button 适配器替换为 Forui 控件**

`AppRadioOption` 与 `AppRadioIndicator` 使用 `FRadio`，`AppDateField` 使用受 `FGridCalendarControl` 边界约束的 `FDateField.calendar`；移除旧 `AppDateFieldButton` 的 Material/InkWell 绘制代码。

- [x] **Step 4: 运行 adapter 测试确认 Forui 控件和日期边界正确**

Run: `flutter test test/term_widgets_test.dart`
Expected: PASS。

### Task 2: 学期与例外表单接入 Forui 适配器

**Files:**
- Modify: `lib/features/terms/dialogs/term_editor_dialog.dart`
- Modify: `lib/features/terms/dialogs/exception_editor_dialog.dart`
- Test: `test/dialog_test.dart`

**Interfaces:**
- 学期首周日期边界为当前日期前后十年；补课日期和停课区间日期继续限制在原有学期/教学周闭区间。
- 学期名称、周数、备注都使用 `AppTextFormField`；每周/单双周和复制模式都使用 `FRadio` 适配器。

- [x] **Step 1: 在 `test/dialog_test.dart` 断言学期和例外表单使用 `AppTextFormField`、`FRadio` 与 `FDateField`**
- [x] **Step 2: 运行 `flutter test test/dialog_test.dart` 确认直接 Material 字段未满足新断言**
- [x] **Step 3: 将学期、周数、日期及例外表单切换到共享 Forui 适配器，保留必填、1–52 周和日期边界校验**
- [x] **Step 4: 运行 `flutter test test/dialog_test.dart` 确认表单操作与日期映射回归通过**

### Task 3: 学期页面按钮、dialog route 和菜单触发统一

**Files:**
- Modify: `lib/core/widgets/app_components.dart`
- Modify: `lib/features/terms/term_page.dart`
- Modify: `lib/features/terms/dialogs/exception_editor_dialog.dart`
- Modify: `lib/features/terms/dialogs/term_editor_dialog.dart`
- Modify: `lib/features/terms/dialogs/term_management_dialog.dart`
- Modify: `lib/features/terms/widgets/term_summary_card.dart`
- Modify: `lib/features/terms/widgets/teaching_calendar_table.dart`
- Test: `test/term_page_test.dart`
- Test: `test/term_widgets_test.dart`
- Test: `test/dialog_test.dart`

**Interfaces:**
- `AppDialog` 内容由 Forui `FDialog` 呈现，`showAppDialog<T>` 使用 Forui `showFDialog<T>` 打开 route。
- 共享 `AppGhostButton`/`AppPrimaryButton`/`AppDestructiveButton`/`AppIconButton` 均使用 Forui `FButton`；`AppMenuButton` 使用 `FPopoverMenu` 和 `FTappable`。

- [x] **Step 1: 为弹窗 route、文本按钮和弹出菜单触发器补充 Forui widget assertions**
- [x] **Step 2: 运行页面、dialog 和 widget 测试确认残留 Material 控件未满足断言**
- [x] **Step 3: 将所有学期页面 `showDialog` 替换为 `showAppDialog`，将直接 Material buttons 与 InkWell 触发器替换为共享 Forui 控件**
- [x] **Step 4: 运行 `flutter test test/dialog_test.dart test/term_page_test.dart test/term_widgets_test.dart` 确认交互、删除禁用、弹窗关闭与窄窗口布局通过**

### Task 4: 完整验证

**Files:**
- Format: 所有本计划修改的 Dart 文件与测试文件

- [x] **Step 1: 格式化 Dart 文件**

Run: `dart format lib/core/widgets/app_components.dart lib/features/terms test`
Expected: 格式化命令成功。

- [x] **Step 2: 运行项目完整测试**

Run: `flutter test`
Expected: PASS。

- [x] **Step 3: 运行 Flutter 静态分析**

Run: `flutter analyze`
Expected: No issues found。

## Self-Review

- 单选、输入、日期、按钮、dialog 和 popover menu 均在 Tasks 1–3 覆盖。
- 日期边界、表单校验、禁用按钮、关闭/保存行为在 Tasks 1–3 保留和验证。
- 改动限制在共享 UI 适配器、学期与日历功能及其现有测试文件。
- Forui 默认日期头部在窄弹层中会横向溢出，因此使用 Forui `FButton`/`FTappable` 组合自定义紧凑头部；日期文字通过实际布局断言确认居中，空值日期的日历初始日和“今天”也限制在可选范围内。
