part of 'temporary_adjustments_page.dart';

final temporaryExportSaveLocationProvider =
    Provider<Future<FileSaveLocation?> Function(String)>(
      (ref) =>
          (name) => getSaveLocation(
            suggestedName: name,
            acceptedTypeGroups: [
              const XTypeGroup(label: 'Excel', extensions: ['xlsx']),
            ],
          ),
    );

String _candidateKey(
  String sourceKey,
  String kind,
  DateTime date,
  String periodId,
  int index,
  String? targetKey,
) =>
    '$sourceKey:$kind:${date.toIso8601String().substring(0, 10)}:$periodId:$index:$targetKey';

typedef _CandidateBatch = ({
  TemporaryTimetableState state,
  List<SchedulePosition> positions,
  String sourceKey,
  String kind,
  String classId,
  DateTime start,
});
typedef _QueuedCandidateBatch = ({String key, _CandidateBatch input});
typedef _CandidateBatchMessage = ({_CandidateBatch input, SendPort replyTo});

typedef _ClassPositionKey = (String, int, String, int);
typedef _ClassLessonKey = (String, int, int, int, String, int);
typedef _TeacherLessonKey = (String, int, int, int, String);
typedef _IndexedRecord = ({TemporaryAdjustmentRecord record, int rank});

String _teacherGridSlotKey(SchedulePosition position) => position.hasClockTime
    ? 'time:${position.startMinute}:${position.endMinute}'
    : '${position.stageId}:${position.periodTypeId}:${position.lessonIndex}';

Map<String, ActualChangePreview> _computeCandidateBatch(_CandidateBatch input) {
  final candidates = <String, ActualChangePreview>{};
  final state = input.state;
  final problem = const ProblemBuilder().build(state.snapshot);
  final positionsByWeekday = <int, List<SchedulePosition>>{};
  for (final position in input.positions) {
    positionsByWeekday.putIfAbsent(position.weekday, () => []).add(position);
  }
  final exceptionsByDate = <(int, int, int), CalendarException>{};
  for (final exception in state.exceptions) {
    exceptionsByDate.putIfAbsent((
      exception.date.year,
      exception.date.month,
      exception.date.day,
    ), () => exception);
  }
  final lessonsBySlot = <(int, int, int, String, int), ActualLesson>{};
  for (final lesson in state.lessons) {
    final position = lesson.item.position;
    if (lesson.item.classId != input.classId || position == null) continue;
    lessonsBySlot.putIfAbsent((
      lesson.date.year,
      lesson.date.month,
      lesson.date.day,
      position.periodTypeId,
      position.lessonIndex,
    ), () => lesson);
  }
  for (var day = 0; day < 7; day++) {
    final date = input.start.add(Duration(days: day));
    final exception = exceptionsByDate[(date.year, date.month, date.day)];
    if (exception?.kind == CalendarExceptionKind.holiday) continue;
    final weekday = exception?.makeupWeekday ?? date.weekday;
    for (final position in positionsByWeekday[weekday] ?? const []) {
      final course =
          lessonsBySlot[(
            date.year,
            date.month,
            date.day,
            position.periodTypeId,
            position.lessonIndex,
          )];
      if (input.kind == 'move' && course == null) {
        candidates[_candidateKey(
          input.sourceKey,
          input.kind,
          date,
          position.periodTypeId,
          position.lessonIndex,
          null,
        )] = state.previewMove(
          TemporaryMoveRequest(
            sourceKey: input.sourceKey,
            targetDate: date,
            targetPosition: position,
          ),
          problem: problem,
        );
      } else if (input.kind == 'swap' &&
          course != null &&
          course.key != input.sourceKey) {
        candidates[_candidateKey(
          input.sourceKey,
          input.kind,
          date,
          position.periodTypeId,
          position.lessonIndex,
          course.key,
        )] = state.previewSwap(
          TemporarySwapRequest(
            firstKey: input.sourceKey,
            secondKey: course.key,
          ),
          problem: problem,
        );
      }
    }
  }
  return candidates;
}

void _candidateBatchWorker(_CandidateBatchMessage message) {
  try {
    message.replyTo.send(_computeCandidateBatch(message.input));
  } on Object catch (error, stackTrace) {
    message.replyTo.send(_CandidateBatchWorkerError('$error', '$stackTrace'));
  }
}

final class _CandidateBatchWorkerError {
  const _CandidateBatchWorkerError(this.message, this.stackTrace);

  final String message;
  final String stackTrace;
}

