---
name: classset-scheduling
description: 课集 (ClassSet) 智能排课、基础数据配置（班级与学段、科目节数、教师任课）、带班安排与调代课 AI Agent 技能。当用户提及课集、学段、年级、建班、科目节数、课时、教师名单、任课分配、排课、课表、禁排、固排、连堂、合班、早自习、课后服务、晚自习、带班安排、调课、代课、换课或替班时触发，通过 classset MCP 连接器完成查询、预览与配置排课操作。
---

# 课集 (ClassSet) 智能排课与课务技能

通过课集桌面端内置的 `classset` MCP 服务（共 14 个工具），辅助教务老师完成基础教学数据批量搭建（班级与学段、科目节数、教师任课）、排课规则配置、自动排课、单课节微调、带班安排（早自习/课后服务/晚自习）以及日常临时调代课。

## 触发场景 (When to Use)

- 查询当前学期的排课准备进度、学段作息、班级、科目、教师任课或实际周课表
- 从 Excel/文档或自然语言批量创建/修改学段、年级与班级（如“一年级到六年级每个年级建 6 个班”）
- 批量设置或修改科目列表、各年级/班级的科目周课时节数、单双周配对及单日/每周连堂次数限制
- 批量导入或修改教师名册（含任教学科标签）、各班各科任课教师分配及跨班合班上课绑定
- 用自然语言批量配置教师禁排/必排、科目禁排/必排、教师互斥、科目同日互斥、午休保护或连堂策略
- 运行自动排课求解器生成草稿课表、诊断未排入课节的冲突原因，或移动/互换单个课节
- 批量创建早自习、课后服务、晚自习等带班岗位，自动分配带班教师并按生效日期发布带班版本
- 查询某周实际日历课表，查找无冲突的代课教师或可对调课位，执行移课、代课、换课、带班替班或撤销调代课记录

## 核心工作流 (Workflow Steps)

### 第一步：读取学期上下文、级联门控与实体字典

任何操作开始前，先调用 `classset_get_context_and_gates`。注意 `includeDictionaries` 默认不返回明细字典，需按任务显式传入所需字典名称：

1. 调用 `classset_get_context_and_gates`：
   - 配置班级与学段、科目节数、教师任课或排课规则时传入：`includeDictionaries: ["stages_and_routines", "grades_and_classes", "subjects", "teachers", "locks"]`
   - 带班安排或调代课查询时传入：`includeDictionaries: ["stages_and_routines", "grades_and_classes", "subjects", "teachers"]`
2. 检查返回的 `hasTerm` 与 `gates`（步骤级联限制）：
   - 若 `hasTerm === false`，提示用户先在课集中创建学校与学期。
   - 课集严格遵循「班级与学段 (`classes`) -> 作息设置 (`routines`) -> 科目节数 (`subjects`) -> 教师任课 (`teachers`) -> 排课与课表 (`scheduling`) -> 调代课 (`temporaryAdjustments`)」级联限制。若目标模块的 `gates.<module>.enabled === false`，直接按顺序先调用前置模块工具（或提示用户完成作息设置），不要越级调用被锁定的后续工具。
3. 将用户提到的教师姓名、班级名称（如“三年级1班”）、科目名称、时段名称精确映射为字典中的 ID（或使用基础配置工具支持的 `*Name` 按名称匹配字段），切勿自行编造 ID。

### 第二步：识别课集「两阶段提案确认」机制

课集 MCP 的所有写操作工具均采用**「预览提案 + 课集内确认」**的安全机制：

1. **只读预览 (`dryRun: true`)**：当用户仅希望评估方案或试算冲突时，传入 `dryRun: true`，工具返回 `{ status: "preview", data: ... }`。
2. **提交待确认提案 (`dryRun: false` 或不传)**：工具不会在后台静默覆写数据库，而是返回：
   - `status: "awaiting_confirmation"`
   - `actionId`: 本次待确认操作的唯一 ID（有效期 10 分钟）
   - `data`: 变更预览与冲突校验结果（数组超过 30 条时会自动截断并附带 `<field>Total` 总数）
   - `nextStep: "请在课集设置中查看并确认操作。"`
3. **跟进确认状态 (`classset_get_action_status`)**：
   - 收到 `awaiting_confirmation` 后，向用户清晰展示变更预览摘要，并提醒用户在课集主窗口的**「设置」**页面点击**「确认保存」**。
   - 当用户告知“已确认”或需要核实落库结果时，调用 `classset_get_action_status({ actionId })` 检查状态是否变为 `committed`（或 `rejected` / `expired` / `error`）。

