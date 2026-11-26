import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from 'vitest';
import type { CalendarException, StageRoutine } from '@/domain/models';
import type {
  ActualChangePreview,
  ActualLesson,
  ActualLessonChange,
  ActualSupervision,
  TemporaryAdjustmentRecord,
  TemporaryTimetableState,
} from '@/domain/actualTimetable';
import type { ScheduleData } from '@/domain/scheduling';
import type { SchedulePosition } from '@/domain/supervision';
import type {
  TemporaryWorkerRequest,
  TemporaryWorkerResponse,
} from '@/features/temporaryAdjustments/temporary-adjustments.worker';
import {
  buildWeekMoveCandidates,
  buildWeekSwapCandidates,
  clampWeekIndex,
  effectiveLessonCountOnDay,
  findActiveRecordForLesson,
  findActiveRecordForSupervision,
  getVisibleScheduleDates,
  recordClassIds,
  recordDates,
  recordTeacherIds,
  sameMoveSlot,
} from '@/features/temporaryAdjustments/temporaryAdjustmentsHelpers';

function emptySnapshot(overrides: Partial<ScheduleData> = {}): ScheduleData {
  return {
    term: {
      id: 'term-1',
      title: 'Unit test term',
      academicYear: '2026-2027',
      semesterLabel: '秋季学期',
      firstTeachingWeekStart: '2026-11-23',
      teachingWeekCount: 20,
      cycleMode: 'alternating',
      createdAt: 1,
    },
    stages: [],
    grades: [],
    classes: [],
    routines: [],
    subjects: [],
    teachers: [],
    assignments: [],
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
    preferences: {} as ScheduleData['preferences'],
    supervision: [],
    visibleSupervision: [],
    ...overrides,
  } as ScheduleData;
}

function createState(
  overrides: Partial<TemporaryTimetableState> = {}
): TemporaryTimetableState {
  return {
    snapshot: emptySnapshot(),
    exceptions: [],
    records: [],
    lessons: [],
    revision: 'revision-1',
    reconciliationPending: false,
    supervisions: [],
    supervisionVersions: [],
    hasSupervisionCalendar: false,
    ...overrides,
  } as TemporaryTimetableState;
}

function makeLesson(
  key: string,
  date: string,
  classId: string,
  periodTypeId = 'morning',
  lessonIndex = 1,
  teacherId = `teacher-${key}`,
  weekday = 1
): ActualLesson {
  const position: SchedulePosition = {
    stageId: 'stage-1',
    weekday,
    periodTypeId,
    lessonIndex,
    startMinute: null,
    endMinute: null,
  };
  return {
    date,
    originDate: date,
    key,
    item: {
      id: key,
      termId: 'term-1',
      assignmentId: `assignment-${key}`,
      classId,
      teacherId,
      subjectId: 'math',
      weekMode: 'weekly',
      combinedGroupId: null,
      meetingId: null,
      position,
    },
  };
}

function makeRecord(
  id: string,
  changes: ActualLessonChange[],
  overrides: Partial<TemporaryAdjustmentRecord> = {}
): TemporaryAdjustmentRecord {
  return {
    id,
    kind: 'substitute',
    changes,
    reason: '',
    createdAt: 1,
    cancelledAt: null,
    needsAttention: false,
    supervisionChange: null,
    ...overrides,
  };
}

function makeException(
  date: string,
  kind: CalendarException['kind'],
  makeupWeekday: number | null = null
): CalendarException {
  return {
    id: `exception-${date}`,
    termId: 'term-1',
    date,
    kind,
    makeupWeekday,
    makeupForDate: null,
    note: '',
  };
}

const emptyPreview: ActualChangePreview = {
  changes: [],
  errors: [],
  skippedDates: [],
};

