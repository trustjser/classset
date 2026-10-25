# 自动排课模块实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为当前学期实现可复现、可取消、按选定范围运行的自动排课，并将完整课表与未排原因一次性提交到本地数据库。

**Architecture:** 新增纯 Dart 排课领域层，将仓库读取的资料编译成不可变 `ScheduleProblem`，由确定性、有预算上限的求解器生成结果；Flutter/Riverpod 只负责范围选择、配置、进度与报告，求解在可取消的 isolate 中执行。Drift 仓库负责一致性快照读取和单事务提交，求解期间不写数据库。

**Tech Stack:** Flutter、Dart、Riverpod、Drift/SQLite、`flutter_test`、Dart isolates；首版不增加第三方求解器依赖。

**Spec:** `docs/PRD.md`（US-012～US-021、US-023、8.2、9.1 的 V7/V8/V17）；`design/DESIGN.md`；`docs/data-schema.md`。当前 `AppDatabase.schemaVersion` 是 13；`docs/data-schema.md` 仍写 v5，实施时以源码迁移链为准并同步修正文档。

## Global Constraints

- 遵循 `AGENTS.md`：Widget 通过 Riverpod 和 `SchoolRepository` 访问数据；领域求解器不得依赖 Flutter、Riverpod 或 Drift；新增 schema 后运行 `dart run build_runner build --delete-conflicting-outputs`，不得手改生成文件。
- 使用 PRD 当前口径：先保证已排课节零硬约束违规，再最大化两周周期已排实际课节数，再最大化四类软偏好满足率之和；不承诺全局最优。
- 每周课占用单周和双周的同一格；单周、双周课程可同格；配对课同格。跨学段教师及场室按节次起止分钟区间重叠判冲突，缺少所需时钟数据时阻止相关排课。
- 未选班级、跨范围合班和受锁保护的课节作为固定占用参与求解。求解取消、失败或提交失败时，数据库保持启动前已提交的课表。
- 固定种子模式使用固定候选顺序和候选检查预算，不以墙钟超时决定结果；快速、正常、高精度档只增加预算，不改变目标优先级。报告保存种子、强度、求解器版本、输入指纹和计分明细。
- UI 使用简体中文、`design/DESIGN.md` 的暖色留白与蓝色主操作规范，兼顾桌面窗口收窄；不得使用“最优课表”等承诺性文案。
- 典型规模目标按 PRD V17 验证：400 班 / 800 教师、可行数据集全部排入且硬违规为零，正常档 ≤ 5 分钟、快速档 ≤ 2 分钟。未完成基准前不得把预算值写成已达标。

## 文件结构

- 新建 `lib/domain/models/schedule_entry.dart`：已排课位置和锁定范围的领域值对象。
- 新建 `lib/domain/models/schedule_run.dart`：一次排课的选项、结果、未排课程阻断明细及评分摘要。
- 新建 `lib/domain/models/schedule_condition.dart`、`schedule_preferences.dart`：五类自定义硬条件和全局规则偏好。
- 新建 `lib/domain/scheduling/scheduling_snapshot.dart`、`schedule_problem.dart`、`schedule_problem_builder.dart`：输入快照、求解问题及排课前检查。
- 新建 `lib/domain/scheduling/schedule_constraints.dart`、`schedule_scoring.dart`、`course_scheduler.dart`：硬约束编译/检查、评分和有界搜索算法。
- 修改 `lib/data/database/app_database.dart`、`lib/data/repositories/school_repository.dart`、`drift_school_repository.dart`、`school_repository_provider.dart`：schema 迁移、输入快照、配置和排课结果持久化。
- 新建 `lib/features/scheduling/scheduling_page.dart`、`scheduling_controller.dart`、`scheduling_worker.dart` 及 `widgets/`：页面、异步状态与 isolate 消息封装。
- 修改 `lib/app.dart`：增加“自动排课”导航项和当前学期页面分发。
- 修改 `docs/data-schema.md`；新增测试到 `test/domain/scheduling/`、`test/features/scheduling/`，并更新 `test/database_migration_test.dart`；新增固定性能数据生成器到 `tool/`。

---

