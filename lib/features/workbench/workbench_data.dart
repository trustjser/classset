import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 新学期排课准备的 6 个步骤（顺序即设计稿步骤条顺序）。
enum PreparationStep {
  stagesAndClasses,
  routine,
  subjectLessons,
  teacherAssignments,
  autoSchedule,
  timetable;

  /// 步骤序号（从 1 开始）。
  int get number => index + 1;

  String get title => switch (this) {
    PreparationStep.stagesAndClasses => '学段与班级',
    PreparationStep.routine => '作息设置',
    PreparationStep.subjectLessons => '科目节数',
    PreparationStep.teacherAssignments => '教师任课',
    PreparationStep.autoSchedule => '开始排课',
    PreparationStep.timetable => '打开课表',
  };
}

/// 准备工作进度摘要，全部由本地真实数据派生。
class WorkbenchSummary {
  const WorkbenchSummary({
    required this.stageCount,
    required this.gradeCount,
    required this.stagesWithRoutine,
  });

  const WorkbenchSummary.empty()
    : stageCount = 0,
      gradeCount = 0,
      stagesWithRoutine = 0;

  final int stageCount;
  final int gradeCount;

  /// 已配置作息（有上课日且至少一个时段）的学段数。
  final int stagesWithRoutine;

  /// 步骤 1「学段与班级」：已建学段且旗下有年级。
  bool get stagesDone => stageCount > 0 && gradeCount > 0;

  /// 步骤 2「作息设置」：步骤 1 已完成，且所有学段都已配置作息。
  /// 顺序语义：步骤 1 未完成时步骤 2 不计入完成。
  bool get routineDone =>
      stagesDone && stageCount > 0 && stagesWithRoutine >= stageCount;
}

/// 监听某学期下的准备进度；学段 / 年级 / 作息变化都会实时刷新。
///
/// 注意：不可在流的异步回调里再订阅其他 drift 流（嵌套订阅在假异步测试
/// 环境中不会完成）；这里改为消费单条联合查询流 `watchStageStructureStats`。
final workbenchSummaryProvider =
    StreamProvider.family<WorkbenchSummary, String>((ref, termId) {
      return ref
          .watch(schoolRepositoryProvider)
          .watchStageStructureStats(termId)
          .map((stats) {
            var gradeCount = 0;
            var stagesWithRoutine = 0;
            for (final stat in stats) {
              gradeCount += stat.gradeCount;
              if (stat.hasRoutine) stagesWithRoutine++;
            }
            return WorkbenchSummary(
              stageCount: stats.length,
              gradeCount: gradeCount,
              stagesWithRoutine: stagesWithRoutine,
            );
          });
    });

/// 当前应进行的步骤。步骤 3 及以后为后续版本，最多推进到「科目节数」。
PreparationStep currentPreparationStep(WorkbenchSummary summary) =>
    summary.stagesDone
    ? (summary.routineDone
          ? PreparationStep.subjectLessons
          : PreparationStep.routine)
    : PreparationStep.stagesAndClasses;

/// 已完成的步骤数（步骤 3 起为后续版本，暂不计入）。
int completedPreparationCount(WorkbenchSummary summary) =>
    (summary.stagesDone ? 1 : 0) + (summary.routineDone ? 1 : 0);

/// 「接下来」卡片按当前步骤展示的文案。
class StepCopy {
  const StepCopy({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.meta,
  });

  final String title;
  final String description;
  final String actionLabel;
  final String meta;
}

