# 带班安排实施计划

**目标**　教务可从现有作息为行政班或实际合班设带班岗位，手动指派或智能补齐。排齐并确认后，三类课表同步显示活动和老师。临时换人走现有调代课。

**架构**　用独立的带班模型表达岗位、方案与日期替班。Flutter 页面通过 Riverpod 和 SchoolRepository 读写 Drift。常规排课和日期调代共用底层占用判断，展示与导出共用投影。

**需求依据**　2026-11-10 确认的产品方案。[晚自习原型](../../../design/evening_duty_design_v2.html)用于参考批量配置、周表和差异预览。页面遵循[课集界面规范](../../../design/DESIGN.md)。

## 产品范围和实施默认值

- 首版包含课后服务、早自习、晚自习及自定义活动。批量选择行政班时，每班各建一岗。实际合班须显式设置组名、地点和来源班，限同学段、同作息节次，每岗一人。首版以班级作为占用粒度，同一来源班同一时间只参加一项带班活动。
- 岗位每周重复。教师禁排、节次和天数上限属于带班规则。先尊重手动指派，再优先排满，最后均衡节次。一节合班计一个教师节次，连续两节计两节，同一天只计一个带班日。
- 草稿可存缺岗、修改和继续排。当前有效方案继续可查。确认要求无缺岗、无冲突，且已有正课遇到新岗位时由教务先调整或排除该格。新版本默认下一教学周周一生效，可选学期内更晚的周一。每学期最多保留一个尚未生效的版本，确认时原子替换该未来版本。学期内没有可选周一时仍可保存草稿。撤销全部岗位通过确认空方案生效，过去的版本仍可查。
- 常规课表使用当前有效周模板，可查看已确认的未来模板。日期周表和日期导出按实际日期选择版本。生效边界取自然日期，补课再按来源作息展开对应星期和节次。历史带班版本保留原岗位、人员、名称和时钟摘要。日期投影沿用现有日历解释。
- 首版交付范围限校内教师排班、课表和替班。实际合班地点为显示信息。所有发布入口在正课双向避让和日期替班完成后一起开放。

## 公共接口与存储

| 接口 | 契约 |
| --- | --- |
| `SupervisionPost` | 稳定岗位 ID、活动类型和名称、学段、星期、时段、节次列表、来源班 ID 列表、活动地点。单节岗位列表只有一节，连续岗位列表为同一时段内相邻节次。 |
| `SupervisionDraft` / `SupervisionPlanVersion` | 每学期一份草稿，保存岗位、教师池、规则、每岗选人结果及手动指派标志。已确认版本包含生效自然日、岗位与人员快照。通过下一版本生效日推导前一版本的结束日。 |
| `SupervisionPreview` | 草稿修订号、依赖指纹、选定生效日、岗位与教师负担差异、结构冲突、缺岗、受影响的未来替班。仓储返回预览供页面展示。 |
| `SchoolRepository` 扩展 | `watchSupervisionDraft(termId)`、`watchSupervisionVersions(termId)`、`saveSupervisionDraft(draft, expectedRevision)`、`previewSupervisionPublish(termId, effectiveDate)`、`publishSupervision(termId, expectedPreview)`。确认时在事务中复算并比对预览。 |
| `EffectiveSupervisionResolver` | 由版本、作息、日期映射和有效替班生成课表行及占用。周期结果用于排课和常规课表，日期结果用于调代课和实际周表。每个节次包含稳定岗位 ID、覆盖班级、实际起止时间和负责老师。 |
| 日期替班 | 现有调整记录新增 `supervision-substitute` 类型。沿用记录表、原因与撤销时间，按类型解码岗位 ID、实际日期、节次集合、原老师和替班老师。原有正课变更 JSON 继续按现有格式读取。 |

持久化使用新增的 `SupervisionDrafts` 和 `SupervisionPlanVersions` 表。草稿以学期为主键，版本按学期与生效日唯一。带班正文存为有格式版本号的 JSON，由仓储转换成有类型的 Dart 对象。已确认快照保存历史展示所需摘要，历史岗位 ID 不依赖可级联删除的班级或教师行。同一学期同一日同一岗位只允许一条未撤销的替班记录，由事务内重读校验。

## 1. 建立数据层与岗位校验

**落点**　新增 `lib/domain/models/supervision.dart`、`lib/domain/scheduling/supervision_validation.dart`、`lib/data/repositories/drift_supervision_repository.dart`。扩展 `app_database.dart`、`school_repository.dart` 和 Drift 实现。