### Task 1: 定义排课与规则数据模型并扩展数据库

**Files:**
- Create: `lib/domain/models/schedule_entry.dart`
- Create: `lib/domain/models/schedule_run.dart`
- Create: `lib/domain/models/schedule_condition.dart`
- Create: `lib/domain/models/schedule_preferences.dart`
- Modify: `lib/data/database/app_database.dart`
- Modify: `docs/data-schema.md`
- Test: `test/database_migration_test.dart`
- Test: `test/domain/scheduling/schedule_models_test.dart`

**Interfaces:**
- `ScheduleEntry` 表示一个班级、一个任课教师、一个科目在某星期/时段/节次的课；`weekMode` 用现有 `WeekMode`，每周课表示同一位置同时覆盖 odd 和 even。
- `ScheduleLock` 表示 `class` 或 `teacher` 范围锁。
- `ScheduleCondition` 使用有判别字段的不可变类型表示 `periodCount`、`dailyCount`、`teachersMutuallyExclusive`、`subjectsDifferentDays`、`forbiddenAdjacentSubjects`；`SchedulePreferences` 表示教师日分布、进度一致、午休保护和连堂策略。
- `ScheduleRun` 保存种子、强度、求解器版本、输入指纹、两周覆盖量、四类偏好分数、已排项和未排项诊断。

- [ ] **Step 1: 先写模型与迁移失败测试**

测试模型拒绝不完整的条件参数，并验证从 schema v13 升级到 v14 后原有学期、班级、科目、教师任课数据仍在；新数据库能创建 `schedule_entries`、`schedule_locks`、`schedule_conditions`、`schedule_preferences` 与 `schedule_run_reports`。

```dart
test('v13 database upgrades without losing teacher assignments', () async {
  final db = await openVersion13Fixture();
  await db.migrateToLatest();
  expect(await db.select(db.teacherAssignments).get(), hasLength(1));
  expect(await db.select(db.scheduleEntries).get(), isEmpty);
});
```

- [ ] **Step 2: 运行迁移和模型测试，确认新增类型/表缺失**

Run: `flutter test test/database_migration_test.dart test/domain/scheduling/schedule_models_test.dart`
Expected: FAIL because the scheduling models/tables and v13→v14 migration do not exist.

- [ ] **Step 3: 实现类型安全模型与 v14 schema**

`ScheduleCondition` 的每个分支只允许其需要的字段；数据库用 `kind`、目标 ID、另一目标 ID、时段 ID、星期、最小/最大值等列保存条件，不把关键规则塞进未经校验的 JSON。`schedule_run_reports` 保存可重建报告的版本化 JSON。新增迁移只增表，不清空旧数据。

```dart
enum ScheduleConditionKind {
  periodCount,
  dailyCount,
  teachersMutuallyExclusive,
  subjectsDifferentDays,
  forbiddenAdjacentSubjects,
}
```

- [ ] **Step 4: 生成 Drift 文件并运行迁移和模型测试**

Run: `dart run build_runner build --delete-conflicting-outputs`
Run: `flutter test test/database_migration_test.dart test/domain/scheduling/schedule_models_test.dart`
Expected: generation completes; the v13 fixture retains all old rows, creates empty scheduling tables, and every invalid condition is rejected.

- [ ] **Step 5: 提交独立模型与迁移改动**

```bash
git add lib/domain/models/schedule_entry.dart lib/domain/models/schedule_run.dart lib/domain/models/schedule_condition.dart lib/domain/models/schedule_preferences.dart lib/data/database/app_database.dart lib/data/database/app_database.g.dart docs/data-schema.md test/database_migration_test.dart test/domain/scheduling/schedule_models_test.dart
git commit -m "feat: add scheduling data model"
```

### Task 2: 增加一致性输入快照和原子保存接口

**Files:**
- Modify: `lib/data/repositories/school_repository.dart`
- Modify: `lib/data/repositories/drift_school_repository.dart`
- Modify: `lib/data/providers/school_repository_provider.dart`
- Test: `test/schedule_repository_test.dart`

