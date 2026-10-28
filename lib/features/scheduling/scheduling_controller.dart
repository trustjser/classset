import 'dart:async';
import 'dart:isolate';

import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/scheduling/course_scheduler.dart';
import 'package:class_set/domain/scheduling/manual_schedule_editor.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/schedule_reconciler.dart';
import 'package:class_set/features/scheduling/scheduling_worker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SchedulingStatus {
  idle,
  loading,
  ready,
  solving,
  committing,
  savingEdit,
  completed,
  cancelled,
  failed,
}

class SchedulingState {
  const SchedulingState({
    this.status = SchedulingStatus.idle,
    this.snapshot,
    this.problem,
    this.selectedClassIds = const {},
    this.progress,
    this.run,
    this.error,
    this.backupWarning,
    this.items = const [],
    this.undoCount = 0,
    this.redoCount = 0,
    this.detectionIssues = const [],
    this.detectionRan = false,
    this.pendingBaseline,
    this.currentSnapshot,
    this.reconciliationPreview,
    this.reconciling = false,
  });

  final SchedulingStatus status;
  final SchedulingSnapshot? snapshot;
  final SchedulingProblem? problem;
  final Set<String> selectedClassIds;
  final ScheduleProgress? progress;
  final ScheduleRun? run;
  final String? error;
  final String? backupWarning;
  final List<ScheduleItem> items;
  final int undoCount;
  final int redoCount;
  final List<ScheduleBlocker> detectionIssues;
  final bool detectionRan;
  final SchedulingSnapshot? pendingBaseline;
  final SchedulingSnapshot? currentSnapshot;
  final ScheduleReconciliationPreview? reconciliationPreview;
  final bool reconciling;

  List<SchedulePreflightCheck> get checks => problem?.checks ?? const [];
  bool get canStart =>
      problem?.isReady == true &&
      status != SchedulingStatus.solving &&
      status != SchedulingStatus.committing &&
      status != SchedulingStatus.savingEdit &&
      status != SchedulingStatus.loading &&
      pendingBaseline == null;

  SchedulingState copyWith({
    SchedulingStatus? status,
    Object? snapshot = _notProvided,
    Object? problem = _notProvided,
    Set<String>? selectedClassIds,
    Object? progress = _notProvided,
    Object? run = _notProvided,
    Object? error = _notProvided,
    Object? backupWarning = _notProvided,
    List<ScheduleItem>? items,
    int? undoCount,
    int? redoCount,
    List<ScheduleBlocker>? detectionIssues,
    bool? detectionRan,
    Object? pendingBaseline = _notProvided,
    Object? currentSnapshot = _notProvided,
    Object? reconciliationPreview = _notProvided,
    bool? reconciling,
  }) => SchedulingState(
    status: status ?? this.status,
    snapshot: identical(snapshot, _notProvided)
        ? this.snapshot
        : snapshot as SchedulingSnapshot?,
    problem: identical(problem, _notProvided)
        ? this.problem
        : problem as SchedulingProblem?,
    selectedClassIds: selectedClassIds ?? this.selectedClassIds,
    progress: identical(progress, _notProvided)
        ? this.progress
        : progress as ScheduleProgress?,
    run: identical(run, _notProvided) ? this.run : run as ScheduleRun?,
    error: identical(error, _notProvided) ? this.error : error as String?,
    backupWarning: identical(backupWarning, _notProvided)
        ? this.backupWarning
        : backupWarning as String?,
    items: items ?? this.items,
    undoCount: undoCount ?? this.undoCount,
    redoCount: redoCount ?? this.redoCount,
    detectionIssues: detectionIssues ?? this.detectionIssues,
    detectionRan: detectionRan ?? this.detectionRan,
    pendingBaseline: identical(pendingBaseline, _notProvided)
        ? this.pendingBaseline
        : pendingBaseline as SchedulingSnapshot?,
    currentSnapshot: identical(currentSnapshot, _notProvided)
        ? this.currentSnapshot
        : currentSnapshot as SchedulingSnapshot?,
    reconciliationPreview: identical(reconciliationPreview, _notProvided)
        ? this.reconciliationPreview
        : reconciliationPreview as ScheduleReconciliationPreview?,
    reconciling: reconciling ?? this.reconciling,
  );
}

