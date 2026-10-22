part of '../teachers_page.dart';

extension _TeacherPresetActions on _TeachersPageState {
  Future<_PresetConfiguration?> _loadPresetConfiguration() async {
    final stages = await ref.read(stagesProvider(widget.termId).future);
    final grades = await ref.read(gradesForTermProvider(widget.termId).future);
    final classes = await ref.read(
      classesForTermProvider(widget.termId).future,
    );
    final routines = <String, StageRoutine>{};
    for (final stage in stages) {
      try {
        final routine = await ref.read(routineProvider(stage.id).future);
        if (routine != null && routine.periodTypes.isNotEmpty) {
          routines[stage.id] = routine;
        }
      } catch (_) {
        // A stage without a saved routine is skipped; other configured stages
        // remain available in the cross-stage preset editor.
      }
    }
    if (routines.isEmpty) {
      _showMessage('请先完成至少一个学段的作息设置');
      return null;
    }
    final scopes = <_PresetScopeOption>[
      for (final stage in stages)
        if (routines.containsKey(stage.id))
          _PresetScopeOption(
            scope: TeacherPresetScope.stage,
            scopeId: stage.id,
            label: stage.name,
            stageIds: {stage.id},
          ),
      for (final grade in grades)
        if (routines.containsKey(grade.stageId))
          _PresetScopeOption(
            scope: TeacherPresetScope.grade,
            scopeId: grade.id,
            label: grade.name,
            stageIds: {grade.stageId},
            parentKey:
                '${TeacherPresetScope.stage.storageValue}:${grade.stageId}',
          ),
      for (final item in classes)
        if (routines.containsKey(item.stageId))
          _PresetScopeOption(
            scope: TeacherPresetScope.schoolClass,
            scopeId: item.id,
            label: item.name,
            stageIds: {item.stageId},
            parentKey:
                '${TeacherPresetScope.grade.storageValue}:${item.gradeId}',
          ),
    ];
    return _PresetConfiguration(routines: routines, scopes: scopes);
  }
}
