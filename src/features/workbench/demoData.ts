import type {
  ClassGroup,
  CommonPeriod,
  FreeSlot,
  GradeGroup,
  LessonPeriodType,
  LessonTime,
  SchoolStage,
  StageRoutine,
  Subject,
  SubjectRequirement,
  Teacher,
  TeacherAssignment,
} from '../../domain/models';
import type { SchoolRepository } from '../../repository/schoolRepository';

const PRIMARY_GRADES = ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级'];
const JUNIOR_GRADES = ['七年级', '八年级', '九年级'];

const LOWER = {
  语文: 8, 数学: 5, 道德与法治: 2, 科学: 1, 体育与健康: 4, 音乐: 2, 美术: 2,
  劳动: 1, 综合实践活动: 1,
};
const UPPER = {
  语文: 7, 数学: 5, 英语: 3, 道德与法治: 2, 科学: 2, 体育与健康: 3, 音乐: 2,
  美术: 2, 劳动: 1, 综合实践活动: 1, 信息科技: 1, 班团队活动: 1,
};
const SEVEN = {
  语文: 5, 数学: 5, 英语: 4, 道德与法治: 2, 历史: 2, 地理: 2, 生物学: 2,
  体育与健康: 3, 音乐: 1, 美术: 1, 劳动: 1, 综合实践活动: 1, 信息科技: 1,
  班团队活动: 1, 校本课程: 3,
};
const EIGHT = {
  语文: 5, 数学: 5, 英语: 4, 道德与法治: 2, 历史: 2, 地理: 2, 生物学: 2,
  物理: 2, 体育与健康: 3, 音乐: 1, 美术: 1, 劳动: 1, 综合实践活动: 1,
  信息科技: 1, 班团队活动: 1, 校本课程: 1,
};
const NINE = {
  语文: 5, 数学: 5, 英语: 4, 道德与法治: 2, 历史: 2, 物理: 3, 化学: 2,
  体育与健康: 3, 音乐: 1, 美术: 1, 劳动: 1, 综合实践活动: 1, 信息科技: 1,
  班团队活动: 1, 校本课程: 2,
};
const PLANS = [LOWER, LOWER, UPPER, UPPER, UPPER, UPPER, SEVEN, EIGHT, NINE];

function isDefaultStageRoutine(routine: StageRoutine): boolean {
  const periods = [['早上', 0], ['上午', 4], ['下午', 4], ['晚上', 2]] as const;
  return routine.teachingDays.filter((day) => day.isTeachingDay).length === 5 &&
    [1, 2, 3, 4, 5].every((weekday) => routine.teachingDays.some((day) => day.weekday === weekday && day.isTeachingDay)) &&
    routine.dailyOverrides.length === 0 &&
    routine.periodTypes.length === periods.length &&
    periods.every(([name, count], index) => {
      const period = routine.periodTypes[index];
      return period.name === name && period.defaultLessonCount === count &&
        routine.lessonTimes.filter((time) => time.periodTypeId === period.id)
          .every((time) => time.startMinute === null && time.endMinute === null);
    });
}

function makeTimes(periodTypeId: string, intervals: [number, number][]): LessonTime[] {
  return intervals.map(([startMinute, endMinute], index) => ({
    id: `${periodTypeId}_${index + 1}`,
    periodTypeId,
    lessonIndex: index + 1,
    label: `第 ${index + 1} 节`,
    startMinute,
    endMinute,
  }));
}