/// Indices shared by every timetable rebuild for the same immutable state.
/// Week navigation changes only the visible date range, not these lookups.
class _TemporaryTimetableIndexes {
  _TemporaryTimetableIndexes(this.state) {
    problem = const ProblemBuilder().build(state.snapshot);
    positionsByClass = problem.positionsByClass;
    for (final entry in positionsByClass.entries) {
      for (final position in entry.value) {
        positionsByCell[(
              entry.key,
              position.weekday,
              position.periodTypeId,
              position.lessonIndex,
            )] =
            position;
      }
    }

    for (final lesson in state.lessons) {
      final position = lesson.item.position;
      if (position == null) continue;
      lessonsByClassSlot.putIfAbsent((
        lesson.item.classId,
        lesson.date.year,
        lesson.date.month,
        lesson.date.day,
        position.periodTypeId,
        position.lessonIndex,
      ), () => lesson);
      teacherLessonsBySlot
          .putIfAbsent((
            lesson.item.teacherId,
            lesson.date.year,
            lesson.date.month,
            lesson.date.day,
            _teacherGridSlotKey(position),
          ), () => [])
          .add(lesson);
      classesByTeacher
          .putIfAbsent(lesson.item.teacherId, () => {})
          .add(lesson.item.classId);
    }

    var rank = 0;
    for (final record in state.records.reversed) {
      if (record.cancelledAt == null && !record.needsAttention) {
        for (final change in record.changes) {
          activeRecordByLessonKey.putIfAbsent(
            change.after.key,
            () => (record: record, rank: rank),
          );
        }
      }
      rank++;
    }
  }

  final TemporaryTimetableState state;
  late final SchedulingProblem problem;
  late final Map<String, List<SchedulePosition>> positionsByClass;
  final Map<_ClassPositionKey, SchedulePosition> positionsByCell = {};
  final Map<_ClassLessonKey, ActualLesson> lessonsByClassSlot = {};
  final Map<_TeacherLessonKey, List<ActualLesson>> teacherLessonsBySlot = {};
  final Map<String, Set<String>> classesByTeacher = {};
  final Map<String, _IndexedRecord> activeRecordByLessonKey = {};

  SchedulePosition? position(
    String classId,
    int weekday,
    String periodTypeId,
    int lessonIndex,
  ) => positionsByCell[(classId, weekday, periodTypeId, lessonIndex)];

  ActualLesson? classLesson(
    String classId,
    DateTime date,
    String periodTypeId,
    int lessonIndex,
  ) =>
      lessonsByClassSlot[(
        classId,
        date.year,
        date.month,
        date.day,
        periodTypeId,
        lessonIndex,
      )];

  List<ActualLesson> teacherLessons(
    String teacherId,
    DateTime date,
    String slotKey,
  ) =>
      teacherLessonsBySlot[(
        teacherId,
        date.year,
        date.month,
        date.day,
        slotKey,
      )] ??
      const [];

  Set<String> classesForTeacher(String teacherId) =>
      classesByTeacher[teacherId] ?? const {};

  _IndexedRecord? recordForLesson(String lessonKey) =>
      activeRecordByLessonKey[lessonKey];

  _IndexedRecord? recordForLessons(Iterable<ActualLesson> lessons) {
    _IndexedRecord? result;
    for (final lesson in lessons) {
      final candidate = recordForLesson(lesson.key);
      if (candidate != null &&
          (result == null || candidate.rank < result.rank)) {
        result = candidate;
      }
    }
    return result;
  }
}

/// 预览弹窗的界面状态（用 ValueNotifier 通知，避免对话框关闭后 setState）。
class _PreviewUi {
  const _PreviewUi({required this.preview, this.computing = false});

  final ActualChangePreview preview;
  final bool computing;
}

/// 空课位的圆角虚线描边（可选目标为蓝色虚线，普通空位为浅灰虚线）。
class _DashBorderPainter extends CustomPainter {
  _DashBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + dash).clamp(0, metric.length),
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _TemporaryLessonHover extends StatefulWidget {
  const _TemporaryLessonHover({
    required this.enabled,
    required this.borderRadius,
    required this.child,
  });

  final bool enabled;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<_TemporaryLessonHover> createState() => _TemporaryLessonHoverState();
}

class _TemporaryLessonHoverState extends State<_TemporaryLessonHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showHover = widget.enabled && _hovered;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        foregroundDecoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: showHover
                ? context.appColors.blue.withValues(alpha: .65)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
