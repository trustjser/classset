# Teacher Matrix Performance and Content Implementation Plan

> **For agentic workers:** Execute inline using the existing task context. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep teacher assignment matrix scrolling responsive, make overflowing cell content discoverable, and show each teacher's lesson count and week mode.

**Architecture:** Keep the pinned subject column and existing vertical lazy lists. Replace each fully materialized horizontal row with a synchronized horizontal `ListView.builder`, so only visible class headers and cells are built. Render assignment summaries as one single-line rich text with ellipsis; wrap it in a tooltip containing the complete text and retain draggable unassigned course spans.

**Tech Stack:** Flutter, Dart, existing `ScrollController`, `ListView.builder`, `Tooltip`, widget tests.

**Spec:** Current user request in this Codex task; preserve `design/DESIGN.md` and the teacher matrix layout.

## Global Constraints

- Keep the project on Flutter/Dart and existing dependencies; no new package is required.
- Keep the subject column pinned and preserve synchronized horizontal and vertical scrolling.
- Preserve drag assignment behavior for unassigned courses and the current per-cell coloring.
- Display weekly assignments as `(N)` and odd/even assignments as `(单.N)` / `(双.N)`.

---

### Task 1: Virtualize the horizontal matrix

**Files:**
- Modify: `lib/features/teachers/presentation/widgets/class_assignment_matrix.dart`
- Test: `test/features/teachers/teacher_page_views_test.dart`

**Interfaces:**
- Add a small horizontal scroll synchronizer that registers one controller per visible header/row list and mirrors offsets.
- Use lazy `ListView.builder` instances for the class header and each visible subject row.

- [x] Add a widget test with many classes that confirms an offscreen class cell/header is not built initially and appears after horizontal scrolling.
- [x] Run that focused test and confirm it fails with the current eager `Row` implementation.
- [x] Add synchronized horizontal list widgets and preserve the fixed subject column and existing vertical list synchronization.
- [x] Run the focused and teacher feature widget tests.

### Task 2: Show compact teacher summaries and full tooltip content

**Files:**
- Modify: `lib/features/teachers/presentation/widgets/class_assignment_matrix.dart`
- Test: `test/features/teachers/teacher_page_views_test.dart`

**Interfaces:**
- Format assignment summaries as teacher name plus `(N)`, `(单.N)`, or `(双.N)`.
- Render one `Text.rich` line with `maxLines: 1` and `TextOverflow.ellipsis`.
- Keep unassigned course entries draggable and include every visible and unassigned entry in the cell tooltip.

- [x] Add a widget test that checks all three formats, one-line ellipsis behavior, and the complete tooltip text on hover.
- [x] Run that focused test and confirm it fails before implementation.
- [x] Replace the per-assignment wrapping layout with rich inline spans and draggable course spans.
- [x] Run the focused test and the teacher feature suite.

### Task 3: Verify layout and performance behavior

**Files:**
- Modify: `test/features/teachers/teacher_page_views_test.dart`

- [x] Confirm pinned subject position, horizontal controller synchronization, tooltip content, and no Flutter layout exceptions.
- [x] Run `flutter test --no-pub test/features/teachers`.
- [x] Run `flutter analyze --no-pub lib/features/teachers test/features/teachers` and `git diff --check`.