const _notProvided = Object();

class SchedulingController extends StateNotifier<SchedulingState> {
  SchedulingController(this._repository, this.termId)
    : super(const SchedulingState()) {
    unawaited(refresh());
  }

  final SchoolRepository _repository;
  final String termId;
  final SchedulingWorker _worker = SchedulingWorker();
  final ProblemBuilder _builder = const ProblemBuilder();
  final ManualScheduleEditor _manualEditor = const ManualScheduleEditor();
  final List<_ManualEdit> _undo = [];
  final List<_ManualEdit> _redo = [];
  int _requestVersion = 0;

  Future<void> refresh({bool preserveHistory = false}) async {
    if (state.status == SchedulingStatus.solving ||
        state.status == SchedulingStatus.committing ||
        (state.status == SchedulingStatus.savingEdit && !preserveHistory)) {
      return;
    }
    final version = ++_requestVersion;
    if (!preserveHistory) {
      _undo.clear();
      _redo.clear();
    }
    state = state.copyWith(status: SchedulingStatus.loading, error: null);
    try {
      final current = await _repository.loadSchedulingSnapshot(termId);
      final pending = await _repository.loadPendingSchedulingBaseline(termId);
      final snapshot = pending ?? current;
      if (!mounted || version != _requestVersion) return;
      final selected = state.snapshot == null
          ? snapshot.classes.map((item) => item.id).toSet()
          : state.selectedClassIds;
      final problem = _builder.build(snapshot, selectedClassIds: selected);
      final view = await _repository.watchSchedule(termId).first;
      if (!mounted || version != _requestVersion) return;
      state = state.copyWith(
        status: SchedulingStatus.ready,
        snapshot: snapshot,
        problem: problem,
        selectedClassIds: selected,
        run: view.latestRun,
        progress: null,
        backupWarning: null,
        items: _withClock(snapshot.existingItems, problem),
        undoCount: _undo.length,
        redoCount: _redo.length,
        detectionIssues: const [],
        detectionRan: false,
        pendingBaseline: pending,
        currentSnapshot: current,
        reconciliationPreview: null,
        reconciling: false,
      );
    } on Object catch (error) {
      if (mounted && version == _requestVersion) {
        state = state.copyWith(
          status: SchedulingStatus.failed,
          error: '加载排课资料失败：$error',
        );
      }
    }
  }

  Future<void> previewReconciliation() async {
    if (state.pendingBaseline == null || state.reconciling) return;
    state = state.copyWith(reconciling: true, error: null);
    try {
      final current = await _repository.loadSchedulingSnapshot(termId);
      final baseline = await _repository.loadPendingSchedulingBaseline(termId);
      if (baseline == null) {
        await refresh();
        return;
      }
      final preview = await Isolate.run(
        () => const ScheduleReconciler().preview(baseline, current),
      );
      if (!mounted) return;
      state = state.copyWith(
        reconciliationPreview: preview,
        reconciling: false,
      );
    } on Object catch (error) {
      if (mounted) {
        state = state.copyWith(error: '增量协调失败：$error', reconciling: false);
      }
    }
  }

  Future<void> applyReconciliation() async {
    final preview = state.reconciliationPreview;
    if (preview == null || !preview.canApply || state.reconciling) return;
    state = state.copyWith(reconciling: true, error: null);
    try {
      final result = await _repository.commitScheduleReconciliation(
        termId: termId,
        expectedFingerprint: preview.inputFingerprint,
      );
      await refresh();
      if (mounted && result.backupWarning != null) {
        state = state.copyWith(backupWarning: result.backupWarning);
      }
    } on Object catch (error) {
      if (mounted) {
        state = state.copyWith(error: '应用调整失败：$error', reconciling: false);
      }
    }
  }

