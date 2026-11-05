# 教师任课双视角实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将教师任课页的教师视角与班级视角改成两张 Ardot 草图中的工作区，并消除切换到大班级矩阵时的 UI 卡顿。

**Architecture:** 页面级工具栏持有视角、搜索和分组状态；教师视角继续复用教师/任课列表能力，班级视角使用按班级科目索引的数据投影并惰性构建矩阵行。批量添加使用一个教师和多条课程草稿，并通过仓库事务整体写入。

**Tech Stack:** Flutter、Riverpod、Forui、Drift、`flutter_test`。

**Spec:** 用户提供的教师视角与班级视角设计稿、`docs/PRD.md` US-009、`design/DESIGN.md`。

## Global Constraints

- 页面使用 Riverpod Provider 与 `SchoolRepository`，Widget 不直接读写 Drift。
- 可复用控件优先使用项目 Forui 包装组件，保持简体中文和主题 token。
- 桌面窗口宽度变化时，教师工具栏和班级右栏必须能换行或上下堆叠。
- 同班同科需求按周模式汇总时，班级级覆盖优先于年级默认；任课总节数仍由仓库校验。
- 批量添加任课应一次选择一名教师并支持多个跨学段课程行，提交失败时不得留下部分写入。

---

### Task 1: 预计算班级矩阵数据并验证卡顿路径

**Files:**
- Create: `lib/features/teachers/domain/teacher_assignment_matrix_data.dart`
- Modify: `lib/features/teachers/presentation/widgets/class_assignment_matrix.dart`
- Test: `test/features/teachers/teacher_assignment_matrix_data_test.dart`

**Interfaces:**
- `TeacherAssignmentMatrixData.build({classes, subjects, requirements, assignments})` 返回按 `(classId, subjectId)` 索引的单元格、需求和未分配课程。
- 矩阵 UI 通过索引读取单元格数据；不再对每个单元格扫描完整 `assignments` 或 `requirements`。

- [ ] **Step 1: Write the failing data projection tests**

覆盖：班级需求覆盖年级需求、按周模式计算剩余课时、识别未分配记录、构造 120 个班级乘 18 个科目的矩阵。

- [ ] **Step 2: Run the data test and confirm missing API failure**

Run: `flutter test test/features/teachers/teacher_assignment_matrix_data_test.dart`
Expected: FAIL because `TeacherAssignmentMatrixData` does not exist.

- [ ] **Step 3: Implement the indexed data projection**

先将 assignment 分组到 `(classId, subjectId)`，将 class override 和 grade default 分别分组；对每个班级科目只做 map lookup，并按周模式计算需求余量。

- [ ] **Step 4: Run the data test and verify projected cells**

Run: `flutter test test/features/teachers/teacher_assignment_matrix_data_test.dart`
Expected: PASS with the expected cells and remaining course counts.

- [ ] **Step 5: Render matrix rows lazily**

将 `class_assignment_matrix.dart` 的一次性 `for (subject in subjects)` 列表改成 `ListView.builder`；表头和行放在同一水平滚动区域中，右侧面板保持固定宽度。

- [ ] **Step 6: Verify matrix widget behavior**

Run: `flutter test test/features/teachers`.
Expected: teacher feature tests pass without layout exceptions.

### Task 2: 重做教师视角与页面工具栏

**Files:**
- Modify: `lib/features/teachers/presentation/teachers_page_state.dart`
- Modify: `lib/features/teachers/presentation/widgets/teacher_assignment_list.dart`
- Modify: `lib/features/teachers/presentation/widgets/teacher_group_widgets.dart`
- Test: `test/features/teachers/teacher_page_views_test.dart`

**Interfaces:**
- 顶部视角切换顺序为“班级视角、教师视角”；搜索位于教师视角工具栏。
- 教师行显示姓名、跨学段标记、总节数、任课 chips 和新增/合班/拆分/预排/编辑/删除入口。
- 教师列表末尾提供“添加新教师（或从 Excel 名单导入）”；分组管理保留在更多操作中。

- [ ] **Step 1: Write failing widget tests for the two view tabs and teacher toolbar**

验证 tab 顺序、教师视角搜索、导入 Excel、批量添加入口、底部新增教师入口。

- [ ] **Step 2: Run the widget test and confirm the missing layout elements**

Run: `flutter test test/features/teachers/teacher_page_views_test.dart`.
Expected: FAIL on the absent batch action and the current reversed tab order.

- [ ] **Step 3: Replace the generic page header with the design toolbar**