**Interfaces:**
- `Future<SchedulingSnapshot> loadSchedulingSnapshot(String termId)` 在一次只读事务中加载学段/班级/作息、节数需求、教师任课与合班、免任课、科目/教师预设、科目限制、场室配置、锁和现有课表。
- `Stream<ScheduleViewData> watchSchedule(String termId)` 供报告页显示最近课表与最近运行报告。
- `Future<void> saveScheduleConfiguration({required String termId, required List<ScheduleCondition> conditions, required SchedulePreferences preferences})` 原子保存五类条件和全局规则。
- `Future<void> commitScheduleRun({required ScheduleRun run, required Set<String> selectedClassIds})` 在一个数据库事务中替换所选班级课表并保存报告。
- `Future<void> setScheduleLock({required String termId, required ScheduleLock lock, required bool locked})` 管理班级/教师锁。

- [ ] **Step 1: 写仓库事务测试**

覆盖：加载快照包含单双周与跨学段时钟数据；只替换已选班级；未选班级课表不变；报告与课表同事务提交；提交中途抛错后旧课表和旧报告不变；锁和规则可关闭数据库后重开读取。

```dart
test('failed schedule commit leaves the previously committed timetable intact', () async {
  final before = await repository.watchSchedule(termId).first;
  repository.failNextScheduleInsertForTest = true;
  await expectLater(repository.commitScheduleRun(run, selectedClassIds), throwsA(anything));
  expect(await repository.watchSchedule(termId).first, before);
});
```

- [ ] **Step 2: 运行仓库测试确认接口和事务行为未实现**

Run: `flutter test test/schedule_repository_test.dart`
Expected: FAIL on missing repository methods and scheduling tables.

- [ ] **Step 3: 实现快照读取、配置读写与事务提交**

读取快照时不得在求解期间继续持有数据库事务。提交时在同一事务中删除所选班级的旧课表行、写入本次这些班级的完整结果、写入未排诊断与复现元数据；任何一步失败都回滚。未选班级不执行删除。

```dart
abstract interface class SchoolRepository {
  Future<SchedulingSnapshot> loadSchedulingSnapshot(String termId);
  Stream<ScheduleViewData> watchSchedule(String termId);
  Future<void> commitScheduleRun({
    required ScheduleRun run,
    required Set<String> selectedClassIds,
  });
}
```

- [ ] **Step 4: 运行仓库与迁移测试**

Run: `flutter test test/schedule_repository_test.dart test/database_migration_test.dart`
Expected: all scheduling repository transactions pass, including rollback and preservation of unselected data.

- [ ] **Step 5: 提交仓库边界与事务**

```bash
git add lib/data/repositories/school_repository.dart lib/data/repositories/drift_school_repository.dart lib/data/providers/school_repository_provider.dart test/schedule_repository_test.dart
git commit -m "feat: persist scheduling snapshots and runs"
```

### Task 3: 将已有资料编译为排课问题并阻止未就绪输入

**Files:**
- Create: `lib/domain/scheduling/scheduling_snapshot.dart`
- Create: `lib/domain/scheduling/schedule_problem.dart`
- Create: `lib/domain/scheduling/schedule_problem_builder.dart`
- Test: `test/domain/scheduling/schedule_problem_builder_test.dart`

**Interfaces:**
- `ScheduleProblemBuilder.build({required SchedulingSnapshot snapshot, required Set<String> selectedClassIds, required ScheduleStrength strength, required int seed})` 返回 `ScheduleBuildResult`，结果是 `ScheduleProblem` 或含字段路径、对象 ID、中文说明的 `SchedulePreflightIssue` 列表。
- `ScheduleOccurrence` 是一个需要排入的教师任课课节；一条每周需求在问题中覆盖 odd+even，两条单周/双周需求只覆盖各自周。班级覆盖需求优先于年级默认，任课分配数之和必须匹配有效需求数。
- `ScheduleProblem` 包含待排课节、当前固定课节、每个班级的有效作息格、规则、预设、合班、场室容量、周模式、种子、强度与候选检查预算。

- [ ] **Step 1: 写输入投影和前置检查测试**

用内存构造小型快照，覆盖班级覆盖年级默认、教师拆分节数、无教师任课、任课节数不符、每周/单周/双周 occurrence 数、跨范围合班未全选、跨学段所需时间缺失、零上课日和超容量需求。

