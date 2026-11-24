import assert from 'node:assert/strict';
import test from 'node:test';
import { createScheduleContext, previewPlacement, solveSchedule, type ScheduleData } from '../../src/domain/scheduling.ts';
import type { ScheduleItem } from '../../src/domain/models.ts';

const termId = 'term';
const data: ScheduleData = {
  term: { id: termId, title: '学期', academicYear: '2026', semesterLabel: '一', firstTeachingWeekStart: null, teachingWeekCount: 20, cycleMode: 'alternating', createdAt: 1 },
  stages: [{ id: 'stage', termId, name: '小学', sortOrder: 0 }],
  grades: [{ id: 'grade', stageId: 'stage', name: '三年级', sortOrder: 0 }],
  classes: ['a', 'b'].map((id, sortOrder) => ({ id, gradeId: 'grade', name: id === 'a' ? '三(1)班' : '三(2)班', sortOrder })),
  subjects: [{ id: 'math', termId, name: '数学', shortName: '数', sortOrder: 0 }],
  teachers: [{ id: 't', name: '张老师', shortName: '张', displayQualifier: '', sortOrder: 0 }],
  routines: [{ stageId: 'stage', teachingDays: [{ id: 'mon', stageId: 'stage', weekday: 1, isTeachingDay: true }],
    periodTypes: [{ id: 'am', stageId: 'stage', name: '上午', defaultLessonCount: 4, sortOrder: 0 }],
    lessonTimes: [], dailyOverrides: [] }],
  assignments: [], items: [], locks: [], freeSlots: [], subjectPresets: [], teacherPresets: [], teacherGroupPresets: [],
  teacherGroupMembers: [], requirements: [], pairings: [], lessonConstraints: [], rooms: [], roomAssignments: [],
  parallelLimits: [], conditions: [], supervision: [], visibleSupervision: [],
  preferences: { termId, strength: 'normal', progressConsistency: 'prefer', teacherDistribution: 'indifferent', lunchProtection: false, consecutivePolicy: 'preferSeparate', detectProgressConsistency: true },
};
function lesson(id: string, classId: string, weekMode: ScheduleItem['weekMode'], lessonIndex: number | null): ScheduleItem {
  return { id, termId, assignmentId: id, classId, teacherId: 't', subjectId: 'math', weekMode,
    combinedGroupId: null, meetingId: null, stageId: lessonIndex ? 'stage' : null, weekday: lessonIndex ? 1 : null,
    periodTypeId: lessonIndex ? 'am' : null, lessonIndex };
}

test('drop zones report the conflicting class and respect alternating weeks', () => {
  const source = lesson('a', 'a', 'odd', 1);
  const sameWeek = lesson('b', 'b', 'weekly', 2);
  const otherWeek = lesson('c', 'b', 'even', 3);
  const context = createScheduleContext({ ...data, items: [source, sameWeek, otherWeek] });
  const slots = context.slotsByStage.get('stage')!;
  assert.match(previewPlacement(context, source, slots[1]).reason, /张老师.*三\(2\)班.*数学/);
  assert.equal(previewPlacement(context, source, slots[2]).status, 'available');
});

test('swap previews both lessons without mutating the draft and blocks locked lessons', () => {
  const source = lesson('a', 'a', 'weekly', 1);
  const other = { ...lesson('b', 'a', 'weekly', 2), teacherId: 'other' };
  const input = { ...data, items: [source, other] };
  const context = createScheduleContext(input);
  const target = context.slotsByStage.get('stage')![1];
  const result = previewPlacement(context, source, target);
  assert.equal(result.status, 'swap');
  assert.deepEqual(result.items?.map((item) => item.lessonIndex), [2, 1]);
  assert.equal(source.lessonIndex, 1);
  const locked = createScheduleContext({ ...input, locks: [{ id: 'l', termId, scope: 'teacher', targetId: 'other' }] });
  assert.equal(previewPlacement(locked, source, target).status, 'blocked');
});

test('solver keeps the locked class and places demand in the other class', () => {
  const source = lesson('a', 'a', 'weekly', 1);
  const draft = { ...data, items: [source], locks: [{ id: 'l', termId, scope: 'class' as const, targetId: 'a' }],
    assignments: ['a', 'b'].map((id) => ({ id, termId, classId: id, teacherId: 't', subjectId: 'math',
      lessonCount: 1, sortOrder: 0, weekMode: 'weekly' as const, combinedLessonGroupId: null })) };
  const result = solveSchedule(draft, ['a', 'b']);
  assert.deepEqual(result.items.find((item) => item.id === 'a'), source);
  assert.ok(result.items.find((item) => item.classId === 'b')?.lessonIndex);
  assert.equal(result.items.length, 2);
});

