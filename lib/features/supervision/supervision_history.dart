import 'dart:convert';

import 'package:class_set/domain/models/supervision.dart';

/// Page-local edits. Persisted revisions belong to storage, never to history.
class SupervisionDraftHistory {
  SupervisionDraftHistory(SupervisionDraft initial)
    : _current = initial,
      _currentContent = _content(initial) {
    _savedContent = _currentContent;
  }

  SupervisionDraft _current;
  String _currentContent;
  late String _savedContent;
  final _undo = <_DutyEdit>[];
  final _redo = <_DutyEdit>[];
  static const _limit = 100;

  SupervisionDraft get current => _current;
  bool get hasChanges => _currentContent != _savedContent;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.lastOrNull?.label;
  String? get redoLabel => _redo.lastOrNull?.label;

  bool isCurrent(SupervisionDraft draft) =>
      draft.revision == _current.revision && _content(draft) == _currentContent;

  bool replace(SupervisionDraft next, String label) {
    final content = _content(next);
    if (content == _currentContent) return false;
    _undo.add(_DutyEdit(label, _snapshot(_current), _snapshot(next)));
    if (_undo.length > _limit) _undo.removeAt(0);
    _redo.clear();
    _current = next.copyWith(revision: _current.revision);
    _currentContent = content;
    return true;
  }

  SupervisionDraft? undo() => _restore(_undo, _redo, undo: true);
  SupervisionDraft? redo() => _restore(_redo, _undo, undo: false);

  SupervisionDraft? _restore(
    List<_DutyEdit> source,
    List<_DutyEdit> target, {
    required bool undo,
  }) {
    if (source.isEmpty) return null;
    final edit = source.removeLast();
    _current = (undo ? edit.before : edit.after).copyWith(
      revision: _current.revision,
    );
    _currentContent = _content(_current);
    target.add(edit);
    return _current;
  }

  void markSaved(SupervisionDraft saved) {
    _current = saved;
    _currentContent = _content(saved);
    _savedContent = _currentContent;
  }

  void reset(SupervisionDraft draft) {
    markSaved(draft);
    _undo.clear();
    _redo.clear();
  }

  static SupervisionDraft _snapshot(SupervisionDraft draft) =>
      SupervisionDraft.fromJson(
        jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
      );

  static String _content(SupervisionDraft draft) =>
      jsonEncode(_canonical(draft.toJson()..remove('revision')));

  /// Order is meaningful for posts and preference priority; membership is a set.
  static Object? _canonical(Object? value, [String? field]) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key], key)};
    }
    if (value is List) {
      final items = value.map((item) => _canonical(item)).toList();
      if (const {
        'teacherIds',
        'manualPostIds',
        'targetSubjectIds',
        'enabled',
        'unavailable',
      }.contains(field)) {
        items.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      }
      return items;
    }
    return value;
  }
}

class _DutyEdit {
  const _DutyEdit(this.label, this.before, this.after);
  final String label;
  final SupervisionDraft before;
  final SupervisionDraft after;
}
