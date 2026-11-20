import 'dart:io';

import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

class AcademicTerms extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get academicYear => text()();
  TextColumn get semesterLabel => text()();
  TextColumn get firstTeachingWeekStart => text().nullable()();
  IntColumn get teachingWeekCount =>
      integer().withDefault(const Constant(20))();
  TextColumn get cycleMode =>
      text().withDefault(const Constant('alternating'))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// This device has one school and one currently selected term.
class AppSettings extends Table {
  IntColumn get id => integer()();
  TextColumn get schoolName => text().withDefault(const Constant(''))();
  TextColumn get activeTermId => text().nullable().references(
    AcademicTerms,
    #id,
    onDelete: KeyAction.setNull,
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SchoolStages extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class GradeGroups extends Table {
  TextColumn get id => text()();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ClassGroups extends Table {
  TextColumn get id => text()();
  TextColumn get gradeId =>
      text().references(GradeGroups, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class StageTeachingDays extends Table {
  TextColumn get id => text()();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  IntColumn get weekday => integer()();
  BoolColumn get isTeachingDay => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LessonPeriodTypes extends Table {
  TextColumn get id => text()();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get defaultLessonCount => integer()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class DailyLessonOverrides extends Table {
  TextColumn get id => text()();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  TextColumn get periodTypeId =>
      text().references(LessonPeriodTypes, #id, onDelete: KeyAction.cascade)();
  IntColumn get weekday => integer()();
  IntColumn get lessonCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LessonTimes extends Table {
  TextColumn get id => text()();
  TextColumn get periodTypeId =>
      text().references(LessonPeriodTypes, #id, onDelete: KeyAction.cascade)();
  IntColumn get lessonIndex => integer()();
  TextColumn get label => text()();
  IntColumn get startMinute => integer().nullable()();
  IntColumn get endMinute => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 教学日历例外：停课 / 节假日与补课日映射。
class CalendarExceptions extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();

  /// yyyy-MM-dd，仅日期。
  TextColumn get date => text()();

  /// holiday=停课/节假日，makeup=补课。
  TextColumn get kind => text()();

  /// 补课日采用的课表星期（1-7）；停课日为 null。
  IntColumn get makeupWeekday => integer().nullable()();

  /// 补课对应的原课日期（yyyy-MM-dd）；停课日为 null。
  TextColumn get makeupForDate => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 科目：按学期维护，同一学期内各学段共享。
class Subjects extends Table {
  TextColumn get id => text()();
  TextColumn get termId => text().nullable().references(
    AcademicTerms,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get name => text()();
  TextColumn get shortName => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 科目节数需求：科目 × 年级（或班级）× 周模式 的每周节数。
class SubjectRequirements extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();
  TextColumn get gradeId =>
      text().references(GradeGroups, #id, onDelete: KeyAction.cascade)();

  /// 非 null = 按班覆盖；null = 年级默认。
  TextColumn get classId => text().nullable().references(
    ClassGroups,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// weekly / odd / even。
  TextColumn get weekMode => text().withDefault(const Constant('weekly'))();
  IntColumn get lessonCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 科目预设：科目 × 范围 × 学段 × 星期 × 时段 × 节次 的位置偏好。
class SubjectPresets extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();

  /// school/stage/grade/class；全校 scopeId = 学期 ID。
  TextColumn get scopeType => text()();
  TextColumn get scopeId => text()();

  /// 所属学段（全校范围行按学段展开存储）。
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  IntColumn get weekday => integer()();
  TextColumn get periodTypeId =>
      text().references(LessonPeriodTypes, #id, onDelete: KeyAction.cascade)();
  IntColumn get lessonIndex => integer()();

  /// auto/prefer/must/forbid。
  TextColumn get value => text().withDefault(const Constant('auto'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 课程配对：同班两门课（一单一双）共用同一时段。
class SubjectPairings extends Table {
  TextColumn get id => text()();
  TextColumn get classId =>
      text().references(ClassGroups, #id, onDelete: KeyAction.cascade)();
  TextColumn get oddSubjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();
  TextColumn get evenSubjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 科目单日课节、单日连堂与每周连堂限制（不含全校范围）。
class SubjectLessonConstraints extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();
  TextColumn get scopeType => text()();
  TextColumn get scopeId => text()();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();

  /// null 表示“每天”；1 到 7 覆盖某个星期。
  IntColumn get weekday => integer().nullable()();
  IntColumn get minimumDailyLessons => integer().nullable()();
  IntColumn get maximumDailyLessons => integer().nullable()();
  IntColumn get minimumDailyConsecutivePairs => integer().nullable()();
  IntColumn get maximumDailyConsecutivePairs => integer().nullable()();
  IntColumn get minimumWeeklyConsecutivePairs => integer().nullable()();
  IntColumn get maximumWeeklyConsecutivePairs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {subjectId, scopeType, scopeId, stageId, weekday},
  ];
}

/// 免任课格子：按范围（全校/学段/年级/班级）标记具体节次不排课。
class FreeSlots extends Table {
  TextColumn get id => text()();

  /// school/stage/grade/class。
  TextColumn get scopeType => text()();

  /// 范围实体 ID：全校=学期 ID，学段=学段 ID，年级=年级 ID，班级=班级 ID。
  TextColumn get scopeId => text()();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  TextColumn get periodTypeId =>
      text().references(LessonPeriodTypes, #id, onDelete: KeyAction.cascade)();
  IntColumn get weekday => integer()();
  IntColumn get lessonIndex => integer()();
  TextColumn get label => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 公共时段（大课间、眼保健操等）：不占授课节次，仅显示于课表与打印。
class CommonPeriods extends Table {
  TextColumn get id => text()();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();

  /// 挂在 lesson_times.id 之后；null = 第 1 节之前。
  TextColumn get insertAfterLessonId => text().nullable()();
  IntColumn get durationMinutes => integer().withDefault(const Constant(10))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get startMinute => integer().nullable()();
  IntColumn get endMinute => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PublicRooms extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get roomCount => integer()();
  IntColumn get capacityPerRoom => integer()();
  IntColumn get sortOrder => integer()();

  @override
  List<String> get customConstraints => [
    'CHECK (room_count > 0)',
    'CHECK (capacity_per_room > 0)',
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SubjectRoomAssignments extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  TextColumn get scopeType => text()();
  TextColumn get scopeId => text()();
  TextColumn get roomId => text().nullable().references(
    PublicRooms,
    #id,
    onDelete: KeyAction.cascade,
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {subjectId, termId, scopeType, scopeId},
  ];
}

class SubjectParallelLimits extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  TextColumn get scopeType => text()();
  TextColumn get scopeId => text()();
  IntColumn get maxParallelLessons => integer()();

  @override
  List<String> get customConstraints => ['CHECK (max_parallel_lessons > 0)'];

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {subjectId, termId, scopeType, scopeId},
  ];
}

/// Global teacher identity. A teacher may be reused by assignments in many terms.
class Teachers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get shortName => text().withDefault(const Constant(''))();
  TextColumn get displayQualifier => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Teacher subject tags are preferences/filter hints, not hard assignment limits.
class TeacherSubjectTags extends Table {
  TextColumn get teacherId =>
      text().references(Teachers, #id, onDelete: KeyAction.cascade)();
  TextColumn get subjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {teacherId, subjectId};
}

/// A term-scoped optional teacher group.
class TeacherGroups extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TeacherGroupMembers extends Table {
  TextColumn get groupId =>
      text().references(TeacherGroups, #id, onDelete: KeyAction.cascade)();
  TextColumn get teacherId =>
      text().references(Teachers, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {groupId, teacherId};
}

/// A teacher split assignment for one class and subject.
class TeacherAssignments extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get teacherId => text().nullable().references(
    Teachers,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get subjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();
  TextColumn get classId =>
      text().references(ClassGroups, #id, onDelete: KeyAction.cascade)();
  TextColumn get weekMode => text().withDefault(const Constant('weekly'))();
  IntColumn get lessonCount => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get combinedLessonGroupId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Personal teacher preset cells. A row is an explicit override, including auto.
class TeacherPresets extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get teacherId =>
      text().references(Teachers, #id, onDelete: KeyAction.cascade)();
  TextColumn get scopeType => text()();
  TextColumn get scopeId => text()();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  IntColumn get weekday => integer()();
  TextColumn get periodTypeId =>
      text().references(LessonPeriodTypes, #id, onDelete: KeyAction.cascade)();
  IntColumn get lessonIndex => integer()();
  TextColumn get weekMode => text().withDefault(const Constant('weekly'))();
  TextColumn get value => text().withDefault(const Constant('auto'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {
      termId,
      teacherId,
      scopeType,
      scopeId,
      stageId,
      weekday,
      periodTypeId,
      lessonIndex,
    },
  ];
}

/// Group preset cells, inherited by members unless a personal row overrides it.
class TeacherGroupPresets extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(TeacherGroups, #id, onDelete: KeyAction.cascade)();
  TextColumn get scopeType => text()();
  TextColumn get scopeId => text()();
  TextColumn get stageId =>
      text().references(SchoolStages, #id, onDelete: KeyAction.cascade)();
  IntColumn get weekday => integer()();
  TextColumn get periodTypeId =>
      text().references(LessonPeriodTypes, #id, onDelete: KeyAction.cascade)();
  IntColumn get lessonIndex => integer()();
  TextColumn get weekMode => text().withDefault(const Constant('weekly'))();
  TextColumn get value => text().withDefault(const Constant('auto'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {groupId, scopeType, scopeId, stageId, weekday, periodTypeId, lessonIndex},
  ];
}

/// One expanded lesson occurrence, including lessons waiting for placement.
@TableIndex(name: 'schedule_items_term', columns: {#termId})
@TableIndex(name: 'schedule_items_assignment', columns: {#assignmentId})
@TableIndex(
  name: 'schedule_items_class_slot',
  columns: {
    #termId,
    #classId,
    #weekMode,
    #weekday,
    #periodTypeId,
    #lessonIndex,
  },
)
@TableIndex(
  name: 'schedule_items_teacher_slot',
  columns: {
    #termId,
    #teacherId,
    #weekMode,
    #weekday,
    #periodTypeId,
    #lessonIndex,
  },
)
class ScheduleItems extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get assignmentId =>
      text().references(TeacherAssignments, #id, onDelete: KeyAction.cascade)();
  TextColumn get classId =>
      text().references(ClassGroups, #id, onDelete: KeyAction.cascade)();
  TextColumn get teacherId => text().nullable().references(
    Teachers,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get subjectId =>
      text().references(Subjects, #id, onDelete: KeyAction.cascade)();
  TextColumn get weekMode => text().withDefault(const Constant('weekly'))();

  /// Shared identifier for lessons taught to multiple classes together.
  TextColumn get combinedGroupId => text().nullable()();

  /// Shared identifier for occurrences placed at the same time.
  TextColumn get meetingId => text().nullable()();

  /// All four slot columns are null while the lesson is waiting for placement.
  TextColumn get stageId => text().nullable().references(
    SchoolStages,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get weekday => integer().nullable()();
  TextColumn get periodTypeId => text().nullable().references(
    LessonPeriodTypes,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get lessonIndex => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A user lock on an occurrence or another schedule target.
@TableIndex(
  name: 'schedule_locks_target',
  columns: {#termId, #scope, #targetId},
  unique: true,
)
class ScheduleLocks extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get scope => text()();
  TextColumn get targetId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A hard or soft condition applied to a schedule target.
@TableIndex(
  name: 'schedule_conditions_target',
  columns: {#termId, #targetKind, #targetId},
)
class ScheduleConditions extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get name => text().nullable()();
  TextColumn get targetKind => text().nullable()();
  TextColumn get targetId => text().nullable()();
  TextColumn get otherId => text().nullable()();
  TextColumn get periodTypeId => text().nullable().references(
    LessonPeriodTypes,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get weekday => integer().nullable()();
  IntColumn get minCount => integer().nullable()();
  IntColumn get maxCount => integer().nullable()();
  IntColumn get exactCount => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Term-wide solver preferences.
class SchedulePreferences extends Table {
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get strength => text()();
  TextColumn get progressConsistency => text()();
  TextColumn get teacherDistribution => text()();
  BoolColumn get lunchProtection => boolean()();
  TextColumn get consecutivePolicy => text()();
  BoolColumn get detectProgressConsistency => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {termId};
}

/// Stored diagnostics and provenance for a solver run.
@TableIndex(
  name: 'schedule_run_reports_term_created',
  columns: {#termId, #createdAt},
)
class ScheduleRunReports extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  IntColumn get createdAt => integer()();
  TextColumn get solverVersion => text()();
  IntColumn get seed => integer()();
  TextColumn get strength => text()();
  TextColumn get inputFingerprint => text()();
  TextColumn get reportJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Frozen scheduling input and manually adjusted timetable before settings
/// change. It survives cascades from edited routines and assignments.
class ScheduleReconciliationBaselines extends Table {
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get snapshotJson => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {termId};
}

class PublishedSchedules extends Table {
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get dataJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {termId};
}

/// 临时调代课记录；常规课表始终保留在 ScheduleItems 中。
class TemporaryCourseAdjustments extends Table {
  TextColumn get id => text()();
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get changesJson => text()();
  TextColumn get reason => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SupervisionDraftRow')
class SupervisionDrafts extends Table {
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {termId};
}

@DataClassName('SupervisionPlanVersionRow')
class SupervisionPlanVersions extends Table {
  TextColumn get termId =>
      text().references(AcademicTerms, #id, onDelete: KeyAction.cascade)();
  TextColumn get effectiveDate => text()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {termId, effectiveDate};
}

@DriftDatabase(
  tables: [
    AcademicTerms,
    AppSettings,
    SchoolStages,
    GradeGroups,
    ClassGroups,
    StageTeachingDays,
    LessonPeriodTypes,
    DailyLessonOverrides,
    LessonTimes,
    CalendarExceptions,
    FreeSlots,
    CommonPeriods,
    Subjects,
    SubjectRequirements,
    SubjectPresets,
    SubjectPairings,
    SubjectLessonConstraints,
    PublicRooms,
    SubjectRoomAssignments,
    SubjectParallelLimits,
    Teachers,
    TeacherSubjectTags,
    TeacherGroups,
    TeacherGroupMembers,
    TeacherAssignments,
    TeacherPresets,
    TeacherGroupPresets,
    ScheduleItems,
    ScheduleLocks,
    ScheduleConditions,
    SchedulePreferences,
    ScheduleRunReports,
    ScheduleReconciliationBaselines,
    PublishedSchedules,
    TemporaryCourseAdjustments,
    SupervisionDrafts,
    SupervisionPlanVersions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open(File file) => AppDatabase(NativeDatabase(file));

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from >= 2 && from < 16) {
        final hasCommonPeriods = (await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'common_periods'",
        ).get()).isNotEmpty;
        if (hasCommonPeriods) {
          await migrator.addColumn(commonPeriods, commonPeriods.sortOrder);
        } else {
          await migrator.createTable(commonPeriods);
        }
      }
      if (from < 12) {
        await migrator.createTable(appSettings);
      }
      if (from < 8) {
        await migrator.createTable(publicRooms);
        await migrator.createTable(subjectRoomAssignments);
        await migrator.createTable(subjectParallelLimits);
      }
      if (from < 9) {
        await migrator.createTable(teachers);
        await migrator.createTable(teacherSubjectTags);
        await migrator.createTable(teacherGroups);
        await migrator.createTable(teacherGroupMembers);
        await migrator.createTable(teacherAssignments);
        await migrator.createTable(teacherPresets);
        await migrator.createTable(teacherGroupPresets);
      }
      if (from >= 9 && from < 10) {
        await migrator.addColumn(
          teacherAssignments,
          teacherAssignments.sortOrder,
        );
      }
      if (from >= 9 && from < 11) {
        await migrator.alterTable(TableMigration(teachers));
      }
      if (from < 2) {
        await migrator.createTable(calendarExceptions);
        await migrator.createTable(freeSlots);
        await migrator.createTable(commonPeriods);
      }
      if (from < 3) {
        await migrator.addColumn(academicTerms, academicTerms.cycleMode);
      }
      if (from < 4) {
        await migrator.createTable(subjects);
        await migrator.createTable(subjectRequirements);
      }
      if (from < 5) {
        await migrator.createTable(subjectPresets);
        await migrator.createTable(subjectPairings);
      }
      if (from < 6) {
        await migrator.createTable(subjectLessonConstraints);
      }
      // A newly-created table already includes these columns when upgrading
      // from before v6; only add them to databases that already had the table.
      if (from >= 6 && from < 7) {
        await migrator.addColumn(
          subjectLessonConstraints,
          subjectLessonConstraints.minimumDailyConsecutivePairs,
        );
        await migrator.addColumn(
          subjectLessonConstraints,
          subjectLessonConstraints.maximumDailyConsecutivePairs,
        );
      }
      if (from < 13) {
        if (from >= 4) {
          final hasSubjects = (await customSelect(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'subjects'",
          ).get()).isNotEmpty;
          if (hasSubjects) {
            await migrator.addColumn(subjects, subjects.termId);
          } else {
            await migrator.createTable(subjects);
          }
        }
        await _migrateSubjectsToTerms();
      }
      if (from < 14) {
        await migrator.createTable(scheduleItems);
        await migrator.createTable(scheduleLocks);
        await migrator.createTable(scheduleConditions);
        await migrator.createTable(schedulePreferences);
        await migrator.createTable(scheduleRunReports);
        await migrator.createIndex(scheduleItemsTerm);
        await migrator.createIndex(scheduleItemsAssignment);
        await migrator.createIndex(scheduleItemsClassSlot);
        await migrator.createIndex(scheduleItemsTeacherSlot);
        await migrator.createIndex(scheduleLocksTarget);
        await migrator.createIndex(scheduleConditionsTarget);
        await migrator.createIndex(scheduleRunReportsTermCreated);
      }
      if (from < 15) {
        await migrator.createTable(scheduleReconciliationBaselines);
      }
      if (from < 17) {
        await migrator.createTable(temporaryCourseAdjustments);
      }
      if (from < 18) {
        await migrator.createTable(supervisionDrafts);
        await migrator.createTable(supervisionPlanVersions);
      }
      if (from < 19 && to >= 19) {
        await transaction(() async {
          await migrator.createTable(publishedSchedules);
          await DriftSchoolRepository(this).migratePublishedSchedules();
        });
      }
    },
    beforeOpen: (details) async => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<void> _migrateSubjectsToTerms() async {
    final hasTerms = (await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'academic_terms'",
    ).get()).isNotEmpty;
    if (!hasTerms) return;
    final terms = await customSelect(
      'SELECT id FROM academic_terms ORDER BY rowid',
    ).get();
    if (terms.isEmpty) return;

    final oldSubjects = await customSelect(
      'SELECT id, name, short_name, sort_order FROM subjects '
      'WHERE term_id IS NULL',
    ).get();
    final existingIds = (await customSelect(
      'SELECT id FROM subjects',
    ).get()).map((row) => row.read<String>('id')).toSet();

    for (final subject in oldSubjects) {
      final oldId = subject.read<String>('id');
      for (final (index, term) in terms.indexed) {
        final termId = term.read<String>('id');
        if (index == 0) {
          await customStatement(
            'UPDATE subjects SET term_id = ? WHERE id = ?',
            [termId, oldId],
          );
          continue;
        }

        final baseId = '${oldId}__term__$termId';
        var newId = baseId;
        var suffix = 1;
        while (existingIds.contains(newId)) {
          newId = '${baseId}_${suffix++}';
        }
        existingIds.add(newId);
        await customStatement(
          'INSERT INTO subjects (id, term_id, name, short_name, sort_order) '
          'VALUES (?, ?, ?, ?, ?)',
          [
            newId,
            termId,
            subject.read<String>('name'),
            subject.read<String>('short_name'),
            subject.read<int>('sort_order'),
          ],
        );
        await _moveSubjectReferencesToTerm(oldId, newId, termId);
      }
    }
  }

  Future<void> _moveSubjectReferencesToTerm(
    String oldId,
    String newId,
    String termId,
  ) async {
    const stageIds = 'SELECT id FROM school_stages WHERE term_id = ?';
    const gradeIds =
        'SELECT g.id FROM grade_groups g '
        'JOIN school_stages s ON s.id = g.stage_id WHERE s.term_id = ?';
    const classIds =
        'SELECT c.id FROM class_groups c '
        'JOIN grade_groups g ON g.id = c.grade_id '
        'JOIN school_stages s ON s.id = g.stage_id WHERE s.term_id = ?';

    for (final (table, column, termPredicate) in <(String, String, String)>[
      ('subject_requirements', 'subject_id', 'grade_id IN ($gradeIds)'),
      ('subject_presets', 'subject_id', 'stage_id IN ($stageIds)'),
      ('subject_lesson_constraints', 'subject_id', 'stage_id IN ($stageIds)'),
      ('subject_pairings', 'odd_subject_id', 'class_id IN ($classIds)'),
      ('subject_pairings', 'even_subject_id', 'class_id IN ($classIds)'),
      ('subject_room_assignments', 'subject_id', 'term_id = ?'),
      ('subject_parallel_limits', 'subject_id', 'term_id = ?'),
      ('teacher_assignments', 'subject_id', 'term_id = ?'),
    ]) {
      await customStatement(
        'UPDATE $table SET $column = ? WHERE $column = ? AND $termPredicate',
        [newId, oldId, termId],
      );
    }
    await customStatement(
      'INSERT OR IGNORE INTO teacher_subject_tags (teacher_id, subject_id) '
      'SELECT teacher_id, ? FROM teacher_subject_tags WHERE subject_id = ?',
      [newId, oldId],
    );
  }
}
