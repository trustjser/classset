import 'dart:async';
import 'dart:isolate';

import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/scheduling/course_scheduler.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';

/// Runs the synchronous solver away from the UI isolate. Nothing is persisted
/// until the caller receives a complete [ScheduleRun].
class SchedulingWorker {
  Isolate? _isolate;
  ReceivePort? _port;
  StreamSubscription<dynamic>? _subscription;
  Completer<ScheduleRun?>? _completion;

  bool get isRunning => _completion != null;

  Future<ScheduleRun?> solve(
    SchedulingProblem problem, {
    required ScheduleRunConfig config,
    void Function(ScheduleProgress)? onProgress,
  }) async {
    if (isRunning) throw StateError('已有排课任务正在运行');
    final port = ReceivePort();
    final completion = Completer<ScheduleRun?>();
    _port = port;
    _completion = completion;
    _subscription = port.listen((dynamic message) {
      if (message is ScheduleProgress) {
        onProgress?.call(message);
      } else if (message is ScheduleRun) {
        if (!completion.isCompleted) completion.complete(message);
      } else if (message is _WorkerFailure) {
        if (!completion.isCompleted) {
          completion.completeError(StateError(message.message));
        }
      }
    });
    try {
      _isolate = await Isolate.spawn<_WorkerRequest>(
        _solveInIsolate,
        _WorkerRequest(problem, config, port.sendPort),
      );
      return await completion.future;
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _port?.close();
      _port = null;
      _completion = null;
    }
  }

  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(null);
    }
  }
}

class _WorkerRequest {
  const _WorkerRequest(this.problem, this.config, this.replyTo);

  final SchedulingProblem problem;
  final ScheduleRunConfig config;
  final SendPort replyTo;
}

class _WorkerFailure {
  const _WorkerFailure(this.message);

  final String message;
}

void _solveInIsolate(_WorkerRequest request) {
  try {
    final run = const CourseScheduler().solve(
      request.problem,
      config: request.config,
      onProgress: request.replyTo.send,
    );
    request.replyTo.send(run);
  } on Object catch (error) {
    request.replyTo.send(_WorkerFailure(error.toString()));
  }
}
