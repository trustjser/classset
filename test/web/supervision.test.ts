import assert from 'node:assert/strict';
import test from 'node:test';
import type { ScheduleData } from '../../src/domain/scheduling.ts';
import type {
  SupervisionDraft,
  SupervisionPost,
} from '../../src/domain/supervision.ts';
import {
  defaultSupervisionMatchingPreferences,
  SUPERVISION_BASE_POOL_ID,
} from '../../src/domain/supervision.ts';
import { SupervisionAllocator } from '../../src/domain/supervisionAllocator.ts';
import { SupervisionDraftHistory } from '../../src/domain/supervisionHistory.ts';
import { SupervisionMatching } from '../../src/domain/supervisionMatching.ts';
import {
  isSupervisionAllowedInSlot,
  postErrors,
  resolveFreeSlotForClass,
} from '../../src/domain/supervisionValidation.ts';

function createMockScheduleData(): ScheduleData {
  return {
    term: {
      id: 'term_1',
      name: '2026秋季学期',
      startDate: '2026-09-01',
      endDate: '2027-01-20',
      teachingWeekCount: 20,
      cycleMode: 'weekly',
      firstTeachingWeekStart: '2026-09-01',
    },
    stages: [{ id: 'stage_1', name: '初中部' }],
    grades: [{ id: 'grade_1', stageId: 'stage_1', name: '初一' }],
    classes: [
      { id: 'class_1', gradeId: 'grade_1', name: '初一(1)班' },
      { id: 'class_2', gradeId: 'grade_1', name: '初一(2)班' },
    ],
    routines: [
      {
        stageId: 'stage_1',
        teachingDays: [
          { stageId: 'stage_1', weekday: 1, isTeachingDay: true },
          { stageId: 'stage_1', weekday: 2, isTeachingDay: true },
          { stageId: 'stage_1', weekday: 3, isTeachingDay: true },
          { stageId: 'stage_1', weekday: 4, isTeachingDay: true },
          { stageId: 'stage_1', weekday: 5, isTeachingDay: true },
        ],
        periodTypes: [
          {
            id: 'period_afternoon',
            stageId: 'stage_1',
            name: '下午',
            defaultLessonCount: 4,
            sortOrder: 1,
            timeSlotCount: 4,
          },
        ],
        dailyOverrides: [],
        lessonTimes: [
          {
            stageId: 'stage_1',
            periodTypeId: 'period_afternoon',
            lessonIndex: 1,
            startMinute: 840,
            endMinute: 885,
            label: '第1节',
          },
          {
            stageId: 'stage_1',
            periodTypeId: 'period_afternoon',
            lessonIndex: 2,
            startMinute: 895,
            endMinute: 940,
            label: '第2节',
          },
          {
            stageId: 'stage_1',
            periodTypeId: 'period_afternoon',
            lessonIndex: 3,
            startMinute: 950,
            endMinute: 995,
            label: '第3节',
          },
          {
            stageId: 'stage_1',
            periodTypeId: 'period_afternoon',
            lessonIndex: 4,
            startMinute: 1005,
            endMinute: 1050,
            label: '第4节',
          },
        ],
      },
    ],
    subjects: [
      { id: 'sub_math', name: '数学', shortName: '数', termId: 'term_1' },
      { id: 'sub_chinese', name: '语文', shortName: '语', termId: 'term_1' },
    ],
    teachers: [
      { id: 'teacher_zhang', name: '张老师' },
      { id: 'teacher_li', name: '李老师' },
    ],
    assignments: [
      {
        id: 'asg_1',
        termId: 'term_1',
        classId: 'class_1',
        teacherId: 'teacher_zhang',
        subjectId: 'sub_math',
        lessonCount: 5,
        weeklyLessonCount: 5,
      },
      {
        id: 'asg_2',
        termId: 'term_1',
        classId: 'class_2',
        teacherId: 'teacher_li',
        subjectId: 'sub_chinese',
        lessonCount: 5,
        weeklyLessonCount: 5,
      },
    ],
    requirements: [],
    items: [
      // Teacher Li teaches regular class_2 on Monday afternoon lesson 1
      {
        id: 'item_1',
        termId: 'term_1',
        assignmentId: 'asg_2',
        classId: 'class_2',
        teacherId: 'teacher_li',
        subjectId: 'sub_chinese',
        weekMode: 'weekly',
        stageId: 'stage_1',
        weekday: 1,
        periodTypeId: 'period_afternoon',
        lessonIndex: 1,
        combinedGroupId: null,
        meetingId: null,
      },
    ],
    locks: [],
    freeSlots: [
      // class_1 has "无课" on Monday afternoon lesson 4 (supervision disallowed)
      {
        id: 'slot_1',
        scopeType: 'class',
        scopeId: 'class_1',
        stageId: 'stage_1',
        periodTypeId: 'period_afternoon',
        weekday: 1,
        lessonIndex: 4,
        label: '无课',
      },
      // class_1 has "自习" on Monday afternoon lesson 3 (supervision allowed)
      {
        id: 'slot_2',
        scopeType: 'class',
        scopeId: 'class_1',
        stageId: 'stage_1',
        periodTypeId: 'period_afternoon',
        weekday: 1,
        lessonIndex: 3,
        label: '自习',
      },
    ],
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
    preferences: {
      termId: 'term_1',
      strength: 'normal',
      progressConsistency: 'prefer',
      teacherDistribution: 'indifferent',
      lunchProtection: false,
      consecutivePolicy: 'preferSeparate',
      detectProgressConsistency: true,
    },
    supervision: [],
    visibleSupervision: [],
  };
}

