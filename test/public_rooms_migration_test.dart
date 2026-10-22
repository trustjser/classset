import 'package:class_set/data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'v7 upgrade creates empty room settings without changing existing subjects',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (connection) {
            connection.execute(
              'CREATE TABLE subjects (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, short_name TEXT NOT NULL, sort_order INTEGER NOT NULL)',
            );
            connection.execute(
              "INSERT INTO subjects VALUES ('music', '音乐', '音', 0)",
            );
            connection.execute('PRAGMA user_version = 7');
          },
        ),
      );
      addTearDown(database.close);
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('public_rooms', 'subject_room_assignments', 'subject_parallel_limits')",
          )
          .get();
      expect(
        tables.map((row) => row.read<String>('name')),
        containsAll([
          'public_rooms',
          'subject_room_assignments',
          'subject_parallel_limits',
        ]),
      );
      expect(
        (await database.select(database.subjects).get()).single.name,
        '音乐',
      );
      for (final table in [
        'public_rooms',
        'subject_room_assignments',
        'subject_parallel_limits',
        'teachers',
        'teacher_groups',
        'teacher_assignments',
      ]) {
        final rows = await database
            .customSelect('SELECT COUNT(*) AS count FROM $table')
            .get();
        expect(rows.single.read<int>('count'), 0);
      }
      expect(
        (await database.customSelect('PRAGMA user_version').get()).single
            .read<int>('user_version'),
        11,
      );
    },
  );
}