function makeRoutine(stageId: string, junior: boolean): StageRoutine {
  const amId = `${stageId}_am`;
  const pmId = `${stageId}_pm`;
  const eveningId = `${stageId}_evening`;
  const periodTypes: LessonPeriodType[] = [
    { id: amId, stageId, name: '上午时段', defaultLessonCount: 4, sortOrder: 0 },
    { id: pmId, stageId, name: '下午时段', defaultLessonCount: 3, sortOrder: 1 },
    ...(junior ? [{ id: eveningId, stageId, name: '晚自习', defaultLessonCount: 2, sortOrder: 2 }] : []),
  ];
  const lessonTimes = [
    ...makeTimes(amId, junior
      ? [[480, 525], [535, 580], [600, 645], [655, 700]]
      : [[480, 520], [530, 570], [590, 630], [640, 680]]),
    ...makeTimes(pmId, junior
      ? [[840, 885], [895, 940], [950, 995]]
      : [[840, 880], [890, 930], [940, 980]]),
    ...(junior ? makeTimes(eveningId, [[1140, 1185], [1195, 1240]]) : []),
  ];
  const commonPeriods: CommonPeriod[] = [
    { id: `${stageId}_common_2`, stageId, name: '眼保健操', insertAfterLessonId: `${amId}_2`, durationMinutes: 10, sortOrder: 0, startMinute: null, endMinute: null },
    { id: `${stageId}_common_4`, stageId, name: '午休', insertAfterLessonId: `${amId}_4`, durationMinutes: 120, sortOrder: 1, startMinute: null, endMinute: null },
  ];
  return {
    stageId,
    teachingDays: Array.from({ length: 7 }, (_, index) => ({
      id: `${stageId}_day_${index + 1}`, stageId, weekday: index + 1,
      isTeachingDay: junior ? index < 5 || index === 6 : index < 5,
    })),
    periodTypes,
    dailyOverrides: [],
    lessonTimes,
    commonPeriods,
  };
}

function makeFreeSlots(stageId: string): FreeSlot[] {
  const slots: FreeSlot[] = [];
  const add = (periodTypeId: string, weekday: number, lessonIndex: number, label: string) => {
    slots.push({
      id: `${stageId}_${label === '不上课' ? 'no_class' : 'free'}_${periodTypeId}_${weekday}_${lessonIndex}`,
      scopeType: 'stage', scopeId: stageId, stageId, periodTypeId, weekday, lessonIndex, label,
    });
  };
  const pmId = `${stageId}_pm`;
  const eveningId = `${stageId}_evening`;
  add(pmId, 5, 3, '不上课');
  for (let lesson = 1; lesson <= 2; lesson++) add(eveningId, 5, lesson, '不上课');
  for (let lesson = 1; lesson <= 4; lesson++) add(`${stageId}_am`, 7, lesson, '不上课');
  for (let lesson = 1; lesson <= 3; lesson++) add(pmId, 7, lesson, '不上课');
  for (const weekday of [1, 2, 3, 4, 7]) {
    for (let lesson = 1; lesson <= 2; lesson++) add(eveningId, weekday, lesson, '自习');
  }
  return slots;
}

