import { describe, it, expect } from 'vitest';
import {
  firstSubjectCharacter,
  buildSubjectDraftInputs,
} from '@/features/subjects/commonSubjects';
import {
  valuesForClass,
  parseLessonInput,
  formatLessonValues,
  formatGradeCell,
  applyGradeInput,
  makeRequirementRows,
  capacityForClass,
  summarizeGradeCapacity,
  parseSubjectImportText,
  requirementKey,
} from '@/features/subjects/subjectLogic';
import {
  resolveConstraintField,
  validateConstraintRanges,
} from '@/features/subjects/subjectAdvancedLogic';
import {
  matrixCellKey,
  rectangleKeys,
  applyMatrixCells,
  pasteMatrixGrid,
  copyMatrixText,
} from '@/features/subjects/subjectMatrixActions';
import { buildSubjectWorkbook, parseSubjectWorkbook } from '@/features/subjects/subjectWorkbook';
import {
  combinedLessonCandidates,
  remainingCourses,
  assignmentError,
  resolveTeacherPreset,
  teacherWeeklyLoad,
} from '@/features/teachers/teacherLogic';
import {
  buildTeachersWorkbook,
  parseTeachersWorkbook,
  buildAssignmentsWorkbook,
  parseAssignmentsWorkbook,
} from '@/features/teachers/teacherWorkbook';
import type {
  ClassGroup,
  FreeSlot,
  GradeGroup,
  SchoolStage,
  StageRoutine,
  Subject,
  SubjectLessonConstraint,
  SubjectRequirement,
  Teacher,
  TeacherAssignment,
} from '@/domain/models';

const stage: SchoolStage = { id: 'st1', termId: 't1', name: '初中部', sortOrder: 0 };
const grade: GradeGroup = { id: 'g1', stageId: 'st1', name: '七年级', sortOrder: 0 };
const classes: ClassGroup[] = [
  { id: 'c1', gradeId: 'g1', name: '七(1)班', sortOrder: 0 },
  { id: 'c2', gradeId: 'g1', name: '七(2)班', sortOrder: 1 },
];
const subjects: Subject[] = [
  { id: 'sub1', termId: 't1', name: '语文', shortName: '语', sortOrder: 0 },
  { id: 'sub2', termId: 't1', name: '数学', shortName: '数', sortOrder: 1 },
];

describe('features/subjects/commonSubjects.ts', () => {
  it('校验手动科目名称、简称、重名与常用科目冲突', () => {
    expect(firstSubjectCharacter(' 道德与法治 ')).toBe('道');
    expect(firstSubjectCharacter('   ')).toBe('');

    expect(
      buildSubjectDraftInputs({
        isNew: true,
        name: '',
        shortName: '',
        selectedCommonSubjects: [],
        existingNames: [],
      })
    ).toEqual({ subjects: [], error: '请输入科目全称' });

    expect(
      buildSubjectDraftInputs({
        isNew: true,
        name: '语文',
        shortName: '语',
        selectedCommonSubjects: [],
        existingNames: ['语文'],
      }).error
    ).toBe('已存在同名科目');

    expect(
      buildSubjectDraftInputs({
        isNew: true,
        name: '物理',
        shortName: '物',
        selectedCommonSubjects: ['物理'],
        existingNames: [],
      }).error
    ).toBe('该科目已在常用科目中选中');

    expect(
      buildSubjectDraftInputs({
        isNew: true,
        name: '',
        shortName: '',
        selectedCommonSubjects: ['数学', '语文'],
        existingNames: [],
      })
    ).toEqual({
      subjects: [
        { name: '语文', shortName: '语' },
        { name: '数学', shortName: '数' },
      ],
      error: null,
    });
  });
});