  void selectClasses(Set<String> classIds) {
    if (state.status == SchedulingStatus.solving ||
        state.status == SchedulingStatus.committing ||
        state.status == SchedulingStatus.savingEdit) {
      return;
    }
    final snapshot = state.snapshot;
    state = state.copyWith(
      selectedClassIds: Set.unmodifiable(classIds),
      problem: snapshot == null
          ? null
          : _builder.build(snapshot, selectedClassIds: classIds),
      status: SchedulingStatus.ready,
      error: null,
    );
  }

  Future<void> saveConfiguration({
    required List<ScheduleCondition> conditions,
    required SchedulePreferences preferences,
  }) async {
    await _repository.saveScheduleConfiguration(
      termId: termId,
      conditions: conditions,
      preferences: preferences,
    );
    await refresh();
  }

  Future<void> setLock(ScheduleLock lock, {required bool enabled}) async {
    if (state.pendingBaseline != null) return;
    try {
      await _repository.setScheduleLock(lock, enabled: enabled);
      await refresh();
    } on Object catch (error) {
      state = state.copyWith(error: '更改锁定状态失败：$error');
    }
  }

  Future<void> setAllClassLocks({required bool enabled}) async {
    final snapshot = state.snapshot;
    if (snapshot == null) return;
    await setClassLocks(
      snapshot.classes.map((item) => item.id).toSet(),
      enabled: enabled,
    );
  }

  Future<void> setClassLocks(
    Set<String> classIds, {
    required bool enabled,
  }) async {
    if (state.pendingBaseline != null) return;
    try {
      await _repository.setScheduleLocks(
        locks: [
          for (final classId in classIds)
            ScheduleLock(
              termId: termId,
              scope: ScheduleLockScope.schoolClass,
              targetId: classId,
            ),
        ],
        enabled: enabled,
      );
      await refresh();
    } on Object catch (error) {
      state = state.copyWith(error: '更改全校锁定状态失败：$error');
    }
  }

  Future<void> detect() async {
    if (state.pendingBaseline != null) return;
    if (state.status != SchedulingStatus.ready &&
        state.status != SchedulingStatus.completed) {
      return;
    }
    final snapshot = state.snapshot;
    if (snapshot == null) return;
    final items = state.items;
    final version = _requestVersion;
    try {
      final issues = await Isolate.run(
        () => const ManualScheduleEditor().detectAll(
          snapshot: snapshot,
          items: items,
        ),
      );
      if (!mounted ||
          version != _requestVersion ||
          !identical(state.items, items)) {
        return;
      }
      state = state.copyWith(
        detectionIssues: issues,
        detectionRan: true,
        error: null,
      );
    } on Object catch (error) {
      if (mounted) state = state.copyWith(error: '检测课表失败：$error');
    }
  }

  ManualMoveResult previewMove(
    String itemId,
    SchedulePosition? target, [
    String? swapWithItemId,
  ]) {
    if (state.pendingBaseline != null) {
      return ManualMoveResult(
        items: state.items,
        blockers: const [
          ScheduleBlocker(code: 'reconciliationPending', message: '请先完成课表协调。'),
        ],
        changedItemIds: const {},
      );
    }
    final snapshot = state.snapshot;
    if (snapshot == null) {
      throw StateError('排课资料尚未加载');
    }
    return _manualEditor.previewMove(
      snapshot: snapshot,
      items: state.items,
      itemId: itemId,
      target: target,
      swapWithItemId: swapWithItemId,
      problem: state.problem,
    );
  }

  Future<ManualMoveResult> move(
    String itemId,
    SchedulePosition? target, [
    String? swapWithItemId,
  ]) async {
    final result = previewMove(itemId, target, swapWithItemId);
    if (state.pendingBaseline != null ||
        !result.allowed ||
        result.changedItemIds.isEmpty ||
        (state.status != SchedulingStatus.ready &&
            state.status != SchedulingStatus.completed)) {
      return result;
    }
    final expectedFingerprint = state.snapshot!.inputFingerprint;
    final before = state.items
        .where((item) => result.changedItemIds.contains(item.id))
        .toList();
    final after = result.items
        .where((item) => result.changedItemIds.contains(item.id))
        .toList();
    state = state.copyWith(status: SchedulingStatus.savingEdit, error: null);
    try {
      await _repository.commitManualScheduleEdit(
        termId: termId,
        before: before,
        after: after,
        expectedFingerprint: expectedFingerprint,
      );
      if (!mounted) return result;
      _undo.add(_ManualEdit(before, after));
      if (_undo.length > 120) _undo.removeAt(0);
      _redo.clear();
      state = state.copyWith(
        status: SchedulingStatus.ready,
        items: result.items,
        undoCount: _undo.length,
        redoCount: 0,
        detectionIssues: const [],
        detectionRan: false,
      );
      await refresh(preserveHistory: true);
    } on Object catch (error) {
      if (mounted) {
        if (error.toString().contains('已改变')) {
          state = state.copyWith(status: SchedulingStatus.ready);
          await refresh();
        }
        if (!mounted) return result;
        state = state.copyWith(
          status: SchedulingStatus.ready,
          error: '保存调课失败：$error',
        );
      }
    }
    return result;
  }

