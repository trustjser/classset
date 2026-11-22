# Tauri Workbench First Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the prototype dashboard with a guided, responsive scheduling workbench that shows real preparation progress and directs users to the next available task.

**Architecture:** Keep readiness derivation in a pure TypeScript model, render it in a focused React workbench page, and let the app shell own navigation and platform context. Keep Schema v19 unchanged. The draft did not build because existing UI/store actions called missing repository methods, so restore those operations and derive progress from actual records as a build and behavior prerequisite.

**Tech Stack:** React 18, TypeScript, Vite, Tailwind CSS 3, CSS container queries, Node 22 `node:test`.

**Spec:** `docs/tauri-web.md` sections 2.1 and 3.3; `design/DESIGN.md` sections 1, 5, 8, and 10.

## Global Constraints

- Desktop Tauri and browser Web use the same React UI and repository state.
- Keep SQLite Schema v19 unchanged; limit repository changes to the existing UI actions and truthful workbench readiness.
- Use the semantic colors and three palette variants already defined in `src/styles/theme.css`.
- Keep the dashboard focused on preparation status; do not expose debug switches, schema table dumps, or subject-color previews as product content.
- Use a short route entrance transition and disable it under `prefers-reduced-motion: reduce`.
- Preserve the existing term, class, and adjustment-record screens; make not-yet-migrated destinations explicit and non-editable.

---

### Task 1: Derive the next workbench task

**Files:**
- Create: `src/features/workbench/workbenchModel.ts`
- Test: `test/web/workbench_model.test.ts`

**Interfaces:**
- Consumes: `AppSection` and `WorkbenchSummary` from `src/domain/models.ts`.
- Produces: `getWorkbenchProgress(hasTerm, summary)` returning `steps`, `completeCount`, `totalCount`, `isLoading`, and `nextSection`.

- [x] **Step 1: Write the failing behavior test**

Test these behaviors with literal expected values:

```typescript
import assert from 'node:assert/strict';
import test from 'node:test';
import type { WorkbenchSummary } from '../../src/domain/models.ts';

async function getProgress(hasTerm: boolean, summary: WorkbenchSummary | null) {
  const model = await import('../../src/features/workbench/workbenchModel.ts').catch(
    () => null
  );
  assert.ok(model, 'workbench progress model should be available');
  return model.getWorkbenchProgress(hasTerm, summary);
}

test('routes an empty school to term setup', async () => {
  const progress = await getProgress(false, null);
  assert.equal(progress.nextSection, 'terms');
  assert.equal(progress.completeCount, 0);
  assert.equal(progress.totalCount, 6);
});

test('routes a prepared school to the first incomplete step', async () => {
  const progress = await getProgress(true, {
    termId: 'term-1', stageCount: 1, gradeCount: 6, classCount: 12,
    subjectCount: 8, teacherCount: 24, publicRoomCount: 0,
    stagesDone: true, routineDone: true, subjectLessonsReady: false,
    teacherAssignmentsReady: false, hasSchedule: false,
  });
  assert.equal(progress.nextSection, 'subjects');
  assert.equal(progress.completeCount, 3);
});

test('does not invent a next task while the active term summary is loading', async () => {
  const progress = await getProgress(true, null);
  assert.equal(progress.isLoading, true);
  assert.equal(progress.nextSection, null);
});

test('reports completion after all six preparation steps are ready', async () => {
  const progress = await getProgress(true, {
    termId: 'term-1', stageCount: 1, gradeCount: 6, classCount: 12,
    subjectCount: 8, teacherCount: 24, publicRoomCount: 0,
    stagesDone: true, routineDone: true, subjectLessonsReady: true,
    teacherAssignmentsReady: true, hasSchedule: true,
  });
  assert.equal(progress.nextSection, null);
  assert.equal(progress.completeCount, 6);
});
```

- [x] **Step 2: Run the test and confirm the model is missing**

Run: `node --experimental-strip-types --test test/web/workbench_model.test.ts`

Expected: FAIL because `workbenchModel.ts` does not exist yet.

- [x] **Step 3: Implement the pure progress model**

Represent the ordered steps as term, classes, routines, subjects, teachers, and scheduling. Count only completed business steps. Return `terms` when there is no active term, return `null` while a term summary is loading, and otherwise return the first incomplete section.

- [x] **Step 4: Run the focused model test**

Run: `node --experimental-strip-types --test test/web/workbench_model.test.ts`

Expected: PASS for all four readiness cases.

---

### Task 2: Build the guided workbench and wire the app shell

**Files:**
- Create: `src/features/workbench/WorkbenchPage.tsx`
- Create: `src/features/workbench/workbench.css`
- Modify: `src/components/AppShell.tsx`
- Modify: `src/store/useAppStore.ts`
- Modify: `src/repository/schoolRepository.ts` (restore wired term/class actions and use stored readiness data)
- Modify: `src/styles/theme.css`

**Interfaces:**
- Consumes: `getWorkbenchProgress`, `getNavSectionAvailability`, current term, school name, and active workbench summary.
- Produces: a dashboard with an accessible progress indicator, ordered preparation list, an actionable next step, responsive single-column fallback, and a reduced-motion-safe route transition.

- [x] **Step 1: Render the workbench as the initial section**

Change the initial `selectedSection` in the Zustand store to `workbench`; keep later user-selected sections in memory as before.

- [x] **Step 2: Replace the diagnostic dashboard**

Render real readiness rows and navigation actions. Remove the manual cascade switches, subject-color gallery, and Schema v19 table list from the shell. Keep the existing terms, classes, and adjustment-record screens; show a clear read-only migration state on routes that do not yet have a migrated page.

- [x] **Step 3: Add motion and responsive rules**

Use an 180 ms opacity and 4 px vertical entrance for the active page. Use CSS container queries so the workbench changes from two columns to one based on the content area, and disable route animation when the user requests reduced motion.

- [x] **Step 4: Build the frontend**

Run: `npm run build`

Expected: TypeScript and Vite build complete without errors.

- [x] **Step 5: Review changed files and report scope**

Confirm no database schema or migration changes. Keep repository edits limited to the existing clone/delete actions and workbench readiness queries. Report the page routes that remain pending migration without describing the larger Tauri rewrite as complete.

### Verification

- `node --experimental-strip-types --test test/web/workbench_model.test.ts` — 4 tests passed.
- `npm run build` — TypeScript and Vite production build passed.
- `git diff --check` — passed.
