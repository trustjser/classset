import 'package:class_set/data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v15 公共时段升级保留数据并添加排序', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (connection) {
          connection.execute(
            'CREATE TABLE common_periods (id TEXT NOT NULL PRIMARY KEY, stage_id TEXT NOT NULL, name TEXT NOT NULL, insert_after_lesson_id TEXT, duration_minutes INTEGER NOT NULL DEFAULT 10, start_minute INTEGER, end_minute INTEGER)',
          );
          connection.execute(
            "INSERT INTO common_periods (id, stage_id, name, duration_minutes) VALUES ('a', 's', '课间', 15)",
          );
          connection.execute('PRAGMA user_version = 15');
        },
      ),
    );
    addTearDown(database.close);
    final rows = await database
        .customSelect('SELECT duration_minutes, sort_order FROM common_periods')
        .get();
    expect(rows.single.read<int>('duration_minutes'), 15);
    expect(rows.single.read<int>('sort_order'), 0);
  });

  test('v2 数据库升级后已有学期默认为单双周交替', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (connection) {
          connection.execute('''
            CREATE TABLE academic_terms (
              id TEXT NOT NULL PRIMARY KEY,
              title TEXT NOT NULL,
              academic_year TEXT NOT NULL,
              semester_label TEXT NOT NULL,
              first_teaching_week_start TEXT,
              teaching_week_count INTEGER NOT NULL DEFAULT 20,
              created_at INTEGER NOT NULL
            )
          ''');
          connection.execute('''
            INSERT INTO academic_terms
              (id, title, academic_year, semester_label, created_at)
            VALUES ('legacy', '旧学期', '2025-2026', '秋季学期', 1)
          ''');
          connection.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(database.close);

    final rows = await database
        .customSelect('SELECT cycle_mode FROM academic_terms')
        .get();
    expect(rows.single.read<String>('cycle_mode'), 'alternating');
  });

  test('v5 数据库升级后创建科目课节限制表', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (connection) => connection.execute('PRAGMA user_version = 5'),
      ),
    );
    addTearDown(database.close);

    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'subject_lesson_constraints'",
        )
        .get();
    expect(rows, hasLength(1));
  });

  test('v6 数据库升级后添加单日连堂限制列', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (connection) {
          connection.execute('''
            CREATE TABLE subject_lesson_constraints (
              id TEXT NOT NULL PRIMARY KEY,
              subject_id TEXT NOT NULL,
              scope_type TEXT NOT NULL,
              scope_id TEXT NOT NULL,
              stage_id TEXT NOT NULL,
              weekday INTEGER,
              minimum_daily_lessons INTEGER,
              maximum_daily_lessons INTEGER,
              minimum_weekly_consecutive_pairs INTEGER,
              maximum_weekly_consecutive_pairs INTEGER
            )
          ''');
          connection.execute('PRAGMA user_version = 6');
        },
      ),
    );
    addTearDown(database.close);

    final rows = await database
        .customSelect('PRAGMA table_info(subject_lesson_constraints)')
        .get();
    final columns = rows.map((row) => row.read<String>('name')).toSet();
    expect(columns, contains('minimum_daily_consecutive_pairs'));
    expect(columns, contains('maximum_daily_consecutive_pairs'));
  });

  test('v10 数据库升级后教师身份脱离学期并保留原有教师 ID', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (connection) {
          connection.execute('''
            CREATE TABLE academic_terms (
              id TEXT NOT NULL PRIMARY KEY
            )
          ''');
          connection.execute('''
            CREATE TABLE teachers (
              id TEXT NOT NULL PRIMARY KEY,
              term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
              name TEXT NOT NULL,
              short_name TEXT NOT NULL DEFAULT '',
              display_qualifier TEXT NOT NULL DEFAULT '',
              sort_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          connection.execute(
            "INSERT INTO academic_terms (id) VALUES ('term-1')",
          );
          connection.execute("""
            INSERT INTO teachers (id, term_id, name, short_name)
            VALUES ('teacher-1', 'term-1', '王老师', '王')
          """);
          connection.execute('PRAGMA user_version = 10');
        },
      ),
    );
    addTearDown(database.close);

    final teacher = await database
        .customSelect('SELECT id, name, short_name FROM teachers')
        .getSingle();
    expect(teacher.read<String>('id'), 'teacher-1');
    expect(teacher.read<String>('name'), '王老师');
    expect(teacher.read<String>('short_name'), '王');
    final columns = await database
        .customSelect('PRAGMA table_info(teachers)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      isNot(contains('term_id')),
    );
  });

  test('v11 数据库升级后增加学校设置表', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (connection) => connection.execute('PRAGMA user_version = 11'),
      ),
    );
    addTearDown(database.close);

    final columns = await database
        .customSelect('PRAGMA table_info(app_settings)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll(['school_name', 'active_term_id']),
    );
  });
}
