import 'package:class_set/data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
