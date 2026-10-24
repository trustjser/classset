import 'dart:io';

import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('学校名称和当前学期在重新打开数据库后仍然保存', () async {
    final directory = await Directory.systemTemp.createTemp(
      'classset-settings-',
    );
    final file = File('${directory.path}/school.sqlite');
    try {
      final firstDatabase = db.AppDatabase.open(file);
      final firstRepository = DriftSchoolRepository(firstDatabase);
      await firstRepository.saveTerm(
        AcademicTerm(
          id: 'term-2',
          title: '2027 学年 · 春季学期',
          academicYear: '2027',
          semesterLabel: '春季学期',
          firstTeachingWeekStart: DateTime(2027, 3, 1),
          teachingWeekCount: 20,
          createdAt: DateTime(2027, 1, 1),
        ),
      );
      await firstRepository.saveSchoolName('  青木实验学校  ');
      await firstRepository.saveActiveTermId('term-2');
      await firstDatabase.close();

      final reopenedDatabase = db.AppDatabase.open(file);
      try {
        final reopenedRepository = DriftSchoolRepository(reopenedDatabase);
        expect(await reopenedRepository.loadActiveTermId(), 'term-2');
        expect(await reopenedRepository.watchSchoolName().first, '青木实验学校');

        await reopenedRepository.saveSchoolName('  ');
        expect(await reopenedRepository.watchSchoolName().first, '');

        await reopenedRepository.deleteTerm('term-2');
        expect(await reopenedRepository.loadActiveTermId(), isNull);
      } finally {
        await reopenedDatabase.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
