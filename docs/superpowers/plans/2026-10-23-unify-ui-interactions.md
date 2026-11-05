# UI Interaction Consistency Implementation Plan

**Goal:** Make the page header, responsive layout transitions, sidebar behavior, save status, and macOS launch size consistent with the ClassSet UI guidelines.

**Architecture:** Keep the current Flutter/Riverpod app shell and page composition. Share the wide content breakpoint through `AppTheme`, animate sidebar width changes in the existing navigation, and set the macOS initial frame in `MainFlutterWindow`.

**Tech Stack:** Flutter, Dart, Riverpod, AppKit.

**Spec:** `design/DESIGN.md` and the user's UI interaction request.

## Global Constraints

- Preserve the existing Flutter/Riverpod/Drift architecture and avoid new dependencies.
- Keep user-facing interface text in Simplified Chinese.
- Base responsive decisions on available width constraints.
- Preserve the user's existing uncommitted subject-capacity and subject-layout changes.
- Do not change database schema or generated files.

---

### Task 1: Align responsive page breakpoints

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `lib/features/terms/term_page.dart`
- Modify: `lib/features/subjects/subjects_page.dart`
- Modify: `lib/features/routines/routine_page.dart`

- [x] Add a shared 1040 px wide-layout breakpoint to `AppTheme`.
- [x] Use the shared breakpoint for semester/calendar side-by-side layout and remove its extra height condition.
- [x] Use the shared breakpoint in the subject page while retaining its existing layout edits and scroll behavior.
- [x] Use the same breakpoint for the routine page stacked-to-two-column transition; retain its existing three-column transition.

### Task 2: Unify the app header and animate sidebar interaction

**Files:**
- Modify: `lib/app.dart`
- Modify: `lib/main.dart`

- [x] Replace the school-to-term breadcrumb with the current page title beside the term selector.
- [x] Remove the F1 help controls and database filename from the visible header/sidebar.
- [x] Change the save badge to `上次保存：HH:mm`, with a clear empty state before any recorded save.
- [x] Add a sidebar collapse control at desktop widths and animate sidebar width changes.
- [x] Remove the database path from the visible header/sidebar while keeping its internal use for database setup and the term page.

### Task 3: Increase the macOS launch window size

**Files:**
- Modify: `macos/Runner/MainFlutterWindow.swift`

- [x] Start at 1440 × 900 logical points, capped to the primary screen's visible frame and centered.

### Completion checks

- Dart formatting was applied; inspect the final diff, especially the pre-existing edits in `subjects_page.dart`.
- Do not add or run tests unless the user asks for verification.
