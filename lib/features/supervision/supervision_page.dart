import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:class_set/app.dart';
import 'package:class_set/core/navigation/draft_navigation_guard.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/supervision_allocator.dart';
import 'package:class_set/domain/scheduling/supervision_matching.dart';
import 'package:class_set/domain/scheduling/supervision_validation.dart';
import 'package:class_set/features/supervision/supervision_history.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart' as f;
import 'package:material_ui/material_ui.dart' as forui_material;

part 'supervision_dialogs.dart';
part 'supervision_post_dialog.dart';
part 'supervision_week.dart';
part 'supervision_workspace.dart';
part 'supervision_selection.dart';
part 'supervision_matching_settings.dart';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// The cell and scope selected in routine settings.
class SupervisionSeed {
  const SupervisionSeed({
    required this.stageId,
    required this.scope,
    required this.scopeId,
    required this.weekday,
    required this.periodTypeId,
    required this.lessonIndex,
  });

  final String stageId;
  final FreeSlotScope scope;
  final String scopeId;
  final int weekday;
  final String periodTypeId;
  final int lessonIndex;
}

final _snapshotProvider = FutureProvider.autoDispose
    .family<SchedulingSnapshot, String>(
      (ref, id) =>
          ref.watch(schoolRepositoryProvider).loadSchedulingSnapshot(id),
    );
final _pendingBaselineProvider = FutureProvider.autoDispose
    .family<bool, String>(
      (ref, id) async =>
          await ref
              .watch(schoolRepositoryProvider)
              .loadPendingSchedulingBaseline(id) !=
          null,
    );
final _draftProvider = StreamProvider.autoDispose
    .family<SupervisionDraft?, String>(
      (ref, id) =>
          ref.watch(schoolRepositoryProvider).watchSupervisionDraft(id),
    );
final _versionsProvider = StreamProvider.autoDispose
    .family<List<SupervisionVersion>, String>(
      (ref, id) =>
          ref.watch(schoolRepositoryProvider).watchSupervisionVersions(id),
    );

class SupervisionPage extends ConsumerWidget {
  const SupervisionPage({required this.termId, this.seed, super.key});