test('supervision validation: postErrors detects invalid and conflicting posts', () => {
  const snapshot = createMockScheduleData();

  const draft: SupervisionDraft = {
    termId: 'term_1',
    revision: 1,
    posts: [
      // Post 1: Valid
      {
        id: 'p_1',
        kind: 'afterSchool',
        name: '课后服务',
        groupName: '',
        location: '',
        stageId: 'stage_1',
        weekday: 1,
        periodTypeId: 'period_afternoon',
        lessonIndices: [2],
        classIds: ['class_1'],
      },
      // Post 2: Missing name
      {
        id: 'p_2',
        kind: 'custom',
        name: '   ',
        groupName: '',
        location: '',
        stageId: 'stage_1',
        weekday: 1,
        periodTypeId: 'period_afternoon',
        lessonIndices: [2],
        classIds: ['class_2'],
      },
      // Post 3: Merged without groupName & location
      {
        id: 'p_3',
        kind: 'eveningStudy',
        name: '晚自习',
        groupName: '',
        location: '',
        stageId: 'stage_1',
        weekday: 2,
        periodTypeId: 'period_afternoon',
        lessonIndices: [1],
        classIds: ['class_1', 'class_2'],
      },
      // Post 4: Conflicts with "无课" free slot
      {
        id: 'p_4',
        kind: 'afterSchool',
        name: '周一托管4',
        groupName: '',
        location: '',
        stageId: 'stage_1',
        weekday: 1,
        periodTypeId: 'period_afternoon',
        lessonIndices: [4],
        classIds: ['class_1'],
      },
      // Post 5: Conflicts with existing regular course for class_2
      {
        id: 'p_5',
        kind: 'afterSchool',
        name: '周一正课冲突',
        groupName: '',
        location: '',
        stageId: 'stage_1',
        weekday: 1,
        periodTypeId: 'period_afternoon',
        lessonIndices: [1],
        classIds: ['class_2'],
      },
    ],
    teacherIds: ['teacher_zhang', 'teacher_li'],
    teacherPools: [],
    defaultTeacherPoolId: null,
    matchingPreferences: defaultSupervisionMatchingPreferences,
    rules: {},
    assignments: {},
    manualPostIds: [],
  };

  const errors = postErrors(snapshot, draft);
  assert.ok(errors.some((e) => e.includes('请填写活动名称')), 'should detect empty name');
  assert.ok(errors.some((e) => e.includes('实际合班须填写组名和地点')), 'should detect missing merged group/location');
  assert.ok(errors.some((e) => e.includes('已有免任课「无课」')), 'should detect free slot without supervision');
  assert.ok(errors.some((e) => e.includes('已有正课「语文」')), 'should detect course item conflict');
});