describe('调代课日期与周次逻辑', () => {
  it('把周次限制在有效范围，教学周数为零时固定返回第 0 周索引', () => {
    const term = { teachingWeekCount: 20 } as ScheduleData['term'];

    expect(clampWeekIndex(-3, term)).toBe(0);
    expect(clampWeekIndex(7, term)).toBe(7);
    expect(clampWeekIndex(25, term)).toBe(19);
    expect(clampWeekIndex(4, { teachingWeekCount: 0 } as ScheduleData['term'])).toBe(0);
  });

  it('从教学日生成周视图日期，并把周末补课日映射到对应教学星期', () => {
    const routine = {
      stageId: 'stage-1',
      teachingDays: [1, 3, 5].map((weekday) => ({
        id: `teaching-${weekday}`,
        stageId: 'stage-1',
        weekday,
        isTeachingDay: true,
      })),
      periodTypes: [],
      dailyOverrides: [],
      lessonTimes: [],
    } as StageRoutine;
    const state = createState({
      exceptions: [
        makeException('2026-11-28', 'holiday'),
        makeException('2026-11-29', 'makeup', 3),
      ],
    });

    expect(getVisibleScheduleDates(state, routine, '2026-11-23')).toEqual([
      '2026-11-23',
      '2026-11-25',
      '2026-11-27',
      '2026-11-29',
    ]);
  });

  it('当天节数覆盖优先，零值有效；未覆盖时回退到默认节数', () => {
    const routine = {
      periodTypes: [
        { id: 'morning', defaultLessonCount: 3 },
        { id: 'afternoon', defaultLessonCount: 1 },
      ],
      dailyOverrides: [
        { periodTypeId: 'morning', weekday: 1, lessonCount: 0 },
        { periodTypeId: 'morning', weekday: 3, lessonCount: 2 },
      ],
    } as StageRoutine;

    expect(effectiveLessonCountOnDay(routine, 'morning', 1)).toBe(0);
    expect(effectiveLessonCountOnDay(routine, 'morning', 3)).toBe(2);
    expect(effectiveLessonCountOnDay(routine, 'morning', 2)).toBe(3);
    expect(effectiveLessonCountOnDay(routine, 'missing-period', 2)).toBe(0);
  });
});

describe('调代课候选课位', () => {
  it('只为可见日期内同一班级的其他课次生成换课候选', () => {
    const source = makeLesson('source', '2026-11-23', 'class-a');
    const visibleCandidate = makeLesson('visible', '2026-11-24', 'class-a');
    const hiddenDate = makeLesson('hidden', '2026-11-25', 'class-a');
    const anotherClass = makeLesson('other-class', '2026-11-24', 'class-b');
    const previewSwap = vi.fn(() => emptyPreview);
    const state = createState({
      lessons: [source, visibleCandidate, hiddenDate, anotherClass],
      previewSwap,
    } as Partial<TemporaryTimetableState>);
    const problem = {} as Parameters<typeof buildWeekSwapCandidates>[1];

    const result = buildWeekSwapCandidates(
      state,
      problem,
      source,
      ['2026-11-23', '2026-11-24']
    );

    expect(Array.from(result.keys())).toEqual(['visible']);
    expect(previewSwap).toHaveBeenCalledTimes(1);
    expect(previewSwap).toHaveBeenCalledWith(
      { firstKey: 'source', secondKey: 'visible' },
      problem
    );
  });

  it('移课候选遵守节数覆盖、占用状态、假日和周末补课日', () => {
    const routine = {
      stageId: 'stage-1',
      teachingDays: [1, 3].map((weekday) => ({
        id: `teaching-${weekday}`,
        stageId: 'stage-1',
        weekday,
        isTeachingDay: true,
      })),
      periodTypes: [
        {
          id: 'morning',
          stageId: 'stage-1',
          name: '上午',
          sortOrder: 1,
          defaultLessonCount: 2,
        },
        {
          id: 'afternoon',
          stageId: 'stage-1',
          name: '下午',
          sortOrder: 2,
          defaultLessonCount: 1,
        },
      ],
      dailyOverrides: [
        {
          id: 'override-morning-1',
          stageId: 'stage-1',
          periodTypeId: 'morning',
          weekday: 1,
          lessonCount: 1,
        },
        {
          id: 'override-afternoon-1',
          stageId: 'stage-1',
          periodTypeId: 'afternoon',
          weekday: 1,
          lessonCount: 0,
        },
      ],
      lessonTimes: [],
    } as StageRoutine;
    const source = makeLesson('source', '2026-11-23', 'class-a', 'morning', 1);
    const occupiedInClass = makeLesson(
      'occupied',
      '2026-11-25',
      'class-a',
      'morning',
      1,
      'teacher-occupied',
      3
    );
    const otherClass = makeLesson(
      'other-class',
      '2026-11-25',
      'class-b',
      'afternoon',
      1,
      'teacher-other',
      3
    );
    const previewMove = vi.fn(() => emptyPreview);
    const state = createState({
      snapshot: emptySnapshot({ routines: [routine] }),
      exceptions: [
        makeException('2026-11-24', 'holiday'),
        makeException('2026-11-29', 'makeup', 3),
      ],
      lessons: [source, occupiedInClass, otherClass],
      previewMove,
    } as Partial<TemporaryTimetableState>);
    const problem = {} as Parameters<typeof buildWeekMoveCandidates>[1];

    const result = buildWeekMoveCandidates(
      state,
      problem,
      source,
      routine,
      ['2026-11-23', '2026-11-24', '2026-11-25', '2026-11-29']
    );

    expect(Array.from(result.keys())).toEqual([
      '2026-11-25:morning:2',
      '2026-11-25:afternoon:1',
      '2026-11-29:morning:1',
      '2026-11-29:morning:2',
      '2026-11-29:afternoon:1',
    ]);
    expect(result.get('2026-11-29:morning:1')?.position.weekday).toBe(3);
    expect(previewMove).toHaveBeenCalledTimes(5);
  });

  it('缺少目标作息时返回空候选，不尝试预览', () => {
    const source = makeLesson('source', '2026-11-23', 'class-a');
    const previewMove = vi.fn(() => emptyPreview);
    const state = createState({ previewMove } as Partial<TemporaryTimetableState>);

    expect(
      buildWeekMoveCandidates(state, {} as never, source, undefined, ['2026-11-23'])
    ).toEqual(new Map());
    expect(previewMove).not.toHaveBeenCalled();
  });
});

