import { describe, it, expect } from 'vitest';
import {
  sameCell,
  hasClockTime,
  overlaps,
  poolIdForPost,
  teachersForPost,
  poolNameForPost,
  allTeacherIdsInDraft,
  defaultSupervisionMatchingPreferences,
  SUPERVISION_BASE_POOL_ID,
  type SupervisionDraft,
  type SupervisionPost,
} from '@/domain/supervision';
import { SupervisionMatching } from '@/domain/supervisionMatching';
import {
  isSupervisionAllowedInSlot,
  resolveFreeSlotForClass,
  effectiveLessonCount,
  postErrors,
  occurrences,
} from '@/domain/supervisionValidation';
import { SupervisionAllocator } from '@/domain/supervisionAllocator';
import { SupervisionDraftHistory } from '@/domain/supervisionHistory';
import { defaultSchedulePreferences, type ScheduleData } from '@/domain/scheduling';

function makeSnapshot(): ScheduleData {
  const termId = 't1';
  return {
    term: {
      id: termId,
      title: '2026 秋',
      academicYear: '2026-2027',
      semesterLabel: '第一学期',
      firstTeachingWeekStart: '2026-09-01',
      teachingWeekCount: 20,
      cycleMode: 'every_week',
      createdAt: 1000,
    },
    stages: [{ id: 'st1', termId, name: '小学部', sortOrder: 0 }],
    grades: [{ id: 'g1', stageId: 'st1', name: '一年级', sortOrder: 0 }],
    classes: [
      { id: 'c1', gradeId: 'g1', name: '一(1)班', sortOrder: 0 },
      { id: 'c2', gradeId: 'g1', name: '一(2)班', sortOrder: 1 },
    ],
    routines: [
      {
        stageId: 'st1',
        teachingDays: [{ id: 'd1', stageId: 'st1', weekday: 1, isTeachingDay: true }],
        periodTypes: [{ id: 'pt1', stageId: 'st1', name: '下午', defaultLessonCount: 2, sortOrder: 0 }],
        dailyOverrides: [],
        lessonTimes: [
          { id: 'lt1', periodTypeId: 'pt1', lessonIndex: 1, label: '第1节', startMinute: 900, endMinute: 940 },
          { id: 'lt2', periodTypeId: 'pt1', lessonIndex: 2, label: '第2节', startMinute: 950, endMinute: 990 },
        ],
      },
    ],
    subjects: [{ id: 'sub1', termId, name: '语文', shortName: '语', sortOrder: 0 }],
    teachers: [
      { id: 'tea1', name: '王老师', shortName: '王', displayQualifier: '', sortOrder: 0 },
      { id: 'tea2', name: '赵老师', shortName: '赵', displayQualifier: '', sortOrder: 1 },
    ],
    assignments: [
      { id: 'a1', termId, teacherId: 'tea1', subjectId: 'sub1', classId: 'c1', weekMode: 'weekly', lessonCount: 4, sortOrder: 0, combinedLessonGroupId: null },
    ],
    requirements: [],
    items: [],
    locks: [],
    freeSlots: [],
    subjectPresets: [],
    teacherPresets: [],
    teacherGroupPresets: [],
    teacherGroupMembers: [],
    pairings: [],
    lessonConstraints: [],
    rooms: [],
    roomAssignments: [],
    parallelLimits: [],
    conditions: [],
    preferences: defaultSchedulePreferences(termId),
    supervision: [],
    visibleSupervision: [],
  };
}

function makeDraft(posts: SupervisionPost[]): SupervisionDraft {
  return {
    termId: 't1',
    revision: 1,
    posts,
    teacherIds: ['tea1', 'tea2'],
    teacherPools: [{ id: 'pool1', name: '语文组', teacherIds: ['tea1'] }],
    defaultTeacherPoolId: SUPERVISION_BASE_POOL_ID,
    matchingPreferences: defaultSupervisionMatchingPreferences,
    rules: {},
    assignments: {},
    manualPostIds: [],
  };
}

describe('domain/supervision.ts', () => {
  it('判断格子相等、时钟时间存在与时段重叠', () => {
    const a = { stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1, startMinute: 900, endMinute: 940 };
    const b = { stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1 };
    expect(sameCell(a, b)).toBe(true);
    expect(hasClockTime(a)).toBe(true);
    expect(hasClockTime(b)).toBe(false);
    expect(overlaps(a, { stageId: 'st2', weekday: 1, periodTypeId: 'pt1', lessonIndex: 2, startMinute: 920, endMinute: 960 })).toBe(true);
    expect(overlaps(a, { stageId: 'st2', weekday: 2, periodTypeId: 'pt1', lessonIndex: 1, startMinute: 900, endMinute: 940 })).toBe(false);
  });

  it('解析岗位候选池与教师集合', () => {
    const post: SupervisionPost = {
      id: 'p1', kind: 'afterSchool', name: '托管', groupName: '', location: '',
      stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndices: [1], classIds: ['c1'],
      teacherPoolId: 'pool1',
    };
    const draft = makeDraft([post]);
    expect(poolIdForPost(draft, post)).toBe('pool1');
    expect([...teachersForPost(draft, post)]).toEqual(['tea1']);
    expect(poolNameForPost(draft, post)).toBe('语文组');
    expect(allTeacherIdsInDraft(draft).size).toBe(2);
  });
});

