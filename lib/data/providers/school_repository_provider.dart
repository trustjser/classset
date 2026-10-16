import 'package:class_set/data/providers/database_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final schoolRepositoryProvider = Provider<SchoolRepository>(
  (ref) => DriftSchoolRepository(ref.watch(appDatabaseProvider)),
);

final termsProvider = StreamProvider<List<AcademicTerm>>(
  (ref) => ref.watch(schoolRepositoryProvider).watchTerms(),
);

final stagesProvider = StreamProvider.family<List<SchoolStage>, String>(
  (ref, termId) => ref.watch(schoolRepositoryProvider).watchStages(termId),
);

final gradesProvider = StreamProvider.family<List<GradeGroup>, String>(
  (ref, stageId) => ref.watch(schoolRepositoryProvider).watchGrades(stageId),
);

final classesProvider = StreamProvider.family<List<ClassGroup>, String>(
  (ref, gradeId) => ref.watch(schoolRepositoryProvider).watchClasses(gradeId),
);

final routineProvider = StreamProvider.family<StageRoutine?, String>(
  (ref, stageId) => ref.watch(schoolRepositoryProvider).watchRoutine(stageId),
);

final calendarExceptionsProvider =
    StreamProvider.family<List<CalendarException>, String>(
      (ref, termId) =>
          ref.watch(schoolRepositoryProvider).watchCalendarExceptions(termId),
    );

final freeSlotsProvider = StreamProvider.family<List<FreeSlot>, String>(
  (ref, stageId) => ref.watch(schoolRepositoryProvider).watchFreeSlots(stageId),
);

final commonPeriodsProvider = StreamProvider.family<List<CommonPeriod>, String>(
  (ref, stageId) =>
      ref.watch(schoolRepositoryProvider).watchCommonPeriods(stageId),
);