  /// 将暂放课程批量放入空位，以一次可撤销操作保存。
  Future<int?> placeUnplaced(Set<String> itemIds) async {
    final snapshot = state.snapshot;
    if (snapshot == null ||
        state.pendingBaseline != null ||
        (state.status != SchedulingStatus.ready &&
            state.status != SchedulingStatus.completed)) {
      return null;
    }
    final originalItems = state.items;
    final problem = state.problem;
    state = state.copyWith(status: SchedulingStatus.savingEdit, error: null);
    try {
      final result = await Isolate.run(
        () => const ManualScheduleEditor().placeUnplaced(
          snapshot: snapshot,
          items: originalItems,
          itemIds: itemIds,
          problem: problem,
        ),
      );
      if (!mounted) return null;
      if (result.changedItemIds.isEmpty) {
        state = state.copyWith(status: SchedulingStatus.ready);
        return 0;
      }
      final before = originalItems
          .where((item) => result.changedItemIds.contains(item.id))
          .toList();
      final after = result.items
          .where((item) => result.changedItemIds.contains(item.id))
          .toList();
      await _repository.commitManualScheduleEdit(
        termId: termId,
        before: originalItems,
        after: result.items,
        expectedFingerprint: snapshot.inputFingerprint,
      );
      if (!mounted) return null;
      _undo.add(_ManualEdit(before, after));
      if (_undo.length > 120) _undo.removeAt(0);
      _redo.clear();
      state = state.copyWith(
        status: SchedulingStatus.ready,
        items: result.items,
        undoCount: _undo.length,
        redoCount: 0,
        detectionIssues: const [],
        detectionRan: false,
      );
      await refresh(preserveHistory: true);
      return result.changedItemIds.where(itemIds.contains).length;
    } on Object catch (error) {
      if (mounted) {
        if (error.toString().contains('已改变')) {
          state = state.copyWith(status: SchedulingStatus.ready);
          await refresh();
        }
        if (mounted) {
          state = state.copyWith(
            status: SchedulingStatus.ready,
            error: '一键放入失败：$error',
          );
        }
      }
      return null;
    }
  }

  Future<void> undo() => _applyHistory(undo: true);

  Future<void> redo() => _applyHistory(undo: false);

  Future<void> _applyHistory({required bool undo}) async {
    if (state.pendingBaseline != null) return;
    if (state.status != SchedulingStatus.ready &&
        state.status != SchedulingStatus.completed) {
      return;
    }
    final source = undo ? _undo : _redo;
    if (source.isEmpty) return;
    final edit = source.last;
    final before = undo ? edit.after : edit.before;
    final after = undo ? edit.before : edit.after;
    final expectedFingerprint = state.snapshot!.inputFingerprint;
    state = state.copyWith(status: SchedulingStatus.savingEdit, error: null);
    try {
      await _repository.commitManualScheduleEdit(
        termId: termId,
        before: before,
        after: after,
        expectedFingerprint: expectedFingerprint,
      );
      if (!mounted) return;
      source.removeLast();
      (undo ? _redo : _undo).add(edit);
      final replacements = {for (final item in after) item.id: item};
      state = state.copyWith(
        status: SchedulingStatus.ready,
        items: [for (final item in state.items) replacements[item.id] ?? item],
        undoCount: _undo.length,
        redoCount: _redo.length,
        detectionIssues: const [],
        detectionRan: false,
      );
      await refresh(preserveHistory: true);
    } on Object catch (error) {
      if (mounted) {
        if (error.toString().contains('已改变')) {
          state = state.copyWith(status: SchedulingStatus.ready);
          await refresh();
        }
        if (!mounted) return;
        state = state.copyWith(
          status: SchedulingStatus.ready,
          error: '${undo ? '撤销' : '重做'}失败：$error',
        );
      }
    }
  }

