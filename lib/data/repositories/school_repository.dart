import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';

abstract interface class SchoolRepository {
  Stream<List<AcademicTerm>> watchTerms();

  Future<void> saveTerm(AcademicTerm term);

  Future<void> cloneTerm({
    required String sourceTermId,
    required AcademicTerm targetTerm,
  });

  Future<void> deleteTerm(String termId);

  Stream<List<SchoolStage>> watchStages(String termId);

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
}
