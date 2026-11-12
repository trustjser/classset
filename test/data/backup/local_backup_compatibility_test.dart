import 'dart:io';

import 'package:class_set/data/backup/local_backup_service.dart';
import 'package:class_set/data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _Version16Database extends AppDatabase {
  _Version16Database(super.executor);
  @override
  int get schemaVersion => 16;
}

void main() {
  test('v16 历史备份可恢复并升级到当前数据库版本', () async {
    final directory = await Directory.systemTemp.createTemp(
      'paike-v16-backup-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/school.sqlite');
    final legacy = _Version16Database(NativeDatabase(file));
    await legacy.customStatement('DROP TABLE temporary_course_adjustments');
    await legacy.customStatement('DROP TABLE supervision_drafts');
    await legacy.customStatement('DROP TABLE supervision_plan_versions');
    await legacy.customStatement(
      "INSERT INTO app_settings (id, school_name) VALUES (1, '旧数据')",
    );
    final backup = await LocalBackupService(
      legacy,
      file,
    ).createSnapshot(label: '旧版本备份');
    await legacy.close();

    final current = AppDatabase(NativeDatabase(file));
    await current.customSelect('SELECT 1').get();
    final service = LocalBackupService(current, file);
    await service.verifySnapshot(backup);
    await service.restoreSnapshot(backup, closeDatabase: current.close);
    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final rows = await reopened
        .customSelect('SELECT school_name FROM app_settings WHERE id = 1')
        .get();
    expect(rows.single.read<String>('school_name'), '旧数据');
    final tables = await reopened
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name = 'temporary_course_adjustments'",
        )
        .get();
    expect(tables, hasLength(1));
  });
}