describe('domain/supervisionMatching.ts & supervisionValidation.ts', () => {
  it('SupervisionMatching 正确计算任教班级/年级/学科匹配度并排序', () => {
    const snapshot = makeSnapshot();
    const post: SupervisionPost = {
      id: 'p1', kind: 'afterSchool', name: '课后服务', groupName: '', location: '',
      stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndices: [1], classIds: ['c1'],
      targetSubjectIds: ['sub1'],
    };
    const draft = makeDraft([post]);
    const matching = new SupervisionMatching(snapshot);

    expect(matching.count('classTeacher', post, 'tea1')).toBe(1);
    expect(matching.count('classTeacher', post, 'tea2')).toBe(0);
    expect(matching.complete('gradeTeacher', post, 'tea1')).toBe(true);
    expect(matching.reasons(post, 'tea1')).toEqual(['任教本班', '任教本年级', '任教语文']);
    expect(matching.compare(draft, post, 'tea1', 'tea2')).toBeLessThan(0);
  });

  it('postErrors 校验合班必填字段、不连续节次、免任课以及正课冲突', () => {
    const snapshot = makeSnapshot();
    snapshot.freeSlots = [
      { id: 'fs1', scopeType: 'class', scopeId: 'c1', stageId: 'st1', periodTypeId: 'pt1', weekday: 1, lessonIndex: 1, label: '无课' },
    ];
    snapshot.items = [
      {
        id: 'i1', termId: 't1', assignmentId: 'a1', classId: 'c2', teacherId: 'tea1',
        subjectId: 'sub1', weekMode: 'weekly', combinedGroupId: null, meetingId: null,
        stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 2,
      },
    ];

    expect(isSupervisionAllowedInSlot(snapshot.freeSlots[0])).toBe(false);
    expect(isSupervisionAllowedInSlot({ ...snapshot.freeSlots[0], label: '课后服务' })).toBe(true);
    expect(resolveFreeSlotForClass(snapshot.freeSlots, 't1', 'st1', 'g1', 'c1', 1, 'pt1', 1)?.id).toBe('fs1');
    expect(effectiveLessonCount(snapshot.routines[0], 'pt1', 1)).toBe(2);

    const badDraft = makeDraft([
      {
        id: 'p1', kind: 'afterSchool', name: '合班托管', groupName: '', location: '',
        stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndices: [1, 2], classIds: ['c1', 'c2'],
      },
    ]);
    const errors = postErrors(snapshot, badDraft);
    expect(errors.some((e) => e.includes('实际合班须填写组名和地点'))).toBe(true);
    expect(errors.some((e) => e.includes('免任课'))).toBe(true);
    expect(errors.some((e) => e.includes('已有正课'))).toBe(true);
  });

  it('occurrences 展开已分配岗位的排班记录', () => {
    const snapshot = makeSnapshot();
    const post: SupervisionPost = {
      id: 'p1', kind: 'afterSchool', name: '课后服务', groupName: '', location: '',
      stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndices: [1, 2], classIds: ['c1'],
    };
    const draft = { ...makeDraft([post]), assignments: { p1: 'tea1' } };
    const occ = occurrences(snapshot, draft);
    expect(occ).toHaveLength(2);
    expect(occ[0].teacherName).toBe('王老师');
    expect(occ[0].classNames).toEqual(['一(1)班']);
  });
});

describe('domain/supervisionAllocator.ts & supervisionHistory.ts', () => {
  it('SupervisionAllocator 能避开正课冲突并自动分配可用教师', () => {
    const snapshot = makeSnapshot();
    snapshot.items = [
      {
        id: 'i1', termId: 't1', assignmentId: 'a1', classId: 'c2', teacherId: 'tea1',
        subjectId: 'sub1', weekMode: 'weekly', combinedGroupId: null, meetingId: null,
        stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1,
      },
    ];
    const post: SupervisionPost = {
      id: 'p1', kind: 'afterSchool', name: '课后服务', groupName: '', location: '',
      stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndices: [1], classIds: ['c1'],
    };
    const draft = makeDraft([post]);
    const allocator = new SupervisionAllocator();

    expect(allocator.teacherBlockers(snapshot, draft, post, 'tea1')).toContain('教师已有正课');
    expect(allocator.teacherBlockers(snapshot, draft, post, 'tea2')).toEqual([]);

    const filled = allocator.fill(snapshot, draft);
    expect(filled.assignments['p1']).toBe('tea2');
  });

  it('SupervisionDraftHistory 支持撤销、重做、脏检查与重置', () => {
    const d1 = makeDraft([]);
    const history = new SupervisionDraftHistory(d1);
    expect(history.hasChanges).toBe(false);
    expect(history.canUndo).toBe(false);

    const d2: SupervisionDraft = { ...d1, assignments: { p1: 'tea1' } };
    expect(history.replace(d2, '分配教师')).toBe(true);
    expect(history.hasChanges).toBe(true);
    expect(history.canUndo).toBe(true);
    expect(history.undoLabel).toBe('分配教师');

    // 相同内容不压栈
    expect(history.replace(d2, '重复操作')).toBe(false);

    const undone = history.undo();
    expect(undone?.assignments).toEqual({});
    expect(history.canRedo).toBe(true);

    const redone = history.redo();
    expect(redone?.assignments).toEqual({ p1: 'tea1' });

    history.markSaved({ ...d2, revision: 2 });
    expect(history.hasChanges).toBe(false);
    expect(history.current.revision).toBe(2);
  });
});