describe('调代课记录查询与筛选数据', () => {
  it('返回最新的有效课次记录，跳过已撤销、需关注和不匹配的记录', () => {
    const before = makeLesson('before', '2026-11-23', 'class-a');
    const lesson = makeLesson('current', '2026-11-24', 'class-a');
    const older = makeRecord('older', [{ before, after: lesson }]);
    const needsAttention = makeRecord(
      'attention',
      [{ before, after: lesson }],
      { needsAttention: true }
    );
    const cancelled = makeRecord(
      'cancelled',
      [{ before, after: lesson }],
      { cancelledAt: 123 }
    );
    const unrelated = makeRecord('unrelated', [
      { before, after: makeLesson('other', '2026-11-24', 'class-a') },
    ]);
    const state = createState({
      records: [older, needsAttention, cancelled, unrelated],
    });

    expect(findActiveRecordForLesson(state, lesson)).toBe(older);
    expect(findActiveRecordForLesson(createState(), lesson)).toBeNull();
  });

  it('只把未撤销且无需关注的最新带班替班记录视为当前记录', () => {
    const before = {
      key: 'before-supervision',
      date: '2026-11-24',
      teacherId: 'a',
      classIds: ['class-a'],
    };
    const after = {
      key: 'after-supervision',
      date: '2026-11-24',
      teacherId: 'b',
      classIds: ['class-a'],
    };
    const active = makeRecord('active', [], {
      supervisionChange: { before, after } as TemporaryAdjustmentRecord['supervisionChange'],
    });
    const cancelled = makeRecord('cancelled', [], {
      cancelledAt: 123,
      supervisionChange: {
        before,
        after,
      } as TemporaryAdjustmentRecord['supervisionChange'],
    });
    const needsAttention = makeRecord('attention', [], {
      needsAttention: true,
      supervisionChange: { before, after } as TemporaryAdjustmentRecord['supervisionChange'],
    });
    const state = createState({ records: [active, cancelled, needsAttention] });

    expect(
      findActiveRecordForSupervision(state, {
        key: 'after-supervision',
      } as ActualSupervision)
    ).toBe(active);
  });

  it('从课次与带班记录收集去重班级、教师和按日期排序的变更日', () => {
    const firstBefore = makeLesson(
      'first-before',
      '2026-11-25',
      'class-a',
      'morning',
      1,
      'teacher-a'
    );
    const firstAfter = makeLesson(
      'first-after',
      '2026-11-23',
      'class-a',
      'morning',
      1,
      'teacher-b'
    );
    const secondBefore = makeLesson(
      'second-before',
      '2026-11-24',
      'class-b',
      'morning',
      1,
      'teacher-b'
    );
    const secondAfter = makeLesson(
      'second-after',
      '2026-11-25',
      'class-b',
      'morning',
      1,
      'teacher-a'
    );
    const record = makeRecord('record', [
      { before: firstBefore, after: firstAfter },
      { before: secondBefore, after: secondAfter },
    ]);

    expect(recordClassIds(record)).toEqual(['class-a', 'class-b']);
    expect(recordTeacherIds(record)).toEqual(['teacher-a', 'teacher-b']);
    expect(recordDates(record)).toEqual([
      '2026-11-23',
      '2026-11-24',
      '2026-11-25',
    ]);
    expect(recordClassIds(makeRecord('empty', []))).toEqual([]);
    expect(recordTeacherIds(makeRecord('empty', []))).toEqual([]);
    expect(recordDates(makeRecord('empty', []))).toEqual([]);
  });

  it('从带班替班记录取前后教师和班级，并只筛选其发生日期', () => {
    const before = {
      key: 'before',
      date: '2026-11-25',
      teacherId: 'teacher-a',
      classIds: ['class-a', 'class-b'],
    };
    const after = {
      key: 'after',
      date: '2026-11-25',
      teacherId: 'teacher-b',
      classIds: ['class-b', 'class-c'],
    };
    const record = makeRecord('supervision', [], {
      supervisionChange: { before, after } as TemporaryAdjustmentRecord['supervisionChange'],
    });

    expect(recordClassIds(record)).toEqual(['class-a', 'class-b', 'class-c']);
    expect(recordTeacherIds(record)).toEqual(['teacher-a', 'teacher-b']);
    expect(recordDates(record)).toEqual(['2026-11-25']);
  });

  it('只在日期和课位相同时匹配同一调课目标，空目标不匹配', () => {
    const position: SchedulePosition = {
      stageId: 'stage-1',
      weekday: 1,
      periodTypeId: 'morning',
      lessonIndex: 1,
      startMinute: 480,
      endMinute: 520,
    };

    expect(
      sameMoveSlot('2026-11-23', position, '2026-11-23', {
        ...position,
        startMinute: 500,
      })
    ).toBe(true);
    expect(sameMoveSlot('2026-11-23', position, '2026-11-24', position)).toBe(false);
    expect(
      sameMoveSlot('2026-11-23', position, '2026-11-23', {
        ...position,
        lessonIndex: 2,
      })
    ).toBe(false);
    expect(sameMoveSlot(null, position, '2026-11-23', position)).toBe(false);
    expect(sameMoveSlot('2026-11-23', null, '2026-11-23', position)).toBe(false);
  });
});