test('paired alternating lessons are placed and moved together', () => {
  const input: ScheduleData = { ...data,
    pairings: [{ id: 'pair', classId: 'a', oddSubjectId: 'math', evenSubjectId: 'art' }],
    assignments: (['odd', 'even'] as const).map((weekMode) => ({ id: weekMode, termId, classId: 'a', teacherId: 't',
      subjectId: weekMode === 'odd' ? 'math' : 'art', lessonCount: 1, sortOrder: 0, weekMode, combinedLessonGroupId: null })),
  };
  const solved = solveSchedule(input, ['a']);
  assert.equal(solved.items[0].lessonIndex, solved.items[1].lessonIndex);
  assert.ok(solved.items[0].meetingId);
  const context = createScheduleContext({ ...input, items: solved.items });
  const target = context.slotsByStage.get('stage')!.find((slot) => slot.lessonIndex !== solved.items[0].lessonIndex)!;
  assert.deepEqual(previewPlacement(context, solved.items[0], target).items?.map((item) => item.lessonIndex), [target.lessonIndex, target.lessonIndex]);
});

test('room limits and school free slots provide distinct placement blockers', () => {
  const source = lesson('a', 'a', 'weekly', 1);
  const other = { ...lesson('b', 'b', 'weekly', 2), teacherId: 'another' };
  const context = createScheduleContext({ ...data, items: [source, other],
    rooms: [{ id: 'lab', name: '实验室', roomCount: 1, capacityPerRoom: 1, sortOrder: 0 }],
    roomAssignments: [{ id: 'room', termId, stageId: 'stage', subjectId: 'math', roomId: 'lab', scopeType: 'stage', scopeId: 'stage' }],
    freeSlots: [{ id: 'free', stageId: 'stage', scopeType: 'school', scopeId: '', weekday: 1, periodTypeId: 'am', lessonIndex: 3, label: '班会' }],
  });
  const slots = context.slotsByStage.get('stage')!;
  assert.match(previewPlacement(context, source, slots[1]).reason, /实验室.*容量/);
  assert.match(previewPlacement(context, source, slots[2]).reason, /免任课.*班会/);
});

test('moving a lesson into the pool cannot introduce a required period count violation', () => {
  const source = lesson('a', 'a', 'weekly', 1);
  const input: ScheduleData = { ...data, items: [source],
    assignments: [{ id: 'a', termId, classId: 'a', teacherId: 't', subjectId: 'math',
      lessonCount: 1, sortOrder: 0, weekMode: 'weekly', combinedLessonGroupId: null }],
    conditions: [{ id: 'minimum', termId, kind: 'periodLimit', name: '上午数学', targetKind: 'subject',
      targetId: 'math', otherId: null, periodTypeId: 'am', weekday: null, minCount: 1, maxCount: null, exactCount: null }],
  };
  const context = createScheduleContext(input);
  assert.match(previewPlacement(context, source, null).reason, /上午数学.*节数要求/);
});

test('automatic scheduling relocates a flexible lesson to recover the only valid slot for a constrained lesson', () => {
  const assignments = ['a-flexible', 'b-constrained'].map((id, index) => ({
    id, termId, classId: 'a', teacherId: index ? 'other' : 't', subjectId: index ? 'art' : 'math',
    weekMode: 'weekly' as const, lessonCount: 1, sortOrder: index, combinedLessonGroupId: null,
  }));
  const input: ScheduleData = { ...data, assignments,
    subjectPresets: [2, 3, 4].map((lessonIndex) => ({
      id: `forbid-${lessonIndex}`, stageId: 'stage', scopeType: 'class', scopeId: 'a', subjectId: 'art',
      weekday: 1, periodTypeId: 'am', lessonIndex, value: 'forbid',
    })),
  };
  const solved = solveSchedule(input, ['a']);
  assert.equal(solved.items.find((row) => row.subjectId === 'art')?.lessonIndex, 1);
  assert.ok((solved.items.find((row) => row.subjectId === 'math')?.lessonIndex ?? 0) > 1);
  assert.deepEqual(solved.issues, []);
  assert.deepEqual(solved.blockers, {});

  const existing = { ...solved.items.find((row) => row.subjectId === 'math')!, lessonIndex: 1 };
  for (const retainPlacements of [false, true]) {
    const result = solveSchedule({ ...input, items: [existing], locks: retainPlacements ? [] : [
      { id: 'lock', termId, scope: 'teacher', targetId: 't' },
    ] }, ['a'], retainPlacements);
    assert.deepEqual(result.items.find((row) => row.subjectId === 'math'), existing);
    assert.equal(result.items.find((row) => row.subjectId === 'art')?.lessonIndex, null);
  }
});