把标题、搜索、视角 tabs、导入、批量操作和更多菜单放入统一工作区顶栏；用项目的 `AppActionPill`、`AppTextFormField`、`AppOutlineButton`、`AppPrimaryButton`。

- [ ] **Step 4: Compact teacher rows to match the sketch**

减少卡片操作区的占宽，任课以紧凑 chips 展示；总节数与行操作置于右侧，底部新增教师用浅色全宽入口。

- [ ] **Step 5: Verify teacher view interactions and responsive toolbar**

Run: `flutter test test/features/teachers/teacher_page_views_test.dart`.
Expected: PASS at desktop and narrow test widths, with no overflow.

### Task 3: 重做班级视角矩阵及右侧拖拽区

**Files:**
- Modify: `lib/features/teachers/presentation/teachers_page_state.dart`
- Modify: `lib/features/teachers/presentation/widgets/class_assignment_matrix.dart`
- Modify: `lib/features/teachers/presentation/widgets/teacher_group_widgets.dart`
- Test: `test/features/teachers/teacher_page_views_test.dart`

**Interfaces:**
- 左侧矩阵为科目行、班级列；单元格显示教师或橙色未分配状态，点击打开现有分配编辑器。
- 右侧上方展示未分配课程，下方展示可拖入的教师摘要、姓名搜索与“查看全部 N 名教师”。
- 窄窗口下矩阵、未分配列表和教师面板纵向排列；拖拽任课返回未分配池仍可用。

- [ ] **Step 1: Add failing class-view widget tests**

验证帮助文案、科目×班级矩阵、未分配课程计数、教师摘要搜索及拖拽区入口。

- [ ] **Step 2: Run the widget test and confirm the current class layout mismatch**

Run: `flutter test test/features/teachers/teacher_page_views_test.dart`.
Expected: FAIL on the unimplemented design labels or panel behavior.

- [ ] **Step 3: Build the matrix from `TeacherAssignmentMatrixData`**

用预计算索引生成表头和可视行；使用轻量状态文本和周模式标记，不在 build 中重复遍历所有记录。

- [ ] **Step 4: Build responsive unassigned and teacher side panels**

未分配卡片显示门数及课程行；教师面板显示最多三名教师，搜索时展示匹配项，展开后展示全部；每名教师显示跨学段标签和课时合计。

- [ ] **Step 5: Verify class-view interactions and stress fixture**

Run: `flutter test test/features/teachers`.
Expected: PASS for class view, drag targets and the large matrix fixture without layout exceptions.

### Task 4: 实现真正的批量添加任课

**Files:**
- Modify: `lib/data/repositories/school_repository.dart`
- Modify: `lib/data/repositories/drift_school_repository.dart`
- Modify: `lib/features/teachers/presentation/teachers_page.dart`
- Modify: `lib/features/teachers/presentation/controllers/teacher_assignment_actions.dart`
- Create: `lib/features/teachers/presentation/dialogs/teacher_batch_assignment_dialog.dart`
- Modify: `test/features/teachers/teacher_repository_test.dart`
- Test: `test/features/teachers/teacher_page_views_test.dart`

**Interfaces:**
- Dialog以教师为主对象，提供一名教师与多行课程；每行可选班级、科目、周模式和承担节数。
- `SchoolRepository.addTeacherAssignments({required String termId, required List<TeacherAssignment> assignments})` 在单个数据库事务内校验教师/班级/科目、课时正数、记录归属和总需求，并整体插入。

- [ ] **Step 1: Write repository tests for atomic multi-course addition**

覆盖跨班级/跨学段一次插入、需求超限拒绝且无部分写入、无效教师拒绝。

- [ ] **Step 2: Run repository tests and confirm the new API is missing**

Run: `flutter test test/features/teachers/teacher_repository_test.dart`.
Expected: FAIL because the batch method is not implemented.

- [ ] **Step 3: Implement the repository contract and one-transaction validation**

按 `(classId, subjectId)` 分组读取需求和已有任课，检查覆盖后的周模式节数，再在事务内插入全部记录。

- [ ] **Step 4: Build the dynamic batch dialog**

默认一行课程，允许添加/删除课程行；下拉选项带学段/年级上下文，提交前确保教师、课程行和正数课时都有效。

- [ ] **Step 5: Connect toolbar batch action and verify**

工具栏按钮打开弹窗并一次调用仓库；测试成功批量保存与失败时无部分写入。

### Final verification

- [ ] Run `dart format` on changed Dart files.
- [ ] Run `flutter analyze lib/features/teachers test/features/teachers`.
- [ ] Run `flutter test test/features/teachers`.
- [ ] Run `git diff --check`.