/** 为尚无年级的学期生成与 Flutter 工作台一致的完整演示数据。 */
export async function seedDemoData(repository: SchoolRepository, termId: string): Promise<void> {
  if ((await repository.loadGradesForTerm(termId)).length > 0) {
    throw new Error('当前学期已有年级数据，不能生成演示数据');
  }
  const existingStages = await repository.loadStages(termId);
  for (const name of ['小学部', '初中部']) {
    if (existingStages.filter((stage) => stage.name.trim() === name).length > 1) {
      throw new Error(`已有多个${name}，请先整理学段`);
    }
  }
  const targetStages = existingStages.filter((stage) => ['小学部', '初中部'].includes(stage.name.trim()));
  for (const stage of targetStages) {
    const routine = await repository.loadStageRoutine(stage.id);
    const hasRoutine = routine.periodTypes.length > 0 && routine.teachingDays.some((day) => day.isTeachingDay);
    const hasCustomSlots = (await repository.loadFreeSlots(stage.id)).length > 0 ||
      (routine.commonPeriods?.length ?? 0) > 0;
    if ((hasRoutine && !isDefaultStageRoutine(routine)) || hasCustomSlots) {
      throw new Error(`${stage.name}已有作息，请先在空学期生成演示数据`);
    }
  }

  const stamp = Date.now() * 1000;
  const names = [...new Set(PLANS.flatMap((plan) => Object.keys(plan)))];
  const existingSubjects = await repository.loadSubjects(termId);
  const subjects = new Map<string, Subject>();
  const newSubjects: Subject[] = [];
  names.forEach((name, index) => {
    const existing = existingSubjects.find((subject) => subject.name === name);
    const subject = existing ?? {
      id: `${stamp}_subject_${index}`, termId, name, shortName: name,
      sortOrder: existingSubjects.length + index,
    };
    subjects.set(name, subject);
    if (!existing) newSubjects.push(subject);
  });
  await repository.saveSubjects(newSubjects);

  const teachers: Teacher[] = [];
  const assignments: TeacherAssignment[] = [];
  let gradeNumber = 0;
  for (let stageIndex = 0; stageIndex < 2; stageIndex++) {
    const name = stageIndex === 0 ? '小学部' : '初中部';
    const stage = existingStages.find((item) => item.name.trim() === name) ?? {
      id: `${stamp}_stage_${stageIndex}`, termId, name, sortOrder: stageIndex,
    } satisfies SchoolStage;
    if (!existingStages.some((item) => item.id === stage.id)) await repository.saveStage(stage);
    const junior = stageIndex === 1;
    await repository.saveStageRoutine(makeRoutine(stage.id, junior));
    if (junior) await repository.saveFreeSlotChanges(makeFreeSlots(stage.id), []);

    const gradeNames = junior ? JUNIOR_GRADES : PRIMARY_GRADES;
    for (let gradeIndex = 0; gradeIndex < gradeNames.length; gradeIndex++, gradeNumber++) {
      const grade: GradeGroup = {
        id: `${stage.id}_grade_${gradeIndex}`, stageId: stage.id,
        name: gradeNames[gradeIndex], sortOrder: gradeIndex,
      };
      await repository.saveGrades([grade]);
      const classes: ClassGroup[] = Array.from({ length: junior ? 8 : 6 }, (_, classIndex) => ({
        id: `${grade.id}_class_${classIndex}`, gradeId: grade.id,
        name: `${grade.name} ${classIndex + 1} 班`, sortOrder: classIndex,
      }));
      await repository.saveClasses(classes);

      const plan = PLANS[gradeNumber];
      const requirements: SubjectRequirement[] = Object.entries(plan).map(([subjectName, lessonCount]) => {
        const subject = subjects.get(subjectName)!;
        return {
          id: `${grade.id}_requirement_${subject.id}`, gradeId: grade.id,
          subjectId: subject.id, classId: null, weekMode: 'weekly', lessonCount,
        };
      });
      await repository.replaceGradeRequirements(grade.id, requirements);

      for (const [subjectName, lessonCount] of Object.entries(plan)) {
        const subject = subjects.get(subjectName)!;
        let teacher: Teacher | undefined;
        let load = 0;
        for (const schoolClass of classes) {
          if (!teacher || load + lessonCount > 18) {
            const index = teachers.length + 1;
            teacher = {
              id: `${stamp}_teacher_${index}`, name: `${subjectName}教师 ${index}`,
              shortName: `${subjectName}${index}`, displayQualifier: '', sortOrder: index,
              subjectIds: [subject.id],
            };
            teachers.push(teacher);
            load = 0;
          }
          load += lessonCount;
          assignments.push({
            id: `${schoolClass.id}_${subject.id}_assignment`, termId,
            teacherId: teacher.id, classId: schoolClass.id, subjectId: subject.id,
            weekMode: 'weekly', lessonCount, sortOrder: 0, combinedLessonGroupId: null,
          });
        }
      }
    }
  }
  await repository.saveTeachers(teachers);
  for (const assignment of assignments) {
    await repository.replaceTeacherAssignments({
      termId, classId: assignment.classId, subjectId: assignment.subjectId,
      assignments: [assignment],
    });
  }
}