describe('调代课 Worker 请求隔离', () => {
  let replyFor: (
    request: TemporaryWorkerRequest
  ) => TemporaryWorkerResponse | null;

  class MockWorker {
    static instances: MockWorker[] = [];
    onmessage: ((event: MessageEvent<TemporaryWorkerResponse>) => void) | null = null;
    onerror: ((event: ErrorEvent) => void) | null = null;
    readonly posted: TemporaryWorkerRequest[] = [];
    readonly terminate = vi.fn();

    constructor(_url: URL, _options?: WorkerOptions) {
      MockWorker.instances.push(this);
    }

    postMessage(request: TemporaryWorkerRequest): void {
      this.posted.push(request);
      const response = replyFor(request);
      if (response) {
        queueMicrotask(() =>
          this.onmessage?.({ data: response } as MessageEvent<TemporaryWorkerResponse>)
        );
      }
    }

    fail(message: string): void {
      this.onerror?.({ message } as ErrorEvent);
    }
  }

  function mockState(): TemporaryTimetableState {
    return createState({ snapshot: emptySnapshot() });
  }

  async function loadWorkerClient() {
    vi.resetModules();
    return (await import('@/features/temporaryAdjustments/temporaryAdjustmentsWorkerClient'))
      .temporaryAdjustmentsWorkerClient;
  }

  beforeEach(() => {
    MockWorker.instances = [];
    replyFor = () => null;
    vi.unstubAllGlobals();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('代课候选排除原任教师，并在原课次缺失时返回空结果', async () => {
    vi.stubGlobal('Worker', undefined);
    const client = await loadWorkerClient();
    const source = makeLesson(
      'source',
      '2026-11-23',
      'class-a',
      'morning',
      1,
      'teacher-current'
    );
    const previewSubstitute = vi.fn(() => emptyPreview);
    const state = createState({
      snapshot: emptySnapshot({
        teachers: [
          { id: 'teacher-current' },
          { id: 'teacher-a' },
        ] as ScheduleData['teachers'],
      }),
      lessons: [source],
      previewSubstitute,
    } as Partial<TemporaryTimetableState>);

    await expect(
      client.computeSubstituteCandidates({
        state,
        sourceKey: 'source',
        targetSubjectId: 'science',
      })
    ).resolves.toEqual({ 'teacher-a': emptyPreview });
    expect(previewSubstitute).toHaveBeenCalledTimes(1);
    expect(previewSubstitute).toHaveBeenCalledWith(
      { sourceKey: 'source', teacherId: 'teacher-a', subjectId: 'science' },
      expect.any(Object)
    );

    await expect(
      client.computeSubstituteCandidates({
        state: createState(),
        sourceKey: 'missing',
        targetSubjectId: 'science',
      })
    ).resolves.toEqual({});
  });

  it('调整目标不完整时返回明确的输入错误', async () => {
    vi.stubGlobal('Worker', undefined);
    const client = await loadWorkerClient();

    await expect(
      client.computeAdjustmentPreview({
        state: mockState(),
        kind: 'move',
        sourceKey: '',
        moveDate: null,
        movePosition: null,
      })
    ).resolves.toEqual({
      changes: [],
      errors: ['未选择完整的调整目标'],
      skippedDates: [],
    });
  });

  it('取消不存在的调代课记录时返回业务提示', async () => {
    vi.stubGlobal('Worker', undefined);
    const client = await loadWorkerClient();

    await expect(
      client.validateCancellation({ state: mockState(), recordId: 'missing' })
    ).resolves.toBe('找不到该调整记录');
  });

  it('把排课预览参数序列化到 Worker，并返回其预览结果', async () => {
    const preview: ActualChangePreview = {
      changes: [],
      errors: ['教师在该时段有冲突'],
      skippedDates: ['2026-11-25'],
    };
    replyFor = (request) => {
      if (request.type === 'syncState') {
        return { id: request.id, type: 'syncStateResult' };
      }
      if (request.type === 'computeAdjustmentPreview') {
        return { id: request.id, type: 'computeAdjustmentPreviewResult', preview };
      }
      return null;
    };
    vi.stubGlobal('Worker', MockWorker);
    const client = await loadWorkerClient();

    await expect(
      client.computeAdjustmentPreview({
        state: mockState(),
        kind: 'substitute',
        sourceKey: 'lesson-1',
        substituteTeacherId: 'teacher-2',
        substituteSubjectId: 'science',
        reason: '请假',
        rangeStart: '2026-11-23',
        rangeEnd: '2026-11-27',
        excludedDates: new Set(['2026-11-25']),
      })
    ).resolves.toEqual(preview);

    expect(MockWorker.instances).toHaveLength(1);
    expect(MockWorker.instances[0].posted).toHaveLength(2);
    expect(MockWorker.instances[0].posted[0]).toMatchObject({
      type: 'syncState',
      state: { revision: 'revision-1' },
    });
    expect(MockWorker.instances[0].posted[1]).toMatchObject({
      type: 'computeAdjustmentPreview',
      kind: 'substitute',
      sourceKey: 'lesson-1',
      substituteTeacherId: 'teacher-2',
      substituteSubjectId: 'science',
      reason: '请假',
      rangeStart: '2026-11-23',
      rangeEnd: '2026-11-27',
      excludedDates: ['2026-11-25'],
    });
  });

  it('保留 Worker 返回的业务错误信息', async () => {
    replyFor = (request) => {
      if (request.type === 'syncState') {
        return { id: request.id, type: 'syncStateResult' };
      }
      return { id: request.id, type: 'error', message: '状态版本已过期' };
    };
    vi.stubGlobal('Worker', MockWorker);
    const client = await loadWorkerClient();

    await expect(
      client.computeAdjustmentPreview({
        state: mockState(),
        kind: 'swap',
        sourceKey: 'lesson-1',
        swapKey: 'lesson-2',
      })
    ).rejects.toThrow('状态版本已过期');
  });

  it('Worker 异常退出时拒绝所有等待请求并终止失效实例', async () => {
    vi.stubGlobal('Worker', MockWorker);
    const client = await loadWorkerClient();
    const pending = client.ensureSynced(mockState());
    const worker = MockWorker.instances[0];

    worker.fail('worker crashed');

    await expect(pending).rejects.toThrow('worker crashed');
    expect(worker.terminate).toHaveBeenCalledOnce();
  });

  it('当前环境不支持 Worker 时返回明确错误', async () => {
    vi.stubGlobal('Worker', undefined);
    const client = await loadWorkerClient();

    await expect(client.ensureSynced(mockState())).rejects.toThrow(
      '当前环境不支持 Web Worker'
    );
  });
});