test('supervision allocator: teacherBlockers checks pools, limits, and conflicts', () => {
  const snapshot = createMockScheduleData();

  const post: SupervisionPost = {
    id: 'post_mon_1',
    kind: 'afterSchool',
    name: '周一第一节带班',
    groupName: '',
    location: '',
    stageId: 'stage_1',
    weekday: 1,
    periodTypeId: 'period_afternoon',
    lessonIndices: [1],
    classIds: ['class_1'],
    teacherPoolId: null,
  };

  const draft: SupervisionDraft = {
    termId: 'term_1',
    revision: 1,
    posts: [post],
    teacherIds: ['teacher_zhang'], // Only teacher_zhang in pool
    teacherPools: [],
    defaultTeacherPoolId: null,
    matchingPreferences: defaultSupervisionMatchingPreferences,
    rules: {
      teacher_zhang: {
        unavailable: [
          {
            stageId: 'stage_1',
            weekday: 1,
            periodTypeId: 'period_afternoon',
            lessonIndex: 1,
          },
        ],
      },
    },
    assignments: {},
    manualPostIds: [],
  };

  const allocator = new SupervisionAllocator();

  // Teacher Li is not in candidate pool
  const liBlockers = allocator.teacherBlockers(snapshot, draft, post, 'teacher_li');
  assert.ok(
    liBlockers.some((b) => b.includes('教师不在岗位候选池中')),
    'should block teacher not in pool'
  );

  // Teacher Zhang is in pool but has unavailable rule (禁排) on Monday lesson 1
  const zhangBlockers = allocator.teacherBlockers(snapshot, draft, post, 'teacher_zhang');
  assert.ok(
    zhangBlockers.some((b) => b.includes('教师在该节次禁排')),
    'should block teacher when banned in cell'
  );

  // Teacher Li also has regular course on Monday lesson 1
  assert.ok(
    liBlockers.some((b) => b.includes('教师已有正课')),
    'should detect teacher having regular course'
  );
});

test('supervision matching: calculates reasons and ranks correctly', () => {
  const snapshot = createMockScheduleData();
  const matching = new SupervisionMatching(snapshot);

  const post: SupervisionPost = {
    id: 'post_1',
    kind: 'afterSchool',
    name: '托管',
    groupName: '',
    location: '',
    stageId: 'stage_1',
    weekday: 1,
    periodTypeId: 'period_afternoon',
    lessonIndices: [2],
    classIds: ['class_1'],
  };

  const draft: SupervisionDraft = {
    termId: 'term_1',
    revision: 1,
    posts: [post],
    teacherIds: ['teacher_zhang', 'teacher_li'],
    teacherPools: [],
    defaultTeacherPoolId: null,
    matchingPreferences: defaultSupervisionMatchingPreferences,
    rules: {},
    assignments: {},
    manualPostIds: [],
  };

  // teacher_zhang teaches class_1 (math)
  const zhangReasons = matching.reasons(post, 'teacher_zhang');
  assert.ok(zhangReasons.includes('任教本班'), 'teacher_zhang should have 任教本班 reason');

  // teacher_li teaches class_2 (same grade)
  const liReasons = matching.reasons(post, 'teacher_li');
  assert.ok(liReasons.includes('任教本年级'), 'teacher_li should have 任教本年级 reason');
});

test('supervision history: supports replace, undo, redo, and change tracking', () => {
  const initial: SupervisionDraft = {
    termId: 'term_1',
    revision: 1,
    posts: [],
    teacherIds: ['t1'],
    teacherPools: [],
    defaultTeacherPoolId: null,
    matchingPreferences: defaultSupervisionMatchingPreferences,
    rules: {},
    assignments: {},
    manualPostIds: [],
  };

  const history = new SupervisionDraftHistory(initial);
  assert.equal(history.hasChanges, false);
  assert.equal(history.canUndo, false);

  const step1: SupervisionDraft = {
    ...initial,
    posts: [
      {
        id: 'p_1',
        kind: 'afterSchool',
        name: '晚自习',
        groupName: '',
        location: '',
        stageId: 'stage_1',
        weekday: 1,
        periodTypeId: 'period_1',
        lessonIndices: [1],
        classIds: ['c_1'],
      },
    ],
  };

  history.replace(step1, '创建岗位');
  assert.equal(history.hasChanges, true);
  assert.equal(history.canUndo, true);
  assert.equal(history.current.posts.length, 1);

  const renderedHistory = history.clone();
  assert.equal(renderedHistory.hasChanges, true);
  assert.equal(renderedHistory.canUndo, true);

  // Undo
  const undone = renderedHistory.undo();
  assert.ok(undone);
  assert.equal(undone.posts.length, 0);
  assert.equal(renderedHistory.canRedo, true);

  // Redo
  const redone = renderedHistory.redo();
  assert.ok(redone);
  assert.equal(redone.posts.length, 1);

  const step2: SupervisionDraft = {
    ...step1,
    assignments: { p_1: 't1' },
  };
  renderedHistory.replace(step2, '安排教师');
  renderedHistory.markSaved({ ...step1, revision: 2 });
  assert.equal(renderedHistory.current.revision, 2);
  assert.deepEqual(renderedHistory.current.assignments, { p_1: 't1' });
  assert.equal(renderedHistory.hasChanges, true);
});