  Future<void> start({required int seed}) async {
    if (state.pendingBaseline != null) return;
    if (state.status == SchedulingStatus.solving ||
        state.status == SchedulingStatus.committing ||
        state.status == SchedulingStatus.savingEdit) {
      return;
    }
    final version = ++_requestVersion;
    state = state.copyWith(status: SchedulingStatus.loading, error: null);
    try {
      final snapshot = await _repository.loadSchedulingSnapshot(termId);
      if (!mounted || version != _requestVersion) return;
      final selected = state.selectedClassIds;
      final problem = _builder.build(snapshot, selectedClassIds: selected);
      state = state.copyWith(snapshot: snapshot, problem: problem);
      if (!problem.isReady) {
        state = state.copyWith(status: SchedulingStatus.ready);
        return;
      }
      final config = ScheduleRunConfig(
        selectedClassIds: selected,
        seed: seed,
        strength: snapshot.preferences.strength,
      );
      state = state.copyWith(
        status: SchedulingStatus.solving,
        progress: null,
        run: null,
        backupWarning: null,
      );
      final run = await _worker.solve(
        problem,
        config: config,
        onProgress: (progress) {
          if (mounted && version == _requestVersion) {
            state = state.copyWith(progress: progress);
          }
        },
      );
      if (!mounted || version != _requestVersion) return;
      if (run == null) {
        state = state.copyWith(status: SchedulingStatus.cancelled);
        return;
      }
      state = state.copyWith(status: SchedulingStatus.committing);
      final committed = await _repository.commitScheduleRun(
        run,
        selectedClassIds: selected,
      );
      if (!mounted || version != _requestVersion) return;
      final updatedSnapshot = await _repository.loadSchedulingSnapshot(termId);
      if (!mounted || version != _requestVersion) return;
      final updatedProblem = _builder.build(
        updatedSnapshot,
        selectedClassIds: selected,
      );
      state = state.copyWith(
        status: SchedulingStatus.completed,
        snapshot: updatedSnapshot,
        problem: updatedProblem,
        run: run,
        backupWarning: committed.backupWarning,
        items: _withClock(updatedSnapshot.existingItems, updatedProblem),
        undoCount: 0,
        redoCount: 0,
        detectionIssues: const [],
        detectionRan: false,
      );
      _undo.clear();
      _redo.clear();
    } on Object catch (error) {
      if (mounted && version == _requestVersion) {
        state = state.copyWith(
          status: SchedulingStatus.failed,
          error: '自动排课失败：$error',
        );
      }
    }
  }

  void cancel() {
    if (state.status != SchedulingStatus.solving) return;
    _requestVersion++;
    _worker.cancel();
    state = state.copyWith(status: SchedulingStatus.cancelled);
  }

  @override
  void dispose() {
    _worker.cancel();
    super.dispose();
  }
}

List<ScheduleItem> _withClock(
  List<ScheduleItem> items,
  SchedulingProblem problem,
) => [
  for (final item in items)
    if (item.position case final position?)
      item.at(
        (problem.positionsByClass[item.classId] ?? const <SchedulePosition>[])
                .where((candidate) => candidate.sameCell(position))
                .firstOrNull ??
            position,
      )
    else
      item,
];

class _ManualEdit {
  const _ManualEdit(this.before, this.after);

  final List<ScheduleItem> before;
  final List<ScheduleItem> after;
}

final schedulingControllerProvider = StateNotifierProvider.autoDispose
    .family<SchedulingController, SchedulingState, String>(
      (ref, termId) =>
          SchedulingController(ref.watch(schoolRepositoryProvider), termId),
    );
