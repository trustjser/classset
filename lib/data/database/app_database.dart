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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open(File file) => AppDatabase(NativeDatabase(file));

  @override
  int get schemaVersion => 3;

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
    },
    beforeOpen: (details) async => customStatement('PRAGMA foreign_keys = ON'),
  );
}