```dart
test('weekly course occurrence occupies both alternating weeks', () {
  final result = builder.build(
    snapshot: snapshotWithWeeklyRequirement(lessons: 2),
    selectedClassIds: {'class-1'},
    strength: ScheduleStrength.normal,
    seed: 17,
  );
  expect(result.problem!.occurrences, hasLength(2));
  expect(result.problem!.occurrences.first.weekMask, WeekMask.both);
});
```

- [ ] **Step 2: 运行 builder 测试确认 builder 未实现**

Run: `flutter test test/domain/scheduling/schedule_problem_builder_test.dart`
Expected: FAIL because `ScheduleProblemBuilder` and normalized schedule types are absent.

- [ ] **Step 3: 实现纯 Dart 快照归一化和 readiness 检查**

归一化仅读取传入快照。为每条任课分配生成稳定的 occurrence ID；同一合班组各班按同一逻辑组关联；未选班级和锁定班级/教师已有课表转成固定占用。校验只阻止无法构造可靠问题的错误；可排容量不足作为明确警告继续进入求解，最终由未排项报告呈现。

```dart
final result = ScheduleProblemBuilder().build(
  snapshot: snapshot,
  selectedClassIds: selection,
  strength: strength,
  seed: seed,
);
if (!result.isReady) return ScheduleBuildResult.blocked(result.issues);
```

- [ ] **Step 4: 运行 builder 与已有科目/教师模型测试**

Run: `flutter test test/domain/scheduling/schedule_problem_builder_test.dart test/subject_lesson_constraints_test.dart test/features/teachers`
Expected: all projection/preflight cases pass and existing subject/teacher behavior remains intact.

- [ ] **Step 5: 提交输入编译器**

```bash
git add lib/domain/scheduling/scheduling_snapshot.dart lib/domain/scheduling/schedule_problem.dart lib/domain/scheduling/schedule_problem_builder.dart test/domain/scheduling/schedule_problem_builder_test.dart
git commit -m "feat: compile scheduling problem inputs"
```

### Task 4: 实现硬约束检查与可复核阻断原因

**Files:**
- Create: `lib/domain/scheduling/schedule_constraints.dart`
- Test: `test/domain/scheduling/schedule_constraints_test.dart`

**Interfaces:**
- `ScheduleConstraintEvaluator.check({required ScheduleState state, required ScheduleOccurrence occurrence, required TimeSlot slot})` 返回所有 `ConstraintBlocker`，不只返回布尔值。
- 每个 blocker 带 `ruleCode`、规则名、涉及对象、候选时间格及短说明；`UnassignedOccurrence` 只保留本次搜索实际检查到的不同 blocker，并设置固定上限防止报告膨胀。

- [ ] **Step 1: 写硬约束拒绝及诊断测试**

覆盖同班同格、同教师同实际周、跨学段钟点重叠、免任课、科目/教师“一定排/不排”、时段限制、每天限制、教师互斥、科目互斥、禁止相邻、强制连堂、单双周配对、合班、场室容量/同科上限和班级/教师锁。每种失败断言具体 blocker 的规则码、对象和格子。

```dart
test('cross-stage teacher overlap reports the conflicting clock interval', () {
  final blockers = evaluator.check(
    state: occupiedByTeacherAt(minutes: (600, 645), teacherId: 't-1'),
    occurrence: courseForTeacher('t-1', stageId: 'middle'),
    slot: slotAt(stageId: 'primary', start: 630, end: 675),
  );
  expect(blockers.single.ruleCode, 'teacher_time_overlap');
});
```

- [ ] **Step 2: 运行约束测试确认 evaluator 缺失**

Run: `flutter test test/domain/scheduling/schedule_constraints_test.dart`
Expected: FAIL because no schedule constraint evaluator exists.

- [ ] **Step 3: 实现格子索引和硬规则**

为班级、教师、房间、科目并发数建立按实际周索引；对跨学段教师/场室以 `(weekday, weekMask, startMinute, endMinute)` 检测严格正长度重叠。`一定排` 约束候选域，`不排` 删除候选；相互矛盾的必排项不违规强塞，改为未排并输出实际阻断条件。

