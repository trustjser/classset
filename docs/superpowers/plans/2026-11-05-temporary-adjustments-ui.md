# 调代课课表 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让调代课的实际周课表和调整面板采用排课页一致的白底卡片层级，并让班级视图、教师视图的课程底色使用同一套科目色强度。

**Architecture:** 只调整 `TemporaryAdjustmentsPage` 的页面组合、`_panel` 容器样式和现有课格配色。继续复用 `AppSectionPanel`、`AppSurface` 与 `SubjectColors`，不改课表数据、选课/预览/确认流程或调代课记录逻辑。

**Tech Stack:** Flutter、Dart、现有 `AppSectionPanel` / `AppSurface` 组件、`SubjectColors`、Flutter widget tests。

**Spec:** 在柔和的页面底色上，把实际周表放进有标题的白色主卡片；选中课次后，右侧调整面板作为同层级白色卡片出现。班级与教师课格使用 `SubjectColors.cellBackground`，与排课界面的科目底色强度一致。保留选中源课次、候选目标、冲突、已生效调整等状态自己的提示色和徽标。

## Global Constraints

- 不改变调代课的入口、工具栏、班级/教师切换、选课方式、候选检测、预览确认、记录查看和撤销行为。
- 使用 `context.appColors.surface` 和现有卡片圆角/阴影，支持暗色主题；浅色主题下呈现白底卡片，不写死 `Colors.white`。
- 宽屏继续使用左侧课表、右侧调整面板的布局；宽度低于 1040 时继续由页面作为唯一纵向滚动容器，周表内部保留自己的横向/纵向滚动。
- 课程色只表示科目；蓝色源课次、绿色目标课次、冲突提示和调整类型徽标继续表示操作状态。
- 不改导航壳、页面顶栏、业务模型、数据库或导出实现。

## Design Direction

- 参考用户提供的排课页截图中的“浅灰页面底色 + 白色工作卡片 + 轻阴影”层级。
- `design-taste-frontend` 方向记录选择 `framed-sheet`，seed `190037291`：采用其白色工作面和克制的卡片层级。该工具输出的 node-graph 画布不适合真实周课表，因此不照搬图形布局；`Open plane` 只作为保留现有应用外壳的方向记录，不重做导航或顶栏。
- 在应用屏幕中以现有真实周表为主视觉：卡片标题用“本周课表”，不复制页面标签“实际课表”；选中课程后才显示调整卡片，保持当前操作节奏。

## Implementation Plan

### Task 1: 先补调代课布局与课程配色回归覆盖

**Files:**
- Modify: `test/features/temporary_adjustments/temporary_adjustments_page_test.dart`

- [x] 在现有实际周表 fixture 的测试中断言主课表卡片存在；选中课次后断言调整卡片出现。给两个容器预留稳定 key：`temporary-adjustments-grid-panel`、`temporary-adjustments-adjustment-panel`。
- [x] 检查两个 key 下第一个 `DecoratedBox` 的填充色等于当前主题的 `context.appColors.surface`，确认浅色主题呈现白底，同时暗色主题跟随主题 surface。
- [x] 在班级视图和教师视图各断言至少一个课程格的 `BoxDecoration.color` 等于 `SubjectColors.cellBackground(context, subjectId)`。从测试数据复用 `subject`，使用现有课格 key 或按 `temporary-adjustments-grid-panel` 限定查找，避免依赖私有 Widget 的整体树结构。
- [x] 扩展窄屏回归：以 `390×780` 和现有 `700×700` 尺寸挂载页面，确认页面可滚动、课格保持可达且 `tester.takeException()` 为 `null`。
- [x] 保留现有“选课后可预览调课方式”、数据库预览不写入、确认后写入与取消恢复等覆盖，确保纯 UI 改动不改变操作流程。

新增断言应采用以下稳定标识：

```dart
expect(
  find.byKey(const ValueKey('temporary-adjustments-grid-panel')),
  findsOneWidget,
);
expect(
  find.byKey(const ValueKey('temporary-adjustments-adjustment-panel')),
  findsOneWidget,
);
```

课程颜色检查按卡片装饰色断言，不截图比对：

```dart
final cellDecorations = tester
    .widgetList<Container>(
      find.descendant(of: gridPanel, matching: find.byType(Container)),
    )
    .map((container) => container.decoration)
    .whereType<BoxDecoration>();
expect(
  cellDecorations.any((decoration) => decoration.color == expectedCourseFill),
  isTrue,
);
```

