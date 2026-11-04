# 调代课工作台重设计

## 现状与数据

- 课次：日期、星期、节次、开始时间、科目、教师、班级，以及现有调整状态。
- 课表位置：按班级和作息生成；位置可能有实际课程、空课位或不可用状态。
- 调整方式：换课、移课、代课，各自具有不同的目标与冲突条件。
- 目标课次：换课选择同班另一节实际课；移课选择同班空课位；代课选择空闲教师并可保留或调整科目。
- 校历例外：停课日和补课日会影响可用位置，补课日可采用其他星期的作息。
- 冲突结果：由现有 preview API 计算，需保留可用、不可用、处理中和失败等真实状态。
- 调整原因：选填并随调整记录保存。
- 调整记录：类型、日期、变更前后、班级、教师、有效或已取消状态，支持筛选、查看、取消与导出。
- 真实数据规模：一个班一周通常显示 5 个上课日和约 5–8 行课次；周末仅在该班实际安排课程或属于补课日时出现，周末停课日不占列。
- 使用者：教务人员在桌面端高频核对课表并发起临时调整；平板端需要能顺序完成操作。
- 最常见任务：从实际课表选中一节课，选择换课、移课或代课，选定目标，检查预览后确认。
- 页面继续使用仓库中的实际学期、课表、校历、教师与调整记录，不引入展示用假数据。

## 主要问题（改前）

- 首屏一秒看到的是许多相同大小的圆角课格；课表自身没有明确的焦点。
- 五个上课日和两个无课周末同宽排列，留下两列大空白。
- 选择课程后，336px 侧栏与至少 920px 的课表并列，窄窗口里课表被迫横向滚动。
- 调整方式三个大卡片纵向堆叠；选中课次、类型、目标提示和原因缺少紧凑的步骤关系。
- 记录页保留了宽松、卡片化的空状态与列表，信息密度和调课工作台不一致。

ROUND 0
Seen in one second: a 7-column timetable beside a tall adjustment form.
Idea (one sentence): none is visible; a course opens a form, while the target action is explained in prose.
Live thing: select the source lesson, then choose a target directly in the timetable.
Layout words by section: shell=labelled sidebar and top bar / toolbar=split tabs and week controls / schedule=7-column tile grid / composer=stacked option cards / history=wide rows and filters.
Scores: design 5 · usability 5 · creativity 3 · content 6 → overall 4.7.
Caps applied: creativity capped at 6 because the screen has no distinct idea; usability capped at 6 because the target action is easy to miss.
Top three problems (most visible first), each with the screenshot it shows in and the fix:
1. Two empty weekend columns dominate the schedule width (user screenshots 1 and 2); render configured teaching days, weekday closures, and make-up days, while skipping ordinary weekend closure exceptions.
2. Opening the composer squeezes a fixed-minimum-width grid (user screenshot 1); size the grid from its visible days and keep overflow inside the grid.
3. Three tall adjustment cards push the target and reason down (user screenshot 1); use one compact mode selector and a source-to-target comparison.

## 设计方向

- Direction: `accent-ladder`, seed `1934525001`; keep ClassSet's blue and warm-neutral palette and current type system.
- Screen question: “这节课可以怎样调整，哪个目标课次符合条件？”
- Finding: the selected lesson and the eligible target slot are the two anchors; status comes from the real preview result.
- Face: the actual course cells and period labels from ClassSet's teaching-week timetable.
- Signature element: a compact weekly course matrix. It shows configured school days, weekday closures, and makeup dates; weekend columns return for scheduled courses or makeup lessons, while ordinary weekend closures do not take a column. The selected source and target are emphasized in the same matrix.
- Idea: a course adjustment is a change between two timetable cells; the selected and target cells become a before/after pair in the inspector and preview.
- Live thing: select a real source lesson and target in the week matrix; the eligible state, target summary and preview readiness update from the existing domain preview.
- Blocks: actual timetable or adjustment history; scope controls; weekly schedule or record rows; contextual composer for the selected source; fixed preview/cancel actions.
- Preserve the global app shell because it is shared by every ClassSet page. Apply the new accent-ladder proportions inside this feature; retain current routing, filters, local persistence, export, cancellation and preview behavior.
- Width arithmetic at a 1440px desktop: about 1200px work area − 40px page gutters = 1160px; a 336px composer + 16px gap leaves about 808px for the schedule. The row label uses 76px and five active day columns need about 5 × 132px = 660px, so the weekday matrix fits without hidden columns. Six- and seven-day schedules scroll only inside the schedule region.
- Visual verification: reviewed native Flutter/macOS screenshots at 1440×900 for the timetable, selected-course composer, and empty history state. Compact-width resizing was not performed. The web `inspect.mjs` cannot inspect this native Flutter target; it was not run.

## 设计方向落地核对

- Weekday matrix and composer were inspected in the running app; this fixture had five teaching days and no scheduled weekend lessons. Weekend closure exceptions no longer add empty columns.
- Selecting a real course opens the compact three-way mode control, retains the source summary, and points to target selection in the week grid. Existing candidate availability completed from “检测中” to “可选 / 不可选” during the visual check.
- History filters remain across the top. The no-match state now keeps its actions directly under the explanation instead of vertically centering them in the page.
- Scores after redesign: design 7 · usability 7 · creativity 6 · content 8 → overall 7.0. Remaining cap: populated record rows were not visually reviewed because the available local fixture showed zero records.
