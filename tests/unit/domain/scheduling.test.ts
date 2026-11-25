import { describe, it, expect } from 'vitest';
import {
  createScheduleContext,
  defaultSchedulePreferences,
  detectSchedule,
  isLessonLocked,
  positionOf,
  preflightSchedule,
  prepareDemand,
  previewPlacement,
  reconcileSchedule,
  solveSchedule,
  timesOverlap,
  validateScheduleSupervision,
  type ScheduleData,
} from '@/domain/scheduling';
import { timetableZip } from '@/features/scheduling/timetableZip';
import {
  createStoredRun,
  decodeScheduleSnapshot,
  encodeScheduleSnapshot,
  readStoredRun,
  readStoredSchedule,
  scheduleReconciliationRevision,
  scheduleRevision,
  writeStoredSchedule,
} from '@/repository/scheduleStorage';

function makeBaseScheduleData(overrides: Partial<ScheduleData> = {}): ScheduleData {
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
      createdAt: 1700000000000,
    },
    stages: [{ id: 'st1', termId, name: '初中部', sortOrder: 0 }],
    grades: [{ id: 'g1', stageId: 'st1', name: '七年级', sortOrder: 0 }],
    classes: [
      { id: 'c1', gradeId: 'g1', name: '七(1)班', sortOrder: 0 },
      { id: 'c2', gradeId: 'g1', name: '七(2)班', sortOrder: 1 },
    ],
    routines: [
      {
        stageId: 'st1',
        teachingDays: [
          { id: 'd1', stageId: 'st1', weekday: 1, isTeachingDay: true },
          { id: 'd2', stageId: 'st1', weekday: 2, isTeachingDay: true },
        ],
        periodTypes: [
          { id: 'pt1', stageId: 'st1', name: '上午', defaultLessonCount: 2, sortOrder: 0 },
          { id: 'pt2', stageId: 'st1', name: '下午', defaultLessonCount: 1, sortOrder: 1 },
        ],
        dailyOverrides: [],
        lessonTimes: [
          { id: 'lt1', periodTypeId: 'pt1', lessonIndex: 1, label: '第1节', startMinute: 480, endMinute: 525 },
          { id: 'lt2', periodTypeId: 'pt1', lessonIndex: 2, label: '第2节', startMinute: 535, endMinute: 580 },
          { id: 'lt3', periodTypeId: 'pt2', lessonIndex: 1, label: '第3节', startMinute: 840, endMinute: 885 },
        ],
      },
    ],
    subjects: [
      { id: 'sub1', termId, name: '语文', shortName: '语', sortOrder: 0 },
      { id: 'sub2', termId, name: '数学', shortName: '数', sortOrder: 1 },
    ],
    teachers: [
      { id: 'tea1', name: '张老师', shortName: '张', displayQualifier: '', sortOrder: 0 },
      { id: 'tea2', name: '李老师', shortName: '李', displayQualifier: '', sortOrder: 1 },
    ],
    assignments: [
      { id: 'a1', termId, teacherId: 'tea1', subjectId: 'sub1', classId: 'c1', weekMode: 'weekly', lessonCount: 2, sortOrder: 0, combinedLessonGroupId: null },
      { id: 'a2', termId, teacherId: 'tea2', subjectId: 'sub2', classId: 'c1', weekMode: 'weekly', lessonCount: 1, sortOrder: 1, combinedLessonGroupId: null },
    ],
    requirements: [
      { id: 'r1', subjectId: 'sub1', gradeId: 'g1', classId: 'c1', weekMode: 'weekly', lessonCount: 2 },
      { id: 'r2', subjectId: 'sub2', gradeId: 'g1', classId: 'c1', weekMode: 'weekly', lessonCount: 1 },
    ],
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
    ...overrides,
  };
}

