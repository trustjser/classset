import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';

abstract interface class SchoolRepository {
  Stream<List<AcademicTerm>> watchTerms();

  Future<void> saveTerm(AcademicTerm term);

  Future<void> cloneTerm({
    required String sourceTermId,
    required AcademicTerm targetTerm,
  });

  Future<void> deleteTerm(String termId);

  Stream<List<SchoolStage>> watchStages(String termId);

  /// 某学期下各学段的结构统计流（年级数 / 是否设上课日 / 是否设时段）。
  /// 学段、年级、上课日、时段变化都会实时刷新，供引导页判断准备进度。
  Stream<List<StageStructureStat>> watchStageStructureStats(String termId);

  Future<void> saveStage(SchoolStage stage);

  Future<void> deleteStage(String stageId);

  Stream<List<GradeGroup>> watchGrades(String stageId);

  Future<void> saveGrade(GradeGroup grade);

  /// 原子保存一批年级，供批量新增和排序使用。
  Future<void> saveGrades(List<GradeGroup> grades);

  Future<void> deleteGrade(String gradeId);

  Stream<List<ClassGroup>> watchClasses(String gradeId);

  Future<void> saveClass(ClassGroup classGroup);

  /// 原子保存一批班级，供批量新增、命名、撤销和排序使用。
  Future<void> saveClasses(List<ClassGroup> classes);

  Future<void> deleteClass(String classId);

  Stream<StageRoutine?> watchRoutine(String stageId);

  Future<void> saveRoutine(StageRoutine routine);

  // —— 教学日历例外 ——

  Stream<List<CalendarException>> watchCalendarExceptions(String termId);

  Future<void> saveCalendarException(CalendarException exception);

  Future<void> saveCalendarExceptions({
    required String termId,
    required List<CalendarException> upserts,
    required Set<String> deleteIds,
  });

  Future<void> deleteCalendarException(String exceptionId);

  // —— 免任课 ——

  /// 某学段下全部范围的免任课格子（含全校 / 学段 / 年级 / 班级）。
  Stream<List<FreeSlot>> watchFreeSlots(String stageId);

  Future<void> saveFreeSlot(FreeSlot slot);

  Future<void> deleteFreeSlot(String slotId);

  // —— 公共时段 ——

  Stream<List<CommonPeriod>> watchCommonPeriods(String stageId);

  Future<void> saveCommonPeriod(CommonPeriod period);

  Future<void> deleteCommonPeriod(String periodId);

  // —— 科目与科目节数 ——

  /// 全校科目流（按 sortOrder 升序）。
  Stream<List<Subject>> watchSubjects();

  /// 原子保存一批科目（新增 / 改名 / 排序）。
  Future<void> saveSubjects(List<Subject> subjects);

  /// 删除科目；其名下的节数需求级联删除。
  Future<void> deleteSubject(String subjectId);

  /// 某年级的节数需求流：含年级默认值与按班覆盖。
  Stream<List<SubjectRequirement>> watchRequirementsForGrade(String gradeId);

  /// 全校节数需求流（单校数据文件，按年级/科目客户端过滤）。
  Stream<List<SubjectRequirement>> watchAllRequirements();

  /// 某学段下各班级的简要信息流（按年级顺序、班级顺序）。
  Stream<List<ClassBrief>> watchClassesForStage(String stageId);

  /// 以给定列表整体替换某年级的全部节数需求（年级默认 + 按班覆盖）。
  Future<void> replaceGradeRequirements({
    required String gradeId,
    required List<SubjectRequirement> requirements,
  });

  // —— 科目预设与课程配对 ——

  /// 某科目的全部预设行流（按范围 / 学段客户端过滤）。
  Stream<List<SubjectPreset>> watchPresetsForSubject(String subjectId);

  /// 全校预设行流（按范围 / 学段客户端过滤）。
  Stream<List<SubjectPreset>> watchAllPresets();

  /// 以给定网格整体替换某科目在 [stageId] 作息上下文中的某范围预设。
  ///
  /// 全校范围仍按学段分别保存；此方法只替换 [stageId] 对应的记录，避免
  /// 保存一个学段时影响其他学段的预设。
  Future<void> replaceSubjectPresets({
    required String subjectId,
    required String termId,
    required FreeSlotScope scope,
    required String scopeId,
    required String stageId,
    required List<SubjectPreset> presets,
  });

  /// 全校课程配对流（按班级客户端过滤）。
  Stream<List<SubjectPairing>> watchAllPairings();

  /// 以给定列表整体替换某班级的配对。
  Future<void> replaceClassPairings({
    required String classId,
    required List<SubjectPairing> pairings,
  });

  // —— 学期级聚合流（「全校」范围视图） ——

  /// 某学期全部年级流（按学段顺序、年级顺序）。
  Stream<List<GradeGroup>> watchGradesForTerm(String termId);

  /// 某学期全部班级简要信息流。
  Stream<List<ClassBrief>> watchClassesForTerm(String termId);

  /// 某学期各学段的作息流（stageId → 作息）。
  Stream<Map<String, StageRoutine>> watchRoutinesForTerm(String termId);

  /// 某学期全部免任课格流（含各学段展开行）。
  Stream<List<FreeSlot>> watchFreeSlotsForTerm(String termId);
}
