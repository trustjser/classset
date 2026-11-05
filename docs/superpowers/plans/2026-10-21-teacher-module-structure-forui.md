# Teacher Module Structure and Forui Alignment

## Goal

Refactor the teacher teaching-assignment feature to match the approved feature plan and `design/DESIGN.md`: split the oversized page by responsibility and use the repository's Forui-backed shared components wherever an equivalent exists. Preserve current teacher, group, subject, preset, import/export, combined-assignment, and drag/drop behavior.

## Architecture

- Keep `lib/features/teachers/teachers_page.dart` as a stable feature entry point so existing navigation imports do not change.
- Keep `presentation/teachers_page.dart` as the feature library and keep page state/build composition in `presentation/teachers_page_state.dart`.
- Move teacher import/export, teacher/group actions, assignment operations, and preset actions into focused `presentation/controllers/` part files.
- Move reusable teacher/group list, assignment matrix, and unassigned-course/drop panels into `presentation/widgets/`.
- Move editor, assignment, preset, and import-preview dialogs into `presentation/dialogs/`.
- Keep workbook parsing/export in `lib/features/teachers/io/` and domain models/repository boundaries unchanged.
- Use `lib/core/widgets/app_components.dart` Forui-backed buttons, fields, selects, panels, and dialogs; use framework layout primitives only for layout, and Forui controls for interactive elements where shared wrappers do not cover the need.

## Implementation Tasks

1. Capture the file map and stable public feature entry point; preserve the existing behavior and types while extracting the page into presentation files.
2. Split the page shell/state orchestration, teacher list and assignment chips, class matrix/unassigned panels, group list, and dialog flows into the directories above. Make only cross-file feature-internal APIs visible as needed.
3. Replace native Material button, input, select, card, and dialog usages in the teacher feature with the matching shared Forui-backed components. Align spacing, colors, radius, and responsive sizing to `design/DESIGN.md`.
4. Add or update focused tests for the affected presentation interactions where the existing test harness supports them; retain repository/domain coverage.
5. Format the touched Dart files and run teacher feature tests, relevant migration tests, analyzer, and `git diff --check`.

## Acceptance Criteria

- `teachers_page.dart` remains a compatible import entry point and no longer contains the full feature implementation.
- Page orchestration, widgets, dialogs, and IO are separated into the planned directories.
- Teacher feature interactive controls use shared Forui-backed UI components wherever available.
- Existing feature behaviors and tests continue to pass; no generated Drift file is manually edited.
