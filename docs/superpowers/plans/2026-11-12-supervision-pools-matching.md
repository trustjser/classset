# 带班候选池与人员匹配 Implementation Plan

> **For agentic workers:** 按本计划逐项实施、验证，保留当前工作区已有改动。

**Goal:** 岗位可继承或指定教师候选池，使用可排序匹配偏好，并让手动指派、智能补齐、发布校验遵循同一限制。

**Architecture:** 在现有 JSON 草稿中追加候选池、默认池、默认偏好、岗位覆盖与目标学科，旧草稿保持可读。领域匹配器从本学期实际任课建立班级、年级、学科关系；分配器先求覆盖，再按排序模式比较偏好与带班负载。页面继续使用 Provider/Repository 与 ForUI 包装控件。

**Tech Stack:** Flutter / Dart / Riverpod / Drift / ForUI；不引入依赖或变更 schema。

**Spec:** 本次对话用户接受的四部分方案：候选池管理、顺序匹配偏好、软硬条件、解释与已有指派保护。

## Global Constraints

- 候选池是硬范围；绝不自动扩池，教师负载与冲突跨池统一计算。
- 任课关系只统计本学期有效且 lessonCount > 0 的任课；合班软偏好按覆盖班级数，硬匹配覆盖全部来源班。
- 软偏好未命中允许池内合法补位；必须符合启用后无合格人选保留缺岗。
- 设置变更保留已指派岗位及手动标记；显示冲突，并在发布前阻止违规指派。
- 正式版本只经现有预览、确认路径更新；所有设置可保存重开。

## Task 1: 领域配置与统一匹配

Files: `lib/domain/models/supervision.dart`, create `lib/domain/scheduling/supervision_matching.dart`, `supervision_allocator.dart`, `supervision_validation.dart`; test `test/domain/scheduling/supervision_matching_test.dart`.

- [x] 用旧 JSON 加新配置写失败测试：独立池不能互借、按任教班级/年级/学科排序、任一/全部硬条件、合班全覆盖、顺序调整、匹配优先与均衡优先、跨池共同上限、旧格式兼容。
- [x] 运行测试观察缺少配置支持造成的失败。
- [x] 新增 `SupervisionTeacherPool`、`SupervisionMatchingPreferences`、`SupervisionPreference`、模式和必须符合枚举；Post 增加 poolId、preferences、targetSubjectIds；Draft 提供继承解析方法。
- [x] 匹配器公开候选范围、关系说明、偏好计数与必须符合判断；teacherBlockers 接入，fill 按覆盖、模式和顺序向量比较，保留手动指派。
- [x] 运行新测试和原 allocator/validation 测试。

## Task 2: 候选池与岗位设置界面

Files: `supervision_page.dart`, `supervision_dialogs.dart`, `supervision_post_dialog.dart`, create `supervision_matching_settings.dart`; test `test/features/supervision/supervision_matching_test.dart`.

- [x] 写界面失败测试：创建并命名池、添加成员、设置默认池；创建岗位指定池与学科；框选批量设池；全局/岗位偏好启停、上移下移、模式、必须符合；取消不改变草稿。
- [x] 候选池管理复用已有教师搜索、教师组与规则编辑，默认池和命名池各自成员，规则全局共用；被引用池禁止删除。
- [x] 创建岗位使用同一个人员设置组件；单岗位从教师面板进入，批量从框选操作栏进入；默认继承，岗位可覆盖或恢复继承。
- [x] 教师面板显示池人数、可安排人数、匹配依据、负载与禁排原因；按统一匹配排序，池外教师禁用。
- [x] 周表增加“偏好未满足”筛选与违规指派/偏好未满足标记，修改设置不清空已有安排。
- [x] 运行 widget 测试，验证普通点击、框选、尺寸适配不回退。

## Task 3: 存储、发布和最终验证

Files: `test/data/repositories/drift_supervision_repository_test.dart`, existing supervision tests.

- [x] 真实 SQLite 保存重开配置，旧草稿兼容；发布预览阻止池外/必须符合违规，软偏好不阻止；正式版本配置随版本保留。
- [x] 检查实际创建、设置、智能补齐、保存、预览、确认路径。
- [x] 格式化、局部 analyze、相关领域/仓库/widget 测试、macOS debug build，截图检查桌面与窄窗口。
- [x] 记录实际验证范围；不把局部检查当作全量通过。


## 实施与验证结果

- 已实现基础池、命名池、默认池、成员搜索/教师组添加、重命名和引用保护删除；岗位可继承或指定池。
- 已实现全局/岗位偏好继承与覆盖、班级/年级/学科优先的启停和顺序、匹配/均衡模式、none/any/all、目标学科和批量设置。
- 手动选择与智能补齐共用候选范围和硬条件；完整岗位支持重新匹配，可选择保留手动指派。既有指派在设置变更后保留并标记，发布前重新校验。
- 旧草稿 JSON 向后兼容；失效学科/池引用可在岗位人员设置中修正。SQLite 保存、重开、预览拒绝违规、确认发布和正式版本配置均已验证。
- 定向验证：34 项测试通过（领域匹配、原分配/校验、岗位创建、框选、真实 isolate 智能匹配、真实 SQLite 保存/发布、智能排课）；局部 `dart analyze` 无问题；`git diff --check` 通过；macOS debug 构建通过。
- 截图验证：全局匹配、候选池管理、岗位设置在 1440 / 768 / 390 宽度无溢出，右侧教师面板显示候选/可安排人数和匹配依据。
- 扩展回归：55 通过、2 失败，其中 1 项通过为临时截图测试；截图测试已移除。两项失败在未包含本次改动的 HEAD 临时副本中分别复现：
  - `actual_timetable_test.dart`：跨学段教师冲突的描述期望与现有结果不一致（第 852 行）。
  - `temporary_adjustments_page_test.dart`：真实数据库调课测试找不到 2026-09-07 课表格（第 323 行）。
- 未执行全量测试。只读代码审查未发现阻塞问题；求解器沿用 12,000 节点搜索预算，匹配/均衡按“尽量优化”解释，不承诺大输入全局最优。