### 第三步：分场景执行工具调用

#### 场景 A：基础教学数据批量设置 (`classes` / `subjects` / `teachers`)

1. **批量配置班级与学段 (`classset_batch_configure_classes_and_stages`)**：
   - 支持通过 `stages` 新增/修改学段（如小学部、初中部）。
   - 支持通过 `grades` 新增/修改年级，并直接传入 `classCount: N` 一键为该年级自动补齐 `1班 ~ N班`。
   - 支持通过 `classes` 自定义特殊班名（如 `实验1班`），或通过 `deletedClassIds` / `deletedGradeIds` / `deletedStageIds` 批量清理。
2. **批量配置科目与节数 (`classset_batch_configure_subjects_and_quotas`)**：
   - 前置要求：已完成学段作息设置（`gates.subjects.enabled === true`）。
   - 支持通过 `subjects` 批量创建或更新科目（省略 `shortName` 时自动取首字作为简称）。
   - 支持通过 `requirements` 按 `subjectId`/`subjectName` 与 `gradeId`/`gradeName`（可选指定单个 `classId`）批量配置周课时 `lessonCount`（传 `0` 清除配额）。
   - 支持通过 `lessonConstraints` 批量配置科目单日最少/最多节数与连堂次数上下限，以及通过 `pairings` 设置单双周科目配对。
3. **批量配置教师与任课 (`classset_batch_configure_teachers_and_assignments`)**：
   - 前置要求：已填写科目节数（`gates.teachers.enabled === true`）。
   - 支持通过 `teachers` 批量导入教师名册，使用 `subjectNames`（如 `["语文", "班会"]`）自动关联所教学科标签，同名教师可通过 `displayQualifier` 区分。
   - 支持通过 `assignments` 按 `classId`（或 `gradeName` + `className`）、`subjectId`/`subjectName`、`teacherId`/`teacherName` 批量分配任课教师；省略 `lessonCount` 时自动按该班该科目的需求节数全额分配；传 `teacherId: null` 且不传 `teacherName` 可清空该班该科任课。
   - 支持通过 `combinedGroups` 将多个班级的同一科目、同一教师任课绑定为合班课（或设 `disband: true` 解除合班）。

#### 场景 B：配置排课规则与自动排课 (`scheduling`)

1. **配置预设与硬条件**：调用 `classset_configure_schedule_rules`：
   - 教师某节禁排/必排：填充 `teacherPresets`，`scopeType` 通常设为 `"stage"`（搭配 `scopeId: stageId`）或 `"class"`（搭配 `scopeId: classId`），`value` 取 `"forbid"`（禁排）、`"must"`（必排）、`"prefer"`（优先）或 `"auto"`（清除预设）。
   - 科目某节禁排/必排：填充 `subjectPresets`。
   - 教师/科目硬条件：填充 `conditions`，支持 `dailyLimit`（单日节数上限）、`periodLimit`（时段节数限制）、`teacherMutualExclusion`（两位教师不同时上课）、`subjectMutualExclusion`（同班两科不同日）、`forbiddenAdjacency`（同班两科不相邻）。
   - 全局排课偏好：填充 `preferences`（`strength: "fast" | "normal" | "high"`、`lunchProtection: true | false`、`consecutivePolicy: "preferSeparate" | "requireSeparate" | "preferTogether"`、`progressConsistency: "indifferent" | "prefer" | "require"`）。
2. **运行自动排课**：调用 `classset_run_auto_schedule`：
   - 初次排课或重排全部未锁定课节：`retainPlacements: false, allowRearrangement: true`。
   - 仅补排暂放区未落位课节：`retainPlacements: true, allowRearrangement: true`。
   - 检查返回的 `data.preflightIssues`（任课配额预检错误）、`data.unplacedItems`（未排入课节）、`data.blockers`（每节课无法排入的原因）和 `data.issues`（整体规则诊断）。
3. **单课节微调**：调用 `classset_move_or_swap_lesson`：
   - 传入 `sourceItemId` 与 `targetSlot`（传 `null` 可将课节移入暂放区），`allowSwap: true` 允许与目标课位已有课程自动互换。

#### 场景 C：带班安排 (`supervision`)