StepCopy stepCopyFor(PreparationStep step, WorkbenchSummary summary) =>
    switch (step) {
      PreparationStep.stagesAndClasses => StepCopy(
        title: '创建学段与班级',
        description: '先搭好学段、年级和班级，后面的作息与排课都挂靠在它上面。',
        actionLabel: '去创建学段与班级',
        meta: '已创建 ${summary.stageCount} 个学段 · ${summary.gradeCount} 个年级',
      ),
      PreparationStep.routine => StepCopy(
        title: '设置各学段作息',
        description: '按学段设置上课日、各时段节数与节次时间。完成后，科目节数会自动解锁。',
        actionLabel: '去设置作息',
        meta: '${summary.stagesWithRoutine} / ${summary.stageCount} 个学段已配置作息',
      ),
      PreparationStep.subjectLessons => StepCopy(
        title: '填写各年级的科目节数',
        description: '核对每个年级每周各科课时。完成后，教师任课会自动解锁。',
        actionLabel: '去填写科目节数',
        meta: '已准备 ${summary.gradeCount} 个年级',
      ),
      _ => const StepCopy(
        title: '准备工作已全部完成',
        description: '基础资料已就绪，后续版本将在这里继续引导排课。',
        actionLabel: '打开课表',
        meta: '',
      ),
    };

