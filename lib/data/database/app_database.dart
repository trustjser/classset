import 'dart:io';

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

/// 科目：全校共享（不按学段隔离）。
class Subjects extends Table {
  TextColumn get id => text()();
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
  IntColumn get startMinute => integer().nullable()();
  IntColumn get endMinute => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    AcademicTerms,
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open(File file) => AppDatabase(NativeDatabase(file));

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
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
    },
    beforeOpen: (details) async => customStatement('PRAGMA foreign_keys = ON'),
  );
}