```dart
List<ConstraintBlocker> check(ScheduleState state, ScheduleOccurrence item, TimeSlot slot) {
  final blockers = <ConstraintBlocker>[];
  blockers.addAll(_checkClassAndTeacherOccupancy(state, item, slot));
  blockers.addAll(_checkAvailabilityAndPresets(item, slot));
  blockers.addAll(_checkRelationalRules(state, item, slot));
  return List.unmodifiable(blockers);
}
```

- [ ] **Step 4: 运行硬约束测试与相关模型测试**

Run: `flutter test test/domain/scheduling/schedule_constraints_test.dart test/subject_lesson_constraints_test.dart test/features/teachers`
Expected: all accepted placements have zero hard blockers; each rejected candidate has a stable, inspectable reason.

- [ ] **Step 5: 提交硬约束引擎**

```bash
git add lib/domain/scheduling/schedule_constraints.dart test/domain/scheduling/schedule_constraints_test.dart
git commit -m "feat: enforce hard timetable constraints"
```

### Task 5: 实现确定性有界求解、计分与未排报告

**Files:**
- Create: `lib/domain/scheduling/schedule_scoring.dart`
- Create: `lib/domain/scheduling/course_scheduler.dart`
- Test: `test/domain/scheduling/course_scheduler_test.dart`
- Test: `test/domain/scheduling/schedule_scoring_test.dart`

**Interfaces:**
- `CourseScheduler.solve(ScheduleProblem problem, {bool Function()? isCancelled, void Function(ScheduleProgress)? onProgress})` 返回 `ScheduleRun`。
- `ScheduleScore.compareTo` 按“硬违规数（必须为 0）→ 两周周期已排实际课节数 → 四类软偏好满足率之和 → 稳定规范课表序列”比较；满足率以分子/分母保留，比较时用整数交叉相乘，不使用浮点误差作平分判断。
- `UnassignedOccurrence` 保存未满足的最少/固定总量要求及候选格实际 blocker；搜索预算耗尽且无 blocker 证据时显示“在本次搜索预算内未找到可行位置”。

- [ ] **Step 1: 写评分优先级、复现与预算单调性测试**

构造两个可行课表，证明硬约束零违规优先于软分；覆盖量高优先于偏好分；同覆盖量按四类等权满足率；相同输入/版本/强度/种子输出完全一致；高档预算包含低档候选前缀，因此不能降低覆盖量或相同覆盖量下的软偏好总分。

```dart
test('same problem and seed produce an identical canonical result', () {
  final first = scheduler.solve(problem(seed: 83));
  final second = scheduler.solve(problem(seed: 83));
  expect(first.canonicalResult, second.canonicalResult);
});
```

- [ ] **Step 2: 运行评分和求解器测试确认 API 缺失**

Run: `flutter test test/domain/scheduling/schedule_scoring_test.dart test/domain/scheduling/course_scheduler_test.dart`
Expected: FAIL because `CourseScheduler` and `ScheduleScore` do not exist.

- [ ] **Step 3: 实现有界搜索和软评分**

按候选数少、冲突度高的课节优先；候选格按硬规则过滤后，以固定 seed 做稳定的候选顺序扰动。先构造可行部分解，再对未排项执行有界移位/移出重排，只接受字典序评分更好的结果。快速/正常/高精度用递增的节点预算；预算集中定义，后续由 Task 8 的固定性能数据集校准。固定复现模式不读当前时间或系统熵。

```dart
while (budget.remaining > 0 && !cancelled) {
  final candidate = search.nextCandidate();
  if (candidate == null) break;
  state.tryPlace(candidate);
  best = ScheduleScore.betterOf(best, state.snapshot());
  onProgress?.call(ScheduleProgress(best: best, checkedNodes: budget.used));
}
```

- [ ] **Step 4: 运行求解器/计分测试并确认三档属性**

Run: `flutter test test/domain/scheduling/schedule_scoring_test.dart test/domain/scheduling/course_scheduler_test.dart`
Expected: deterministic replay matches byte-for-byte canonical placements/report; no accepted placement breaks a hard constraint; high strength never returns a lower lexicographic score than fast strength on the fixture suite.

