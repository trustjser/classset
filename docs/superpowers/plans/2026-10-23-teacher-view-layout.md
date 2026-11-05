# Teacher View Layout Implementation Plan

> **For agentic workers:** Implement this plan in the current session with test-first steps. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Put a compact 班级 / 教师 / 分组 switcher first in the page header, show only the matrix in class view, and put a collapsible unassigned-course panel to the right of the teacher table.

**Architecture:** Keep the selected view in `TeachersPage` as one index. The class matrix renders only its matrix. The teacher overview owns the visibility of its right-hand course panel and adapts to narrow windows with a right-side overlay.

**Tech Stack:** Flutter, Riverpod, Forui, Flutter Widget Test.

**Spec:** User request in this chat; visual guidance in `design/DESIGN.md`.

## Global Constraints

- Keep simplified Chinese UI text.
- Use existing theme tokens and repository/provider architecture.
- Preserve drag and drop from the teacher table to the unassigned course panel.
- Use the available width for responsive layout decisions.

---

### Task 1: Three compact header tabs and class-only matrix

**Files:**
- Modify: `test/features/teachers/teacher_page_views_test.dart`
- Modify: `lib/features/teachers/presentation/teachers_page_state.dart`
- Modify: `lib/features/teachers/presentation/widgets/class_assignment_matrix.dart`

- [x] Add a widget test that verifies header tab order, switching to group management, and absence of side panels in class view. The assertions should include:

  ```dart
  expect(find.byKey(const ValueKey('teacher-view-tab-group')), findsOneWidget);
  expect(find.byKey(const ValueKey('teacher-class-matrix-border')), findsOneWidget);
  expect(find.text('未分配课程'), findsNothing);
  expect(find.byKey(const ValueKey('teacher-drop-panel')), findsNothing);
  ```

- [x] Run that test by name and observe a failure caused by the missing group tab or class-only layout.
- [x] Replace `_showGroups` with a three-value `_viewIndex`; place the small `FTabs` first in header actions; route index 2 to `_GroupList`.
- [x] Remove `_UnassignedCoursePanel` and `_TeacherDropPanel` from `_ClassMatrix`, keeping its matrix and existing narrow-window scrolling.
- [x] Run the focused test and confirm it passes.

### Task 2: Right-hand collapsible unassigned panel

**Files:**
- Modify: `test/features/teachers/teacher_page_views_test.dart`
- Modify: `lib/features/teachers/presentation/widgets/teacher_assignment_overview.dart`

- [x] Add a widget test that switches to 教师, confirms the course panel is right of the teacher table, taps `teacher-unassigned-toggle`, confirms the panel disappears, taps again, and confirms it returns:

  ```dart
  expect(tester.getLeft(find.text('未分配课程')),
      greaterThan(tester.getLeft(find.byKey(const ValueKey('teacher-assignment-table')))));
  await tester.tap(find.byKey(const ValueKey('teacher-unassigned-toggle')));
  await tester.pumpAndSettle();
  expect(find.text('未分配课程'), findsNothing);
  ```

- [x] Run that test by name and observe the expected failure.
- [x] Make `_TeacherAssignmentOverview` stateful and place the table before the right panel. Keep a visible trailing toggle when the panel is collapsed. Use a right-hand overlay on narrow windows so the table remains usable.
- [x] Run the focused test and confirm it passes.

### Task 3: Align existing tests and verify

**Files:**
- Modify: `test/features/teachers/teacher_page_views_test.dart`

- [x] Update assertions and interactions that refer to 班级视角 / 教师视角, the old left switcher block, the old group return button, or the old class-side panels.
- [x] Run `dart format` on changed Dart files.
- [x] Run `flutter test test/features/teachers/teacher_page_views_test.dart`.
- [x] Run `flutter analyze` and inspect the final diff.
