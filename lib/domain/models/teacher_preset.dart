import 'package:class_set/domain/models/subject.dart';

/// 教师预排的四级作用域，与免任课/科目预设保持一致。
enum TeacherPresetScope {
  school,
  stage,
  grade,
  schoolClass;

  String get storageValue => switch (this) {
    TeacherPresetScope.school => 'school',
    TeacherPresetScope.stage => 'stage',
    TeacherPresetScope.grade => 'grade',
    TeacherPresetScope.schoolClass => 'class',
  };

  static TeacherPresetScope fromStorage(String? value) => switch (value) {
    'stage' => TeacherPresetScope.stage,
    'grade' => TeacherPresetScope.grade,
    'class' => TeacherPresetScope.schoolClass,
    _ => TeacherPresetScope.school,
  };
}

abstract class _TeacherPresetCell {
  const _TeacherPresetCell({
    required this.scope,
    required this.scopeId,
    required this.stageId,
    required this.weekday,
    required this.periodTypeId,
    required this.lessonIndex,
    required this.value,
  });

  final TeacherPresetScope scope;
  final String scopeId;
  final String stageId;
  final int weekday;
  final String periodTypeId;
  final int lessonIndex;
  final PresetValue value;

  String get cellKey =>
      '${scope.storageValue}_${scopeId}_${stageId}_${weekday}_${periodTypeId}_$lessonIndex';
}

class TeacherPreset extends _TeacherPresetCell {
  const TeacherPreset({
    required this.id,
    required this.teacherId,
    required super.scope,
    required super.scopeId,
    required super.stageId,
    required super.weekday,
    required super.periodTypeId,
    required super.lessonIndex,
    required super.value,
  });

  final String id;
  final String teacherId;
}

class TeacherGroupPreset extends _TeacherPresetCell {
  const TeacherGroupPreset({
    required this.id,
    required this.groupId,
    required super.scope,
    required super.scopeId,
    required super.stageId,
    required super.weekday,
    required super.periodTypeId,
    required super.lessonIndex,
    required super.value,
  });

  final String id;
  final String groupId;
}

class TeacherPresetConflictException implements Exception {
  const TeacherPresetConflictException(this.values);

  final Set<PresetValue> values;

  @override
  String toString() =>
      'Teacher preset conflict: ${values.map((e) => e.label).join(', ')}';
}

/// 解析个人预设与多个分组预设。
///
/// 个人记录只要存在就拥有最高优先级，包括显式的「自动」；否则忽略分组
/// 的自动态。多个分组给出不同非自动状态时返回冲突，调用方应阻止保存。
PresetValue resolveTeacherPreset({
  required TeacherPreset? personal,
  required Iterable<TeacherGroupPreset> groups,
}) {
  if (personal != null) return personal.value;
  final values = groups
      .map((preset) => preset.value)
      .where((value) => value != PresetValue.auto)
      .toSet();
  if (values.length > 1) {
    throw TeacherPresetConflictException(values);
  }
  return values.isEmpty ? PresetValue.auto : values.single;
}
