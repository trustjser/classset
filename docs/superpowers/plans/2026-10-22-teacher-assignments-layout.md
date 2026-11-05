# 教师任课页面布局调整实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将教师任课页改为页面级标题栏与左右分栏内容布局，使视角切换和未分配课程位于左侧、班级矩阵或教师表格位于右侧。

**Architecture:** 复用 `AppPageHeader` 展示页面标题、说明和操作按钮；视角切换保留现有状态与 ForUI 控件，作为两种视角共用的左侧区域入口。班级矩阵和教师任课表继续保留各自组件，只调整容器顺序与响应式布局。

**Tech Stack:** Flutter、Dart、Riverpod、ForUI、`flutter_test`。

**Spec:** `design/DESIGN.md` 与用户提供的两张布局示意图。

## Global Constraints

- 页面标题约 24–28 px；模块标题约 15–17 px；正文约 13–14 px；辅助信息约 11–12 px。
- 间距基于 4 px：4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 px。
- 以留白、轻边框和清晰层级组织页面；一个主要区域只设一个蓝色主按钮。
- Flutter 页面需兼顾桌面窗口尺寸变化，避免固定尺寸导致溢出；复用现有主题和组件风格。
- 用户界面文本默认使用简体中文。
- 延续 Riverpod 与现有功能组件边界，不在 Widget 中直接操作数据库。

---

### Task 1: 为页面级标题栏和左右分栏布局添加回归测试

**Files:**
- Modify: `test/features/teachers/teacher_page_views_test.dart`

**Interfaces:**
- Consumes: 现有 `_mountTeacherPage` 测试装配函数及页面稳定键。
- Produces: 对页面标题、页面说明、头部操作和两种视角左右顺序的行为断言。

- [x] **Step 1: 写失败的页面布局测试**

在页面装配后检查“教师任课”标题、说明和头部功能按钮；切换班级视角时断言视角切换与未分配课程位于矩阵左侧；切换教师视角时断言视角切换与未分配课程位于教师表格左侧。

- [x] **Step 2: 运行测试确认旧布局失败**

运行：

```bash
flutter test test/features/teachers/teacher_page_views_test.dart --plain-name '教师任课页面标题栏和双视角内容布局'
```

预期：旧布局不满足页面级标题和左侧分栏位置断言。

---

### Task 2: 调整教师任课页面容器层级

**Files:**
- Modify: `lib/features/teachers/presentation/teachers_page_state.dart`
- Modify: `lib/features/teachers/presentation/widgets/class_assignment_matrix.dart`
- Modify: `lib/features/teachers/presentation/widgets/teacher_assignment_overview.dart`
- Test: `test/features/teachers/teacher_page_views_test.dart`

**Interfaces:**
- Consumes: `AppPageHeader`、现有视角状态、`_ClassMatrix`、`_TeacherAssignmentOverview` 和教师操作回调。
- Produces: 页面级头部动作；两种视角可接收相同的视角切换控件；桌面端左侧侧栏与右侧主内容并排，小窗口按列堆叠。

- [x] **Step 1: 将标题、说明和操作按钮放入 `AppPageHeader`**

把“教师任课”和当前视角说明作为标题与副标题；把教师搜索、批量任课、Excel 导入和更多菜单放到 `actions`，并启用响应式动作布局。

- [x] **Step 2: 将视角切换移入内容左侧栏**

复用现有 `teacher-view-tab-class` 与 `teacher-view-tab-teacher` 键和按钮行为；将控件作为参数传给矩阵和教师视角容器，保持 `_viewIndex` 与 `_showGroups` 行为。

- [x] **Step 3: 调整两种视角的左右顺序和窄窗布局**

桌面端班级视角使用左侧“视角切换、未分配课程、教师”栏，右侧显示班级矩阵；教师视角左侧显示“视角切换、未分配课程”，右侧显示教师表格。内容宽度不足时改为纵向排列，保证表格和侧栏可滚动、无溢出。

- [x] **Step 4: 运行教师页面测试和静态分析**

运行：

```bash
flutter test test/features/teachers/teacher_page_views_test.dart --plain-name '教师任课页面标题栏和双视角内容布局'
flutter analyze lib/features/teachers/teachers_page.dart test/features/teachers/teacher_page_views_test.dart
```

预期：新增布局测试通过，静态分析无问题。