- [ ] 先扩展 `test/database_migration_test.dart` 与新增的 `test/data/repositories/drift_supervision_repository_test.dart`。从 v17 数据库升级时，既有作息、免任课、正课和调代课行均保留，带班查询为空。保存一份含缺岗的草稿，重新打开数据库仍能读取，正式课表查询保持原结果。
- [ ] 当前 schema 为 17。新增表与索引，升级到 18，运行 `dart run build_runner build --delete-conflicting-outputs`。草稿保存使用期望修订号，过期写入提示刷新。
- [ ] 使用 `StageRoutine`、`FreeSlot` 和当前课表验证岗位。周五该时段为零节则拒绝，周日有作息则允许。创建岗位可选择所选班级均为免任课、且标记不为「无课」「不上课」的课格（含自习、劳动、教研及自定义活动）；正课、无课和不上课以禁用样式展示，整天、整行及全选也须过滤。草稿与免任课分别存储。校验应指出现有正课、重复来源班、跨学段组和非相邻连续节次的具体位置。
- [ ] 运行数据库迁移、带班仓储及作息网格测试，完成后再接 UI。

## 2. 实现带班工作台与智能补齐

**落点**　新增 `lib/features/supervision/supervision_page.dart`、`supervision_controller.dart` 和领域层 `supervision_allocator.dart`。在 `app.dart` 注册「带班安排」，`routine_page.dart` 传入当前学段、范围和选中节次，打开同一草稿编辑流程。

- [ ] 新增 `test/domain/scheduling/supervision_allocator_test.dart`。用受限岗位只有张老师可排、另一岗张李都可排的例子，验证补齐会优先处理受限岗位。覆盖连续岗位整段校验、老师在不同学段节次时间重叠、上限为零和手动指派保留。
- [ ] 从同一个只读快照构建候选名单。候选资格、禁排、周上限与时间冲突为硬约束，周期岗位同时检查单周和双周正课。有时钟时比较半开区间，首尾相接可排；需跨学段比较但时间缺失时提示补全时钟。教师组选择按当时成员展开。候选列表显示冲突或上限原因、已排节次和天数。
- [ ] 求解先锁定合法手动指派，按可用候选少者优先，对未锁定岗位做有界回溯。按已覆盖岗位节次、教师节次均衡、稳定 ID 顺序比较方案。后台执行，超时返回已找到的最好合法草案，取消后保留原草稿。缺岗时保留原因，允许继续手动编辑。
- [ ] 周表按作息显示周末，连续岗位合并为一格，支持批量选班、实际合班、直接选老师和保存草稿。新增 `test/features/supervision/supervision_page_test.dart`，覆盖作息跳转、批量建独立岗位、显式合班、选人、重开草稿和窄窗口可操作。

## 3. 事务确认、正课避让与课表投影

**落点**　扩展 `scheduling_snapshot.dart`、`scheduling_snapshot_codec.dart`、`problem_builder.dart`、`constraint_evaluator.dart`、`schedule_reconciler.dart` 和 `drift_scheduling_repository.dart`。展示接 `scheduling_timetable.dart` 与 `schedule_export.dart`。

- [ ] 先在 `test/data/repositories/drift_scheduling_repository_test.dart` 和带班仓储测试覆盖真实链路。保存有缺岗草稿、预览、提交被拒、补齐、再次预览、确认、从数据库重读。并发修改课表或日历后使用旧预览提交，结果应失败且旧版本仍可读取。
- [ ] 预览比较所选生效日原模板和草稿。依赖指纹包括草稿、现有版本、作息、班级、老师、周期正课、日历及调代记录。生成受影响日期上的实际占用，包含已生效调代课和未来替班。岗位或来源规则变化导致未来替班失效时，列出记录，要求撤销或修正后重新预览。提交事务复查版本和冲突，通过才写版本并清理本次草稿。
- [ ] 周期快照增加已确认带班占用，旧快照缺省为空。常规正课表覆盖整个剩余学期，因此候选位置需避让当前与未来有效版本在各自有效区间内实际出现的岗位。班级和教师占用进入 `ConstraintEvaluator`，并通过 `ProblemBuilder` 接入自动排课、手动移动、未排补排和增量协调。周期排课使用原定带班教师，日期调代按当日替班后的教师判断。周期课表提交时另外校验受影响日期上的既有替班，防止新正课与替班老师相撞。
- [ ] 在作息、班级、教师和日历的实际保存路径校验带班依赖。影响生效岗位时，捕获并保留旧快照，包括只有带班、尚无正课的学期。复用现有只读协调界面。若影响正式带班，要求先准备完整的修正方案，在协调确认事务内一起写回课表和带班版本。无语义变化的保存不触发协调。
- [ ] 用同一投影实现班级、教师、学校周表和常规导出。班级格显示活动名和教师，合班教师侧按岗位与节次去重，学校视图显示来源班。待生效方案只在明确选择的模板预览显示。扩展现有求解、手调、课表 UI 和导出测试，断言显示内容与实际持久化数据一致。