- [ ] **Step 5: 提交可复现求解器**

```bash
git add lib/domain/scheduling/schedule_scoring.dart lib/domain/scheduling/course_scheduler.dart test/domain/scheduling/schedule_scoring_test.dart test/domain/scheduling/course_scheduler_test.dart
git commit -m "feat: add deterministic timetable solver"
```

### Task 6: 将求解放入可取消 worker 并接入 Riverpod 状态

**Files:**
- Create: `lib/features/scheduling/scheduling_worker.dart`
- Create: `lib/features/scheduling/scheduling_controller.dart`
- Create: `lib/features/scheduling/scheduling_state.dart`
- Test: `test/features/scheduling/scheduling_controller_test.dart`

**Interfaces:**
- Controller 状态为 `idle / checking / ready / solving / committing / completed / cancelled / failed`，携带就绪项、进度、最近报告及错误。
- Worker 接受不可变 `ScheduleProblem`，经 `SendPort` 输出 `progress/result/error`；取消消息在安全检查点停止工作，不发 `result`。
- `start()` 只在前置检查全通过后启动 isolate；只有收到完整 `ScheduleRun` 才调用 `commitScheduleRun`；取消路径绝不调用提交接口。

- [ ] **Step 1: 写异步状态测试**

覆盖开始前清单、进度事件、取消后 worker 退出、求解错误提示、提交失败状态、未选课表没变化，以及连续点击开始只会启动一个 worker。

```dart
test('cancelled solve never commits a partial schedule', () async {
  await controller.start(selection);
  await controller.cancel();
  expect(repository.committedRuns, isEmpty);
  expect(controller.state.status, SchedulingStatus.cancelled);
});
```

- [ ] **Step 2: 运行 controller 测试确认 lifecycle 缺失**

Run: `flutter test test/features/scheduling/scheduling_controller_test.dart`
Expected: FAIL because no scheduling controller/worker exists.

- [ ] **Step 3: 实现 isolate 协议与单一提交门**

使用 `Isolate.spawn`、`ReceivePort` 和显式 cancel message；输入/输出只传 sendable DTO，不能把 Drift 对象、Widget 或 ProviderContainer 传进 worker。启动时保存快照指纹，提交前若当前学期或输入版本已改变则拒绝提交并提示重新检查。

```dart
Future<void> start(Set<String> selectedClassIds) async {
  final snapshot = await repository.loadSchedulingSnapshot(termId);
  final build = builder.build(snapshot: snapshot, selectedClassIds: selectedClassIds,
      strength: state.strength, seed: state.seed);
  if (!build.isReady) return state = state.withIssues(build.issues);
  final run = await worker.solve(build.problem!);
  if (run == null || !ref.mounted) return;
  await repository.commitScheduleRun(run: run, selectedClassIds: selectedClassIds);
}
```

- [ ] **Step 4: 运行 controller 和求解器测试**

Run: `flutter test test/features/scheduling/scheduling_controller_test.dart test/domain/scheduling`
Expected: cancel/error produces no database commit; normal completion commits once after solve completion.

- [ ] **Step 5: 提交 worker 与 controller**

```bash
git add lib/features/scheduling/scheduling_worker.dart lib/features/scheduling/scheduling_controller.dart lib/features/scheduling/scheduling_state.dart test/features/scheduling/scheduling_controller_test.dart
git commit -m "feat: run schedule solver in cancellable isolate"
```

### Task 7: 增加自动排课页面、设置入口与导航

**Files:**
- Create: `lib/features/scheduling/scheduling_page.dart`
- Create: `lib/features/scheduling/widgets/schedule_scope_selector.dart`
- Create: `lib/features/scheduling/widgets/schedule_preflight_panel.dart`
- Create: `lib/features/scheduling/widgets/schedule_progress_panel.dart`
- Create: `lib/features/scheduling/widgets/schedule_result_report.dart`
- Create: `lib/features/scheduling/dialogs/schedule_condition_editor.dart`
- Create: `lib/features/scheduling/widgets/schedule_preferences_panel.dart`
- Modify: `lib/app.dart`
- Test: `test/features/scheduling/scheduling_page_test.dart`

