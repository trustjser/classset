import 'dart:async';

import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/scheduling/course_scheduler.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/scheduling_worker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SchedulingStatus {
  idle,
  loading,
  ready,
  solving,
  committing,
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
  });

  final SchedulingStatus status;
  final SchedulingSnapshot? snapshot;
  final SchedulingProblem? problem;
  final Set<String> selectedClassIds;
  final ScheduleProgress? progress;
  final ScheduleRun? run;
  final String? error;
  final String? backupWarning;

  List<SchedulePreflightCheck> get checks => problem?.checks ?? const [];
  bool get canStart =>
      problem?.isReady == true &&
      status != SchedulingStatus.solving &&
      status != SchedulingStatus.committing &&
      status != SchedulingStatus.loading;

  SchedulingState copyWith({
    SchedulingStatus? status,
    Object? snapshot = _notProvided,
    Object? problem = _notProvided,
    Set<String>? selectedClassIds,
    Object? progress = _notProvided,
    Object? run = _notProvided,
    Object? error = _notProvided,
    Object? backupWarning = _notProvided,
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
  int _requestVersion = 0;

  Future<void> refresh() async {
    if (state.status == SchedulingStatus.solving ||
        state.status == SchedulingStatus.committing) {
      return;
    }
    final version = ++_requestVersion;
    state = state.copyWith(status: SchedulingStatus.loading, error: null);
    try {
      final snapshot = await _repository.loadSchedulingSnapshot(termId);
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

  void selectClasses(Set<String> classIds) {
    if (state.status == SchedulingStatus.solving ||
        state.status == SchedulingStatus.committing) {
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
    await _repository.setScheduleLock(lock, enabled: enabled);
    await refresh();
  }

  Future<void> start({required int seed}) async {
    if (state.status == SchedulingStatus.solving ||
        state.status == SchedulingStatus.committing) {
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
      state = state.copyWith(
        status: SchedulingStatus.completed,
        run: run,
        backupWarning: committed.backupWarning,
      );
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

final schedulingControllerProvider = StateNotifierProvider.autoDispose
    .family<SchedulingController, SchedulingState, String>(
      (ref, termId) =>
          SchedulingController(ref.watch(schoolRepositoryProvider), termId),
    );
