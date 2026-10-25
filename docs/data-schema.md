# 本地数据 Schema v14

课集以单个 SQLite 文件保存一所学校的本地资料。应用在启动时打开平台 Application Support 目录下的 `class_set/school.sqlite`。SQLite 是唯一数据源，UI 状态只用于编辑尚未提交的表单。

## 表与归属

| 表 | 关键字段 | 关系 |
|---|---|---|
| `academic_terms` | stable ID、标题、学年、学期标签、第 1 教学周日期、教学周数、课表周期（every_week/alternating） | 一个学期拥有多个学段 |
| `school_stages` | stable ID、term ID、名称、顺序 | 学段属于唯一学期 |
| `grade_groups` | stable ID、stage ID、名称、顺序 | 年级属于唯一学段 |
| `class_groups` | stable ID、grade ID、名称、顺序 | 班级属于唯一年级 |
| `stage_teaching_days` | stage ID、weekday、isTeachingDay | 每个学段分别存星期一至星期日 |
| `lesson_period_types` | stage ID、名称、默认节数、顺序 | 节数设置属于一个学段 |
| `daily_lesson_overrides` | stage ID、period type ID、weekday、lessonCount | 每天的显式覆盖；0 是有效值，缺少记录代表沿用默认值 |
| `lesson_times` | period type ID、lessonIndex、名称、起止分钟 | 节次时间属于对应时段类型 |
| `calendar_exceptions` | stable ID、term ID、date、kind（holiday/makeup）、makeupWeekday、makeupForDate、note | 教学日历例外：停课/节假日与补课映射，属于唯一学期 |
| `free_slots` | stable ID、scopeType（school/stage/grade/class）、scopeId、stage ID、period type ID、weekday、lessonIndex、label | 免任课格子；按学段展开存储，「全校」范围写入时展开到所有学段（按时段名称匹配） |
| `common_periods` | stable ID、stage ID、名称、insertAfterLessonId、时长、起止分钟 | 公共时段（大课间、眼保健操等），挂在某节次之后（null = 第 1 节之前） |
| `subjects` | stable ID、term ID、名称、简称、顺序 | 科目属于学期，在同一学期内跨学段共享 |
| `subject_requirements` | stable ID、subject ID、grade ID、class ID（可空）、weekMode（weekly/odd/even）、lessonCount | 科目节数需求；class ID 为 null = 年级默认，非 null = 按班覆盖（更具体优先） |
| `subject_presets` | stable ID、subject ID、scopeType（school/stage/grade/class）、scopeId、stage ID、weekday、period type ID、lessonIndex、value（auto/prefer/must/forbid） | 科目预设（星期 × 时段 × 节次 位置偏好）；不区分单双周（D14）；全校范围按学段展开存储（stage ID + 时段名称匹配），渲染时更具体范围优先 |
| `subject_pairings` | stable ID、class ID、odd subject ID、even subject ID | 课程配对：同班两门课（一单一双）共用同一时段（US-013 AC2） |
| `subject_lesson_constraints` | 科目、范围、学段、星期、单日课节上下限、单日/每周连堂上下限 | 更具体范围覆盖上级科目课节规则 |
| `public_rooms` | stable ID、名称、房间数、每间容量 | 全校公共场室资料 |
| `subject_room_assignments` | 科目、学期、学段、范围、场室 ID（可空） | 为科目分配场室；显式空值可覆盖继承分配 |
| `subject_parallel_limits` | 科目、学期、学段、范围、并发上限 | 同一时间同科并发控制 |
| `teachers`、`teacher_subject_tags` | 教师 stable ID、姓名、简称、排序、同名限定词；科目标签关系 | 教师实体与可检索标签 |
| `teacher_groups`、`teacher_group_members` | 分组及教师成员 stable ID | 学期内教师分组与成员关系 |
| `teacher_assignments` | 学期、教师、班级、科目、周模式、节数、合班组 ID | 任课份额；同班同科可由多名教师拆分 |
| `teacher_presets`、`teacher_group_presets` | 教师/分组、范围、节次与 auto/prefer/must/forbid | 教师个人与分组预排，个人优先 |
| `app_settings` | 设置键与值 | 当前学期等本地应用设置 |
| `schedule_items` | stable ID、term/assignment/class/teacher/subject ID、weekMode、合班/同课次 ID、学段/星期/时段/节次（可空） | 每条任课需求展开为具体课节；位置全空表示暂放，班级和任课删除时级联清理 |
| `schedule_locks` | stable ID、term ID、scope（class/teacher）、target ID | 锁定班级或教师的已有课节，重排时保留位置 |
| `schedule_conditions` | stable ID、term ID、kind、对象/另一对象/时段/星期、最少/最多/恰好节数 | 五类自定义硬条件的结构化存储 |
| `schedule_preferences` | term ID、强度、进度一致性、教师分布、午休保护、连堂策略 | 学期级排课规则与偏好 |
| `schedule_run_reports` | stable ID、term ID、创建时间、求解版本、种子、强度、输入指纹、报告 JSON | 一次求解的诊断、暂放原因与复现参数 |

### 范围与级联

- 免任课范围四级：全校（scopeId = 学期 ID，行按学段展开）、学段（scopeId = 学段 ID）、年级（scopeId = 年级 ID）、班级（scopeId = 班级 ID）；渲染时更具体的范围优先。
- 删除年级 / 班级时同步清理其范围的免任课行；删除学段、时段类型由外键级联完成。
- 保存作息（`saveRoutine`）会保留未越界的免任课行，并修复公共时段漂移的挂载点（引用的节次被删时挂到该时段最后一节，时段删除则移到最前）。
- 新建学段时按「同时段名称 + 同节次」继承全校范围免任课，使全校标记对新学段生效。

所有子表通过 SQLite 外键级联清理。学期、学段、年级和班级的名称可以修改，因为关联均使用稳定 ID。作息保存和父级数据创建都在 SQLite 事务中完成。

## 迁移

当前 `schemaVersion` 为 14。v2 新增 `calendar_exceptions`、`free_slots`、`common_periods`；v3 增加学期周期；v4 新增科目与需求；v5 新增科目预设与课程配对；v6～v7 增加科目课节约束及连堂字段；v8 新增公共场室、场室分配、同科并发上限；v9～v11 增加教师、任课、分组与教师预设；v12 新增应用设置；v13 将科目归属到学期；v14 新增自动排课的课节、锁定、条件、偏好与运行报告五张表及索引。升级均通过 `AppDatabase.migration.onUpgrade` 显式迁移，不清空数据库。

科目节数需求按年级整体替换保存（`replaceGradeRequirements`：先删该年级全部需求行再批量插入，一个事务）；删除科目时其名下需求由外键级联清理。节数仅接受非负整数；周模式 weekly/odd/even 中录入数字表示「一个实际出现周」的节数，容量按单双周分别校验。

科目预设按「科目 + 范围 + 学段」整体替换（`replaceSubjectPresets`）：全校范围保存时把时段按名称匹配展开到该学期所有学段各存一份，只对未单独设置的范围生效；范围优先级 班级 > 年级 > 学段 > 全校。课程配对按班级整体替换（`replaceClassPairings`），删除班级或科目时级联清理。

日历例外仍按自然日逐条保存，停课区间由领域格式化逻辑按连续日期与备注合并；批量新增、修改、删除在一个事务中提交。复制学期时，例外日期和补课映射日期按新旧第 1 教学周起始日的日数差平移。
