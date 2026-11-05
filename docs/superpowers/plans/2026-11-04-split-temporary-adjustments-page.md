# 调代课页面拆分 Implementation Plan

> **For agentic workers:** Use this checklist to split the existing page in the current authorized checkout. Keep each step behavior-preserving and review the diff before moving on.

**Goal:** Split the 4,000+ line temporary-adjustments page into responsibility-focused Dart files without changing scheduling behavior or UI.

**Architecture:** Keep `TemporaryAdjustmentsPage` and its state fields in the entry file. Use Dart `part` files with private extensions on `_TemporaryAdjustmentsPageState` for methods that share page state; move private index/worker/painter helpers into a support part. This preserves private APIs and avoids introducing a controller or widget callback layer during a mechanical refactor.

**Tech Stack:** Flutter, Dart, Riverpod, existing temporary-adjustments domain models.

**Spec:** `docs/superpowers/plans/2026-11-02-temporary-course-adjustments.md`; this task changes organization only, not its behavior.

## Global Constraints

- Follow the repository layering, Dart formatting and Flutter UI rules in `AGENTS.md`.
- Preserve the current worktree changes, including subject colors, hover styling and the existing `lib/app.dart` edit.
- Do not change adjustment rules, persistence, filters, labels, selection, or preview behavior.
- Do not add or run tests for this task; verify the refactor with formatting, analysis and a macOS debug build.
- Continue in the main checkout as previously authorized by the user.

---

### Task 1: Separate shared temporary-adjustment support

**Files:**
- Modify: `lib/features/temporary_adjustments/temporary_adjustments_page.dart`
- Create: `lib/features/temporary_adjustments/temporary_adjustments_page_support.dart`

- [x] Move the candidate-batch typedefs, candidate worker helpers, `_TemporaryTimetableIndexes`, `_PreviewUi`, `_DashBorderPainter` and `_TemporaryLessonHover` into the support part.
- [x] Add the matching `part` / `part of` declarations and keep all imports in the library entry file.
- [x] Format and compile before continuing.

### Task 2: Split the page shell, controls and timetable

**Files:**
- Modify: `lib/features/temporary_adjustments/temporary_adjustments_page.dart`
- Create: `lib/features/temporary_adjustments/temporary_adjustments_page_common.dart`
- Create: `lib/features/temporary_adjustments/temporary_adjustments_page_timetable.dart`

- [x] Keep widget construction, state fields, lifecycle and `build` in the entry file.
- [x] Move shared labels, date helpers, selectors, tabs, navigation and toolbars into a common state extension.
- [x] Move day/period headers, class and teacher timetable rendering, `_cell` and slot styling into a timetable state extension.
- [x] Preserve the existing state transitions and the local hover/subject-color presentation.

### Task 3: Split adjustment creation and history

**Files:**
- Modify: `lib/features/temporary_adjustments/temporary_adjustments_page.dart`
- Create: `lib/features/temporary_adjustments/temporary_adjustments_page_adjustment.dart`
- Create: `lib/features/temporary_adjustments/temporary_adjustments_page_preview.dart`
- Create: `lib/features/temporary_adjustments/temporary_adjustments_page_records.dart`

- [x] Move the candidate-batch lifecycle and adjustment selection/composer methods into the adjustment extension.
- [x] Move preview rendering and commit methods into a separate preview extension.
- [x] Move history filters, summary rows, details, export and cancellation methods into the records extension.
- [x] Keep extension names private and distinct; retain the same method names and signatures so existing calls resolve inside this Dart library.

### Task 4: Verify the structural refactor

**Files:**
- Verify: all `lib/features/temporary_adjustments/temporary_adjustments_page*.dart`

- [x] Format all changed Dart files.
- [x] Run Dart analysis and a macOS debug build.
- [x] Review `git diff --check`, the final file responsibilities, and the full diff to ensure no business or UI logic changed.
- [x] Do not run tests for this task.