**Interfaces:**
- 页面默认全校范围；可按学段、年级、逐班选取。跨范围合班未全部纳入时显示阻断项和“加入相关班级”操作。
- 页面展示第一次排课检查清单、快速/正常/高精度、固定种子高级入口、五类条件入口、全局规则、开始/取消、候选检查进度、评分摘要和未排清单。
- 未排报告逐条显示课程、实际遇到的阻断规则与时间格；搜索预算没有找到位置时用明确文案，禁止误称数学无解。
- 页面不实现 M4 的完整课表矩阵、拖动调课、打印或导出。

- [ ] **Step 1: 写页面状态和关键交互 widget tests**

测试默认全校范围、按年级/班级勾选、检查项可读、未就绪时不能开始、开始后显示进度和取消、结果呈现覆盖量/偏好/未排原因、条件与偏好编辑后重开仍相同。

```dart
testWidgets('start is disabled until the preflight checklist is ready', (tester) async {
  await tester.pumpWidget(testSchedulingApp(snapshot: incompleteSnapshot));
  expect(find.text('开始自动排课'), findsOneWidget);
  expect(tester.widget<AppPrimaryButton>(find.byType(AppPrimaryButton)).onPressed, isNull);
});
```

- [ ] **Step 2: 运行页面测试确认新页面和导航缺失**

Run: `flutter test test/features/scheduling/scheduling_page_test.dart`
Expected: FAIL because `SchedulingPage` and the `AppSection` route do not exist.

- [ ] **Step 3: 实现页面与响应式布局**

在 `lib/app.dart` 的 `AppSection`、标题映射、侧栏和页面 switch 增加 `scheduling`。页面沿用 `SchoolRepository` provider；窄窗口把范围/配置区与结果区上下排列，不固定宽度。排课操作只有一个蓝色主按钮；取消只发给 worker，不写临时结果。

```dart
AppSection.scheduling => activeTermId == null
    ? const _ChooseTermMessage()
    : SchedulingPage(termId: activeTermId),
```

- [ ] **Step 4: 运行排课页面与 app shell 测试**

Run: `flutter test test/features/scheduling/scheduling_page_test.dart test/app_shell_settings_test.dart`
Expected: navigation opens the active-term scheduler; all progress, report, and narrow-layout assertions pass without overflow.

- [ ] **Step 5: 提交页面与导航**

```bash
git add lib/features/scheduling lib/app.dart test/features/scheduling/scheduling_page_test.dart
git commit -m "feat: add automatic scheduling workspace"
```

### Task 8: 对齐 V7/V8 并校准典型规模预算

**Files:**
- Create: `tool/scheduling_fixture_generator.dart`
- Create: `test/features/scheduling/scheduling_acceptance_test.dart`
- Create: `docs/superpowers/plans/../scheduling-benchmark.md` (测量方式和基准结果)
- Modify: `docs/data-schema.md`

**Interfaces:**
- 固定 fixture generator 以显式种子生成完整输入；fixture manifest 记录课程密度、五类条件、单双周、跨学段时间、场室、合班、硬性规则和已知可行解。
- 集成场景复用 `SchoolRepository` + controller +真实数据库迁移，不 mock 持久化边界。
- 基准工具记录三次冷启动的机器/OS/种子/solver 版本、耗时、覆盖数、硬违规数和偏好分；不写入产品遥测。

- [ ] **Step 1: 写端到端验收场景**

固定小数据覆盖 V7/V8：全部五类硬条件、固定课表/锁、单双周、跨学段教师、未选择班级占用、矛盾必排、求解取消、重复种子、三档强度。确认取消后关闭再开数据库仍是原课表，正常求解后课表与报告一起可重开读取。

```dart
test('cancelled run survives close and reopen with prior timetable unchanged', () async {
  await controller.cancelAfterFirstProgressForTest();
  await repository.close();
  repository = await openRepository(databasePath);
  expect(await repository.watchSchedule(termId).first, priorCommittedSchedule);
});
```