### Task 2: 用排课页的白底区块组织周表和调整面板

**Files:**
- Modify: `lib/features/temporary_adjustments/temporary_adjustments_page.dart`
- Modify: `lib/features/temporary_adjustments/temporary_adjustments_page_adjustment.dart`

- [x] 在 `TemporaryAdjustmentsPage` 增加一个小型周表面板构造方法，使用 `AppSectionPanel`、标题“本周课表”、12px 内边距和 `temporary-adjustments-grid-panel` key。
- [x] 将班级/教师两种周表都放入该面板。桌面版面板填满左侧 `Expanded`；窄屏版面板放入现有 420px 区域。继续将 `_gridFootNote()` 放在卡片下方，并沿用现有 1040px 断点和滚动方向。
- [x] 将 `_panel` 的外层 `Container` 改用 `AppSurface`，通过 `temporary-adjustments-adjustment-panel` key 暴露可测试边界。使用主题 surface、现有卡片圆角和阴影，保留内部标题、内容滚动、底部操作按钮以及窄屏 `scrollBody: false` 行为。
- [x] 保持主周表在未选课时占满可用空间；右侧调整卡片仍只在选中课次后出现，不新增空面板状态。

周表面板的目标接口：

```dart
Widget _timetablePanel(Widget grid, {required bool expandChild}) =>
    AppSectionPanel(
      key: const ValueKey('temporary-adjustments-grid-panel'),
      title: '本周课表',
      padding: const EdgeInsets.all(12),
      expandChild: expandChild,
      child: grid,
    );
```

### Task 3: 统一班级和教师视图的课程底色

**Files:**
- Modify: `lib/features/temporary_adjustments/temporary_adjustments_page_timetable.dart`
- Modify: `lib/core/theme/subject_colors.dart`
- Modify: `test/features/temporary_adjustments/temporary_adjustments_page_test.dart`

- [x] 将教师视图和班级视图两处 `SubjectColors.quietCellBackground` 替换为 `SubjectColors.cellBackground`，让相同科目在两种视图以及排课页具有同样的底色强度。
- [x] 保留课格文字层级、班级视图科目色条、教师视图边框，以及选中源/目标和冲突状态覆盖；科目底色只作用于普通课程状态。
- [x] 删除 `SubjectColors.quietCellBackground` 及其“仅供调代课使用”的注释，前提是改动时再次确认仓库没有其他调用方；保留 `SubjectColors.of` 和 `cellBackground` 的现有色板与暗色模式算法。
- [x] 在 Task 1 中补齐两种视图的底色断言。课程色断言应以实际课格背景和 `SubjectColors.cellBackground` 的相等性为准，不固定某个科目对应的具体色号。

### Task 4: 定向验证布局与调代课行为

**Files:**
- Verify: `test/features/temporary_adjustments/temporary_adjustments_page_test.dart`
- Verify: `test/subject_colors_test.dart`

- [ ] 运行 `flutter test --no-pub test/features/temporary_adjustments/temporary_adjustments_page_test.dart`，确认桌面/窄屏布局、班级/教师课色、选课预览、确认和撤销路径通过。
- [x] 运行 `flutter test --no-pub test/subject_colors_test.dart`，确认科目色稳定映射、浅/暗主题底色和色点显示通过。
- [x] 对修改的 Dart 文件运行 `dart format`。格式工具报告 5 个文件 0 处需调整；命令末尾因遥测路径权限问题返回非零。
- [x] 运行 `flutter analyze --no-pub` 与 `git diff --check`。分析器报告 39 条既有 warning；`git diff --check` 通过。
- [ ] 若完整测试套件有已知基线失败，单独记录定向覆盖与全量套件结果，不把未执行或有基线失败的检查写成通过。

---

## Completion Criteria

- 排课页和调代课页都以主题白色卡片承载工作区；调代课主周表在选课前也有明确白色区块。
- 同一科目在调代课班级视图、教师视图和排课课表中使用相同的底色强度。
- 窄窗口无溢出或异常，仍能通过页面滚动访问周表和调整面板。
- 选课、预览、确认、记录、撤销以及调整状态提示的现有语义保持不变。
