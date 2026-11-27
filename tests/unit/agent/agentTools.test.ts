import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { SqlDatabaseAdapter } from '@/adapter/db/databaseAdapter';
import {
  CLASSSET_AGENT_TOOL_SCHEMAS,
  getAgentToolSchema,
} from '@/agent/domain/agentToolSchemas';
import {
  ClassSetAgentToolExecutor,
  registerClassSetToolsToWebMCP,
} from '@/agent/domain/agentToolExecutor';
import { SchoolRepository } from '@/repository/schoolRepository';

function createMemoryRepository() {
  const adapter: SqlDatabaseAdapter = {
    runtimeMode: 'web-browser',
    schemaVersion: 19,
    engineStatus: 'memory-fallback',
    init: vi.fn(async () => undefined),
    select: vi.fn(async () => []),
    execute: vi.fn(async () => ({ rowsAffected: 0 })),
    transaction: vi.fn(async (fn) =>
      fn({
        select: vi.fn(async () => []),
        execute: vi.fn(async () => ({ rowsAffected: 0 })),
      })
    ),
    exportSqliteBytes: vi.fn(async () => null),
    importSqliteBytes: vi.fn(async () => undefined),
    clearAllData: vi.fn(async () => undefined),
  };
  return new SchoolRepository(adapter);
}

async function seedReadySemester(repo: SchoolRepository) {
  await repo.initialize();
  const termId = 'term_2026_fall';
  await repo.saveTerm({
    id: termId,
    title: '2026-2027学年第一学期',
    academicYear: '2026-2027',
    semesterLabel: '第一学期',
    firstTeachingWeekStart: '2026-09-07',
    teachingWeekCount: 16,
    cycleMode: 'every_week',
    createdAt: Date.now(),
  });
  await repo.saveActiveTermId(termId);

  const stages = await repo.loadStages(termId);
  const stageId = stages[0].id;

  const gradeId = 'grade_1';
  const classId = 'class_1_1';
  await repo.saveGrades([
    { id: gradeId, stageId, name: '一年级', sortOrder: 0 },
  ]);
  await repo.saveClasses([
    { id: classId, gradeId, name: '1班', sortOrder: 0 },
  ]);

  const morningId = 'period_morning';
  const afterSchoolId = 'period_after';
  await repo.saveStageRoutine({
    stageId,
    teachingDays: [1, 2, 3, 4, 5, 6, 7].map((w) => ({
      id: `td_${stageId}_${w}`,
      stageId,
      weekday: w,
      isTeachingDay: w <= 5,
    })),
    periodTypes: [
      {
        id: morningId,
        stageId,
        name: '上午',
        defaultLessonCount: 2,
        sortOrder: 0,
      },
      {
        id: afterSchoolId,
        stageId,
        name: '课后',
        defaultLessonCount: 1,
        sortOrder: 1,
      },
    ],
    dailyOverrides: [],
    lessonTimes: [
      {
        id: `${morningId}_1`,
        periodTypeId: morningId,
        lessonIndex: 1,
        label: '第1节',
        startMinute: 480,
        endMinute: 520,
      },
      {
        id: `${morningId}_2`,
        periodTypeId: morningId,
        lessonIndex: 2,
        label: '第2节',
        startMinute: 530,
        endMinute: 570,
      },
      {
        id: `${afterSchoolId}_1`,
        periodTypeId: afterSchoolId,
        lessonIndex: 1,
        label: '第1节',
        startMinute: 960,
        endMinute: 1000,
      },
    ],
    commonPeriods: [],
  });

  // 将每天的“课后第1节”设为课后服务免任课（允许排带班，不排正课）
  await repo.saveFreeSlotChanges(
    [1, 2, 3, 4, 5].map((w) => ({
      id: `free_after_${w}`,
      scopeType: 'stage',
      scopeId: stageId,
      stageId,
      periodTypeId: afterSchoolId,
      weekday: w,
      lessonIndex: 1,
      label: '课后服务',
    })),
    []
  );

  const mathId = 'sub_math';
  const chineseId = 'sub_chinese';
  await repo.saveSubjects([
    { id: mathId, termId, name: '数学', shortName: '数', sortOrder: 0 },
    { id: chineseId, termId, name: '语文', shortName: '语', sortOrder: 1 },
  ]);

  await repo.replaceGradeRequirements(gradeId, [
    {
      id: 'req_math',
      subjectId: mathId,
      gradeId,
      classId: null,
      weekMode: 'weekly',
      lessonCount: 2,
    },
    {
      id: 'req_chinese',
      subjectId: chineseId,
      gradeId,
      classId: null,
      weekMode: 'weekly',
      lessonCount: 2,
    },
  ]);

  const teacherZhang = 't_zhang';
  const teacherLi = 't_li';
  await repo.saveTeachers([
    {
      id: teacherZhang,
      name: '张老师',
      shortName: '张',
      displayQualifier: '',
      sortOrder: 0,
      subjectIds: [mathId],
    },
    {
      id: teacherLi,
      name: '李老师',
      shortName: '李',
      displayQualifier: '',
      sortOrder: 1,
      subjectIds: [chineseId],
    },
  ]);

  await repo.addTeacherAssignments(termId, [
    {
      id: 'assign_math',
      termId,
      teacherId: teacherZhang,
      subjectId: mathId,
      classId,
      weekMode: 'weekly',
      lessonCount: 2,
      sortOrder: 0,
      combinedLessonGroupId: null,
    },
    {
      id: 'assign_chinese',
      termId,
      teacherId: teacherLi,
      subjectId: chineseId,
      classId,
      weekMode: 'weekly',
      lessonCount: 2,
      sortOrder: 1,
      combinedLessonGroupId: null,
    },
  ]);

  return {
    termId,
    stageId,
    gradeId,
    classId,
    morningId,
    afterSchoolId,
    mathId,
    chineseId,
    teacherZhang,
    teacherLi,
  };
}

