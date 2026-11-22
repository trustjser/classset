import assert from 'node:assert/strict';
import test from 'node:test';
import type { ClassGroup, GradeGroup, StageRoutine, SubjectRequirement } from '../../src/domain/models.ts';
import {
  applyGradeInput, capacityForClass, makeRequirementRows, parseLessonInput,
  parseSubjectImportText, requirementKey, summarizeGradeCapacity, valuesForClass,
} from '../../src/features/subjects/subjectLogic.ts';

const classes: ClassGroup[] = [
  { id: 'c1', gradeId: 'g1', name: '一(1)班', sortOrder: 0 },
  { id: 'c2', gradeId: 'g1', name: '一(2)班', sortOrder: 1 },
];
const grade: GradeGroup = { id: 'g1', stageId: 's1', name: '一年级', sortOrder: 0 };

test('grade default and per-class override resolve independently', () => {
  const rows: SubjectRequirement[] = [
    { id: 'default', subjectId: 'math', gradeId: 'g1', classId: null, weekMode: 'weekly', lessonCount: 4 },
    { id: 'override', subjectId: 'math', gradeId: 'g1', classId: 'c2', weekMode: 'weekly', lessonCount: 5 },
  ];
  assert.equal(valuesForClass(rows, 'math', classes[0]).weekly, 4);
  assert.equal(valuesForClass(rows, 'math', classes[1]).weekly, 5);
});

test('single value applies to all classes; per-class input follows class order', () => {
  const uniform = applyGradeInput({}, 'math', classes, '3|1|2', true);
  assert.equal(uniform?.[requirementKey('math', 'c2')].even, 2);
  const separate = applyGradeInput(uniform ?? {}, 'math', classes, '4,5', false);
  assert.equal(separate?.[requirementKey('math', 'c1')].weekly, 4);
  assert.equal(separate?.[requirementKey('math', 'c2')].weekly, 5);
  assert.equal(parseLessonInput('3|1|2', false), null);
  assert.equal(applyGradeInput({}, 'math', classes, '1,2,3', false), null);
  assert.equal(parseLessonInput('-1', true), null);
});

test('requirement rows retain existing IDs and omit cleared values', () => {
  const old: SubjectRequirement[] = [
    { id: 'known', subjectId: 'math', gradeId: 'g1', classId: 'c1', weekMode: 'weekly', lessonCount: 3 },
  ];
  const values = {
    [requirementKey('math', 'c1')]: { weekly: 4, odd: 0, even: 0 },
    [requirementKey('math', 'c2')]: { weekly: 0, odd: 1, even: 0 },
  };
  const rows = makeRequirementRows(['math'], classes, values, old);
  assert.equal(rows.length, 2);
  assert.equal(rows.find((row) => row.classId === 'c1')?.id, 'known');
  assert.equal(rows.find((row) => row.classId === 'c2')?.weekMode, 'odd');
});

test('capacity deducts inherited free slots once and flags the pressured class', () => {
  const routine: StageRoutine = {
    stageId: 's1', teachingDays: [1, 2].map((weekday) => ({ id: `d${weekday}`, stageId: 's1', weekday, isTeachingDay: true })),
    periodTypes: [{ id: 'am', stageId: 's1', name: '上午', defaultLessonCount: 2, sortOrder: 0 }],
    dailyOverrides: [], lessonTimes: [],
  };
  const freeSlots = [
    { id: 'stage', scopeType: 'stage' as const, scopeId: 's1', stageId: 's1', periodTypeId: 'am', weekday: 1, lessonIndex: 1, label: '无课' },
    { id: 'class', scopeType: 'class' as const, scopeId: 'c1', stageId: 's1', periodTypeId: 'am', weekday: 1, lessonIndex: 1, label: '无课' },
  ];
  assert.equal(capacityForClass(routine, freeSlots, 'term', grade, classes[0]), 3);
  const values = {
    [requirementKey('math', 'c1')]: { weekly: 3, odd: 1, even: 0 },
    [requirementKey('math', 'c2')]: { weekly: 2, odd: 0, even: 0 },
  };
  const summary = summarizeGradeCapacity(grade, classes, ['math'], values, routine, freeSlots, 'term');
  assert.equal(summary?.className, '一(1)班');
  assert.equal(summary?.excess, 1);
});

test('Excel TSV import validates names and class count before applying any row', () => {
  const stage = { id: 's1', termId: 'term', name: '小学部', sortOrder: 0 };
  const subject = { id: 'math', termId: 'term', name: '数学', shortName: '数', sortOrder: 0 };
  const header = '学段\t年级\t科目\t节数\n';
  const valid = parseSubjectImportText(header + '小学部\t一年级\t数学\t4,5', [stage], [grade], classes, [subject], false);
  assert.deepEqual(valid.errors, []);
  assert.equal(valid.values[requirementKey('math', 'c2')].weekly, 5);
  const invalid = parseSubjectImportText(header + '小学部\t一年级\t数学\t4,5\n小学部\t一年级\t数学\t3',
    [stage], [grade], classes, [subject], false);
  assert.equal(Object.keys(invalid.values).length, 0);
  assert.match(invalid.errors[0], /重复/);
});