describe('domain/scheduling.ts - 核心排课规则与求解器', () => {
  it('正确构建排课上下文并判断时间重叠与锁状态', () => {
    const data = makeBaseScheduleData({
      locks: [{ id: 'lk1', termId: 't1', scope: 'class', targetId: 'c1' }],
    });
    const ctx = createScheduleContext(data);
    expect(ctx.slotsByStage.get('st1')).toHaveLength(6); // 2 days * (2 + 1)

    expect(
      timesOverlap(
        { stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1, startMinute: 480, endMinute: 525 },
        { stageId: 'st2', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1, startMinute: 500, endMinute: 540 }
      )
    ).toBe(true);
    expect(
      timesOverlap(
        { stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1, startMinute: 480, endMinute: 525 },
        { stageId: 'st2', weekday: 1, periodTypeId: 'pt1', lessonIndex: 2, startMinute: 525, endMinute: 570 }
      )
    ).toBe(false);

    expect(
      isLessonLocked(ctx, {
        id: 'i1', termId: 't1', assignmentId: 'a1', classId: 'c1', teacherId: 'tea1',
        subjectId: 'sub1', weekMode: 'weekly', combinedGroupId: null, meetingId: null,
        stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1,
      })
    ).toBe(true);
  });

  it('preflightSchedule 能检测超容、未分配教师和任课节数不足', () => {
    const data = makeBaseScheduleData({
      assignments: [
        { id: 'a1', termId: 't1', teacherId: null, subjectId: 'sub1', classId: 'c1', weekMode: 'weekly', lessonCount: 1, sortOrder: 0, combinedLessonGroupId: null },
      ],
    });
    const issues = preflightSchedule(data, ['c1']);
    expect(issues.some((m) => m.includes('尚未分配教师'))).toBe(true);
    expect(issues.some((m) => m.includes('还有 1 节未配置任课'))).toBe(true);
  });

  it('previewPlacement 阻止禁排、免任课、教师冲突，并支持同班互换', () => {
    const data = makeBaseScheduleData({
      freeSlots: [
        { id: 'fs1', scopeType: 'class', scopeId: 'c1', stageId: 'st1', periodTypeId: 'pt2', weekday: 1, lessonIndex: 1, label: '班会' },
      ],
      items: [
        {
          id: 'i1', termId: 't1', assignmentId: 'a1', classId: 'c1', teacherId: 'tea1',
          subjectId: 'sub1', weekMode: 'weekly', combinedGroupId: null, meetingId: null,
          stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1,
        },
        {
          id: 'i2', termId: 't1', assignmentId: 'a2', classId: 'c1', teacherId: 'tea2',
          subjectId: 'sub2', weekMode: 'weekly', combinedGroupId: null, meetingId: null,
          stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 2,
        },
      ],
    });
    const ctx = createScheduleContext(data);
    const slots = ctx.slotsByStage.get('st1')!;
    const freeTarget = slots.find((s) => s.weekday === 1 && s.periodTypeId === 'pt2')!;
    const blockedFree = previewPlacement(ctx, data.items[0], freeTarget);
    expect(blockedFree.status).toBe('blocked');
    expect(blockedFree.reason).toContain('免任课');

    // 同班两节课互换
    const slot2 = positionOf(ctx, data.items[1])!;
    const swap = previewPlacement(ctx, data.items[0], slot2, true, true);
    expect(swap.status).toBe('swap');
    expect(swap.items?.find((r) => r.id === 'i1')?.lessonIndex).toBe(2);
    expect(swap.items?.find((r) => r.id === 'i2')?.lessonIndex).toBe(1);
  });

  it('solveSchedule 在满足硬约束下排完所有课程且无冲突', () => {
    const data = makeBaseScheduleData();
    const res = solveSchedule(data, ['c1'], false, undefined, 1, false);
    expect(res.issues).toEqual([]);
    expect(res.items).toHaveLength(3);
    expect(res.items.every((item) => item.weekday !== null)).toBe(true);
    expect(Object.keys(res.blockers)).toHaveLength(0);
  });

  it('solveSchedule 在无可用节次时返回未排课与阻塞原因', () => {
    const data = makeBaseScheduleData({
      freeSlots: [
        { id: 'fs1', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', periodTypeId: 'pt1', weekday: 1, lessonIndex: 1, label: '无课' },
        { id: 'fs2', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', periodTypeId: 'pt1', weekday: 1, lessonIndex: 2, label: '无课' },
        { id: 'fs3', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', periodTypeId: 'pt2', weekday: 1, lessonIndex: 1, label: '无课' },
        { id: 'fs4', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', periodTypeId: 'pt1', weekday: 2, lessonIndex: 1, label: '无课' },
        { id: 'fs5', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', periodTypeId: 'pt1', weekday: 2, lessonIndex: 2, label: '无课' },
        { id: 'fs6', scopeType: 'stage', scopeId: 'st1', stageId: 'st1', periodTypeId: 'pt2', weekday: 2, lessonIndex: 1, label: '无课' },
      ],
    });
    const res = solveSchedule(data, ['c1']);
    expect(res.items.every((item) => item.weekday === null)).toBe(true);
    expect(Object.keys(res.blockers)).toHaveLength(3);
  });

  it('validateScheduleSupervision 与 detectSchedule 能捕获带班与正课冲突', () => {
    const data = makeBaseScheduleData({
      items: [
        {
          id: 'i1', termId: 't1', assignmentId: 'a1', classId: 'c1', teacherId: 'tea1',
          subjectId: 'sub1', weekMode: 'weekly', combinedGroupId: null, meetingId: null,
          stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1,
        },
      ],
      supervision: [
        {
          teacherId: 'tea1',
          teacherName: '张老师',
          classNames: ['七(2)班'],
          post: { id: 'p1', name: '早读', classIds: ['c2'] },
          position: { stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1, startMinute: 480, endMinute: 525 },
        },
      ],
    });
    expect(validateScheduleSupervision(data)).toContain('带班冲突');
    expect(detectSchedule(data).some((m) => m.includes('带班安排'))).toBe(true);
  });

  it('prepareDemand 与 reconcileSchedule 保持锁定课程并处理作息变更', () => {
    const baseline = makeBaseScheduleData({
      items: [
        {
          id: 'i1', termId: 't1', assignmentId: 'a1', classId: 'c1', teacherId: 'tea1',
          subjectId: 'sub1', weekMode: 'weekly', combinedGroupId: null, meetingId: null,
          stageId: 'st1', weekday: 1, periodTypeId: 'pt1', lessonIndex: 1,
        },
      ],
      locks: [{ id: 'lk1', termId: 't1', scope: 'class', targetId: 'c1' }],
    });
    const demand = prepareDemand(baseline, ['c1'], false);
    // 锁定的课程即使 retainPlacements=false 也应保留位置
    expect(demand.find((d) => d.id === 'i1')?.weekday).toBe(1);

    const reconciled = reconcileSchedule(baseline, baseline);
    expect(reconciled.locks).toHaveLength(1);
    expect(reconciled.items.filter((i) => i.weekday !== null)).toHaveLength(3);
  });
});

describe('features/scheduling/timetableZip.ts', () => {
  it('生成带 PKZIP 文件头与 EOCD 尾部的有效 ZIP 字节流', () => {
    const zip = timetableZip([
      { name: '七(1)班.xlsx', content: new Uint8Array([1, 2, 3, 4]) },
      { name: '总表.xlsx', content: new Uint8Array([5, 6]) },
    ]);
    const view = new DataView(zip.buffer);
    expect(view.getUint32(0, true)).toBe(0x04034b50); // Local file header signature
    expect(view.getUint32(zip.length - 22, true)).toBe(0x06054b50); // EOCD signature
    expect(view.getUint16(zip.length - 12, true)).toBe(2); // total entries
  });
});

describe('repository/scheduleStorage.ts', () => {
  it('修订哈希、快照编解码、读写与运行报告序列化可无损往返', () => {
    const data = makeBaseScheduleData();
    const rev1 = scheduleRevision(data);
    const rev2 = scheduleRevision({ ...data, subjects: [...data.subjects].reverse() });
    expect(rev1).toBe(rev2);

    const rec1 = scheduleReconciliationRevision(data);
    const rec2 = scheduleReconciliationRevision({
      ...data,
      locks: [{ id: 'lk', termId: 't1', scope: 'class', targetId: 'c1' }],
    });
    expect(rec1).toBe(rec2);

    const encoded = encodeScheduleSnapshot(data);
    const decoded = decodeScheduleSnapshot(encoded as unknown as Parameters<typeof decodeScheduleSnapshot>[0]);
    expect(decoded.term.id).toBe('t1');
    expect(decoded.subjects).toHaveLength(2);

    const storedJson = writeStoredSchedule(data, true);
    const readBack = readStoredSchedule(storedJson);
    expect(readBack.term.title).toBe('2026 秋');

    const run = createStoredRun(data, [], {
      classIds: ['c1'],
      seed: 42,
      strength: 'normal',
      candidateChecks: 100,
      blockers: {},
      issues: ['测试问题'],
    });
    const parsedRun = readStoredRun(JSON.stringify(run));
    expect(parsedRun).toMatchObject({ classIds: ['c1'], seed: 42, issues: ['测试问题'] });
  });
});