describe('domain/agentToolSchemas & agentToolExecutor', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  afterEach(() => {
    localStorage.clear();
  });

  it('定义完整的 13 个核心 AI Agent Tool Schema 并支持按名称检索与 WebMCP 注册', () => {
    expect(CLASSSET_AGENT_TOOL_SCHEMAS).toHaveLength(13);
    for (const schema of CLASSSET_AGENT_TOOL_SCHEMAS) {
      expect(schema.inputSchema.type).toBe('object');
      expect(schema.inputSchema.additionalProperties).toBe(false);
      expect(getAgentToolSchema(schema.name)).toEqual(schema);
    }

    const registeredTools: Array<{ name: string }> = [];
    const repo = createMemoryRepository();
    const executor = new ClassSetAgentToolExecutor(repo);
    const result = registerClassSetToolsToWebMCP(executor, {
      registerTool: (tool) => {
        registeredTools.push(tool);
      },
    });

    expect(result).toEqual({ registered: true, toolCount: 13 });
    expect(registeredTools.map((t) => t.name)).toEqual(
      CLASSSET_AGENT_TOOL_SCHEMAS.map((s) => s.name)
    );
  });

  it('严格执行步骤级联门控：未完成前置步骤时拒绝调用科目节数、教师任课、排课、带班或调代课工具', async () => {
    const repo = createMemoryRepository();
    await repo.initialize();
    const executor = new ClassSetAgentToolExecutor(repo);

    // 尚未创建学期时，上下文查询返回 hasTerm=false 且受控模块未解锁
    const emptyCtx = await executor.getContextAndGates();
    expect(emptyCtx.hasTerm).toBe(false);
    expect(emptyCtx.gates.scheduling.enabled).toBe(false);

    // 创建学期但尚未完成学段班级、作息、科目与教师任课
    await repo.saveTerm({
      id: 'term_empty',
      title: '空学期',
      academicYear: '2026-2027',
      semesterLabel: '第一学期',
      firstTeachingWeekStart: '2026-09-07',
      teachingWeekCount: 16,
      cycleMode: 'every_week',
      createdAt: Date.now(),
    });
    await repo.saveActiveTermId('term_empty');

    await expect(
      executor.batchConfigureSubjectsAndQuotas({
        subjects: [{ name: '数学' }],
      })
    ).rejects.toThrow('请先创建学段、年级与班级');

    await expect(
      executor.batchConfigureTeachersAndAssignments({
        teachers: [{ name: '张老师' }],
      })
    ).rejects.toThrow('请先填写各年级科目节数');

    await expect(executor.runAutoSchedule({})).rejects.toThrow(
      '请先补齐各班教师任课'
    );
    await expect(
      executor.batchCreateSupervisionPosts({
        kind: 'afterSchool',
        name: '课后服务',
        stageId: 'stage_term_empty_primary',
        classIds: ['c1'],
        weekdays: [1],
        periodTypeId: 'p1',
        lessonIndices: [1],
      })
    ).rejects.toThrow('请先创建学段、年级与班级');
    await expect(
      executor.queryActualTimetable({
        startDate: '2026-09-07',
        endDate: '2026-09-11',
      })
    ).rejects.toThrow('请先在排课与课表中生成课表');
  });

  it('支持通过 3 个基础配置工具完成「班级与学段 → 科目节数 → 教师任课与合班」全链路批量配置', async () => {
    const repo = createMemoryRepository();
    await repo.initialize();
    const termId = 'term_batch_setup';
    await repo.saveTerm({
      id: termId,
      title: '2026学年春季学期',
      academicYear: '2026-2027',
      semesterLabel: '第二学期',
      firstTeachingWeekStart: '2026-03-02',
      teachingWeekCount: 18,
      cycleMode: 'every_week',
      createdAt: Date.now(),
    });
    await repo.saveActiveTermId(termId);
    const executor = new ClassSetAgentToolExecutor(repo);

    // 1. 批量配置班级与学段：为默认小学部创建一年级（自动生成 1班、2班）
    const classRes = await executor.batchConfigureClassesAndStages({
      grades: [
        {
          name: '一年级',
          classCount: 2,
        },
      ],
    });
    expect(classRes.upsertedGradeCount).toBe(1);
    expect(classRes.upsertedClassCount).toBe(2);
    expect(classRes.classes.map((c) => c.name)).toEqual(['1班', '2班']);

    // 配置作息以解锁科目节数门控
    const stageId = classRes.stages[0].id;
    await repo.saveStageRoutine({
      stageId,
      teachingDays: [1, 2, 3, 4, 5, 6, 7].map((w) => ({
        id: `td_${stageId}_${w}`,
        stageId,
        weekday: w,
        isTeachingDay: w <= 5,
      })),
      periodTypes: [
        {
          id: 'p_am',
          stageId,
          name: '上午',
          defaultLessonCount: 4,
          sortOrder: 0,
        },
      ],
      dailyOverrides: [],
      lessonTimes: [1, 2, 3, 4].map((idx) => ({
        id: `p_am_${idx}`,
        periodTypeId: 'p_am',
        lessonIndex: idx,
        label: `第${idx}节`,
        startMinute: 480 + (idx - 1) * 45,
        endMinute: 520 + (idx - 1) * 45,
      })),
      commonPeriods: [],
    });

    // 2. 批量配置科目与节数：新增语文、数学、体育，并设置一年级周课时与单日上限
    const subjectRes = await executor.batchConfigureSubjectsAndQuotas({
      subjects: [
        { name: '语文' },
        { name: '数学' },
        { name: '体育', shortName: '体' },
      ],
      requirements: [
        { subjectName: '语文', gradeName: '一年级', lessonCount: 3 },
        { subjectName: '数学', gradeName: '一年级', lessonCount: 3 },
        { subjectName: '体育', gradeName: '一年级', lessonCount: 2 },
      ],
      lessonConstraints: [
        {
          subjectName: '数学',
          scopeType: 'stage',
          scopeId: stageId,
          stageId,
          maximumDailyLessons: 1,
        },
      ],
    });
    expect(subjectRes.upsertedSubjectCount).toBe(3);
    expect(subjectRes.updatedRequirementCount).toBe(3);
    expect(subjectRes.updatedConstraintCount).toBe(1);

    // 3. 批量配置教师与任课（含自动按科目需求节数分配与体育课跨班合班）
    const [class1, class2] = classRes.classes;
    const teacherRes = await executor.batchConfigureTeachersAndAssignments({
      teachers: [
        { name: '王老师', subjectNames: ['语文'] },
        { name: '张老师', subjectNames: ['数学'] },
        { name: '陈老师', subjectNames: ['体育'] },
      ],
      assignments: [
        {
          gradeName: '一年级',
          className: '1班',
          subjectName: '语文',
          teacherName: '王老师',
        },
        {
          gradeName: '一年级',
          className: '2班',
          subjectName: '语文',
          teacherName: '王老师',
        },
        {
          classId: class1.id,
          subjectName: '数学',
          teacherName: '张老师',
        },
        {
          classId: class2.id,
          subjectName: '数学',
          teacherName: '张老师',
        },
        {
          classId: class1.id,
          subjectName: '体育',
          teacherName: '陈老师',
        },
        {
          classId: class2.id,
          subjectName: '体育',
          teacherName: '陈老师',
        },
      ],
      combinedGroups: [
        {
          classIds: [class1.id, class2.id],
          subjectName: '体育',
        },
      ],
    });
    expect(teacherRes.upsertedTeacherCount).toBe(3);
    expect(teacherRes.updatedAssignmentCellCount).toBe(6);
    expect(teacherRes.combinedGroupCount).toBe(1);

    // 验证四步级联全部完成后可直接运行自动排课
    const autoRes = await executor.runAutoSchedule({
      retainPlacements: false,
    });
    expect(autoRes.status).toBe('complete');
    expect(autoRes.placedItems).toBe(16);
  });

  it('支持通过 Tool 配置排课预设规则、自动排课与单课节移动互换', async () => {
    const repo = createMemoryRepository();
    const ids = await seedReadySemester(repo);
    const executor = new ClassSetAgentToolExecutor(repo);

    // 1. 查询全局上下文与级联门控
    const ctx = await executor.getContextAndGates({
      includeDictionaries: ['grades_and_classes', 'subjects', 'teachers'],
    });
    expect(ctx.hasTerm).toBe(true);
    expect(ctx.gates.scheduling.enabled).toBe(true);
    expect(ctx.gates.supervision.enabled).toBe(true);
    expect(ctx.gates.temporaryAdjustments.enabled).toBe(false);

    // 2. 配置排课规则：将张老师周一上午第1节设为禁排，并设置高强度求解
    const ruleResult = await executor.configureScheduleRules({
      teacherPresets: [
        {
          teacherId: ids.teacherZhang,
          scopeType: 'stage',
          scopeId: ids.stageId,
          stageId: ids.stageId,
          weekday: 1,
          periodTypeId: ids.morningId,
          lessonIndex: 1,
          weekMode: 'weekly',
          value: 'forbid',
        },
      ],
      preferences: {
        strength: 'high',
        lunchProtection: true,
      },
    });
    expect(ruleResult.updatedTeacherCount).toBe(1);
    expect(ruleResult.preferences.strength).toBe('high');

    // 3. 执行自动排课
    const scheduleResult = await executor.runAutoSchedule({
      retainPlacements: false,
      publish: true,
    });
    expect(scheduleResult.status).toBe('complete');
    expect(scheduleResult.totalItems).toBe(4);
    expect(scheduleResult.placedItems).toBe(4);
    expect(scheduleResult.published).toBe(true);

    // 验证张老师的数学课没有排在被禁排的周一上午第1节
    const dataAfterSchedule = await repo.loadSchedulingData(ids.termId);
    const zhangMondayFirst = dataAfterSchedule.items.find(
      (item) =>
        item.teacherId === ids.teacherZhang &&
        item.weekday === 1 &&
        item.periodTypeId === ids.morningId &&
        item.lessonIndex === 1
    );
    expect(zhangMondayFirst).toBeUndefined();

    // 4. 移动单节课到暂放区（dryRun=true 不落库，dryRun=false 落库）
    const targetLesson = dataAfterSchedule.items[0];
    const dryMove = await executor.moveOrSwapLesson({
      sourceItemId: targetLesson.id,
      targetSlot: null,
      dryRun: true,
    });
    expect(dryMove.status).toBe('available');
    expect(dryMove.committed).toBe(false);
  });

  it('支持带班安排岗位批量创建、自动分配教师与按生效日期发布版本', async () => {
    const repo = createMemoryRepository();
    const ids = await seedReadySemester(repo);
    const executor = new ClassSetAgentToolExecutor(repo);

    // 先生成正课课表
    await executor.runAutoSchedule({ retainPlacements: false });

    // 1. 在免任课“课后第1节”批量创建周一、周二的课后服务带班岗位
    const createRes = await executor.batchCreateSupervisionPosts({
      kind: 'afterSchool',
      name: '课后托管',
      stageId: ids.stageId,
      classIds: [ids.classId],
      weekdays: [1, 2],
      periodTypeId: ids.afterSchoolId,
      lessonIndices: [1],
    });
    expect(createRes.errors).toEqual([]);
    expect(createRes.createdPosts).toHaveLength(2);
    expect(createRes.saved).toBe(true);

    // 2. 自动分配带班教师
    const allocRes = await executor.autoAllocateSupervision({
      matchingPreferences: {
        mode: 'balanceFirst',
      },
    });
    expect(allocRes.errors).toEqual([]);
    expect(allocRes.totalPosts).toBe(2);
    expect(allocRes.assignedCount).toBe(2);

    // 3. 发布带班版本
    const pubRes = await executor.publishSupervisionVersion({
      effectiveDate: '2026-09-07',
    });
    expect(pubRes.canPublish).toBe(true);
    expect(pubRes.published).toBe(true);
  });

  it('支持调代课模块的实际日历课表查询、无冲突候选计算、正课代课与撤销', async () => {
    const repo = createMemoryRepository();
    const ids = await seedReadySemester(repo);
    const executor = new ClassSetAgentToolExecutor(repo);

    await executor.runAutoSchedule({ retainPlacements: false });

    // 1. 查询第一周（2026-09-07 ~ 2026-09-11）实际课表
    const weekTimetable = await executor.queryActualTimetable({
      startDate: '2026-09-07',
      endDate: '2026-09-11',
      classId: ids.classId,
    });
    expect(weekTimetable.lessons.length).toBe(4);

    const firstLesson = weekTimetable.lessons[0];
    const otherTeacherId =
      firstLesson.teacherId === ids.teacherZhang
        ? ids.teacherLi
        : ids.teacherZhang;

    // 2. 查询该课次的无冲突调代课候选方案
    const withCandidates = await executor.queryActualTimetable({
      startDate: '2026-09-07',
      endDate: '2026-09-11',
      findCandidatesForSourceKey: firstLesson.sourceKey,
    });
    expect(withCandidates.candidates).not.toBeNull();
    expect(
      withCandidates.candidates?.availableSubstituteTeachers.map(
        (t) => t.teacherId
      )
    ).toContain(otherTeacherId);

    // 3. 执行正课代课
    const subRes = await executor.applyTemporaryAdjustment({
      kind: 'substitute',
      sourceKey: firstLesson.sourceKey,
      substituteTeacherId: otherTeacherId,
      reason: '外出教研代课',
    });
    expect(subRes.canCommit).toBe(true);
    expect(subRes.committed).toBe(true);
    expect(subRes.errors).toEqual([]);

    // 4. 再次查询确认产生一条生效中的调代课记录，随后撤销该记录
    const afterSub = await executor.queryActualTimetable({
      startDate: '2026-09-07',
      endDate: '2026-09-11',
    });
    expect(afterSub.activeAdjustments).toHaveLength(1);
    const recordId = afterSub.activeAdjustments[0].id;

    const cancelRes = await executor.cancelTemporaryAdjustment({
      recordId,
    });
    expect(cancelRes.cancelled).toBe(true);

    const afterCancel = await executor.queryActualTimetable({
      startDate: '2026-09-07',
      endDate: '2026-09-11',
    });
    expect(afterCancel.activeAdjustments).toHaveLength(0);
  });
});
