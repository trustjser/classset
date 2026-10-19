import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
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

/// 生成一套演示数据：两个学段，各 3 个年级、每年级 3 个班，并配置基础作息。
/// 仅用于快速体验界面；已存在学段时调用方应先行拦截。
Future<void> seedDemoData({
  required SchoolRepository repository,
  required AcademicTerm term,
}) async {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  const stageNames = ['小学部', '初中部'];
  const gradeNames = ['一年级', '二年级', '三年级'];
  for (var s = 0; s < stageNames.length; s++) {
    final stage = SchoolStage(
      id: '${stamp}_stage_$s',
      termId: term.id,
      name: stageNames[s],
      sortOrder: s,
    );
    await repository.saveStage(stage);
    for (var g = 0; g < gradeNames.length; g++) {
      final grade = GradeGroup(
        id: '${stage.id}_grade_$g',
        stageId: stage.id,
        name: gradeNames[g],
        sortOrder: g,
      );
      await repository.saveGrade(grade);
      await repository.saveClasses([
        for (var c = 0; c < 3; c++)
          ClassGroup(
            id: '${grade.id}_class_$c',
            gradeId: grade.id,
            name: '${gradeNames[g]} ${c + 1} 班',
            sortOrder: c,
          ),
      ]);
    }
    await repository.saveRoutine(
      StageRoutine(
        stageId: stage.id,
        teachingWeekdays: const {1, 2, 3, 4, 5},
        periodTypes: [
          LessonPeriodType(
            id: '${stage.id}_am',
            name: '上午时段',
            defaultLessonCount: 4,
            sortOrder: 0,
            lessonTimes: const [],
          ),
          LessonPeriodType(
            id: '${stage.id}_pm',
            name: '下午时段',
            defaultLessonCount: 3,
            sortOrder: 1,
            lessonTimes: const [],
          ),
        ],
        overrides: const [],
      ),
    );
  }
}
