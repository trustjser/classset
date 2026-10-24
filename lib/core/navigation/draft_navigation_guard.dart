import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gives the app shell access to the active editor's unsaved draft.
final draftNavigationGuardProvider = Provider<DraftNavigationGuard>(
  (ref) => DraftNavigationGuard(),
);

class DraftNavigationGuard {
  Object? _owner;
  String? _pageKey;
  bool Function()? _hasChanges;
  bool Function()? _isSaving;
  Future<bool> Function()? _save;

  void register({
    required Object owner,
    required String pageKey,
    required bool Function() hasChanges,
    required bool Function() isSaving,
    required Future<bool> Function() save,
  }) {
    _owner = owner;
    _pageKey = pageKey;
    _hasChanges = hasChanges;
    _isSaving = isSaving;
    _save = save;
  }

  void unregister(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _pageKey = null;
    _hasChanges = null;
    _isSaving = null;
    _save = null;
  }

  bool hasChangesFor(String pageKey) =>
      _pageKey == pageKey && (_hasChanges?.call() ?? false);

  bool isSavingFor(String pageKey) =>
      _pageKey == pageKey && (_isSaving?.call() ?? false);

  Future<bool> saveFor(String pageKey) async {
    if (_pageKey != pageKey || !(_hasChanges?.call() ?? false)) return true;
    return await _save?.call() ?? false;
  }
}
