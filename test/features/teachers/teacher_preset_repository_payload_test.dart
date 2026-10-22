import 'package:class_set/domain/models/teacher_preset.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/teachers/domain/teacher_preset_repository_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const groupPreset = TeacherGroupPreset(
    id: 'group-a-preset',
    groupId: 'group-a',
    scope: TeacherPresetScope.school,
    scopeId: 'term-1',
    stageId: 'stage-1',
    weekday: 1,
    periodTypeId: 'period-1',
    lessonIndex: 0,
    value: PresetValue.forbid,
  );
  const otherGroupPreset = TeacherGroupPreset(
    id: 'group-b-preset',
    groupId: 'group-b',
    scope: TeacherPresetScope.school,
    scopeId: 'term-1',
    stageId: 'stage-1',
    weekday: 1,
    periodTypeId: 'period-1',
    lessonIndex: 0,
    value: PresetValue.must,
  );
  const teacherPreset = TeacherPreset(
    id: 'teacher-a-preset',
    teacherId: 'teacher-a',
    scope: TeacherPresetScope.school,
    scopeId: 'term-1',
    stageId: 'stage-1',
    weekday: 1,
    periodTypeId: 'period-1',
    lessonIndex: 0,
    value: PresetValue.forbid,
  );
  const otherTeacherPreset = TeacherPreset(
    id: 'teacher-b-preset',
    teacherId: 'teacher-b',
    scope: TeacherPresetScope.school,
    scopeId: 'term-1',
    stageId: 'stage-1',
    weekday: 1,
    periodTypeId: 'period-1',
    lessonIndex: 0,
    value: PresetValue.must,
  );

  test('group replacement payload contains only the selected group', () {
    final payload = teacherGroupPresetReplacementPayload(
      groupId: 'group-a',
      allPresets: [groupPreset, otherGroupPreset],
    );

    expect(payload, [groupPreset]);
  });

  test('teacher replacement payload contains only the selected teacher', () {
    final payload = teacherPresetReplacementPayload(
      teacherId: 'teacher-a',
      allPresets: [teacherPreset, otherTeacherPreset],
    );

    expect(payload, [teacherPreset]);
  });

  test('group edits replace only edited scopes and retain other groups', () {
    const oldStagePreset = TeacherGroupPreset(
      id: 'group-a-stage-old',
      groupId: 'group-a',
      scope: TeacherPresetScope.stage,
      scopeId: 'stage-1',
      stageId: 'stage-1',
      weekday: 1,
      periodTypeId: 'period-1',
      lessonIndex: 0,
      value: PresetValue.forbid,
    );
    const updatedStagePreset = TeacherGroupPreset(
      id: 'group-a-stage-new',
      groupId: 'group-a',
      scope: TeacherPresetScope.stage,
      scopeId: 'stage-1',
      stageId: 'stage-1',
      weekday: 1,
      periodTypeId: 'period-1',
      lessonIndex: 0,
      value: PresetValue.must,
    );

    final merged = mergeTeacherGroupPresetEdit(
      groupId: 'group-a',
      current: [groupPreset, oldStagePreset, otherGroupPreset],
      editedScopeKeys: {'stage:stage-1'},
      editedPresets: [updatedStagePreset],
    );

    expect(merged.map((preset) => preset.id), [
      groupPreset.id,
      otherGroupPreset.id,
      updatedStagePreset.id,
    ]);
  });

  test(
    'teacher edits replace only edited scopes and retain other teachers',
    () {
      const oldStagePreset = TeacherPreset(
        id: 'teacher-a-stage-old',
        teacherId: 'teacher-a',
        scope: TeacherPresetScope.stage,
        scopeId: 'stage-1',
        stageId: 'stage-1',
        weekday: 1,
        periodTypeId: 'period-1',
        lessonIndex: 0,
        value: PresetValue.forbid,
      );
      const updatedStagePreset = TeacherPreset(
        id: 'teacher-a-stage-new',
        teacherId: 'teacher-a',
        scope: TeacherPresetScope.stage,
        scopeId: 'stage-1',
        stageId: 'stage-1',
        weekday: 1,
        periodTypeId: 'period-1',
        lessonIndex: 0,
        value: PresetValue.must,
      );

      final merged = mergeTeacherPresetEdit(
        teacherId: 'teacher-a',
        current: [teacherPreset, oldStagePreset, otherTeacherPreset],
        editedScopeKeys: {'stage:stage-1'},
        editedPresets: [updatedStagePreset],
      );

      expect(merged.map((preset) => preset.id), [
        teacherPreset.id,
        otherTeacherPreset.id,
        updatedStagePreset.id,
      ]);
    },
  );
}
