import 'package:class_set/domain/models/teacher_preset.dart';

/// Merges an edited scope into the full preset set used for conflict checks.
///
/// Rows from other groups and untouched scopes are retained in [current].
List<TeacherGroupPreset> mergeTeacherGroupPresetEdit({
  required String groupId,
  required Iterable<TeacherGroupPreset> current,
  required Set<String> editedScopeKeys,
  required Iterable<TeacherGroupPreset> editedPresets,
}) => _mergeEditedScopes(
  current: current,
  editedScopeKeys: editedScopeKeys,
  editedPresets: editedPresets,
  belongsToOwner: (preset) => preset.groupId == groupId,
  scopeKeyOf: (preset) => _scopeKey(preset.scope, preset.scopeId),
);

/// Merges an edited scope into the full personal preset set.
List<TeacherPreset> mergeTeacherPresetEdit({
  required String teacherId,
  required Iterable<TeacherPreset> current,
  required Set<String> editedScopeKeys,
  required Iterable<TeacherPreset> editedPresets,
}) => _mergeEditedScopes(
  current: current,
  editedScopeKeys: editedScopeKeys,
  editedPresets: editedPresets,
  belongsToOwner: (preset) => preset.teacherId == teacherId,
  scopeKeyOf: (preset) => _scopeKey(preset.scope, preset.scopeId),
);

/// Limits a group replacement write to rows owned by the selected group.
List<TeacherGroupPreset> teacherGroupPresetReplacementPayload({
  required String groupId,
  required Iterable<TeacherGroupPreset> allPresets,
}) => allPresets
    .where((preset) => preset.groupId == groupId)
    .toList(growable: false);

/// Limits a personal replacement write to rows owned by the selected teacher.
List<TeacherPreset> teacherPresetReplacementPayload({
  required String teacherId,
  required Iterable<TeacherPreset> allPresets,
}) => allPresets
    .where((preset) => preset.teacherId == teacherId)
    .toList(growable: false);

List<T> _mergeEditedScopes<T>({
  required Iterable<T> current,
  required Set<String> editedScopeKeys,
  required Iterable<T> editedPresets,
  required bool Function(T preset) belongsToOwner,
  required String Function(T preset) scopeKeyOf,
}) => [
  for (final preset in current)
    if (!belongsToOwner(preset) ||
        !editedScopeKeys.contains(scopeKeyOf(preset)))
      preset,
  for (final preset in editedPresets)
    if (belongsToOwner(preset) && editedScopeKeys.contains(scopeKeyOf(preset)))
      preset,
];

String _scopeKey(TeacherPresetScope scope, String scopeId) =>
    '${scope.storageValue}:$scopeId';
