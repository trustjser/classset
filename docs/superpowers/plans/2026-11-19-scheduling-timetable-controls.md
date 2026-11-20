# Scheduling Timetable Controls Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax.

**Goal:** Show week filters only for alternating-week terms, align Export to the toolbar's right edge when it fits, and keep the class selector order stable between published and draft timetables.

**Architecture:** Keep view-specific controls in `SchedulingTimetable`. Gate week controls from `snapshot.term.cycleMode`, align only the final Export section to the toolbar edge when all sections fit, keep the final tool and Export together when wrapping, and pass the draft class ID order into the timetable so a published snapshot can display its own classes in that same order.

**Tech Stack:** Flutter, Dart, `flutter_test`, Riverpod.

**Spec:** `design/DESIGN.md`, especially responsive toolbars and 36–40 px pointer controls.

## Global Constraints

- Keep UI copy in Simplified Chinese and use the existing theme and toolbar components.
- Preserve the published snapshot's classes and labels; only normalize their display order to the draft class order.
- Do not change database schema or add dependencies.
- Base wrapping on the toolbar's available width; do not add a device-type check.

---

### Task 1: Gate Week Filters by Term Cycle

**Files:**
- Modify: `lib/features/scheduling/scheduling_timetable.dart`
- Test: `test/features/scheduling/scheduling_timetable_ui_test.dart`

**Interfaces:**
- Reads `SchedulingSnapshot.term.cycleMode` and `AcademicTermCycle.alternating`.
- No new public API.

- [x] **Step 1: Write the failing widget test.** Build the timetable with `AcademicTermCycle.everyWeek` and assert that `周别`, `单周`, and `双周` are absent; rebuild it with `AcademicTermCycle.alternating` and assert the selector is present.
- [x] **Step 2: Run the focused test and confirm it fails** because the week selector is currently always rendered.
- [x] **Step 3: Gate the selector.** Render the label and `ScheduleSegmentedControl<_WeekView>` only when `snapshot.term.cycleMode == AcademicTermCycle.alternating`.
- [x] **Step 4: Run the focused test and confirm both cycle modes pass.**

```dart
if (snapshot.term.cycleMode == AcademicTermCycle.alternating)
  Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _controlLabel(context, '周别'),
      const SizedBox(width: 8),
      ScheduleSegmentedControl<_WeekView>(
        label: '周别',
        options: const [
          (_WeekView.merged, '合并'),
          (_WeekView.odd, '单周'),
          (_WeekView.even, '双周'),
        ],
        value: _week,
        onChanged: (value) => setState(() => _week = value),
      ),
    ],
  ),
```

### Task 2: Keep Export at the Right Edge When the Toolbar Fits

**Files:**
- Modify: `lib/features/scheduling/scheduling_timetable.dart`
- Test: `test/features/scheduling/scheduling_timetable_ui_test.dart`

**Interfaces:**
- Uses a width-aware toolbar layout that wraps controls naturally and right-aligns only Export on a single row.
- No new public API.

- [x] **Step 1: Write the failing widget test.** At a wide window, assert the Export button's right edge matches the toolbar's inner right edge and adjacent groups stay compact. At a narrow window, assert Export follows the final tool on its row and the toolbar wraps without a layout exception.
- [x] **Step 2: Run the focused test and confirm** Export currently remains after the left-aligned controls instead of reaching the right edge.
- [x] **Step 3: Use a width-aware render layout.** Keep fixed spacing between groups, align only Export to the right when the entire toolbar fits, and move the final tool and Export together when wrapping is required. Keep each divider attached to a control group so it cannot wrap by itself.
- [x] **Step 4: Run the focused test at wide and narrow widths.**

```dart
if (allSectionsFit)
  alignLastSectionToRight();
else
  wrapAtFixedSpacing();
```

### Task 3: Share Class Selector Order Between Published and Draft Views

**Files:**
- Modify: `lib/features/scheduling/scheduling_page.dart`
- Modify: `lib/features/scheduling/scheduling_timetable.dart`
- Test: `test/features/scheduling/scheduling_reconciliation_ui_test.dart`

**Interfaces:**
- Add optional `classOrderIds` to `SchedulingTimetable`.
- `SchedulingPage` supplies IDs from the current draft snapshot even while displaying the published snapshot.
- The timetable sorts the displayed snapshot's class options by this ID order and keeps snapshot-specific labels.

- [x] **Step 1: Write the failing page widget test.** Use a draft snapshot ordered `[class-2, class-1]` and a published snapshot ordered `[class-1, class-2]`; inspect the class selector in both versions and assert the options appear `[class-2, class-1]` in each.
- [x] **Step 2: Run the focused test and confirm** the published selector initially follows its own snapshot order.
- [x] **Step 3: Pass the draft snapshot's class IDs** to `SchedulingTimetable`; sort the displayed snapshot's classes by those IDs, with unmatched published-only IDs placed after matched IDs in a deterministic fallback order.
- [x] **Step 4: Run the focused page test and confirm** both versions use the same class option order.

```dart
classOrderIds: (state.snapshot ?? snapshot)
    .classes
    .map((schoolClass) => schoolClass.id)
    .toList(growable: false),
```

## Final Verification

- Run `flutter test test/features/scheduling/scheduling_timetable_ui_test.dart`.
- Run the focused reconciliation page test added for published/draft selector order.
- Run `dart format --output=none --set-exit-if-changed` on the modified Dart files and `git diff --check`.
- Report hot-reload availability separately; the repository rule requires it only when Flutter/Dart MCP tools are connected.