/// 为尚无年级的学期生成可用于排课的完整演示数据。
Future<void> seedDemoData({
  required SchoolRepository repository,
  required AcademicTerm term,
}) async {
  if ((await repository.watchGradesForTerm(term.id).first).isNotEmpty) {
    throw StateError('当前学期已有年级数据，不能生成演示数据');
  }
  final existingStages = await repository.watchStages(term.id).first;
  for (final name in ['小学部', '初中部']) {
    if (existingStages.where((stage) => stage.name.trim() == name).length > 1) {
      throw StateError('已有多个$name，请先整理学段');
    }
  }
  // 不覆盖用户在空学期中已经配置的作息。
  for (final stage in existingStages.where(
    (stage) => stage.name.trim() == '小学部' || stage.name.trim() == '初中部',
  )) {
    final routine = await repository.watchRoutine(stage.id).first;
    final defaults = [('早上', 0), ('上午', 4), ('下午', 4), ('晚上', 2)];
    final isDefault =
        routine != null &&
        routine.teachingWeekdays.length == 5 &&
        routine.teachingWeekdays.containsAll({1, 2, 3, 4, 5}) &&
        routine.overrides.isEmpty &&
        routine.periodTypes.length == defaults.length &&
        List.generate(defaults.length, (i) {
          final period = routine.periodTypes[i];
          return period.name == defaults[i].$1 &&
              period.defaultLessonCount == defaults[i].$2 &&
              period.lessonTimes.every(
                (time) => time.startMinute == null && time.endMinute == null,
              );
        }).every((value) => value);
    final hasCustomSlots =
        (await repository.watchFreeSlots(stage.id).first).isNotEmpty ||
        (await repository.watchCommonPeriods(stage.id).first).isNotEmpty;
    if ((routine != null && !isDefault) || hasCustomSlots) {
      throw StateError('${stage.name}已有作息，请先在空学期生成演示数据');
    }
  }

  final stamp = DateTime.now().microsecondsSinceEpoch;
  final stageNames = ['小学部', '初中部'];
  const primaryGrades = ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级'];
  const juniorGrades = ['七年级', '八年级', '九年级'];
  // 参照义务教育课程方案和地方课程设置示例，校本课程用于补足演示课时。
  const lower = {
    '语文': 8,
    '数学': 5,
    '道德与法治': 2,
    '科学': 1,
    '体育与健康': 4,
    '音乐': 2,
    '美术': 2,
    '劳动': 1,
    '综合实践活动': 1,
  };
  const upper = {
    '语文': 7,
    '数学': 5,
    '英语': 3,
    '道德与法治': 2,
    '科学': 2,
    '体育与健康': 3,
    '音乐': 2,
    '美术': 2,
    '劳动': 1,
    '综合实践活动': 1,
    '信息科技': 1,
    '班团队活动': 1,
  };
  const seven = {
    '语文': 5,
    '数学': 5,
    '英语': 4,
    '道德与法治': 2,
    '历史': 2,
    '地理': 2,
    '生物学': 2,
    '体育与健康': 3,
    '音乐': 1,
    '美术': 1,
    '劳动': 1,
    '综合实践活动': 1,
    '信息科技': 1,
    '班团队活动': 1,
    '校本课程': 3,
  };
  const eight = {
    '语文': 5,
    '数学': 5,
    '英语': 4,
    '道德与法治': 2,
    '历史': 2,
    '地理': 2,
    '生物学': 2,
    '物理': 2,
    '体育与健康': 3,
    '音乐': 1,
    '美术': 1,
    '劳动': 1,
    '综合实践活动': 1,
    '信息科技': 1,
    '班团队活动': 1,
    '校本课程': 1,
  };
  const nine = {
    '语文': 5,
    '数学': 5,
    '英语': 4,
    '道德与法治': 2,
    '历史': 2,
    '物理': 3,
    '化学': 2,
    '体育与健康': 3,
    '音乐': 1,
    '美术': 1,
    '劳动': 1,
    '综合实践活动': 1,
    '信息科技': 1,
    '班团队活动': 1,
    '校本课程': 2,
  };
  final plans = [lower, lower, upper, upper, upper, upper, seven, eight, nine];
  final names = <String>{for (final plan in plans) ...plan.keys}.toList();
  final existingSubjects = await repository.watchSubjectsForTerm(term.id).first;
  final subjects = <String, Subject>{};
  final newSubjects = <Subject>[];
  for (var i = 0; i < names.length; i++) {
    final name = names[i];
    final matches = existingSubjects.where((subject) => subject.name == name);
    final subject = matches.isNotEmpty
        ? matches.first
        : Subject(
            id: '${stamp}_subject_$i',
            termId: term.id,
            name: name,
            shortName: name,
            sortOrder: existingSubjects.length + i,
          );
    subjects[name] = subject;
    if (matches.isEmpty) newSubjects.add(subject);
  }
  await repository.saveSubjects(newSubjects);

  final teachers = <Teacher>[];
  final assignments = <TeacherAssignment>[];
  var gradeNumber = 0;
  for (var stageIndex = 0; stageIndex < 2; stageIndex++) {
    final name = stageNames[stageIndex];
    final matches = existingStages.where((stage) => stage.name.trim() == name);
    final stage = matches.isNotEmpty
        ? matches.first
        : SchoolStage(
            id: '${stamp}_stage_$stageIndex',
            termId: term.id,
            name: name,
            sortOrder: stageIndex,
          );
    if (matches.isEmpty) await repository.saveStage(stage);
    final isJunior = stageIndex == 1;
    final am = '${stage.id}_am';
    final pm = '${stage.id}_pm';
    final evening = '${stage.id}_evening';
    List<LessonTime> times(List<(int, int)> intervals) => [
      for (var i = 0; i < intervals.length; i++)
        LessonTime(
          lessonIndex: i + 1,
          label: '第 ${i + 1} 节',
          startMinute: intervals[i].$1,
          endMinute: intervals[i].$2,
        ),
    ];
    await repository.saveRoutine(
      StageRoutine(
        stageId: stage.id,
        teachingWeekdays: isJunior ? {1, 2, 3, 4, 5, 7} : {1, 2, 3, 4, 5},
        periodTypes: [
          LessonPeriodType(
            id: am,
            name: '上午时段',
            defaultLessonCount: 4,
            sortOrder: 0,
            lessonTimes: times(
              isJunior
                  ? [(480, 525), (535, 580), (600, 645), (655, 700)]
                  : [(480, 520), (530, 570), (590, 630), (640, 680)],
            ),
          ),
          LessonPeriodType(
            id: pm,
            name: '下午时段',
            defaultLessonCount: 3,
            sortOrder: 1,
            lessonTimes: times(
              isJunior
                  ? [(840, 885), (895, 940), (950, 995)]
                  : [(840, 880), (890, 930), (940, 980)],
            ),
          ),
          if (isJunior)
            LessonPeriodType(
              id: evening,
              name: '晚自习',
              defaultLessonCount: 2,
              sortOrder: 2,
              lessonTimes: times([(1140, 1185), (1195, 1240)]),
            ),
        ],
        overrides: const [],
      ),
    );
    for (final common in [('眼保健操', 2, 10), ('午休', 4, 120)]) {
      await repository.saveCommonPeriod(
        CommonPeriod(
          id: '${stage.id}_common_${common.$2}',
          stageId: stage.id,
          name: common.$1,
          insertAfterLessonId: '${am}_${common.$2}',
          durationMinutes: common.$3,
          startMinute: null,
          endMinute: null,
        ),
      );
    }
    if (isJunior) {
      for (final (periodId, weekday, lesson) in [
        (pm, 5, 3),
        for (var lesson = 1; lesson <= 2; lesson++) (evening, 5, lesson),
        for (var lesson = 1; lesson <= 4; lesson++) (am, 7, lesson),
        for (var lesson = 1; lesson <= 3; lesson++) (pm, 7, lesson),
      ]) {
        await repository.saveFreeSlot(
          FreeSlot(
            id: '${stage.id}_no_class_${periodId}_${weekday}_$lesson',
            scope: FreeSlotScope.stage,
            scopeId: stage.id,
            stageId: stage.id,
            periodTypeId: periodId,
            weekday: weekday,
            lessonIndex: lesson,
            label: FreeSlotLabels.noClass,
          ),
        );
      }
      for (final day in [1, 2, 3, 4, 7]) {
        for (var lesson = 1; lesson <= 2; lesson++) {
          await repository.saveFreeSlot(
            FreeSlot(
              id: '${stage.id}_free_${day}_$lesson',
              scope: FreeSlotScope.stage,
              scopeId: stage.id,
              stageId: stage.id,
              periodTypeId: evening,
              weekday: day,
              lessonIndex: lesson,
              label: FreeSlotLabels.selfStudy,
            ),
          );
        }
      }
    }
    final gradeNames = isJunior ? juniorGrades : primaryGrades;
    for (var g = 0; g < gradeNames.length; g++, gradeNumber++) {
      final grade = GradeGroup(
        id: '${stage.id}_grade_$g',
        stageId: stage.id,
        name: gradeNames[g],
        sortOrder: g,
      );
      await repository.saveGrade(grade);
      final classes = [
        for (var c = 0; c < (isJunior ? 8 : 6); c++)
          ClassGroup(
            id: '${grade.id}_class_$c',
            gradeId: grade.id,
            name: '${grade.name} ${c + 1} 班',
            sortOrder: c,
          ),
      ];
      await repository.saveClasses(classes);
      final plan = plans[gradeNumber];
      await repository.replaceGradeRequirements(
        gradeId: grade.id,
        requirements: [
          for (final entry in plan.entries)
            SubjectRequirement(
              id: '${grade.id}_requirement_${subjects[entry.key]!.id}',
              gradeId: grade.id,
              subjectId: subjects[entry.key]!.id,
              weekMode: WeekMode.weekly,
              lessonCount: entry.value,
            ),
        ],
      );
      for (final entry in plan.entries) {
        final subject = subjects[entry.key]!;
        Teacher? teacher;
        var load = 0;
        for (final schoolClass in classes) {
          if (teacher == null || load + entry.value > 18) {
            final index = teachers.length + 1;
            teacher = Teacher(
              id: '${stamp}_teacher_$index',
              name: '${entry.key}教师 $index',
              shortName: '${entry.key}$index',
              sortOrder: index,
              subjectIds: {subject.id},
            );
            teachers.add(teacher);
            load = 0;
          }
          load += entry.value;
          assignments.add(
            TeacherAssignment(
              id: '${schoolClass.id}_${subject.id}_assignment',
              termId: term.id,
              teacherId: teacher.id,
              classId: schoolClass.id,
              subjectId: subject.id,
              weekMode: WeekMode.weekly,
              lessonCount: entry.value,
            ),
          );
        }
      }
    }
  }
  await repository.saveTeachers(teachers);
  for (final assignment in assignments) {
    await repository.replaceTeacherAssignments(
      termId: term.id,
      classId: assignment.classId,
      subjectId: assignment.subjectId,
      assignments: [assignment],
    );
  }
}