1. **批量创建带班岗位**：调用 `classset_batch_create_supervision_posts`：
   - `kind`: `"morningStudy"`（早自习）、`"afterSchool"`（课后服务）、`"eveningStudy"`（晚自习）或 `"custom"`（自定义）。
   - 若多个班级合班看管，设置 `combineClasses: true` 并必填 `groupName` 与 `location`；若各班独立带班，设置 `combineClasses: false`。
   - 若相邻多节课由同一教师连带，设置 `consecutiveLessons: true`。
   - 检查返回的 `data.errors`（如与正课冲突或与“无课/不上课”免任课冲突）。
2. **自动分配带班教师**：调用 `classset_auto_allocate_supervision`：
   - 可通过 `matchingPreferences` 指定优先级（`classTeacher` 任教班级优先、`gradeTeacher` 本年级优先、`subjectTeacher` 指定学科优先）及模式（`matchFirst` 匹配度优先 或 `balanceFirst` 课时均衡优先）。
   - 可通过 `teacherRules` 设置特定教师的每周最大带班节数 `maxLessons`、最大天数 `maxDays` 或禁排坐标 `unavailable`。
3. **发布带班方案版本**：确认所有岗位均已分配且无冲突后，调用 `classset_publish_supervision_version({ effectiveDate: "YYYY-MM-DD" })`。

#### 场景 D：日常临时调代课 (`temporaryAdjustments`)

- **前置要求**：调代课依赖已发布的正式课程课表。若 `classset_query_actual_timetable` 返回 `hasPublishedSchedule: false`，提示用户先在课集「排课与课表」页面发布正式课表。
1. **查询实际日历课表与无冲突候选**：调用 `classset_query_actual_timetable`：
   - `startDate` 与 `endDate` 必须为 `YYYY-MM-DD` 格式，且跨度**不能超过 31 天**（建议按单周 7 天查询，以周一作为每周起始）。
   - 尽量传入 `classId` 或 `teacherId` 缩小结果体积；若返回 `nextCursor` 非空，可传入 `cursor: nextCursor` 翻页。
   - 定位到目标课次后，获取其 `sourceKey`（格式为 `${itemId}:${originDate}`），再次调用 `classset_query_actual_timetable` 并传入 `findCandidatesForSourceKey: sourceKey`，即可一次性获取引擎校验过的无冲突代课教师 `availableSubstituteTeachers`、同班可互换课次 `availableSwapLessons` 及可移入空课位 `availableMoveSlots`。
2. **执行调代课**：调用 `classset_apply_temporary_adjustment`：
   - **找人代课 (`kind: "substitute"`)**：传入 `sourceKey`、`substituteTeacherId`（可选 `substituteSubjectId`、`reason`）。
   - **移到空课位 (`kind: "move"`)**：传入 `sourceKey`、`targetDate`、`targetPosition`（可选 `reason`）。
   - **同班两课互换 (`kind: "swap"`)**：传入 `sourceKey`、`secondKey`（可选 `reason`）。
   - **带班临时替班 (`kind: "supervision-substitute"`)**：传入 `targetDate`、`supervisionPostId`、`substituteTeacherId`（可选 `supervisionPositions`、`reason`）。
   - 若需按多周周期批量调代课，可同时传入 `rangeStart`、`rangeEnd` 与 `excludedDates`。
3. **撤销调代课**：从 `classset_query_actual_timetable` 返回的 `activeAdjustments` 中找到对应记录 `id`，调用 `classset_cancel_temporary_adjustment({ recordId })`。

## 常见错误处理与避坑指南 (Gotchas)

- **窗口可见性要求 (`NOT_READY`)**：课集桌面端出于安全约束，仅在主窗口打开且可见时响应 MCP 请求。若收到 `请打开课集主窗口后重试` 或 `课集主窗口尚未连接`，提醒用户点开课集主界面（不要最小化隐藏到托盘）并确认「设置 -> AI Agent 连接（MCP）」开关处于开启状态。
- **日期区间上限 (`INVALID_ARGUMENT` / `RESULT_TOO_LARGE`)**：`classset_query_actual_timetable` 强制校验 `endDate - startDate < 31 天` 且响应上限为 256KB。查询全校课表时务必按单周或指定 `classId` / `teacherId` 查询。
- **草稿协调阻塞 (`RECONCILIATION_REQUIRED`)**：当修改了基础教学资料（如增删班级、修改任课或作息）导致已有课表需要协调时，排课发布与调代课会返回 `RECONCILIATION_REQUIRED`，需引导用户先在课集「排课与课表」页面确认草稿协调。
- **只能操作当前激活学期**：所有写操作工具仅允许修改课集当前激活的学期；若传入的 `termId` 与当前激活学期不一致会被拒绝，因此默认省略 `termId` 即可。
