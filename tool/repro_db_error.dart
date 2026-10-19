// 复现真实数据库上的保存错误：dart run tool/repro_db_error.dart
// 用法：拷贝真实库到 /tmp/repro.sqlite 后运行本脚本。
import 'dart:io';

import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';

// ignore_for_file: unused_import
Future<void> main() async {
  final file = File('/tmp/repro.sqlite');
  final database = db.AppDatabase.open(file);
  try {
    final version =
        await database.customSelect('PRAGMA user_version').getSingle();
    // ignore: avoid_print
    print('user_version after open: ${version.data['user_version']}');

    final stages = await database
        .select(database.schoolStages)
        .get();
    // ignore: avoid_print
    print('stages: ${stages.map((s) => '${s.id}:${s.name}')}');

    final periods = await database
        .select(database.lessonPeriodTypes)
        .get();
    // ignore: avoid_print
    print('periodTypes: ${periods.map((p) => '${p.id}:${p.name}:${p.stageId}')}');

    final grades = await database.select(database.gradeGroups).get();
    // ignore: avoid_print
    print('grades: ${grades.map((g) => '${g.id}:${g.name}:${g.stageId}')}');

    final classes = await database.select(database.classGroups).get();
    // ignore: avoid_print
    print('classes: ${classes.map((c) => '${c.id}:${c.name}')}');

    // 1) 模拟保存科目。
    try {
      await database
          .into(database.subjects)
          .insert(
            db.SubjectsCompanion.insert(
              id: 'repro_subject',
              name: '复现科目',
              shortName: '复',
              sortOrder: 99,
            ),
            mode: InsertMode.insertOrReplace,
          );
      // ignore: avoid_print
      print('STEP saveSubjects: OK');
    } on Object catch (error) {
      // ignore: avoid_print
      print('STEP saveSubjects FAILED: $error');
    }

    // 2) 模拟保存预设（grade 范围）。
    final periodId = periods.isNotEmpty ? periods.first.id : 'missing';
    try {
      await database
          .into(database.subjectPresets)
          .insert(
            db.SubjectPresetsCompanion.insert(
              id: 'repro_preset',
              subjectId: 'repro_subject',
              scopeType: FreeSlotScope.grade.storageValue,
              scopeId: grades.isNotEmpty ? grades.first.id : 'missing',
              stageId: stages.isNotEmpty ? stages.first.id : 'missing',
              weekday: 1,
              periodTypeId: periodId,
              lessonIndex: 1,
              value: const Value('prefer'),
            ),
          );
      // ignore: avoid_print
      print('STEP savePresets: OK');
    } on Object catch (error) {
      // ignore: avoid_print
      print('STEP savePresets FAILED: $error');
    }

    // 3) 走仓库接口（与 app 完全同路径）。
    final repository = DriftSchoolRepository(database);
    try {
      await repository.saveSubjects([
        const Subject(
          id: 'repro_subject2',
          name: '复现科目2',
          shortName: '复2',
          sortOrder: 98,
        ),
      ]);
      // ignore: avoid_print
      print('STEP repo.saveSubjects: OK');
    } on Object catch (error) {
      // ignore: avoid_print
      print('STEP repo.saveSubjects FAILED: $error');
    }
    try {
      await repository.replaceSubjectPresets(
        subjectId: 'repro_subject2',
        termId: stages.isNotEmpty ? stages.first.termId : 'missing',
        scope: FreeSlotScope.grade,
        scopeId: grades.isNotEmpty ? grades.first.id : 'missing',
        stageId: stages.isNotEmpty ? stages.first.id : 'missing',
        presets: [
          SubjectPreset(
            id: '',
            subjectId: 'repro_subject2',
            scope: FreeSlotScope.grade,
            scopeId: grades.isNotEmpty ? grades.first.id : 'missing',
            stageId: stages.isNotEmpty ? stages.first.id : 'missing',
            weekday: 1,
            periodTypeId: periodId,
            lessonIndex: 1,
            value: PresetValue.prefer,
          ),
        ],
      );
      // ignore: avoid_print
      print('STEP repo.replaceSubjectPresets: OK');
    } on Object catch (error) {
      // ignore: avoid_print
      print('STEP repo.replaceSubjectPresets FAILED: $error');
    }
  } finally {
    await database.close();
  }
}