describe('features/subjects/subjectLogic.ts', () => {
  it('按年级默认与班级覆盖合并节数需求', () => {
    const reqs: SubjectRequirement[] = [
      { id: 'r1', subjectId: 'sub1', gradeId: 'g1', classId: null, weekMode: 'weekly', lessonCount: 5 },
      { id: 'r2', subjectId: 'sub1', gradeId: 'g1', classId: 'c2', weekMode: 'weekly', lessonCount: 6 },
    ];
    expect(valuesForClass(reqs, 'sub1', classes[0])).toEqual({ weekly: 5, odd: 0, even: 0 });
    expect(valuesForClass(reqs, 'sub1', classes[1])).toEqual({ weekly: 6, odd: 0, even: 0 });
  });

  it('解析常规与单双周节数输入，拒绝负数与非法格式', () => {
    expect(parseLessonInput('  ', false)).toEqual([]);
    expect(parseLessonInput('3, 4', false)).toEqual([
      { weekly: 3, odd: 0, even: 0 },
      { weekly: 4, odd: 0, even: 0 },
    ]);
    expect(parseLessonInput('2|1|1', false)).toBeNull();
    expect(parseLessonInput('2|1|1', true)).toEqual([{ weekly: 2, odd: 1, even: 1 }]);
    expect(parseLessonInput('-1', false)).toBeNull();
    expect(parseLessonInput('3.5', false)).toBeNull();
  });

  it('格式化年级单元格并支持批量应用与生成需求行', () => {
    expect(formatLessonValues({ weekly: 3, odd: 0, even: 0 })).toBe('3');
    expect(formatLessonValues({ weekly: 2, odd: 1, even: 0 })).toBe('2|1|0');
    expect(formatGradeCell([])).toBe('—');
    expect(
      formatGradeCell([
        { weekly: 4, odd: 0, even: 0 },
        { weekly: 4, odd: 0, even: 0 },
      ])
    ).toBe('4');
    expect(
      formatGradeCell([
        { weekly: 4, odd: 0, even: 0 },
        { weekly: 5, odd: 0, even: 0 },
      ])
    ).toBe('各班不同');

    const applied = applyGradeInput({}, 'sub1', classes, '5,6', false);
    expect(applied?.[requirementKey('sub1', 'c1')]).toEqual({ weekly: 5, odd: 0, even: 0 });
    expect(applied?.[requirementKey('sub1', 'c2')]).toEqual({ weekly: 6, odd: 0, even: 0 });
    // 班级数不匹配时返回 null
    expect(applyGradeInput({}, 'sub1', classes, '5,6,7', false)).toBeNull();

    const rows = makeRequirementRows(['sub1'], classes, applied!, []);
    expect(rows).toHaveLength(2);
    expect(rows.map((r) => r.lessonCount)).toEqual([5, 6]);
  });

  it('计算班级容量、超容情况并解析导入文本', () => {
    const routine: StageRoutine = {
      stageId: 'st1',
      teachingDays: [
        { id: 'd1', stageId: 'st1', weekday: 1, isTeachingDay: true },
        { id: 'd2', stageId: 'st1', weekday: 2, isTeachingDay: true },
      ],
      periodTypes: [{ id: 'pt1', stageId: 'st1', name: '上午', defaultLessonCount: 4, sortOrder: 0 }],
      dailyOverrides: [{ id: 'ov1', stageId: 'st1', periodTypeId: 'pt1', weekday: 2, lessonCount: 3 }],
      lessonTimes: [],
    };
    const freeSlots: FreeSlot[] = [
      { id: 'fs1', scopeType: 'class', scopeId: 'c1', stageId: 'st1', periodTypeId: 'pt1', weekday: 1, lessonIndex: 1, label: '班会' },
      { id: 'fs2', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', periodTypeId: 'pt1', weekday: 1, lessonIndex: 1, label: '重复同节' },
    ];
    expect(capacityForClass(routine, freeSlots, 't1', grade, classes[0])).toBe(6); // 4 + 3 - 1 (班级+学段同节去重)
    expect(capacityForClass(routine, freeSlots, 't1', grade, classes[1])).toBe(6); // 4 + 3 - 1 (受学段级 fs2 影响)

    const cap = summarizeGradeCapacity(
      grade,
      classes,
      ['sub1'],
      { [requirementKey('sub1', 'c1')]: { weekly: 8, odd: 0, even: 0 } },
      routine,
      freeSlots,
      't1'
    );
    expect(cap).toMatchObject({ className: '七(1)班', weekly: 8, available: 6, excess: 2 });

    const importOk = parseSubjectImportText(
      '学段\t年级\t科目\t节数\n初中部\t七年级\t语文\t5,4',
      [stage],
      [grade],
      classes,
      subjects,
      false
    );
    expect(importOk.errors).toEqual([]);
    expect(importOk.values[requirementKey('sub1', 'c1')]).toEqual({ weekly: 5, odd: 0, even: 0 });

    const importBad = parseSubjectImportText(
      '学段\t年级\t科目\n初中部\t七年级\t语文',
      [stage],
      [grade],
      classes,
      subjects,
      false
    );
    expect(importBad.errors).toHaveLength(1);
  });
});

describe('features/subjects/subjectAdvancedLogic.ts & subjectMatrixActions.ts', () => {
  it('按 班级 > 年级 > 学段 > 学校 与 指定星期 > 通用星期 优先级解析约束字段并校验上下限', () => {
    const rows: SubjectLessonConstraint[] = [
      {
        id: 'lc1',
        subjectId: 'sub1',
        scopeType: 'stage',
        scopeId: 'st1',
        stageId: 'st1',
        weekday: null,
        minimumDailyLessons: 1,
        maximumDailyLessons: 2,
        minimumDailyConsecutivePairs: null,
        maximumDailyConsecutivePairs: null,
        minimumWeeklyConsecutivePairs: null,
        maximumWeeklyConsecutivePairs: null,
      },
      {
        id: 'lc2',
        subjectId: 'sub1',
        scopeType: 'class',
        scopeId: 'c1',
        stageId: 'st1',
        weekday: 1,
        minimumDailyLessons: 3, // 超过学段上限 2，产生冲突
        maximumDailyLessons: null,
        minimumDailyConsecutivePairs: null,
        maximumDailyConsecutivePairs: null,
        minimumWeeklyConsecutivePairs: null,
        maximumWeeklyConsecutivePairs: null,
      },
    ];
    expect(
      resolveConstraintField(rows, classes, 't1', 'class', 'c1', 'st1', 1, 'minimumDailyLessons')
    ).toBe(3);
    expect(
      validateConstraintRanges(rows, [stage], [grade], classes, { st1: [1] }, 't1')
    ).toBe('七(1)班周1的每日课节上下限冲突');
  });

  it('矩阵矩形选择、批量填充、粘贴与复制逻辑正确', () => {
    const keys = rectangleKeys(subjects, [grade], { row: 0, column: 0 }, { row: 1, column: 0 });
    expect(keys).toEqual([matrixCellKey('sub1', 'g1'), matrixCellKey('sub2', 'g1')]);

    const applied = applyMatrixCells(keys, '4', classes, {}, false);
    expect(applied.error).toBeNull();
    expect(applied.changedKeys).toHaveLength(4);

    const pasted = pasteMatrixGrid('5\n6', keys[0], [keys[0]], subjects, [grade], classes, {}, false);
    expect(pasted.error).toBeNull();
    expect(pasted.values[requirementKey('sub1', 'c1')].weekly).toBe(5);
    expect(pasted.values[requirementKey('sub2', 'c1')].weekly).toBe(6);

    const text = copyMatrixText(keys, subjects, [grade], classes, pasted.values);
    expect(text).toBe('5\n6');
  });
});

describe('features/subjects/subjectWorkbook.ts & teachers/teacherWorkbook.ts', () => {
  it('科目工作簿可往返导出并解析', async () => {
    const bytes = await buildSubjectWorkbook({
      stages: [stage],
      grades: [grade],
      classes,
      subjects,
      values: { [requirementKey('sub1', 'c1')]: { weekly: 4, odd: 0, even: 0 } },
      includeExisting: true,
    });
    const parsed = await parseSubjectWorkbook(bytes, [stage], [grade], classes, subjects, false);
    expect(parsed.errors).toEqual([]);
    expect(parsed.values[requirementKey('sub1', 'c1')]).toEqual({ weekly: 4, odd: 0, even: 0 });
  });

  it('教师与任课工作簿可往返导出并解析，且对非法输入报错', async () => {
    const teachers: Teacher[] = [
      { id: 'tea1', name: '张老师', shortName: '张', displayQualifier: '', sortOrder: 0, subjectIds: ['sub1'] },
    ];
    const assignments: TeacherAssignment[] = [
      { id: 'a1', termId: 't1', teacherId: 'tea1', subjectId: 'sub1', classId: 'c1', weekMode: 'weekly', lessonCount: 5, sortOrder: 0, combinedLessonGroupId: null },
    ];

    const tBytes = await buildTeachersWorkbook(teachers, [], [], subjects);
    const parsedTeachers = await parseTeachersWorkbook(tBytes);
    expect(parsedTeachers).toEqual([
      { name: '张老师', shortName: '张', groups: [], subjects: ['语文'] },
    ]);

    const aBytes = await buildAssignmentsWorkbook([stage], [grade], classes, subjects, teachers, assignments);
    const parsedAssignments = await parseAssignmentsWorkbook(aBytes);
    expect(parsedAssignments).toEqual([
      {
        stage: '初中部',
        grade: '七年级',
        schoolClass: '七(1)班',
        subject: '语文',
        teacher: '张老师',
        weekMode: 'weekly',
        lessonCount: 5,
      },
    ]);

    await expect(parseTeachersWorkbook(new Uint8Array([1, 2, 3]))).rejects.toThrow();
  });
});

describe('features/teachers/teacherLogic.ts', () => {
  const reqs: SubjectRequirement[] = [
    { id: 'r1', subjectId: 'sub1', gradeId: 'g1', classId: null, weekMode: 'weekly', lessonCount: 5 },
  ];

  it('识别合班候选与待分配课程', () => {
    const assignments: TeacherAssignment[] = [
      { id: 'a1', termId: 't1', teacherId: 'tea1', subjectId: 'sub1', classId: 'c1', weekMode: 'weekly', lessonCount: 3, sortOrder: 0, combinedLessonGroupId: null },
      { id: 'a2', termId: 't1', teacherId: 'tea1', subjectId: 'sub1', classId: 'c2', weekMode: 'weekly', lessonCount: 3, sortOrder: 1, combinedLessonGroupId: null },
    ];
    const candidates = combinedLessonCandidates(assignments, 'tea1');
    expect(candidates).toHaveLength(1);
    expect(candidates[0].rows).toHaveLength(2);

    const remaining = remainingCourses(classes, [subjects[0]], reqs, assignments);
    expect(remaining).toEqual([
      { classId: 'c1', subjectId: 'sub1', weekMode: 'weekly', remainingLessons: 2 },
      { classId: 'c2', subjectId: 'sub1', weekMode: 'weekly', remainingLessons: 2 },
    ]);
  });

  it('校验任课超额与教师周课时统计（含单双周与合班去重）', () => {
    const existing: TeacherAssignment[] = [
      { id: 'a1', termId: 't1', teacherId: 'tea1', subjectId: 'sub1', classId: 'c1', weekMode: 'weekly', lessonCount: 3, sortOrder: 0, combinedLessonGroupId: null },
    ];
    const invalidOver: TeacherAssignment[] = [
      { id: 'a2', termId: 't1', teacherId: 'tea2', subjectId: 'sub1', classId: 'c1', weekMode: 'weekly', lessonCount: 3, sortOrder: 1, combinedLessonGroupId: null },
    ];
    expect(assignmentError(invalidOver, classes, subjects, reqs, existing)).toContain('超过科目节数需求');

    const load = teacherWeeklyLoad([
      { id: 'a1', termId: 't1', teacherId: 'tea1', subjectId: 'sub1', classId: 'c1', weekMode: 'weekly', lessonCount: 3, sortOrder: 0, combinedLessonGroupId: 'grp1' },
      { id: 'a2', termId: 't1', teacherId: 'tea1', subjectId: 'sub1', classId: 'c2', weekMode: 'weekly', lessonCount: 3, sortOrder: 1, combinedLessonGroupId: 'grp1' },
      { id: 'a3', termId: 't1', teacherId: 'tea1', subjectId: 'sub2', classId: 'c1', weekMode: 'odd', lessonCount: 1, sortOrder: 2, combinedLessonGroupId: null },
    ]);
    expect(load).toBe(3.5);
  });

  it('正确解析个人与教研组教师预设冲突', () => {
    expect(
      resolveTeacherPreset(undefined, [
        { id: 'gp1', groupId: 'g1', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1, weekMode: 'weekly', value: 'prefer' },
        { id: 'gp2', groupId: 'g2', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1, weekMode: 'weekly', value: 'forbid' },
      ])
    ).toBe('conflict');

    expect(
      resolveTeacherPreset(
        { id: 'tp1', termId: 't1', teacherId: 'tea1', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1, weekMode: 'weekly', value: 'must' },
        []
      )
    ).toBe('must');
  });
});