test('repair can move both the class occupant and a different teacher occupant', () => {
  const input: ScheduleData = { ...data,
    assignments: [
      { id: 'a-other-class', classId: 'b', teacherId: 't', subjectId: 'math' },
      { id: 'b-constrained', classId: 'a', teacherId: 't', subjectId: 'art' },
      { id: 'c-other-subject', classId: 'a', teacherId: 'other', subjectId: 'music' },
    ].map((assignment, sortOrder) => ({ ...assignment, sortOrder, termId, lessonCount: 1, weekMode: 'weekly', combinedLessonGroupId: null })),
    subjectPresets: [2, 3, 4].map((lessonIndex) => ({
      id: `forbid-${lessonIndex}`, stageId: 'stage', scopeType: 'class', scopeId: 'a', subjectId: 'art',
      weekday: 1, periodTypeId: 'am', lessonIndex, value: 'forbid',
    })),
  };
  const result = solveSchedule(input, ['a', 'b']);
  assert.ok(result.items.every((item) => item.weekday !== null));
  assert.equal(result.items.find((row) => row.subjectId === 'art')?.lessonIndex, 1);
  assert.ok(result.items.filter((row) => row.subjectId !== 'art').every((row) => row.lessonIndex! > 1));
  assert.deepEqual(result.issues, []);
});

test('teacher timetable can swap two lessons for different classes and keeps locked targets protected', () => {
  const first = lesson('a', 'a', 'weekly', 1);
  const second = lesson('b', 'b', 'weekly', 2);
  const input = { ...data, items: [first, second] };
  const context = createScheduleContext(input);
  const target = context.slotsByStage.get('stage')![1];
  const preview = previewPlacement(context, first, target, true, true, second);
  assert.equal(preview.status, 'swap');
  assert.deepEqual(preview.items?.map(({ id, lessonIndex }) => [id, lessonIndex]), [['a', 2], ['b', 1]]);
  const locked = createScheduleContext({ ...input, locks: [{ id: 'b', termId, scope: 'class', targetId: 'b' }] });
  assert.match(previewPlacement(locked, first, target, true, true, second).reason, /锁定/);
});

test('supplemental scheduling moves an unlocked lesson to period one to place PE without violating its first-period ban', () => {
  const existing = [lesson('a', 'a', 'weekly', 2), { ...lesson('pe', 'a', 'weekly', null), subjectId: 'pe', teacherId: 'coach' }];
  const input: ScheduleData = { ...data, items: existing,
    assignments: existing.map((row) => ({
      id: row.id, termId, teacherId: row.teacherId, subjectId: row.subjectId, classId: row.classId,
      weekMode: row.weekMode, lessonCount: 1, sortOrder: 0, combinedLessonGroupId: null,
    })),
    routines: data.routines.map((routine) => ({
      ...routine, periodTypes: routine.periodTypes.map((period) => ({ ...period, defaultLessonCount: 2 })),
    })),
    subjectPresets: [{ id: 'no-pe-first-period', subjectId: 'pe', scopeType: 'class', scopeId: 'a', stageId: 'stage',
      weekday: 1, periodTypeId: 'am', lessonIndex: 1, value: 'forbid' }],
  };
  const result = solveSchedule(input, ['a'], true, undefined, 0, true);
  assert.deepEqual(result.items.map((row) => [row.id, row.lessonIndex]), [['a', 1], ['pe', 2]]);
  assert.deepEqual(result.issues, []);
  assert.equal(solveSchedule(input, ['a']).items.find((row) => row.id === 'pe')?.lessonIndex, 2);
  const locked = solveSchedule({ ...input, locks: [{ id: 'lock', termId, scope: 'teacher', targetId: 't' }] }, ['a'], true, undefined, 0, true);
  assert.deepEqual(locked.items, existing);
  assert.equal(solveSchedule(input, ['a'], true).items.find((row) => row.id === 'pe')?.lessonIndex, null);
});