- [ ] **Step 2: 运行端到端验收测试确认全链路结果**

Run: `flutter test test/features/scheduling/scheduling_acceptance_test.dart`
Expected: all V7/V8 acceptance scenarios pass against persisted SQLite data.

- [ ] **Step 3: 生成 400 班标准 fixture 并校准节点预算**

运行生成器的固定种子可行数据集；记录每档节点数与耗时。调整 `SolverBudgetPolicy` 后重复三次，要求快速档 ≤ 2 分钟、正常档 ≤ 5 分钟、可行集全部排入、硬违规为零，且高档评分不低于低档。另生成 600 班上限数据确认可排、可保存和可重开；未达目标时保留实测并优化算法，不得降低应排覆盖标准。

```bash
dart run tool/scheduling_fixture_generator.dart --classes 400 --teachers 800 --seed 20261024 --output /tmp/paike-scheduling-400.json
dart run tool/scheduling_benchmark.dart --input /tmp/paike-scheduling-400.json --runs 3
```

- [ ] **Step 4: 更新 schema 文档和基准记录，执行全量静态分析**

Run: `dart format lib test tool`
Run: `flutter analyze`
Run: `flutter test`
Expected: data schema 文档与 `AppDatabase.schemaVersion` 一致；静态分析无问题；既有测试和排课测试全部通过。性能目标逐平台单独记实际数值，未测平台标记为未测。

- [ ] **Step 5: 提交 V7/V8 回归与基准产物**

```bash
git add tool/scheduling_fixture_generator.dart tool/scheduling_benchmark.dart test/features/scheduling/scheduling_acceptance_test.dart docs/data-schema.md docs/scheduling-benchmark.md
git commit -m "test: validate scheduling acceptance and scale"
```

## 实施边界与决策记录

- 本计划以当前 `docs/PRD.md` 的 US-019～021 作为自动排课行为基线。用户已指示开始实施；若后续产品口径变化，再按变更调整跨学段冲突、锁粒度、软评分、固定种子与未排诊断。
- M4 的课表矩阵查看、手工拖动、撤销重做、检测、打印和导出不在本计划内；M3 负责将课表写入数据库并呈现本次运行报告，后续 M4 直接读取同一 `ScheduleEntry` 数据。
- 目前没有排课实体或数据库 API；现有 `SubjectRequirement`、`TeacherAssignment`、`StageRoutine`、`FreeSlot`、预设、课程配对及场室模型是输入来源。当前 M2 的完整五类自定义条件和全部全局规则也尚未形成统一持久化模型，因此 Task 1 必须提供这些模型与表，Task 7 必须提供其排课页编辑入口。
- `docs/data-schema.md` 的 schema v5 与当前源码 schema v13 不一致；Task 1/8 应以迁移链为准修订为 v14，避免把历史文档版本当作数据库当前版本。

## 实施记录（2026-10-25）

- 领域模型按职责拆成 `schedule_position.dart`、`schedule_item.dart`、`schedule_lock.dart`、`schedule_condition.dart`、`schedule_preferences.dart`、`schedule_run.dart`，而非计划中的单个 `schedule_entry.dart`。
- 纯 Dart 求解模块采用 `scheduling_snapshot.dart`、`problem_builder.dart`、`constraint_evaluator.dart`、`course_scheduler.dart`；约束和评分在求解器中合并调用，尚未拆成单独的 `schedule_scoring.dart`。
- v14 表名为 `schedule_items`，位置四元组可空表示暂放。实现包含仓库指纹校验、受锁位置校验、事务提交与提交前后本地备份。
- `SchedulingWorker` 使用 isolate 执行同步求解，`SchedulingController` 管理范围、配置、进度、取消和提交；排课页接入主导航。
- 求解器先构造部分解，再在固定候选预算内对暂放课程尝试补位和单个课组移位；快速、正常、高精度共享相同的首轮候选前缀。四类软偏好分数用整数分数比较，避免浮点并列误判。
- 原计划的测试与性能基准仍是验收工作项；本轮开发未执行测试，因此本文件中的测试步骤仍保留待办状态。不要把静态分析视为性能或业务验收结果。