## 4. 接入现有调代课与导出

**落点**　扩展 `actual_timetable.dart`、`drift_temporary_adjustment_repository.dart`、`temporary_preview_worker.dart` 和 `lib/features/temporary_adjustments/` 中的周表、操作、记录和导出组件。

- [ ] 先补 `test/domain/scheduling/actual_timetable_test.dart` 和 `test/data/repositories/temporary_adjustment_repository_test.dart`。覆盖周日连续岗位、停课日、补课日来源星期、相同岗位重复替班，以及撤销时原老师已有其他占用。
- [ ] 从现有日期解析入口取得是否上课、采用的作息日和来源周。当天先选有效带班版本，再展开所有节次和已有替班。对班级范围日历例外，合班仅保留实际出席且映射到同一岗位的成员。该日期没有有效成员时无岗位；成员映射到不同节次时提示教务修复日历或方案。
- [ ] 添加带班替班预览与提交。候选使用实际日期上调代后的正课和带班占用，按整岗全部节次校验。单次临时替班遵守教师禁排和岗位资格，固定周上限用于常规排班。替班成功后改当天显示人员，周期版本保持原人。撤销时重验原老师的实际占用，成功后保留已撤销记录。
- [ ] 调代课周表沿用现有日期导航与筛选，连续岗位合并成一次可操作的格。历史与调课、代课共用日期、状态和教师筛选，增加「带班替班」类型。沿用现有导出入口，加入替班明细及班级、教师日期周表投影。扩展现有调代课页面和导出测试。

## 5. 迁移、回归和开放入口

- [ ] 更新 `docs/PRD.md` 的 D13、US-032 至 US-034 及 `docs/data-schema.md`。学期复制沿用当前资料复制行为，带班方案与日期记录继续归原学期。
- [ ] 更新 `LocalBackupService` 的迁移兼容判断，保留 v16、v17 备份可在 v18 安装后迁移的能力。扩展 `test/data/backup/local_backup_compatibility_test.dart`，校验旧库恢复、新版草稿与已确认版本往返、替班历史保留。
- [ ] 执行定向测试和 `flutter analyze --no-pub`。用 macOS 窗口走一遍「作息 → 建岗 → 草稿重开 → 补齐 → 差异预览 → 确认 → 三类课表 → 调代课替班 → 撤销与导出」。若连接 Dart/Flutter MCP，按仓库规则做热重载检查。
- [ ] 运行 `flutter test --no-pub`、`flutter build macos --debug` 和 `git diff --check`。分别记录定向与全量结果。全量若有失败，以当前主线同环境对照确认是否为既有失败。

## 定向验证命令

新增测试先观察目标断言失败，再完成对应阶段并运行同一组测试。第 3 阶段先验证事务和避让，再验证课表展示与导出。

| 阶段 | 命令 |
| --- | --- |
| 数据层 | `flutter test --no-pub test/database_migration_test.dart test/data/repositories/drift_supervision_repository_test.dart test/routine_grid_test.dart` |
| 工作台 | `flutter test --no-pub test/domain/scheduling/supervision_allocator_test.dart test/features/supervision/supervision_page_test.dart` |
| 正课联动 | `flutter test --no-pub test/data/repositories/drift_scheduling_repository_test.dart test/domain/scheduling/course_scheduler_test.dart test/domain/scheduling/manual_schedule_editor_test.dart test/features/scheduling/scheduling_reconciliation_ui_test.dart test/features/scheduling/scheduling_timetable_ui_test.dart test/features/scheduling/timetable_export_test.dart` |
| 日期调代 | `flutter test --no-pub test/domain/scheduling/actual_timetable_test.dart test/data/repositories/temporary_adjustment_repository_test.dart test/features/temporary_adjustments/` |
| 备份恢复 | `flutter test --no-pub test/data/backup/local_backup_compatibility_test.dart` |