  final String termId;
  final SupervisionSeed? seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(_snapshotProvider(termId));
    final draft = ref.watch(_draftProvider(termId));
    final versions = ref.watch(_versionsProvider(termId));
    if (snapshot.hasError || draft.hasError || versions.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('读取带班安排失败：${snapshot.error ?? draft.error ?? versions.error}'),
            _DutyOutlineButton(
              onPressed: () {
                ref.invalidate(_snapshotProvider(termId));
                ref.invalidate(_draftProvider(termId));
                ref.invalidate(_versionsProvider(termId));
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (!snapshot.hasValue || !draft.hasValue || !versions.hasValue) {
      return const Center(
        child: f.FCircularProgress(semanticsLabel: '正在读取带班安排'),
      );
    }
    return _SupervisionEditor(
      key: ValueKey(termId),
      snapshot: snapshot.requireValue,
      draft: draft.requireValue,
      versions: versions.requireValue,
      canRepair:
          versions.requireValue.isNotEmpty &&
          ref.watch(_pendingBaselineProvider(termId)).valueOrNull == true,
      seed: seed,
    );
  }
}

class _SupervisionEditor extends ConsumerStatefulWidget {
  const _SupervisionEditor({
    required this.snapshot,
    required this.draft,
    required this.versions,
    required this.canRepair,
    required this.seed,
    super.key,
  });

  final SchedulingSnapshot snapshot;
  final SupervisionDraft? draft;
  final List<SupervisionVersion> versions;
  final bool canRepair;
  final SupervisionSeed? seed;

  @override
  ConsumerState<_SupervisionEditor> createState() => _SupervisionEditorState();
}

class _SupervisionEditorState extends ConsumerState<_SupervisionEditor> {
  late final _history = SupervisionDraftHistory(_initialDraft());
  SupervisionDraft get _draft => _history.current;
  late final DraftNavigationGuard _guard;
  SupervisionDraft? _pendingDraft;
  bool get _dirty => _history.hasChanges;
  bool _publishing = false;
  Future<bool>? _saveInFlight;
  ReceivePort? _fillPort;
  Isolate? _fillIsolate;
  DateTime? _viewVersionDate;
  String? _selectedPostId;
  Set<String> _selectedPostIds = {};
  String _searchQuery = '';
  bool _missingOnly = false;
  bool _preferenceOnly = false;
  _DutyView _view = _DutyView.week;

  String get _termId => widget.snapshot.term.id;
  bool get _busy => _saveInFlight != null || _publishing;
  bool get _filling => _fillPort != null;
  bool get _editable => _viewVersionDate == null && !_busy && !_filling;

  SupervisionDraft _initialDraft() =>
      widget.draft ??
      _latestVersion(widget.versions)?.draft.copyWith(revision: 0) ??
      SupervisionDraft(termId: _termId);

  @override
  void initState() {
    super.initState();
    _guard = ref.read(draftNavigationGuardProvider);
    _guard.register(
      owner: this,
      pageKey: 'supervision:$_termId',
      hasChanges: () => _dirty,
      isSaving: () => _saveInFlight != null,
      save: _save,
    );
    final seed = widget.seed;
    if (seed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_addPosts(seed));
      });
    }
  }

  @override
  void didUpdateWidget(covariant _SupervisionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.draft != widget.draft ||
        (widget.draft == null && oldWidget.versions != widget.versions);
    if (!sourceChanged) return;
    final incoming = _initialDraft();
    // A delayed echo of our own save must not restore an older storage revision.
    if (widget.draft != null && incoming.revision < _draft.revision) return;
    _pendingDraft = _history.isCurrent(incoming) ? null : incoming;
    _adoptPendingDraft();
  }

  void _adoptPendingDraft() {
    if (_pendingDraft == null || _dirty || _busy || _filling) return;
    final incoming = _pendingDraft!;
    _pendingDraft = null;
    if (_history.isCurrent(incoming)) return;
    _history.reset(incoming);
    _selectedPostId = null;
    _pruneSelection();
  }

  @override
  void dispose() {
    _guard.unregister(this);
    _stopFill();
    super.dispose();
  }

  void _pruneSelection() {
    final remaining = _draft.posts.map((post) => post.id).toSet();
    _selectedPostIds = _selectedPostIds.intersection(remaining);
    if (!remaining.contains(_selectedPostId)) _selectedPostId = null;
  }

  void _replaceDraft(SupervisionDraft next, {required String label}) {
    setState(() {
      if (_history.replace(next, label)) _pruneSelection();
      _adoptPendingDraft();
    });
  }

  void _undo() => _restoreHistory(undo: true);
  void _redo() => _restoreHistory(undo: false);
  void _restoreHistory({required bool undo}) {
    if (!_editable) return;
    setState(() {
      final restored = undo ? _history.undo() : _history.redo();
      if (restored == null) return;
      _selectedPostId = null;
      _selectedPostIds = {};
      _adoptPendingDraft();
    });
  }

  KeyEventResult _historyKey(FocusNode node, KeyEvent event) {
    if (!_editable ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if ((!keyboard.isControlPressed && !keyboard.isMetaPressed) ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      keyboard.isShiftPressed ? _redo() : _undo();
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed &&
        !keyboard.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _message(String message) {
    if (mounted) {
      f.showFToast(
        context: context,
        title: Text(message),
        alignment: f.FToastAlignment.topCenter,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<bool> _save() {
    if (_saveInFlight case final existing?) return existing;
    if (!_dirty && _draft.revision == widget.draft?.revision) {
      return Future.value(true);
    }
    final operation = _persist();
    setState(() {
      _saveInFlight = operation;
    });
    return operation;
  }

  Future<bool> _persist() async {
    try {
      final repository = ref.read(schoolRepositoryProvider);
      final saved = await repository.saveSupervisionDraft(
        _draft,
        expectedRevision: _draft.revision,
      );
      if (!mounted) return false;
      setState(() {
        _history.markSaved(saved);
        if (_pendingDraft != null &&
            widget.draft != null &&
            _pendingDraft!.revision <= saved.revision) {
          _pendingDraft = null;
        }
      });
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      _message('草稿已保存');
      return true;
    } on Object catch (error) {
      _message('保存草稿失败：$error');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _saveInFlight = null;
          _adoptPendingDraft();
        });
      }
    }
  }

  Future<void> _addPosts([SupervisionSeed? seed]) async {
    final posts = await showAppDialog<List<SupervisionPost>>(
      context: context,
      builder: (_) =>
          _PostDialog(snapshot: widget.snapshot, draft: _draft, seed: seed),
    );
    if (!mounted || posts == null) return;
    _replaceDraft(
      _draft.copyWith(posts: [..._draft.posts, ...posts]),
      label: '创建 ${posts.length} 个岗位',
    );
  }

  Future<void> _removePost(SupervisionPost post) => _removePosts({post.id});

  Future<void> _removePosts(Set<String> ids, {bool batch = false}) async {
    if (!_editable) return;
    final targets = _draft.posts
        .where((post) => ids.contains(post.id))
        .toList();
    if (targets.isEmpty) return;
    final classes = {
      for (final group in widget.snapshot.classes) group.id: group.name,
    };
    final assigned = targets
        .where((post) => _draft.assignments.containsKey(post.id))
        .length;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: Text(batch ? '批量移除带班岗位' : '移除带班岗位'),
        content: DefaultTextStyle.merge(
          style: TextStyle(color: context.appColors.inkSecondary),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('将从草稿移除 ${targets.length} 个岗位，其中 $assigned 个已安排教师。'),
              const SizedBox(height: 8),
              for (final post in targets.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_weekdays[post.weekday - 1]} · ${post.name} · ${_slotLabel(widget.snapshot, post)} · ${post.groupName.isNotEmpty ? post.groupName : post.classIds.map((id) => classes[id] ?? id).join('、')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (targets.length > 8) Text('另有 ${targets.length - 8} 个岗位。'),
              const SizedBox(height: 8),
              const Text('已生效的安排会继续显示，直到预览并确认新版本。'),
            ],
          ),
        ),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          AppDestructiveButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(batch ? '移除 ${targets.length} 个岗位' : '移除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !_editable) return;
    _replaceDraft(
      _draft.copyWith(
        posts: _draft.posts.where((post) => !ids.contains(post.id)).toList(),
        assignments: {..._draft.assignments}
          ..removeWhere((id, _) => ids.contains(id)),
        manualPostIds: {..._draft.manualPostIds}..removeAll(ids),
      ),
      label: '移除 ${targets.length} 个岗位',
    );
  }

  void _assignTeacher(SupervisionPost post, String picked) {
    final assignments = {..._draft.assignments};
    final manualPostIds = {..._draft.manualPostIds};
    if (picked.isEmpty) {
      assignments.remove(post.id);
      manualPostIds.remove(post.id);
    } else {
      final errors = const SupervisionAllocator().teacherBlockers(
        widget.snapshot,
        _draft,
        post,
        picked,
      );
      if (errors.isNotEmpty) {
        _message(errors.join(' · '));
        return;
      }
      assignments[post.id] = picked;
      manualPostIds.add(post.id);
    }
    _replaceDraft(
      _draft.copyWith(assignments: assignments, manualPostIds: manualPostIds),
      label: picked.isEmpty ? '清除教师指派' : '指派带班教师',
    );
  }

  Future<void> _editTeacherPool() async {
    final groups = await ref
        .read(schoolRepositoryProvider)
        .watchTeacherGroups(_termId)
        .first
        .catchError((Object error) {
          _message('读取教师组失败：$error');
          return <TeacherGroup>[];
        });
    if (!mounted) return;
    final revised = await showAppDialog<SupervisionDraft>(
      context: context,
      builder: (_) => _TeacherPoolDialog(
        draft: _draft,
        snapshot: widget.snapshot,
        groups: groups,
      ),
    );
    if (mounted && revised != null) _replaceDraft(revised, label: '设置候选池与教师规则');
  }

  Future<void> _editMatching() async {
    final value = await showAppDialog<SupervisionMatchingPreferences>(
      context: context,
      builder: (_) =>
          _MatchingPreferencesDialog(initial: _draft.matchingPreferences),
    );
    if (mounted && value != null && _editable) {
      _replaceDraft(
        _draft.copyWith(matchingPreferences: value),
        label: '调整人员匹配',
      );
    }
  }

  Future<void> _editPostPersonnel(
    Set<String> ids, {
    _PersonnelEditMode mode = _PersonnelEditMode.all,
  }) async {
    if (!_editable) return;
    final posts = _draft.posts.where((post) => ids.contains(post.id)).toList();
    if (posts.isEmpty) return;
    final first = posts.first;
    final value = await showAppDialog<_PersonnelSettings>(
      context: context,
      builder: (_) => _PostPersonnelDialog(
        draft: _draft,
        snapshot: widget.snapshot,
        count: posts.length,
        mode: mode,
        initial: (
          poolId: first.teacherPoolId,
          preferences: first.matchingPreferences,
          subjects: first.targetSubjectIds,
        ),
      ),
    );
    if (!mounted || value == null || !_editable) return;
    _replaceDraft(
      _draft.copyWith(
        posts: [
          for (final post in _draft.posts)
            if (!ids.contains(post.id))
              post
            else
              post.copyWith(
                teacherPoolId: mode == _PersonnelEditMode.matching
                    ? null
                    : value.poolId,
                inheritPool:
                    mode != _PersonnelEditMode.matching && value.poolId == null,
                matchingPreferences: mode == _PersonnelEditMode.pool
                    ? null
                    : value.preferences,
                inheritPreferences:
                    mode != _PersonnelEditMode.pool &&
                    value.preferences == null,
                targetSubjectIds: mode == _PersonnelEditMode.pool
                    ? null
                    : value.subjects,
              ),
        ],
      ),
      label: '设置 ${posts.length} 个岗位的人员规则',
    );
  }

  Future<void> _rematch() async {
    var keepManual = true;
    final choice = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AppDialog(
          title: const Text('重新匹配带班教师'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('按当前候选池与人员匹配规则重新安排草稿中的岗位。已生效版本在预览确认前保持原安排。'),
              const SizedBox(height: 12),
              f.FSwitch(
                label: const Text('保留手动指派'),
                description: Text(
                  '当前有 ${_draft.manualPostIds.length} 个手动指派岗位。关闭后这些岗位也会重新匹配。',
                ),
                value: keepManual,
                onChange: (value) => setDialogState(() => keepManual = value),
              ),
            ],
          ),
          actions: [
            AppGhostButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            AppPrimaryButton(
              onPressed: () => Navigator.pop(context, keepManual),
              child: const Text('开始匹配'),
            ),
          ],
        ),
      ),
    );
    if (mounted && choice != null && _editable) {
      await _smartFill(resetManual: !choice);
    }
  }

  Future<void> _smartFill({bool resetManual = false}) async {
    final port = ReceivePort();
    setState(() => _fillPort = port);
    try {
      final snapshot = await ref
          .read(schoolRepositoryProvider)
          .loadSchedulingSnapshot(_termId);
      if (!mounted || _fillPort != port) return;
      final input = resetManual ? _draft.copyWith(manualPostIds: {}) : _draft;
      if (kIsWeb) {
        _replaceDraft(
          const SupervisionAllocator().fill(snapshot, input),
          label: '智能匹配带班教师',
        );
        return;
      }
      final output = port.first;
      final isolate = await Isolate.spawn(_fillSupervision, (
        port.sendPort,
        snapshot,
        input,
      ), onError: port.sendPort);
      if (!mounted || _fillPort != port) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      _fillIsolate = isolate;
      final result = await output;
      if (!mounted || _fillPort != port || result == null) return;
      if (result is SupervisionDraft) {
        _replaceDraft(result, label: '智能匹配带班教师');
      } else {
        _message('智能补齐失败：$result');
      }
    } on Object catch (error) {
      if (_fillPort == port) _message('智能补齐失败：$error');
    } finally {
      if (mounted && _fillPort == port) setState(_stopFill);
    }
  }

  void _stopFill() {
    _fillIsolate?.kill(priority: Isolate.immediate);
    _fillPort?.close();
    _fillIsolate = null;
    _fillPort = null;
    _adoptPendingDraft();
  }

  Future<void> _publish({bool repair = false}) async {
    final dates = repair
        ? [DateUtils.dateOnly(DateTime.now())]
        : _publishDates(widget.snapshot.term);
    if (dates.isEmpty) return;
    if (!await _save() || !mounted) return;
    setState(() => _publishing = true);
    try {
      final repository = ref.read(schoolRepositoryProvider);
      final preview = await showAppDialog<SupervisionPreview>(
        context: context,
        builder: (_) => _PublishDialog(
          dates: dates,
          load: (date) => repository.previewSupervisionPublish(_termId, date),
          snapshot: widget.snapshot,
          repair: repair,
        ),
      );
      if (!mounted || preview == null) return;
      await repository.publishSupervision(_termId, preview);
      if (!mounted) return;
      setState(() {
        _pendingDraft = null;
        _history.reset(preview.draft.copyWith(revision: 0));
        _viewVersionDate = preview.effectiveDate;
        _selectedPostIds = {};
      });
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      ref.invalidate(_pendingBaselineProvider(_termId));
      ref.invalidate(_snapshotProvider(_termId));
      _message(
        repair ? '带班与课表已协调' : '已确认，${_dateLabel(preview.effectiveDate)} 起生效',
      );
    } on Object catch (error) {
      _message('确认带班方案失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _publishing = false;
          _adoptPendingDraft();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _historyKey,
    child: _buildEditor(context),
  );

  Widget _buildEditor(BuildContext context) {
    final versions = [...widget.versions]
      ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
    final selected = versions
        .where((version) => version.effectiveDate == _viewVersionDate)
        .firstOrNull;
    final draft = selected?.draft ?? _draft;
    final missing = draft.posts
        .where((post) => !draft.assignments.containsKey(post.id))
        .length;
    final focused = selected == null
        ? draft.posts.where((post) => post.id == _selectedPostId).firstOrNull
        : null;
    final canPreview =
        _editable &&
        (versions.isNotEmpty || _draft.posts.isNotEmpty) &&
        _publishDates(widget.snapshot.term).isNotEmpty;
    final matching = SupervisionMatching(widget.snapshot);
    final statuses = <String, String>{};
    final preferenceMisses = <String>{};
    var invalidAssignments = 0;
    for (final post in draft.posts) {
      final teacher = draft.assignments[post.id];
      if (teacher == null || selected != null) continue;
      final errors = const SupervisionAllocator().teacherBlockers(
        widget.snapshot,
        draft,
        post,
        teacher,
        matching: matching,
      );
      if (errors.isNotEmpty && selected == null) {
        statuses[post.id] = '指派需调整';
        invalidAssignments++;
      }
      if (matching.hasUnmetPreferences(draft, post, teacher)) {
        preferenceMisses.add(post.id);
        statuses.putIfAbsent(post.id, () => '偏好未满足');
      }
    }
    final colors = context.appColors;
    final theme = Theme.of(context).textTheme;
    final canUndo = _editable && _history.canUndo;
    final canRedo = _editable && _history.canRedo;
    final undoTip =
        '撤销${_history.undoLabel == null ? '' : '：${_history.undoLabel}'} · Cmd/Ctrl+Z';
    final redoTip =
        '重做${_history.redoLabel == null ? '' : '：${_history.redoLabel}'} · Cmd/Ctrl+Shift+Z / Ctrl+Y';

    return LayoutBuilder(
      builder: (context, constraints) {
        final pagePadding = AppTheme.pagePaddingForWidth(constraints.maxWidth);
        final wide = constraints.maxWidth >= 768;
        final picker = SizedBox(
          width: 142,
          child: _DutyVersionPicker(
            child: AppSelectField<String>(
              items: {
                '编辑草稿 (v${versions.length + 1})': '',
                for (final entry in versions.indexed)
                  '正式发布版 (v${versions.length - entry.$1})': entry
                      .$2
                      .effectiveDate
                      .toIso8601String(),
              },
              value: selected?.effectiveDate.toIso8601String() ?? '',
              enabled: !_busy && !_filling,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _viewVersionDate = value.isEmpty
                      ? null
                      : DateTime.parse(value);
                  _selectedPostId = null;
                  _selectedPostIds = {};
                  _missingOnly = false;
                  _preferenceOnly = false;
                });
              },
            ),
          ),
        );
        final headerActions = <Widget>[
          _DutyToolbarField(
            label: '当前版本',
            labelColor: _headerMuted(context),
            child: picker,
          ),
          Container(width: 1, height: 22, color: _headerBorder(context)),
          _DutyOutlinedIconButton(
            key: const ValueKey('duty-undo'),
            icon: Icons.undo_rounded,
            tooltip: undoTip,
            onPressed: canUndo ? _undo : null,
          ),
          _DutyOutlinedIconButton(
            key: const ValueKey('duty-redo'),
            icon: Icons.redo_rounded,
            tooltip: redoTip,
            onPressed: canRedo ? _redo : null,
          ),
          if (selected == null)
            _DutyCommandGroup(
              children: [
                _DutyCommand(
                  key: const ValueKey('duty-pool-manager'),
                  icon: Icons.tune_rounded,
                  label: '候选池',
                  count: _draft.teacherPools.length + 1,
                  onPressed: _editable ? _editTeacherPool : null,
                ),
                _DutyCommand(
                  icon: Icons.person_add_alt_1_outlined,
                  label: '人员匹配',
                  onPressed: _editable ? _editMatching : null,
                ),
                _DutyCommand(
                  icon: Icons.refresh_rounded,
                  onPressed: _filling
                      ? () => setState(_stopFill)
                      : _editable &&
                            _draft.posts.isNotEmpty &&
                            _draft.allTeacherIds.isNotEmpty
                      ? missing == 0
                            ? _rematch
                            : _smartFill
                      : null,
                  label: _filling
                      ? '取消补齐'
                      : missing == 0 && _draft.posts.isNotEmpty
                      ? '重新匹配'
                      : '智能补齐',
                ),
              ],
            ),
          if (selected == null)
            _DutyCreatePostButton(onPressed: _editable ? _addPosts : null),
        ];
        final body = _DutySelectionRegion(
          key: ValueKey((
            _view,
            _missingOnly,
            _preferenceOnly,
            _viewVersionDate,
            _searchQuery,
          )),
          enabled: _editable,
          selectedIds: _selectedPostIds,
          onChanged: (ids) {
            if (mounted && _editable) {
              setState(
                () =>
                    _selectedPostIds = {...ids}
                      ..retainAll(_draft.posts.map((post) => post.id)),
              );
            }
          },
          onFinished: () {
            if (mounted) setState(() => _selectedPostId = null);
          },
          builder: (context, selection) => _SupervisionWeek(
            selection: selection,
            draft: draft,
            snapshot: widget.snapshot,
            historical: selected,
            view: _view,
            day: null,
            searchQuery: _searchQuery,
            missingOnly: _missingOnly,
            preferenceOnly: _preferenceOnly,
            preferenceMisses: preferenceMisses,
            statuses: statuses,
            selectedPostId: focused?.id,
            onSelect: !_editable
                ? null
                : (post) => setState(() => _selectedPostId = post.id),
            onClear: _editable ? (post) => _assignTeacher(post, '') : null,
          ),
        );
        final weekBody = draft.posts.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    selected == null ? '周表还是空的。创建岗位后，即可按节次安排老师。' : '此版本没有带班岗位。',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : body;
        final legend = _DutyLegend(
          activities: {for (final post in draft.posts) post.name: post.kind},
        );
        return ColoredBox(
          color: colors.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            pagePadding,
                            AppTheme.pageTopPadding,
                            pagePadding,
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppPageHeader(
                                title: '带班安排',
                                subtitle: '为课后时段安排带班教师，与课表协调后生效',
                                actions: headerActions,
                                actionsFlex: 2,
                                narrowActionsAlignment: WrapAlignment.start,
                              ),
                              const SizedBox(height: AppTheme.pageSectionGap),
                              _DutyToolbarRow(
                                leading: [
                                  _DutySegments<int>(
                                    pills: true,
                                    itemKey: (value) =>
                                        ValueKey('duty-filter-$value'),
                                    items: {0: '全部岗位', 1: '待安排', 2: '偏好未满足'},
                                    counts: {
                                      0: draft.posts.length,
                                      1: missing,
                                      2: preferenceMisses.length,
                                    },
                                    value: _preferenceOnly
                                        ? 2
                                        : _missingOnly
                                        ? 1
                                        : 0,
                                    onChanged: (value) => setState(() {
                                      _missingOnly = value == 1;
                                      _preferenceOnly = value == 2;
                                      _selectedPostId = null;
                                      _selectedPostIds = {};
                                    }),
                                  ),
                                ],
                                trailing: [
                                  _DutyHeaderSearchField(
                                    onChanged: (value) => setState(() {
                                      _searchQuery = value;
                                      _selectedPostId = null;
                                      _selectedPostIds = {};
                                    }),
                                  ),
                                  _DutyToolbarField(
                                    label: '视角',
                                    labelColor: _headerSecondary(context),
                                    child: _DutySegments<_DutyView>(
                                      items: const {
                                        _DutyView.week: '整周网格',
                                        _DutyView.schoolClass: '按班级',
                                        _DutyView.teacher: '按教师',
                                      },
                                      value: _view,
                                      onChanged: (view) => setState(() {
                                        _view = view;
                                        _selectedPostId = null;
                                        _selectedPostIds = {};
                                      }),
                                    ),
                                  ),
                                  if (draft.posts.isNotEmpty) ...[
                                    Container(
                                      width: 1,
                                      height: 18,
                                      color: _headerBorder(context),
                                    ),
                                    legend,
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              pagePadding,
                              0,
                              pagePadding,
                              12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (invalidAssignments > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      '$invalidAssignments 个指派不符合当前规则，已保留原安排，请调整后发布。',
                                      style: theme.bodySmall?.copyWith(
                                        color: colors.destructive,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: AppSurface(
                                    child: Column(
                                      children: [
                                        if (_filling)
                                          const f.FProgress(
                                            semanticsLabel: '正在智能补齐带班',
                                          ),
                                        Expanded(child: weekBody),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (focused != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: colors.dialogBarrier.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                    if (focused != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        left: wide ? null : 0,
                        width: wide ? 440 : null,
                        child: _TeacherPickerPanel(
                          key: ValueKey(focused.id),
                          snapshot: widget.snapshot,
                          draft: _draft,
                          post: focused,
                          editable: _editable,
                          onConfirm: (picked) =>
                              _assignTeacher(focused, picked),
                          onClose: () => setState(() => _selectedPostId = null),
                          onRemove: _editable
                              ? () => _removePost(focused)
                              : null,
                          onSettings: _editable
                              ? () =>
                                    unawaited(_editPostPersonnel({focused.id}))
                              : null,
                          onManagePool: _editable
                              ? () => unawaited(_editTeacherPool())
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                key: const ValueKey('duty-actionbar'),
                constraints: const BoxConstraints(minHeight: 56),
                padding: EdgeInsets.symmetric(
                  horizontal: pagePadding,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _DutyProgress(
                      assigned: draft.posts.length - missing,
                      total: draft.posts.length,
                    ),
                    if (_selectedPostIds.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '已选 ${_selectedPostIds.length} 个岗位',
                            style: theme.bodySmall?.copyWith(
                              color: colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          AppGhostButton(
                            onPressed: () =>
                                setState(() => _selectedPostIds = {}),
                            child: const Text('取消选择'),
                          ),
                          AppGhostButton(
                            onPressed: _editable
                                ? () => _editPostPersonnel({
                                    ..._selectedPostIds,
                                  }, mode: _PersonnelEditMode.pool)
                                : null,
                            child: const Text('设置候选池'),
                          ),
                          AppGhostButton(
                            onPressed: _editable
                                ? () => _editPostPersonnel({
                                    ..._selectedPostIds,
                                  }, mode: _PersonnelEditMode.matching)
                                : null,
                            child: const Text('匹配偏好'),
                          ),
                          AppDestructiveButton(
                            onPressed: _editable
                                ? () => _removePosts({
                                    ..._selectedPostIds,
                                  }, batch: true)
                                : null,
                            child: const Text('批量移除'),
                          ),
                        ],
                      ),
                    if (selected == null)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_dirty)
                            Text(
                              '有未保存的修改',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.warning,
                              ),
                            ),
                          _DutyOutlineButton(
                            onPressed: _editable
                                ? () => unawaited(_save())
                                : null,
                            child: const Text('保存草稿'),
                          ),
                          if (widget.canRepair)
                            _DutyOutlineButton(
                              onPressed: _editable
                                  ? () => _publish(repair: true)
                                  : null,
                              child: const Text('修正带班并协调'),
                            ),
                          AppPrimaryButton(
                            onPressed: canPreview ? _publish : null,
                            child: const Text('预览并确认'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

void _fillSupervision((SendPort, SchedulingSnapshot, SupervisionDraft) input) {
  final (port, snapshot, draft) = input;
  port.send(const SupervisionAllocator().fill(snapshot, draft));
}

SupervisionVersion? _latestVersion(List<SupervisionVersion> versions) => ([
  ...versions,
]..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate))).firstOrNull;

String _dateLabel(DateTime date) => '${date.year}年${date.month}月${date.day}日';

List<DateTime> _publishDates(AcademicTerm term) {
  final now = DateUtils.dateOnly(DateTime.now());
  return [
    for (var week = 1; week <= term.teachingWeekCount; week++)
      if (term.teachingWeekStart(week) case final start?)
        if (DateUtils.addDaysToDate(
              start,
              (DateTime.daysPerWeek + DateTime.monday - start.weekday) %
                  DateTime.daysPerWeek,
            )
            case final monday when monday.isAfter(now))
          monday,
  ];
}

LessonPeriodType? _postPeriod(
  SchedulingSnapshot snapshot,
  SupervisionPost post,
) => snapshot.routines
    .where((routine) => routine.stageId == post.stageId)
    .firstOrNull
    ?.periodTypes
    .where((period) => period.id == post.periodTypeId)
    .firstOrNull;

int _postMinute(SchedulingSnapshot snapshot, SupervisionPost post) =>
    _postPeriod(snapshot, post)?.lessonTimes
        .where((time) => time.lessonIndex == post.lessonIndices.first)
        .firstOrNull
        ?.startMinute ??
    1440;

String _slotLabel(SchedulingSnapshot snapshot, SupervisionPost post) {
  final period = _postPeriod(snapshot, post);
  return '${period?.name ?? post.periodTypeId} · 第 ${post.lessonIndices.join('、')} 节';
}
