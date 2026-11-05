# Unified Teacher Preset Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Replace separate teacher and group preset dialogs with one page that edits either target type, lists every saved rule, supports rule deletion, and retains the originating teacher/group selection.

**Architecture:** Keep `TeachersPage` as the local navigation host and open a dedicated preset workspace within it. Reuse the existing scope tree and preset matrix, add an owner selector plus an all-rules list, and persist edits through `SchoolRepository` replacement methods. Teacher/group entry actions pass the target kind and ID into the workspace.

**Tech Stack:** Flutter, Riverpod, ForUI, Drift repository, Flutter widget tests.

**Spec:** User request in this conversation; visual tokens and component guidance in `design/DESIGN.md`.

## Global Constraints

- Continue the existing feature layering: widgets use Riverpod providers and `SchoolRepository`; they do not access Drift tables directly.
- Use ForUI tabs and the existing `AppPageHeader`, `AppSectionPanel`, and `TeacherPresetMatrix` patterns.
- Keep personal and group preset conflict behavior unchanged.
- Do not edit generated Drift files for this feature.
- Add regression coverage, format Dart files, and run targeted widget tests and analysis.

---

### Task 1: Add unified-page navigation acceptance tests

**Files:**
- Modify: `test/features/teachers/teacher_page_views_test.dart`

**Interfaces:**
- The teacher page overflow gains a `预排` action.
- Teacher and group preset actions open the same page with their selected owner preselected.

- [x] Add tests that open the page from overflow, from a teacher preset action, and from a group preset action. Assert the shared page key/title and selected teacher/group name.
- [x] Add provider fixture inputs for personal and group preset streams and a minimal stage routine.
- [x] Run focused widget tests for navigation and selected owner.

### Task 2: Add a unified preset workspace and route actions to it

**Files:**
- Modify: `lib/features/teachers/presentation/teachers_page.dart`
- Modify: `lib/features/teachers/presentation/teachers_page_state.dart`
- Modify: `lib/features/teachers/presentation/controllers/teacher_preset_actions.dart`
- Modify: `lib/features/teachers/presentation/widgets/teacher_group_widgets.dart`
- Create: `lib/features/teachers/presentation/widgets/teacher_preset_page.dart`

**Interfaces:**
- Add `_openTeacherPresetPage({required _PresetOwnerKind ownerKind, String? ownerId})` to `_TeachersPageState`.
- Add `TeacherPresetWorkspace(termId, configuration, initialOwnerKind, initialOwnerId, onBack)` as the editor/list page.
- Preserve the existing `TeacherPresetScopeTree` and `TeacherPresetMatrix` edit behavior.

- [x] Add page state for target mode, selected target, selected scope, changed cells, and changed scopes.
- [x] Render ForUI mode tabs, searchable teacher/group target list, scope tree, and matrix with stable page-level scroll constraints.
- [x] Route the global overflow, teacher row, and group row preset actions to the workspace with their owner kind and ID.
- [x] Add an explicit return action to the teacher assignment page.

### Task 3: List and delete all saved preset rules

**Files:**
- Modify: `lib/features/teachers/presentation/widgets/teacher_preset_page.dart`
- Modify: `test/features/teachers/teacher_page_views_test.dart`

**Interfaces:**
- The rules list displays teacher/group owner, scope, weekday, period/lesson, and preset value.
- Deleting one rule replaces only that owner’s persisted rule collection, retaining all other rules.

- [x] Add a “全部预排规则” list from both preset providers, using teacher/group/scope/routine labels.
- [x] Add a per-rule delete action with confirmation; persist via the corresponding repository replacement method and keep other owners’ rules unchanged.
- [x] Test that both teacher and group rules appear and deleting one keeps the other rules.

### Task 4: Verify the unified page

**Files:**
- Format changed Dart files.

- [x] Run targeted teacher widget tests for navigation, rule display, and deletion.
- [x] Run `flutter analyze lib/features/teachers test/features/teachers`; no issues found in the affected feature.
- [x] Check `git diff --check` and record unrelated failures from the broader teacher widget suite.
