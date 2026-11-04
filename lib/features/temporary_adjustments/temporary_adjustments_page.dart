import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/temporary_preview_worker.dart';
import 'package:class_set/features/temporary_adjustments/temporary_adjustment_export.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

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

/// 按实际日期查看课表并预览临时调整。
class TemporaryAdjustmentsPage extends ConsumerStatefulWidget {
  const TemporaryAdjustmentsPage({required this.termId, super.key});
  final String termId;

  @override
  ConsumerState<TemporaryAdjustmentsPage> createState() =>
      _TemporaryAdjustmentsPageState();
}

class _TemporaryAdjustmentsPageState
    extends ConsumerState<TemporaryAdjustmentsPage> {
  TemporaryTimetableState? _data;
  _TemporaryTimetableIndexes? _timetableIndexes;
  String? _error;
  String? _classId;
  bool _teacherView = false;
  String? _viewTeacherId;
  int? _week;
  bool _records = false;
  bool _showCancelled = false;
  String? _recordType;
  String? _recordStatus;
  String? _recordClass;
  String? _recordTeacher;
  DateTimeRange? _recordDates;
  ActualLesson? _source;
  ActualLesson? _swapTarget;
  DateTime? _targetDate;
  SchedulePosition? _targetPosition;
  String? _teacherId;
  String? _subjectId;
  String? _kind;
  final _reason = TextEditingController();
  bool _saving = false;
  final _candidateCache = <String, ActualChangePreview>{};
  String? _candidateBatchKey;
  String? _candidateBatchError;
  bool _candidateBatchComplete = false;
  String? _candidateBatchInFlightKey;
  _QueuedCandidateBatch? _queuedCandidateBatch;
  bool _candidateBatchRunning = false;
  int _candidateBatchGeneration = 0;
  Isolate? _candidateBatchIsolate;
  ReceivePort? _candidateBatchResultPort;
  ReceivePort? _candidateBatchErrorPort;
  Completer<Map<String, ActualChangePreview>?>? _candidateBatchCompleter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancelCandidateBatchWorker();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = await ref
          .read(schoolRepositoryProvider)
          .loadTemporaryTimetable(widget.termId);
      if (!mounted) return;
      final start = state.snapshot.term.firstTeachingWeekStart;
      final currentWeek = state.snapshot.term.teachingWeekOf(DateTime.now());
      setState(() {
        _data = state;
        if (state.reconciliationPending) {
          _source = null;
          _kind = null;
        }
        _candidateCache.clear();
        _candidateBatchKey = null;
        _candidateBatchError = null;
        _candidateBatchComplete = false;
        _queuedCandidateBatch = null;
        _error = null;
        _classId = state.snapshot.classes.any((c) => c.id == _classId)
            ? _classId
            : state.snapshot.classes.firstOrNull?.id;
        _viewTeacherId =
            state.snapshot.teachers.any((t) => t.id == _viewTeacherId)
            ? _viewTeacherId
            : state.snapshot.teachers.firstOrNull?.id;
        if (!_records) {
          _recordClass = _teacherView ? null : _classId;
          _recordTeacher = _teacherView ? _viewTeacherId : null;
        }
        _week ??= currentWeek == null || start == null ? 0 : currentWeek - 1;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '加载调代课失败：$error');
    }
  }

  _TemporaryTimetableIndexes _indexesFor(TemporaryTimetableState state) {
    final current = _timetableIndexes;
    if (current != null && identical(current.state, state)) return current;
    return _timetableIndexes = _TemporaryTimetableIndexes(state);
  }

  void _changeWeek(int week) {
    if (_week == week) return;
    setState(() {
      _week = week;
      _invalidateCandidateBatch();
    });
  }

  void _invalidateCandidateBatch() {
    _cancelCandidateBatchWorker();
    _candidateBatchKey = null;
    _candidateBatchError = null;
    _candidateBatchComplete = false;
    _candidateCache.clear();
    _queuedCandidateBatch = null;
  }

  void _cancelCandidateBatchWorker() {
    _candidateBatchGeneration++;
    _candidateBatchIsolate?.kill(priority: Isolate.immediate);
    _candidateBatchIsolate = null;
    _candidateBatchResultPort?.close();
    _candidateBatchResultPort = null;
    _candidateBatchErrorPort?.close();
    _candidateBatchErrorPort = null;
    final completer = _candidateBatchCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    _candidateBatchCompleter = null;
    _candidateBatchInFlightKey = null;
    _candidateBatchRunning = false;
  }

  // ---------------------------------------------------------------- 基础查询

  String _subject(String id) =>
      _data!.snapshot.subjects.where((s) => s.id == id).firstOrNull?.name ?? id;
  String _teacher(String id) =>
      _data!.snapshot.teachers
          .where((t) => t.id == id)
          .firstOrNull
          ?.displayName ??
      id;
  String _className(String id) =>
      _data!.snapshot.classes.where((c) => c.id == id).firstOrNull?.name ?? id;
  String _kindLabel(String kind) => switch (kind) {
    'move' => '移课',
    'swap' => '换课',
    _ => '代课',
  };

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _md(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  String _dateLabel(DateTime date) => '${date.month}月${date.day}日';
  String _weekdayLabel(DateTime date) =>
      '周${['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}';

  String _slotLabel(SchedulePosition? position) {
    final routine = _data!.snapshot.routines
        .where((r) => r.stageId == position?.stageId)
        .firstOrNull;
    final period = routine?.periodTypes
        .where((p) => p.id == position?.periodTypeId)
        .firstOrNull;
    return '${period?.name ?? ''}第 ${position?.lessonIndex ?? '-'} 节';
  }

  String _subjectTeacher(ActualLesson lesson) =>
      '${_subject(lesson.item.subjectId)}·${_teacher(lesson.item.teacherId)}';

  String _lesson(ActualLesson lesson) =>
      '${_dateLabel(lesson.date)}（${_weekdayLabel(lesson.date)}）'
      '${_slotLabel(lesson.item.position)} '
      '${_subject(lesson.item.subjectId)} ${_teacher(lesson.item.teacherId)}';

  String? _lessonStartTime(SchedulePosition? position) {
    final routine = _data!.snapshot.routines
        .where((r) => r.stageId == position?.stageId)
        .firstOrNull;
    final period = routine?.periodTypes
        .where((p) => p.id == position?.periodTypeId)
        .firstOrNull;
    return period?.lessonTimes
        .where((t) => t.lessonIndex == position?.lessonIndex)
        .firstOrNull
        ?.startLabel;
  }

  CalendarException? _exceptionOn(
    TemporaryTimetableState state,
    DateTime date,
  ) => state.exceptions.where((e) => _date(e.date) == _date(date)).firstOrNull;

  bool _isWeekend(DateTime date) => date.weekday >= DateTime.saturday;

  List<DateTime> _visibleScheduleDates(
    TemporaryTimetableState state,
    DateTime start,
    Iterable<SchedulePosition> positions,
  ) {
    final weekdays = positions.map((position) => position.weekday).toSet();
    final week = List.generate(7, (index) => start.add(Duration(days: index)));
    final visible = week.where((date) {
      final exception = _exceptionOn(state, date);
      final scheduleWeekday = exception?.makeupWeekday ?? date.weekday;
      if (exception?.kind == CalendarExceptionKind.holiday &&
          _isWeekend(date)) {
        return false;
      }
      return exception != null || weekdays.contains(scheduleWeekday);
    }).toList();
    return visible.isEmpty ? week : visible;
  }

  // ---------------------------------------------------------------- 视觉令牌

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _borderStrong =>
      _isDark ? const Color(0x38FFFFFF) : const Color(0x24000000);
  Color get _blueWash =>
      _isDark ? const Color(0xFF1C2D3D) : const Color(0xFFF3F8FE);
  Color get _segBackground =>
      _isDark ? const Color(0xFF262A31) : const Color(0xFFEFEDEB);
  Color get _hintNeutral =>
      _isDark ? const Color(0xFF2A2E35) : const Color(0xFFF4F3F2);
  Color get _amberText =>
      _isDark ? context.appColors.warning : const Color(0xFF8A5A14);
  Color get _blueHintText =>
      _isDark ? context.appColors.inkSecondary : const Color(0xFF1C5A96);
  Color get _switchTrackOff =>
      _isDark ? const Color(0xFF4A4F57) : const Color(0xFFD8D5D2);

  // ---------------------------------------------------------------- 小控件

  Widget _secLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: .2,
      color: context.appColors.muted,
    ),
  );

  Widget _hintBox(Widget child, {String tone = 'neutral'}) {
    final colors = context.appColors;
    final (bg, fg) = switch (tone) {
      'blue' => (colors.selectedBlue, _blueHintText),
      'amber' => (colors.warningSurface, _amberText),
      _ => (_hintNeutral, colors.inkSecondary),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 12, height: 1.55, color: fg),
        child: child,
      ),
    );
  }

  Widget _textButton(
    String label, {
    VoidCallback? onTap,
    Color? color,
    double fontSize = 13,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          color:
              color ??
              (onTap == null
                  ? context.appColors.muted
                  : context.appColors.blue),
        ),
      ),
    ),
  );

  Widget _iconButton(IconData icon, String tooltip, VoidCallback? onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 16,
            color: onTap == null
                ? context.appColors.muted
                : context.appColors.inkSecondary,
          ),
        ),
      );

  Widget _segmentShell(List<Widget> children) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: _segBackground,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );

  Widget _segmentButton(
    String label, {
    required bool active,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active ? _blueWash : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                color: active ? colors.blue : colors.inkSecondary,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing],
          ],
        ),
      ),
    );
  }

  /// 弹出式选择按钮：白底描边小壳 + FPopoverMenu 菜单（30px 行）。
  /// 带搜索的弹出选择控件：Forui FSelect 自带搜索框与限高滚动列表，
  /// 班级 / 教师等长选项列表不会溢出屏幕。
  Widget _selectField({
    required Map<String, String?> items,
    required String? value,
    required ValueChanged<String?> onChanged,
    String? hint,
    String searchHint = '搜索',
    double width = 148,
    bool compact = true,
    bool stretch = false,
  }) {
    final field = AppSelectField<String?>(
      compact: compact,
      items: items,
      value: value,
      hint: hint,
      searchable: true,
      searchHint: searchHint,
      onChanged: onChanged,
    );
    return stretch ? field : SizedBox(width: width, child: field);
  }

  // ---------------------------------------------------------------- 工具栏

  Widget _tabsSegment(TemporaryTimetableState state, {bool showCount = true}) {
    final visibleCount = _filteredRecords(state).length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pageTabButton(
          '实际课表',
          active: !_records,
          onTap: () => setState(() {
            _records = false;
            if (_recordClass != null) _classId = _recordClass;
            if (_recordTeacher != null) {
              _viewTeacherId = _recordTeacher;
              _teacherView = true;
            }
            _recordClass = _teacherView ? null : _classId;
            _recordTeacher = _teacherView ? _viewTeacherId : null;
          }),
        ),
        _pageTabButton(
          '调整记录',
          active: _records,
          onTap: () => setState(() {
            _records = true;
            if (_teacherView) {
              _recordTeacher = _viewTeacherId;
              _recordClass = null;
            } else {
              _recordClass = _classId;
              _recordTeacher = null;
            }
          }),
          trailing: showCount
              ? Text(
                  '$visibleCount 条',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.appColors.inkSecondary,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _pageTabButton(
    String label, {
    required bool active,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? colors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? colors.ink : colors.inkSecondary,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      ),
    );
  }

  Widget _viewSegment() => _segmentShell([
    _segmentButton(
      '班级视图',
      active: !_teacherView,
      onTap: () => setState(() {
        _invalidateCandidateBatch();
        _teacherView = false;
        _recordClass = _classId;
        _recordTeacher = null;
      }),
    ),
    _segmentButton(
      '教师视图',
      active: _teacherView,
      onTap: () => setState(() {
        _invalidateCandidateBatch();
        _teacherView = true;
        _recordClass = null;
        _recordTeacher = _viewTeacherId;
        _source = null;
        _kind = null;
      }),
    ),
  ]);

  Widget _classSelect(TemporaryTimetableState state, {double width = 148}) =>
      _selectField(
        width: width,
        items: {for (final c in state.snapshot.classes) c.name: c.id},
        value: _classId,
        hint: '选择班级',
        searchHint: '搜索班级',
        onChanged: (value) => setState(() {
          _invalidateCandidateBatch();
          _classId = value;
          _recordClass = value;
          _source = null;
          _kind = null;
        }),
      );

  Widget _teacherSelect(TemporaryTimetableState state, {double width = 148}) =>
      _selectField(
        width: width,
        items: {
          for (final teacher in state.snapshot.teachers)
            teacher.displayName: teacher.id,
        },
        value: _viewTeacherId,
        hint: '选择教师',
        searchHint: '搜索教师',
        onChanged: (value) => setState(() {
          _viewTeacherId = value;
          _recordTeacher = value;
        }),
      );

  Widget _weekNav(
    TemporaryTimetableState state,
    DateTime start, {
    bool compact = false,
  }) {
    final colors = context.appColors;
    final week = _week ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconButton(
          Icons.chevron_left,
          '上一周',
          week > 0 ? () => _changeWeek(week - 1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                compact
                    ? '第${week + 1}教学周'
                    : '第${week + 1}教学周 · ${state.snapshot.term.weekCycleLabel(week + 1)}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: colors.ink,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_md(start)}–${_md(start.add(const Duration(days: 6)))}',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
            ],
          ),
        ),
        _iconButton(
          Icons.chevron_right,
          '下一周',
          week + 1 < state.snapshot.term.teachingWeekCount
              ? () => _changeWeek(week + 1)
              : null,
        ),
        _textButton(
          '本周',
          onTap: () => _changeWeek(
            (state.snapshot.term.teachingWeekOf(DateTime.now()) ?? 1) - 1,
          ),
        ),
      ],
    );
  }

  Widget _exportMenuButton() {
    final colors = context.appColors;
    final shell = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('导出', style: TextStyle(fontSize: 13, color: colors.ink)),
          const SizedBox(width: 5),
          Icon(Icons.expand_more, size: 14, color: colors.muted),
        ],
      ),
    );
    return FPopoverMenu(
      menuBuilder: (context, controller, menu) => [
        FItemGroup(
          divider: .none,
          children: [
            for (final kind in TemporaryExportKind.values)
              AppMenuTile(
                item: AppMenuItem(
                  label: switch (kind) {
                    TemporaryExportKind.teacher => '教师通知',
                    TemporaryExportKind.schoolClass => '班级通知',
                    TemporaryExportKind.details => '调整明细',
                  },
                  onPressed: () {
                    unawaited(controller.hide());
                    unawaited(_export(kind));
                  },
                ),
              ),
          ],
        ),
      ],
      builder: (context, controller, child) => FTappable(
        semanticsLabel: '导出',
        onPress: () => unawaited(controller.toggle()),
        child: child!,
      ),
      child: shell,
    );
  }

  Widget _showCancelledToggle() {
    final colors = context.appColors;
    final on = _showCancelled;
    return InkWell(
      onTap: () => setState(() => _showCancelled = !on),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? colors.selectedBlue : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? colors.blue.withValues(alpha: .35) : _borderStrong,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 12,
              decoration: BoxDecoration(
                color: on ? colors.blue : _switchTrackOff,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 150),
                    left: on ? 11 : 2,
                    top: 1.5,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '显示已取消',
              style: TextStyle(
                fontSize: 12.5,
                color: on ? colors.blue : colors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleToolbar(TemporaryTimetableState state, DateTime start) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        final scopeControls = [
          _viewSegment(),
          _teacherView
              ? _teacherSelect(state, width: wide ? 148 : 132)
              : _classSelect(state, width: wide ? 148 : 132),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 38,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.appColors.border),
                ),
              ),
              child: Row(
                children: [
                  _tabsSegment(state),
                  const Spacer(),
                  if (wide) ...[
                    _weekNav(state, start),
                    const SizedBox(width: 10),
                  ],
                  _exportMenuButton(),
                ],
              ),
            ),
            if (!wide) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _weekNav(
                  state,
                  start,
                  compact: constraints.maxWidth < 560,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: scopeControls,
            ),
          ],
        );
      },
    );
  }

  Widget _recordsToolbar(TemporaryTimetableState state) {
    final colors = context.appColors;
    final filters = [
      _selectField(
        width: 112,
        hint: '全部类型',
        searchHint: '搜索类型',
        items: const {
          '全部类型': null,
          '换课': 'swap',
          '移课': 'move',
          '代课': 'substitute',
        },
        value: _recordType,
        onChanged: (value) => setState(() => _recordType = value),
      ),
      _selectField(
        width: 112,
        hint: '全部状态',
        searchHint: '搜索状态',
        items: const {
          '全部状态': null,
          '有效': 'active',
          '需处理': 'invalid',
          '已取消': 'cancelled',
        },
        value: _recordStatus,
        onChanged: (value) => setState(() => _recordStatus = value),
      ),
      _selectField(
        width: 132,
        hint: '全部班级',
        searchHint: '搜索班级',
        items: {
          '全部班级': null,
          for (final c in state.snapshot.classes) c.name: c.id,
        },
        value: _recordClass,
        onChanged: (value) => setState(() => _recordClass = value),
      ),
      _selectField(
        width: 132,
        hint: '全部教师',
        searchHint: '搜索教师',
        items: {
          '全部教师': null,
          for (final teacher in state.snapshot.teachers)
            teacher.displayName: teacher.id,
        },
        value: _recordTeacher,
        onChanged: (value) => setState(() => _recordTeacher = value),
      ),
      InkWell(
        onTap: _selectRecordDates,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            // 与 compact 筛选器一致的浅灰底无边框样式。
            color: colors.tableHeader,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _recordDates == null
                    ? '全部日期'
                    : '${_date(_recordDates!.start)} 至 ${_date(_recordDates!.end)}',
                style: TextStyle(fontSize: 12.5, color: colors.inkSecondary),
              ),
            ],
          ),
        ),
      ),
      if (_recordDates != null)
        _textButton(
          '清除日期',
          onTap: () => setState(() => _recordDates = null),
          fontSize: 12.5,
        ),
      _showCancelledToggle(),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1050;
        final filterRow = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: filters,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 38,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.appColors.border),
                ),
              ),
              child: wide
                  ? Row(
                      children: [
                        _tabsSegment(state),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: filterRow,
                          ),
                        ),
                      ],
                    )
                  : _tabsSegment(state),
            ),
            if (!wide) ...[const SizedBox(height: 10), filterRow],
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- 页面骨架

  @override
  Widget build(BuildContext context) {
    final state = _data;
    if (_error != null && state == null) return Center(child: Text(_error!));
    if (state == null) return const Center(child: CircularProgressIndicator());
    if (state.snapshot.term.firstTeachingWeekStart == null) {
      return const Center(child: Text('请先在学期与日历中设置第 1 教学周起始日期。'));
    }
    if (state.snapshot.classes.isEmpty) {
      return const Center(child: Text('请先添加班级。'));
    }
    final start = state.snapshot.term.firstTeachingWeekStart!.add(
      Duration(days: (_week ?? 0) * 7),
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _records ? _recordsToolbar(state) : _scheduleToolbar(state, start),
          if (state.reconciliationPending) ...[
            const SizedBox(height: 10),
            _hintBox(const Text('课表待协调，完成协调后才能进行临时调整。'), tone: 'amber'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: _records
                ? _recordList(state)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 1040) {
                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              if (_source != null) ...[
                                SizedBox(
                                  height: 500,
                                  width: double.infinity,
                                  child: _panel(state),
                                ),
                                const SizedBox(height: 14),
                              ],
                              _teacherView
                                  ? _teacherGrid(state, start)
                                  : _grid(state, start),
                              _gridFootNote(),
                            ],
                          ),
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child: _teacherView
                                      ? _teacherGrid(state, start)
                                      : _grid(state, start),
                                ),
                                _gridFootNote(),
                              ],
                            ),
                          ),
                          if (_source != null) ...[
                            const SizedBox(width: 16),
                            SizedBox(width: 336, child: _panel(state)),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _gridFootNote() {
    final message = _teacherView
        ? '教师视图用于核对占用；请在班级视图选择课次发起调整。'
        : switch (_kind) {
            'swap' when _source != null => '在课表中选择另一节课程作为互换目标。',
            'move' => '在课表中选择一个空课位；原课位会空出来。',
            'substitute' => '选择代课教师后，可预览本次变更。',
            _ => '选择一节课开始调整；已生效的变更会标记在课格中。',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: context.appColors.inkSecondary),
      ),
    );
  }

  // ---------------------------------------------------------------- 周课表

  Widget _dayHeading(TemporaryTimetableState state, DateTime date) {
    final colors = context.appColors;
    final today = DateUtils.isSameDay(date, DateTime.now());
    final exception = _exceptionOn(state, date);
    final note = switch (exception?.kind) {
      CalendarExceptionKind.holiday =>
        exception!.note.isNotEmpty ? exception.note : '休息日',
      CalendarExceptionKind.makeup =>
        '补 · 按周${['一', '二', '三', '四', '五', '六', '日'][exception!.makeupWeekday! - 1]}作息',
      _ => null,
    };
    final noteColor = exception?.kind == CalendarExceptionKind.makeup
        ? colors.warning
        : colors.muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _weekdayLabel(date),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: today ? colors.blue : colors.ink,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _md(date),
                style: TextStyle(
                  fontSize: 12,
                  color: today ? colors.blue : colors.inkSecondary,
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                note,
                style: TextStyle(fontSize: 11, color: noteColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _periodHead(String periodName, int index, SchedulePosition? position) {
    final colors = context.appColors;
    final time = _lessonStartTime(position);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$periodName 第 $index 节',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: colors.inkSecondary,
            ),
          ),
          if (time != null)
            Text(time, style: TextStyle(fontSize: 11, color: colors.muted)),
        ],
      ),
    );
  }

  Widget _typePill(String kind) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _blueWash,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _kindLabel(kind),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: colors.blue,
        ),
      ),
    );
  }

  Widget _grid(TemporaryTimetableState state, DateTime start) {
    final colors = context.appColors;
    final classId = _classId!;
    final stage = state.snapshot.stageIdForClass(classId);
    final routine = state.snapshot.routines
        .where((r) => r.stageId == stage)
        .firstOrNull;
    if (routine == null) return const Center(child: Text('请先设置该班级的作息。'));
    final indexes = _indexesFor(state);
    final positions = indexes.positionsByClass[classId] ?? const [];
    final days = _visibleScheduleDates(state, start, positions);
    final periods = [...routine.periodTypes]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final rows = <(String, int, String, SchedulePosition?)>[];
    for (final period in periods) {
      final count = positions
          .where((p) => p.periodTypeId == period.id)
          .fold<int>(0, (n, p) => p.lessonIndex > n ? p.lessonIndex : n);
      for (var i = 1; i <= count; i++) {
        final position = positions
            .where((p) => p.periodTypeId == period.id && p.lessonIndex == i)
            .firstOrNull;
        rows.add((period.id, i, period.name, position));
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth > 76.0 + days.length * 132.0
              ? constraints.maxWidth
              : 76.0 + days.length * 132.0,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 76),
                    for (final date in days)
                      Expanded(
                        child: Container(
                          color: _isWeekend(date) ? colors.tableHeader : null,
                          child: _dayHeading(state, date),
                        ),
                      ),
                  ],
                ),
                for (final row in rows)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 76,
                        height: 75,
                        child: _periodHead(row.$3, row.$2, row.$4),
                      ),
                      for (final date in days)
                        Expanded(
                          child: Container(
                            color: _isWeekend(date) ? colors.tableHeader : null,
                            child: _cell(state, date, row.$1, row.$2, indexes),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _teacherGrid(TemporaryTimetableState state, DateTime start) {
    final colors = context.appColors;
    if (_viewTeacherId == null) return const Center(child: Text('暂无教师'));
    final indexes = _indexesFor(state);
    String timeLabel(int minute) =>
        '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
    final classIds = {
      for (final assignment in state.snapshot.assignments)
        if (assignment.teacherId == _viewTeacherId) assignment.classId,
      ...indexes.classesForTeacher(_viewTeacherId!),
    };
    final days = _visibleScheduleDates(
      state,
      start,
      classIds.expand(
        (classId) =>
            indexes.positionsByClass[classId] ?? const <SchedulePosition>[],
      ),
    );
    final slots = <String, ({String label, int sort})>{};
    for (final classId in classIds) {
      for (final position
          in indexes.positionsByClass[classId] ?? const <SchedulePosition>[]) {
        final routine = state.snapshot.routines
            .where((r) => r.stageId == position.stageId)
            .firstOrNull;
        final period = routine?.periodTypes
            .where((p) => p.id == position.periodTypeId)
            .firstOrNull;
        final stage = state.snapshot.stages
            .where((s) => s.id == position.stageId)
            .firstOrNull;
        slots.putIfAbsent(
          _teacherGridSlotKey(position),
          () => (
            label: position.hasClockTime
                ? '${timeLabel(position.startMinute!)}\n${timeLabel(position.endMinute!)}'
                : '${stage?.name ?? ''} ${period?.name ?? ''}\n第 ${position.lessonIndex} 节',
            sort:
                position.startMinute ??
                10000 +
                    (stage?.sortOrder ?? 0) * 1000 +
                    (period?.sortOrder ?? 0) * 100 +
                    position.lessonIndex,
          ),
        );
      }
    }
    final ordered = slots.entries.toList()
      ..sort((a, b) => a.value.sort.compareTo(b.value.sort));
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth > 76.0 + days.length * 132.0
              ? constraints.maxWidth
              : 76.0 + days.length * 132.0,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 76),
                    for (final date in days)
                      Expanded(
                        child: Container(
                          color: _isWeekend(date) ? colors.tableHeader : null,
                          child: _dayHeading(state, date),
                        ),
                      ),
                  ],
                ),
                for (final slot in ordered)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 76,
                        height: 75,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 6, 10, 4),
                          child: Text(
                            slot.value.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              color: colors.inkSecondary,
                            ),
                          ),
                        ),
                      ),
                      for (final date in days)
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final courses = indexes.teacherLessons(
                                _viewTeacherId!,
                                date,
                                slot.key,
                              );
                              final changed = indexes
                                  .recordForLessons(courses)
                                  ?.record;
                              return Container(
                                color: _isWeekend(date)
                                    ? colors.tableHeader
                                    : null,
                                child: Container(
                                  height: 75,
                                  margin: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: _slotBackground(
                                      filled: courses.isNotEmpty,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: courses.isEmpty
                                          ? _isDark
                                                ? const Color(0x1FFFFFFF)
                                                : const Color(0x1A000000)
                                          : colors.border,
                                    ),
                                  ),
                                  child: courses.isEmpty
                                      ? null
                                      : InkWell(
                                          onTap: state.reconciliationPending
                                              ? null
                                              : () => setState(() {
                                                  _invalidateCandidateBatch();
                                                  _classId = courses
                                                      .first
                                                      .item
                                                      .classId;
                                                  _recordClass = _classId;
                                                  _recordTeacher = null;
                                                  _teacherView = false;
                                                  _source = courses.first;
                                                  _kind = 'swap';
                                                }),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Stack(
                                              children: [
                                                Padding(
                                                  padding: changed != null
                                                      ? const EdgeInsets.only(
                                                          right: 34,
                                                        )
                                                      : EdgeInsets.zero,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        _subject(
                                                          courses
                                                              .first
                                                              .item
                                                              .subjectId,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: colors.ink,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        courses
                                                            .map(
                                                              (
                                                                lesson,
                                                              ) => _className(
                                                                lesson
                                                                    .item
                                                                    .classId,
                                                              ),
                                                            )
                                                            .join('、'),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: colors
                                                              .inkSecondary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (changed != null)
                                                  Positioned(
                                                    top: 5,
                                                    right: 6,
                                                    child: _typePill(
                                                      changed.kind,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _slotBackground({required bool filled, bool candidate = false}) {
    if (candidate) {
      return _isDark ? const Color(0xFF20384F) : const Color(0xFFF0F7FF);
    }
    return filled ? Theme.of(context).colorScheme.surface : Colors.transparent;
  }

  Widget _cell(
    TemporaryTimetableState state,
    DateTime date,
    String periodId,
    int index,
    _TemporaryTimetableIndexes indexes,
  ) {
    final colors = context.appColors;
    final exception = _exceptionOn(state, date);
    final weekday = exception?.makeupWeekday ?? date.weekday;
    final classId = _classId!;
    final position = indexes.position(classId, weekday, periodId, index);
    final available =
        exception?.kind != CalendarExceptionKind.holiday && position != null;
    final course = indexes.classLesson(classId, date, periodId, index);
    final record = course == null
        ? null
        : indexes.recordForLesson(course.key)?.record;
    final selecting = _source != null && (_kind == 'move' || _kind == 'swap');
    final eligible =
        selecting &&
        available &&
        ((_kind == 'move' && course == null) ||
            (_kind == 'swap' && course != null && course.key != _source!.key));
    ActualChangePreview? candidate;
    if (eligible) {
      final key = _candidateKey(
        _source!.key,
        _kind!,
        date,
        periodId,
        index,
        course?.key,
      );
      if (state.lessons.length > 2000) {
        _queueCandidateBatch(
          state,
          indexes.positionsByClass[classId] ?? const [],
        );
        candidate = _candidateCache[key];
      } else {
        candidate = _candidateCache.putIfAbsent(
          key,
          () => _kind == 'move'
              ? state.previewMove(
                  TemporaryMoveRequest(
                    sourceKey: _source!.key,
                    targetDate: date,
                    targetPosition: position,
                  ),
                  problem: indexes.problem,
                )
              : state.previewSwap(
                  TemporarySwapRequest(
                    firstKey: _source!.key,
                    secondKey: course!.key,
                  ),
                  problem: indexes.problem,
                ),
        );
      }
    }
    final batchError = state.lessons.length > 2000
        ? _candidateBatchError ??
              (_candidateBatchComplete && eligible && candidate == null
                  ? '未找到对应课位，请重新选择调整方式'
                  : null)
        : null;
    final waiting = eligible && candidate == null && batchError == null;
    final invalid =
        eligible &&
        (batchError != null ||
            (candidate != null && candidate.errors.isNotEmpty));
    final hint = batchError != null
        ? '候选检测失败：$batchError'
        : invalid
        ? candidate!.errors.join('；')
        : waiting
        ? '正在检测'
        : eligible
        ? '可选'
        : selecting
        ? '不可选'
        : '';
    final isChosenTarget =
        course != null && course.key == _swapTarget?.key ||
        (_targetDate != null &&
            DateUtils.isSameDay(_targetDate, date) &&
            _targetPosition?.periodTypeId == periodId &&
            _targetPosition?.lessonIndex == index);
    final isSource = course != null && course.key == _source?.key;
    final makeupDay = exception?.kind == CalendarExceptionKind.makeup;

    // 底色与描边
    Color bg() {
      if (!available) return Colors.transparent;
      if (isChosenTarget) return colors.selectedBlue;
      if (invalid) return colors.tableHeader;
      if (makeupDay) return _blueWash;
      return _slotBackground(filled: course != null, candidate: eligible);
    }

    Widget body;
    if (!available) {
      body = Center(
        child: Text('—', style: TextStyle(fontSize: 12, color: colors.muted)),
      );
    } else if (course == null) {
      final text = eligible
          ? (waiting
                ? '检测中'
                : invalid
                ? '不可选'
                : '可选')
          : '空课位';
      final color = invalid
          ? colors.warning
          : eligible
          ? colors.blue
          : colors.muted;
      body = Center(
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color)),
      );
    } else {
      final stateText = selecting && eligible
          ? (waiting
                ? '检测中'
                : invalid
                ? '不可选'
                : '可选')
          : null;
      // 课格内容直接作为容器子节点（容器已有 8px 内边距），
      // 再包一层会挤压三行文字的可用高度导致溢出。
      body = Stack(
        children: [
          Padding(
            padding: record != null && !selecting
                ? const EdgeInsets.only(right: 34)
                : EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _subject(course.item.subjectId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _teacher(course.item.teacherId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.inkSecondary),
                ),
                if (stateText != null)
                  Text(
                    stateText,
                    style: TextStyle(
                      fontSize: 11,
                      color: invalid
                          ? colors.warning
                          : waiting
                          ? colors.muted
                          : colors.blue,
                    ),
                  ),
              ],
            ),
          ),
          if (record != null && !selecting)
            Positioned(top: 5, right: 6, child: _typePill(record.kind)),
        ],
      );
    }

    final highlight = isSource || isChosenTarget;
    final dashed = course == null && available;
    Widget decorated;
    if (dashed) {
      decorated = Container(
        height: 75,
        margin: const EdgeInsets.all(3),
        child: CustomPaint(
          foregroundPainter: _DashBorderPainter(
            color: eligible
                ? (invalid
                      ? colors.warning
                      : colors.blue.withValues(alpha: .45))
                : _isDark
                ? const Color(0x1FFFFFFF)
                : const Color(0x1A000000),
            radius: 8,
          ),
          child: Container(
            height: 75,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bg(),
              borderRadius: BorderRadius.circular(8),
            ),
            child: body,
          ),
        ),
      );
    } else {
      decorated = Container(
        height: 75,
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bg(),
          borderRadius: BorderRadius.circular(8),
          border: highlight ? Border.all(color: colors.blue, width: 1.5) : null,
        ),
        child: body,
      );
    }
    Widget cell = Tooltip(
      message: hint,
      child: InkWell(
        key: ValueKey('temporary-cell-${_date(date)}-$periodId-$index'),
        onTap:
            !state.reconciliationPending &&
                available &&
                !invalid &&
                !waiting &&
                (!selecting || eligible)
            ? () => setState(() {
                if (_source != null && _kind == 'move' && course == null) {
                  _targetDate = date;
                  _targetPosition = position;
                } else if (_source != null &&
                    _kind == 'swap' &&
                    course != null &&
                    course.key != _source!.key) {
                  _swapTarget = course;
                } else if (course != null) {
                  _invalidateCandidateBatch();
                  _source = course;
                  _kind = 'swap';
                  _targetDate = null;
                  _targetPosition = null;
                  _swapTarget = null;
                  _teacherId = null;
                  _subjectId = null;
                }
              })
            : null,
        child: decorated,
      ),
    );
    if (selecting && !eligible && !isSource) {
      cell = Opacity(opacity: .45, child: cell);
    }
    final draggable = course == null || state.reconciliationPending || selecting
        ? cell
        : Draggable<ActualLesson>(
            data: course,
            feedback: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: colors.surface,
              // 拖拽提示靠近视口边缘时会被压紧约束，用 OverflowBox 按自然尺寸绘制。
              child: OverflowBox(
                minWidth: 0,
                maxWidth: 220,
                minHeight: 0,
                maxHeight: double.infinity,
                alignment: Alignment.topLeft,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _subject(course.item.subjectId),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.ink,
                        ),
                      ),
                      Text(
                        _teacher(course.item.teacherId),
                        style: TextStyle(fontSize: 11, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child: cell,
          );
    return DragTarget<ActualLesson>(
      onWillAcceptWithDetails: (details) =>
          !state.reconciliationPending &&
          available &&
          details.data.item.classId == _classId &&
          details.data.key != course?.key,
      onAcceptWithDetails: (details) {
        setState(() {
          _invalidateCandidateBatch();
          _source = details.data;
          _kind = course == null ? 'move' : 'swap';
          _targetDate = course == null ? date : null;
          _targetPosition = course == null ? position : null;
          _swapTarget = course;
          _teacherId = null;
          _subjectId = null;
          _error = null;
        });
      },
      builder: (context, candidates, rejected) => draggable,
    );
  }

  void _queueCandidateBatch(
    TemporaryTimetableState state,
    List<SchedulePosition> positions,
  ) {
    final sourceKey = _source!.key;
    final kind = _kind!;
    final classId = _classId!;
    final weekIndex = _week ?? 0;
    final batchKey = '$sourceKey:$kind:$classId:$weekIndex';
    if (_candidateBatchKey == batchKey) return;
    _cancelCandidateBatchWorker();
    _candidateBatchKey = batchKey;
    _candidateBatchError = null;
    _candidateBatchComplete = false;
    _candidateCache.clear();
    if (_candidateBatchInFlightKey == batchKey) {
      _queuedCandidateBatch = null;
      return;
    }
    final start = state.snapshot.term.firstTeachingWeekStart!.add(
      Duration(days: weekIndex * 7),
    );
    _queuedCandidateBatch = (
      key: batchKey,
      input: (
        state: state,
        positions: positions,
        sourceKey: sourceKey,
        kind: kind,
        classId: classId,
        start: start,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_runNextCandidateBatch());
    });
  }

  Future<void> _runNextCandidateBatch() async {
    if (!mounted || _candidateBatchRunning) return;
    final queued = _queuedCandidateBatch;
    if (queued == null) return;
    _queuedCandidateBatch = null;
    if (_candidateBatchKey != queued.key) return;

    final generation = _candidateBatchGeneration;
    _candidateBatchRunning = true;
    _candidateBatchInFlightKey = queued.key;
    try {
      final result = await _runCandidateBatchIsolate(queued.input, generation);
      if (result != null &&
          mounted &&
          generation == _candidateBatchGeneration &&
          _candidateBatchKey == queued.key) {
        setState(() {
          _candidateCache.addAll(result);
          _candidateBatchComplete = true;
        });
      }
    } on Object catch (error) {
      if (mounted &&
          generation == _candidateBatchGeneration &&
          _candidateBatchKey == queued.key) {
        setState(() {
          _candidateBatchError = '$error';
          _error = '候选课位检测失败，请重新选择调整方式：$error';
        });
      }
    } finally {
      if (generation == _candidateBatchGeneration) {
        _candidateBatchRunning = false;
        _candidateBatchInFlightKey = null;
      }
      if (mounted &&
          generation == _candidateBatchGeneration &&
          _queuedCandidateBatch != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_runNextCandidateBatch());
        });
      }
    }
  }

  Future<Map<String, ActualChangePreview>?> _runCandidateBatchIsolate(
    _CandidateBatch input,
    int generation,
  ) async {
    final resultPort = ReceivePort();
    final errorPort = ReceivePort();
    final completer = Completer<Map<String, ActualChangePreview>?>();
    _candidateBatchResultPort = resultPort;
    _candidateBatchErrorPort = errorPort;
    _candidateBatchCompleter = completer;
    resultPort.listen((message) {
      if (generation != _candidateBatchGeneration || completer.isCompleted) {
        return;
      }
      if (message is Map<String, ActualChangePreview>) {
        completer.complete(message);
      } else if (message is _CandidateBatchWorkerError) {
        completer.completeError(
          StateError('${message.message}\n${message.stackTrace}'),
        );
      } else {
        completer.completeError(StateError('候选课位检测返回了无法识别的结果。'));
      }
    });
    errorPort.listen((message) {
      if (generation != _candidateBatchGeneration || completer.isCompleted) {
        return;
      }
      completer.completeError(StateError('候选课位检测 isolate 异常：$message'));
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<_CandidateBatchMessage>(
        _candidateBatchWorker,
        (input: input, replyTo: resultPort.sendPort),
        onError: errorPort.sendPort,
      );
      if (generation != _candidateBatchGeneration || !mounted) {
        isolate.kill(priority: Isolate.immediate);
        if (!completer.isCompleted) completer.complete(null);
      } else {
        _candidateBatchIsolate = isolate;
      }
      return await completer.future;
    } finally {
      resultPort.close();
      errorPort.close();
      if (identical(_candidateBatchResultPort, resultPort)) {
        _candidateBatchResultPort = null;
      }
      if (identical(_candidateBatchErrorPort, errorPort)) {
        _candidateBatchErrorPort = null;
      }
      if (identical(_candidateBatchCompleter, completer)) {
        _candidateBatchCompleter = null;
      }
      if (identical(_candidateBatchIsolate, isolate)) {
        _candidateBatchIsolate = null;
      }
    }
  }

  // ---------------------------------------------------------------- 面板

  bool get _panelReady {
    if (_kind == null || _saving) return false;
    if (_kind == 'substitute') return _teacherId != null;
    if (_kind == 'move') return _targetDate != null && _targetPosition != null;
    return _swapTarget != null;
  }

  Widget _radioIndicator(bool selected) {
    final colors = context.appColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colors.blue : _borderStrong,
          width: 1.5,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }

  Widget _courseCard({
    required String line1,
    String? line2,
    Widget? extra,
    bool plain = false,
  }) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: plain ? _hintNeutral : colors.selectedBlue,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line1,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: colors.ink,
            ),
          ),
          if (line2 != null) ...[
            const SizedBox(height: 2),
            Text(
              line2,
              style: TextStyle(fontSize: 12, color: colors.inkSecondary),
            ),
          ],
          if (extra != null) ...[const SizedBox(height: 3), extra],
        ],
      ),
    );
  }

  void _setAdjustmentKind(String value) {
    if (_kind == value) return;
    setState(() {
      _kind = value;
      _invalidateCandidateBatch();
      _error = null;
      _targetDate = null;
      _targetPosition = null;
      _swapTarget = null;
    });
  }

  Widget _adjustmentModeSelector() {
    final colors = context.appColors;
    Widget option(String value, String label) {
      final selected = _kind == value;
      return Expanded(
        child: InkWell(
          onTap: () => _setAdjustmentKind(value),
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? _blueWash : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? colors.blue : colors.inkSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _segBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          option('swap', '换课'),
          option('move', '移课'),
          option('substitute', '代课'),
        ],
      ),
    );
  }

  String get _adjustmentModeDescription => switch (_kind) {
    'move' => '移到本班空课位，原位置变为空位。',
    'substitute' => '更换任课教师，时间和班级保持不变。',
    _ => '与本班另一实际课次互换时间，可跨日期、跨周。',
  };

  Widget _panel(TemporaryTimetableState state) {
    final colors = context.appColors;
    final source = _source!;
    final group = source.item.meetingId == null
        ? [source]
        : state.lessons
              .where(
                (lesson) =>
                    lesson.item.meetingId == source.item.meetingId &&
                    lesson.date == source.date,
              )
              .toList();
    final classIds = group.map((lesson) => lesson.item.classId).toSet();
    final teacherIds = group.map((lesson) => lesson.item.teacherId).toSet();
    final locks = state.snapshot.locks
        .where(
          (lock) =>
              (lock.scope == ScheduleLockScope.schoolClass &&
                  classIds.contains(lock.targetId)) ||
              (lock.scope == ScheduleLockScope.teacher &&
                  teacherIds.contains(lock.targetId)),
        )
        .toList();
    final previous = state.records.reversed
        .where(
          (record) =>
              record.cancelledAt == null &&
              !record.needsAttention &&
              record.changes.any((change) => change.after.key == source.key),
        )
        .firstOrNull;

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _secLabel('已选课次'),
            const SizedBox(height: 7),
            _courseCard(
              line1:
                  '${_subject(source.item.subjectId)} · ${_dateLabel(source.date)}（${_weekdayLabel(source.date)}）',
              line2:
                  '${_slotLabel(source.item.position)} · ${_teacher(source.item.teacherId)} · ${_className(source.item.classId)}'
                  '${classIds.length > 1 ? ' 等 ${classIds.length} 个班' : ''}',
            ),
          ],
        ),
        if (locks.isNotEmpty)
          _hintBox(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '课表已锁定：${locks.map((lock) => lock.scope == ScheduleLockScope.teacher ? '教师 ${_teacher(lock.targetId)}' : '班级 ${_className(lock.targetId)}').join('、')}。',
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: _amberText,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () =>
                      ref.read(selectedSectionProvider.notifier).state =
                          AppSection.scheduling,
                  child: const Text('前往课表解锁'),
                ),
              ],
            ),
            tone: 'amber',
          ),
        if (previous != null)
          _hintBox(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '此课格已按调整生效，常规周课表不受影响。调整前：'
                  '${_lesson(previous.changes.firstWhere((change) => change.after.key == source.key).before)}。',
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: _blueHintText,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => setState(() {
                    _records = true;
                    _recordClass = source.item.classId;
                  }),
                  child: const Text('查看关联记录'),
                ),
              ],
            ),
            tone: 'blue',
          ),
        const SizedBox(height: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _secLabel('调整方式'),
            const SizedBox(height: 7),
            _adjustmentModeSelector(),
            const SizedBox(height: 6),
            Text(
              _adjustmentModeDescription,
              style: TextStyle(fontSize: 12, color: colors.inkSecondary),
            ),
          ],
        ),
        if (_kind == 'swap')
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              _secLabel('目标课次'),
              const SizedBox(height: 7),
              _swapTarget != null
                  ? _courseCard(
                      plain: true,
                      line1:
                          '${_subject(_swapTarget!.item.subjectId)} · ${_dateLabel(_swapTarget!.date)}（${_weekdayLabel(_swapTarget!.date)}）',
                      line2:
                          '${_slotLabel(_swapTarget!.item.position)} · ${_teacher(_swapTarget!.item.teacherId)} · ${_className(_swapTarget!.item.classId)}',
                      extra: Text(
                        '⇅ 与已选课次互换',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.blue,
                        ),
                      ),
                    )
                  : _hintBox(
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: '在周课表中'),
                            TextSpan(
                              text: '选择另一节课程',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: colors.ink,
                              ),
                            ),
                            const TextSpan(text: '作为互换目标，可跨日期、跨周。'),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        if (_kind == 'move')
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              _secLabel('目标空课位'),
              const SizedBox(height: 7),
              _targetDate != null && _targetPosition != null
                  ? _courseCard(
                      plain: true,
                      line1:
                          '${_dateLabel(_targetDate!)}（${_weekdayLabel(_targetDate!)}）'
                          '${_slotLabel(_targetPosition)}',
                      line2:
                          '空课位 · ${_subject(source.item.subjectId)} 将移入，原位置变为空位',
                    )
                  : _hintBox(
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: '在周课表中'),
                            TextSpan(
                              text: '选择一个空课位',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: colors.ink,
                              ),
                            ),
                            const TextSpan(text: '作为目标，原位置会空出来。'),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        if (_kind == 'substitute')
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              _secLabel('代课教师'),
              const SizedBox(height: 7),
              _teacherId != null
                  ? _courseCard(
                      plain: true,
                      line1: _teacher(_teacherId!),
                      line2:
                          '${_subject(_subjectId ?? source.item.subjectId)} · 该时段空闲 · ${_className(source.item.classId)}',
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: AppOutlineButton(
                        onPressed: _saving ? null : _chooseTeacher,
                        child: const Text('选择代课教师'),
                      ),
                    ),
              const SizedBox(height: 7),
              AppSelectField<String?>(
                items: {
                  '保留原科目': null,
                  for (final s in state.snapshot.subjects) s.name: s.id,
                },
                value: _subjectId,
                hint: '保留原科目（可更改）',
                searchable: true,
                searchHint: '搜索科目',
                onChanged: (value) => setState(() => _subjectId = value),
              ),
            ],
          ),
        const SizedBox(height: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _secLabel('原因（选填，会记录在调整记录中）'),
            const SizedBox(height: 7),
            AppTextFormField(
              controller: _reason,
              decoration: const InputDecoration(hintText: '如：教研活动、外出培训、场地占用'),
            ),
          ],
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '调整课次',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.close,
                  tooltip: '关闭',
                  iconSize: 15,
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _invalidateCandidateBatch();
                          _source = null;
                        }),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: body,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                AppGhostButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _invalidateCandidateBatch();
                          _source = null;
                        }),
                  child: const Text('取消'),
                ),
                const Spacer(),
                AppPrimaryButton(
                  onPressed: _panelReady ? _openPreview : null,
                  child: Text(_saving ? '正在处理…' : '下一步 · 预览'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 弹窗部件

  Widget _dialogHeader(
    String title, {
    String? sub,
    required VoidCallback onClose,
  }) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 23 / 16,
                    color: colors.ink,
                  ),
                ),
              ),
              AppIconButton(
                icon: Icons.close,
                tooltip: '关闭',
                iconSize: 15,
                onPressed: onClose,
              ),
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(
              sub,
              style: TextStyle(fontSize: 12.5, color: colors.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scopeRadio({
    required String title,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? _blueWash : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _radioIndicator(selected),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: colors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopeBlock({
    required TemporaryTimetableState state,
    required ActualLesson source,
    required bool range,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required ValueChanged<bool> onScopeChanged,
    required void Function(DateTime start, DateTime end) onDatesChanged,
  }) {
    final colors = context.appColors;
    final term = state.snapshot.term;
    final firstDate = term.firstTeachingWeekStart!;
    final lastDate = term.teachingWeekEnd(term.teachingWeekCount) ?? firstDate;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _scopeRadio(
            title: '仅本次',
            desc:
                '仅 ${_dateLabel(source.date)}（${_weekdayLabel(source.date)}）'
                '${_slotLabel(source.item.position)} 这一次课',
            selected: !range,
            onTap: () {
              if (range) onScopeChanged(false);
            },
          ),
          Divider(height: 1, color: colors.border),
          _scopeRadio(
            title: '日期范围',
            desc: '按选定星期与节次逐周展开，换课保留源与目标的日期间隔',
            selected: range,
            onTap: () {
              if (!range) onScopeChanged(true);
            },
          ),
          if (range)
            Container(
              color: _blueWash,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '开始日期',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.inkSecondary,
                        ),
                      ),
                      SizedBox(
                        width: 132,
                        child: AppDateField(
                          value: rangeStart,
                          onChanged: (value) {
                            if (value != null) {
                              onDatesChanged(value, rangeEnd);
                            }
                          },
                          firstDate: firstDate,
                          lastDate: lastDate,
                          hint: '请选择日期',
                          format: _dateLabel,
                        ),
                      ),
                      Text(
                        '至',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.inkSecondary,
                        ),
                      ),
                      Text(
                        '结束日期',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.inkSecondary,
                        ),
                      ),
                      SizedBox(
                        width: 132,
                        child: AppDateField(
                          value: rangeEnd,
                          onChanged: (value) {
                            if (value != null) {
                              onDatesChanged(rangeStart, value);
                            }
                          },
                          firstDate: firstDate,
                          lastDate: lastDate,
                          hint: '请选择日期',
                          format: _dateLabel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '按教学日历、单双周与补课映射生成实际课次',
                    style: TextStyle(fontSize: 11.5, color: colors.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _previewItem({
    required String mark,
    required Color markBackground,
    required Color markForeground,
    String? date,
    required String change,
    String? issue,
    String? skipNote,
    Widget? action,
    bool bad = false,
    bool skip = false,
  }) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bad
            ? _isDark
                  ? colors.destructiveSurface
                  : const Color(0xFFFDF7F6)
            : colors.surface,
        border: Border.all(
          color: bad ? colors.destructive.withValues(alpha: .4) : colors.border,
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Opacity(
        opacity: skip ? .65 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: markBackground,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  mark,
                  style: TextStyle(fontSize: 11, color: markForeground),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (date != null)
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.ink,
                      ),
                    ),
                  Text(
                    change,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: colors.inkSecondary,
                    ),
                  ),
                  if (issue != null)
                    Text(
                      issue,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: colors.destructive,
                      ),
                    ),
                  if (skipNote != null)
                    Text(
                      skipNote,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: colors.muted,
                      ),
                    ),
                  ?action,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 预览弹窗

  Future<void> _openPreview() async {
    final state = _data!;
    final source = _source!;
    final term = state.snapshot.term;
    final defaultEnd =
        term.teachingWeekEnd(term.teachingWeekCount) ?? source.date;
    var range = false;
    var rangeStart = source.date;
    var rangeEnd = defaultEnd;
    final excluded = <DateTime>{};
    var computeToken = 0;

    ({
      TemporaryMoveRequest? move,
      TemporarySwapRequest? swap,
      TemporarySubstituteRequest? sub,
    })
    buildRequests() => (
      move: _kind == 'move' && _targetDate != null && _targetPosition != null
          ? TemporaryMoveRequest(
              sourceKey: source.key,
              targetDate: _targetDate!,
              targetPosition: _targetPosition!,
              reason: _reason.text,
              rangeStart: range ? rangeStart : null,
              rangeEnd: range ? rangeEnd : null,
              excludedDates: excluded,
            )
          : null,
      swap: _kind == 'swap' && _swapTarget != null
          ? TemporarySwapRequest(
              firstKey: source.key,
              secondKey: _swapTarget!.key,
              reason: _reason.text,
              rangeStart: range ? rangeStart : null,
              rangeEnd: range ? rangeEnd : null,
              excludedDates: excluded,
            )
          : null,
      sub: _kind == 'substitute' && _teacherId != null
          ? TemporarySubstituteRequest(
              sourceKey: source.key,
              teacherId: _teacherId!,
              subjectId: _subjectId,
              reason: _reason.text,
              rangeStart: range ? rangeStart : null,
              rangeEnd: range ? rangeEnd : null,
              excludedDates: excluded,
            )
          : null,
    );

    final ui = ValueNotifier<_PreviewUi>(
      const _PreviewUi(
        preview: ActualChangePreview(changes: [], errors: ['请先选择调整目标']),
      ),
    );

    Future<void> recompute() async {
      final reqs = buildRequests();
      if (reqs.move == null && reqs.swap == null && reqs.sub == null) {
        ui.value = const _PreviewUi(
          preview: ActualChangePreview(changes: [], errors: ['请先选择调整目标']),
        );
        return;
      }
      final token = ++computeToken;
      if (state.lessons.length <= 2000) {
        ui.value = _PreviewUi(
          preview: reqs.move != null
              ? state.previewMove(reqs.move!)
              : reqs.swap != null
              ? state.previewSwap(reqs.swap!)
              : state.previewSubstitute(reqs.sub!),
        );
        return;
      }
      ui.value = _PreviewUi(preview: ui.value.preview, computing: true);
      if (mounted) setState(() => _saving = true);
      try {
        final preview = await computeTemporaryPreview(
          state: state,
          move: reqs.move,
          swap: reqs.swap,
          substitute: reqs.sub,
        );
        if (token != computeToken || !mounted) return;
        if (_data?.revision != state.revision) {
          ui.value = const _PreviewUi(
            preview: ActualChangePreview(
              changes: [],
              errors: ['课表已改变，请重新选择并预览。'],
            ),
            computing: false,
          );
          return;
        }
        ui.value = _PreviewUi(preview: preview, computing: false);
      } on Object catch (error) {
        if (token != computeToken || !mounted) return;
        ui.value = _PreviewUi(
          preview: ActualChangePreview(changes: [], errors: ['预览失败：$error']),
          computing: false,
        );
      } finally {
        if (mounted && token == computeToken) setState(() => _saving = false);
      }
    }

    await recompute();
    if (!mounted) {
      ui.dispose();
      return;
    }

    final colors = context.appColors;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<_PreviewUi>(
        valueListenable: ui,
        builder: (context, value, _) {
          final preview = value.preview;
          final reqs = buildRequests();
          final count = <String>{};
          for (var index = 0; index < preview.changes.length; index++) {
            if (reqs.swap != null && index.isOdd) continue;
            final lesson = preview.changes[index].before;
            count.add(
              '${_date(lesson.date)}:${lesson.item.meetingId ?? lesson.item.id}',
            );
          }
          final canConfirm =
              preview.errors.isEmpty &&
              preview.changes.isNotEmpty &&
              !value.computing;

          final previewItems = <Widget>[];
          for (var index = 0; index < preview.changes.length; index++) {
            final change = preview.changes[index];
            if (reqs.swap != null && index.isOdd) continue;
            final dateLine =
                '${_dateLabel(change.before.date)}（${_weekdayLabel(change.before.date)}）';
            final changeLine = switch (_kind) {
              'swap' when index + 1 < preview.changes.length =>
                '${_subjectTeacher(change.before)} ↔ ${_subjectTeacher(preview.changes[index + 1].before)}（互换时间，各自科目与教师不变）',
              'swap' => '${_subjectTeacher(change.before)}（互换时间）',
              'move' =>
                '${_subjectTeacher(change.before)} → ${_dateLabel(change.after.date)}（${_weekdayLabel(change.after.date)}）'
                    '${_slotLabel(change.after.item.position)}（移至空课位，原位置变为空位）',
              _ => _substitutionSummary(change),
            };
            previewItems.add(
              _previewItem(
                mark: '✓',
                markBackground: colors.successSurface,
                markForeground: colors.success,
                date: dateLine,
                change: changeLine,
              ),
            );
          }
          for (final error in preview.errors) {
            final excludeDate = range && error.length >= 10
                ? DateTime.tryParse(error.substring(0, 10))
                : null;
            previewItems.add(
              _previewItem(
                mark: '✕',
                markBackground: colors.destructiveSurface,
                markForeground: colors.destructive,
                change: error,
                bad: true,
                action: excludeDate != null
                    ? _textButton(
                        '移除此日期',
                        fontSize: 12,
                        onTap: () {
                          excluded.add(excludeDate);
                          unawaited(recompute());
                        },
                      )
                    : null,
              ),
            );
          }
          for (final date in preview.skippedDates) {
            previewItems.add(
              _previewItem(
                mark: '－',
                markBackground: _hintNeutral,
                markForeground: colors.muted,
                change: '${_dateLabel(date)}（${_weekdayLabel(date)}）',
                skipNote: '没有实际课次，已跳过',
                skip: true,
              ),
            );
          }

          final subTitle = switch (_kind) {
            'swap' =>
              _swapTarget == null
                  ? '换课'
                  : '换课 · ${_subjectTeacher(source)} 与 ${_subjectTeacher(_swapTarget!)} 互换时间',
            'move' =>
              _targetDate == null
                  ? '移课'
                  : '移课 · ${_subjectTeacher(source)} 移至 ${_dateLabel(_targetDate!)}（${_weekdayLabel(_targetDate!)}）${_slotLabel(_targetPosition)}',
            _ =>
              _teacherId == null
                  ? '代课'
                  : _subjectId != null && _subjectId != source.item.subjectId
                  ? '代课 · ${_subjectTeacher(source)} → ${_subject(_subjectId!)}·${_teacher(_teacherId!)}（保留时间）'
                  : '代课 · ${_teacher(source.item.teacherId)} → ${_teacher(_teacherId!)}（保留科目与时间）',
          };

          return AppDialog(
            maxWidth: 560,
            padding: EdgeInsets.zero,
            titleGap: 0,
            actionsGap: 0,
            title: _dialogHeader(
              '预览调整',
              sub: subTitle,
              onClose: () => Navigator.pop(dialogContext, false),
            ),
            content: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _scopeBlock(
                    state: state,
                    source: source,
                    range: range,
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd,
                    onScopeChanged: (value) {
                      range = value;
                      unawaited(recompute());
                    },
                    onDatesChanged: (start, end) {
                      rangeStart = start;
                      rangeEnd = end;
                      unawaited(recompute());
                    },
                  ),
                  const SizedBox(height: 14),
                  if (value.computing)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '正在生成预览…',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (previewItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '没有可调整的课次',
                        style: TextStyle(fontSize: 12.5, color: colors.muted),
                      ),
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < previewItems.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          previewItems[i],
                        ],
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: Row(
                  children: [
                    AppGhostButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('返回修改'),
                    ),
                    const Spacer(),
                    if (!canConfirm &&
                        preview.errors.isNotEmpty &&
                        !value.computing)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          '存在冲突课次，需修正后再确认',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.destructive,
                          ),
                        ),
                      ),
                    AppPrimaryButton(
                      onPressed: canConfirm
                          ? () => Navigator.pop(dialogContext, true)
                          : null,
                      child: Text('确认调整（${count.length}次）'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    ui.dispose();
    if (confirmed != true || !mounted) return;
    await _commitAdjustment(
      move: buildRequests().move,
      swap: buildRequests().swap,
      sub: buildRequests().sub,
    );
  }

  Future<void> _commitAdjustment({
    required TemporaryMoveRequest? move,
    required TemporarySwapRequest? swap,
    required TemporarySubstituteRequest? sub,
  }) async {
    final state = _data!;
    setState(() => _saving = true);
    try {
      final repo = ref.read(schoolRepositoryProvider);
      if (move != null) {
        await repo.commitTemporaryMove(
          termId: widget.termId,
          request: move,
          expectedRevision: state.revision,
        );
      }
      if (swap != null) {
        await repo.commitTemporarySwap(
          termId: widget.termId,
          request: swap,
          expectedRevision: state.revision,
        );
      }
      if (sub != null) {
        await repo.commitTemporarySubstitute(
          termId: widget.termId,
          request: sub,
          expectedRevision: state.revision,
        );
      }
      if (!mounted) return;
      _source = null;
      _kind = null;
      _swapTarget = null;
      _targetDate = null;
      _targetPosition = null;
      _teacherId = null;
      _subjectId = null;
      _reason.clear();
      await _load();
    } on Object catch (error) {
      if (error.toString().contains('已改变')) {
        await _load();
        _source = null;
        _kind = null;
      }
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------- 代课弹窗

  Widget _miniPill(String label, {Color? background, Color? foreground}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: background ?? _hintNeutral,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: foreground ?? context.appColors.inkSecondary,
          ),
        ),
      );

  Widget _filterChip(String label, bool value, ValueChanged<bool> onChanged) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: value ? colors.selectedBlue : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value ? colors.blue.withValues(alpha: .35) : _borderStrong,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: value ? colors.blue : colors.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseTeacher() async {
    final state = _data!;
    final source = _source!;
    var sameSubject = false;
    var sameGrade = false;
    var sameClass = false;
    var pickedId = _teacherId;
    var expandedId = <String>{};
    final week = state.snapshot.term.teachingWeekOf(source.date);
    final weeklyByTeacher = <String, List<ActualLesson>>{};
    for (final lesson in state.lessons) {
      if (state.snapshot.term.teachingWeekOf(lesson.date) == week) {
        weeklyByTeacher
            .putIfAbsent(lesson.item.teacherId, () => [])
            .add(lesson);
      }
    }
    final avatarPalette = [
      context.appColors.blue,
      context.appColors.success,
      context.appColors.warning,
      context.appColors.purple,
    ];

    final selected = await showAppDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final colors = context.appColors;
          final candidates = state.snapshot.teachers.where((teacher) {
            final assignments = state.snapshot.assignments.where(
              (assignment) => assignment.teacherId == teacher.id,
            );
            if (sameSubject &&
                !teacher.subjectIds.contains(
                  _subjectId ?? source.item.subjectId,
                ) &&
                !assignments.any(
                  (assignment) =>
                      assignment.subjectId ==
                      (_subjectId ?? source.item.subjectId),
                )) {
              return false;
            }
            if (sameGrade &&
                !assignments.any(
                  (assignment) =>
                      state.snapshot.gradeIdForClass(assignment.classId) ==
                      state.snapshot.gradeIdForClass(source.item.classId),
                )) {
              return false;
            }
            if (sameClass &&
                !assignments.any(
                  (assignment) => assignment.classId == source.item.classId,
                )) {
              return false;
            }
            return true;
          }).toList();

          return AppDialog(
            maxWidth: 560,
            padding: EdgeInsets.zero,
            titleGap: 0,
            actionsGap: 0,
            title: _dialogHeader(
              '选择代课教师',
              sub:
                  '${_dateLabel(source.date)}（${_weekdayLabel(source.date)}）'
                  '${_slotLabel(source.item.position)} · ${_subject(source.item.subjectId)} · ${_className(source.item.classId)}',
              onClose: () => Navigator.pop(dialogContext),
            ),
            content: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hintBox(
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                '科目：${_subject(_subjectId ?? source.item.subjectId)}',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const TextSpan(text: '（默认保留，可在发起调整中更改）'),
                        ],
                      ),
                    ),
                    tone: 'blue',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _filterChip('同科目', sameSubject, (value) {
                        if (sameSubject != value) {
                          update(() => sameSubject = value);
                        }
                      }),
                      _filterChip('同年级', sameGrade, (value) {
                        if (sameGrade != value) update(() => sameGrade = value);
                      }),
                      _filterChip('本班优先', sameClass, (value) {
                        if (sameClass != value) update(() => sameClass = value);
                      }),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (candidates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '没有符合条件的教师',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                    )
                  else
                    for (var index = 0; index < candidates.length; index++)
                      Builder(
                        builder: (context) {
                          final teacher = candidates[index];
                          final weekLessons =
                              weeklyByTeacher[teacher.id] ??
                              const <ActualLesson>[];
                          var busy = false;
                          var missingClock = false;
                          ActualLesson? busyLesson;
                          final sourcePosition = source.item.position!;
                          for (final lesson in weekLessons.where(
                            (lesson) => lesson.date == source.date,
                          )) {
                            if (lesson.key == source.key ||
                                (source.item.meetingId != null &&
                                    lesson.item.meetingId ==
                                        source.item.meetingId)) {
                              continue;
                            }
                            final position = lesson.item.position;
                            if (position == null) continue;
                            if (sourcePosition.stageId != position.stageId &&
                                (!sourcePosition.hasClockTime ||
                                    !position.hasClockTime)) {
                              missingClock = true;
                            } else if (sourcePosition.overlaps(position)) {
                              busy = true;
                              busyLesson = lesson;
                            }
                          }
                          final noChange =
                              teacher.id == source.item.teacherId &&
                              (_subjectId == null ||
                                  _subjectId == source.item.subjectId);
                          final teacherLocked = state.snapshot.locks.any(
                            (lock) =>
                                lock.scope == ScheduleLockScope.teacher &&
                                lock.targetId == teacher.id,
                          );
                          final available =
                              !busy &&
                              !missingClock &&
                              !noChange &&
                              !teacherLocked;
                          final weekCount = weekLessons
                              .map(
                                (lesson) =>
                                    '${_date(lesson.date)}:${lesson.item.meetingId ?? lesson.item.id}',
                              )
                              .toSet()
                              .length;
                          final statusLine = available
                              ? '本次新增 1 节 · 本周 $weekCount 节'
                              : missingClock
                              ? '✕ 缺少可对比的作息时间'
                              : busy
                              ? '✕ 该时段有课：${_className(busyLesson!.item.classId)} ${_subject(busyLesson.item.subjectId)}'
                              : noChange
                              ? '✕ 与当前任课教师相同'
                              : '✕ 教师课表已锁定';
                          final expanded = expandedId.contains(teacher.id);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: pickedId == teacher.id
                                      ? colors.blue
                                      : colors.border,
                                ),
                                borderRadius: BorderRadius.circular(11),
                                color: pickedId == teacher.id
                                    ? _blueWash
                                    : colors.surface,
                              ),
                              child: Column(
                                children: [
                                  InkWell(
                                    onTap: available
                                        ? () => update(
                                            () => pickedId = teacher.id,
                                          )
                                        : null,
                                    child: Opacity(
                                      opacity: available ? 1 : .62,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color:
                                                    avatarPalette[index %
                                                        avatarPalette.length],
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  teacher
                                                      .displayName
                                                      .characters
                                                      .first,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 11),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          teacher.displayName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 13.5,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: colors.ink,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      _miniPill(
                                                        teacher.subjectIds
                                                                .map(_subject)
                                                                .firstOrNull ??
                                                            _subject(
                                                              _subjectId ??
                                                                  source
                                                                      .item
                                                                      .subjectId,
                                                            ),
                                                      ),
                                                      if (available) ...[
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        _miniPill(
                                                          '该时段空闲',
                                                          background: colors
                                                              .successSurface,
                                                          foreground:
                                                              colors.success,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    statusLine,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: available
                                                          ? colors.inkSecondary
                                                          : colors.warning,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            _textButton(
                                              '查看课表',
                                              fontSize: 12,
                                              onTap: () => update(() {
                                                if (expandedId.contains(
                                                  teacher.id,
                                                )) {
                                                  expandedId.remove(teacher.id);
                                                } else {
                                                  expandedId.add(teacher.id);
                                                }
                                              }),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (expanded)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final lesson in weekLessons)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 2,
                                                  ),
                                              child: Text(
                                                _lesson(lesson),
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: colors.muted,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: Row(
                  children: [
                    Text(
                      '候选默认按空闲状态排序；可展开查看候选教师同期课表。',
                      style: TextStyle(fontSize: 11.5, color: colors.muted),
                    ),
                    const Spacer(),
                    AppGhostButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('关闭'),
                    ),
                    const SizedBox(width: 8),
                    AppPrimaryButton(
                      onPressed: pickedId != null
                          ? () => Navigator.pop(dialogContext, pickedId)
                          : null,
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    if (selected != null && mounted) setState(() => _teacherId = selected);
  }

  // ---------------------------------------------------------------- 记录列表

  String _recordDateSummary(TemporaryAdjustmentRecord record) {
    if (record.changes.isEmpty) return '';
    final first = record.changes.first;
    final last = record.changes.last;
    String slot(ActualLessonChange change) =>
        '${_dateLabel(change.before.date)}（${_weekdayLabel(change.before.date)}）'
        '${_slotLabel(change.before.item.position)}';
    if (record.kind == 'swap' && record.changes.length >= 2) {
      final count = record.changes.length ~/ 2;
      return '${slot(first)} ↔ ${slot(record.changes[1])}${count > 1 ? ' 等 $count 组' : ''}';
    }
    if (record.kind == 'move') {
      return '${slot(first)} → ${_dateLabel(last.after.date)}（${_weekdayLabel(last.after.date)}）'
          '${_slotLabel(last.after.item.position)}';
    }
    return slot(first);
  }

  String _substitutionSummary(ActualLessonChange change) {
    final before = change.before.item;
    final after = change.after.item;
    if (before.subjectId != after.subjectId) {
      return '${_subjectTeacher(change.before)} → ${_subjectTeacher(change.after)}（保留时间）';
    }
    return '${_teacher(before.teacherId)} → ${_teacher(after.teacherId)}（保留科目与时间）';
  }

  String _recordChangeSummary(TemporaryAdjustmentRecord record) {
    if (record.changes.isEmpty) return '';
    if (record.kind == 'swap') {
      final pairs = [
        for (var index = 0; index + 1 < record.changes.length; index += 2)
          '${_subjectTeacher(record.changes[index].before)} ↔ ${_subjectTeacher(record.changes[index + 1].before)}',
      ];
      if (pairs.isEmpty) return _subjectTeacher(record.changes.first.before);
      final shownPairs = pairs.take(2).join('；');
      final remaining = pairs.length - 2;
      return '$shownPairs${remaining > 0 ? '；另 $remaining 组' : ''} · 互换时间，科目与教师不变';
    }
    final change = record.changes.first;
    final summary = record.kind == 'move'
        ? '${_subjectTeacher(change.before)} 移至 ${_dateLabel(change.after.date)}（${_weekdayLabel(change.after.date)}）${_slotLabel(change.after.item.position)}'
        : _substitutionSummary(change);
    return record.changes.length > 1
        ? '$summary · 共 ${record.changes.length} 节'
        : summary;
  }

  Widget _statusBadge(TemporaryAdjustmentRecord record) {
    final colors = context.appColors;
    final (color, label) = record.cancelledAt != null
        ? (colors.muted, '已取消')
        : record.needsAttention
        ? (colors.warning, '需处理')
        : (colors.success, '有效');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12.5, color: color)),
      ],
    );
  }

  Widget _recordList(TemporaryTimetableState state) {
    final colors = context.appColors;
    final records = _filteredRecords(state).reversed.toList();
    if (records.isEmpty) {
      final noRecordsYet = state.records.isEmpty;
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      noRecordsYet ? '还没有调整记录' : '没有符合筛选条件的记录',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      noRecordsYet
                          ? '确认一次调整后，变更课次与原因会显示在这里。'
                          : '当前筛选范围内没有调整记录。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.inkSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                noRecordsYet
                    ? AppPrimaryButton(
                        onPressed: () => setState(() => _records = false),
                        child: const Text('查看实际课表'),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _textButton('清除筛选条件', onTap: _clearRecordFilters),
                          if (!_showCancelled &&
                              _recordStatus == null &&
                              state.records.any(
                                (record) => record.cancelledAt != null,
                              ))
                            _textButton(
                              '显示已取消记录',
                              onTap: () =>
                                  setState(() => _showCancelled = true),
                            ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1280,
            maxHeight: constraints.maxHeight,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < records.length; i++)
                Container(
                  decoration: i == records.length - 1
                      ? null
                      : BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: colors.border),
                          ),
                        ),
                  child: _recordRow(records[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearRecordFilters() => setState(() {
    _recordType = null;
    _recordStatus = null;
    _recordClass = null;
    _recordTeacher = null;
    _recordDates = null;
    _showCancelled = false;
  });

  Widget _recordRow(TemporaryAdjustmentRecord record) {
    final colors = context.appColors;
    final cancelled = record.cancelledAt != null;
    final className = record.changes.isEmpty
        ? ''
        : _className(record.changes.first.before.item.classId);
    final title = Text(
      '$className · ${_recordDateSummary(record)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: colors.ink,
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _recordChangeSummary(record),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: colors.inkSecondary,
          ),
        ),
        if (record.needsAttention)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: colors.warning),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '常规课表已变化，此调整需人工处理',
                    style: TextStyle(fontSize: 12, color: colors.warning),
                  ),
                ),
              ],
            ),
          ),
        if (record.reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '原因：${record.reason}',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
          ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _textButton('详情', onTap: () => _showRecordDetails(record)),
        if (!cancelled)
          _textButton(
            '取消',
            color: colors.destructive,
            onTap: _saving ? null : () => _cancel(record),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Opacity(
          opacity: cancelled ? .6 : 1,
          child: constraints.maxWidth < 760
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _typePill(record.kind),
                        const SizedBox(width: 10),
                        Expanded(child: title),
                        const SizedBox(width: 8),
                        _statusBadge(record),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: details,
                    ),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                )
              : Row(
                  children: [
                    _typePill(record.kind),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 3), details],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _statusBadge(record),
                    const SizedBox(width: 12),
                    actions,
                  ],
                ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: content,
        );
      },
    );
  }

  Future<void> _showRecordDetails(TemporaryAdjustmentRecord record) async {
    final colors = context.appColors;
    final className = record.changes.isEmpty
        ? ''
        : _className(record.changes.first.before.item.classId);
    await showAppDialog(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 560,
        padding: EdgeInsets.zero,
        titleGap: 0,
        actionsGap: 0,
        title: _dialogHeader(
          '调整详情',
          sub:
              '${_kindLabel(record.kind)} · $className · ${_recordDateSummary(record)}',
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final change in record.changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_lesson(change.before)}\n→ ${_lesson(change.after)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: colors.inkSecondary,
                    ),
                  ),
                ),
              if (record.reason.isNotEmpty)
                Text(
                  '原因：${record.reason}',
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              if (record.cancelledAt != null) ...[
                const SizedBox(height: 8),
                _hintBox(const Text('此调整已取消，未应用在实际课表中。')),
              ],
              if (record.needsAttention) ...[
                const SizedBox(height: 8),
                _hintBox(const Text('常规课表已变化，此调整需人工处理。'), tone: 'amber'),
              ],
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Row(
              children: [
                const Spacer(),
                AppGhostButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 记录筛选 / 导出 / 取消

  List<TemporaryAdjustmentRecord> _filteredRecords(
    TemporaryTimetableState state,
  ) => state.records.where((record) {
    final status = record.cancelledAt != null
        ? 'cancelled'
        : record.needsAttention
        ? 'invalid'
        : 'active';
    if (_recordStatus != null && status != _recordStatus) return false;
    if (_recordStatus == null && !_showCancelled && status == 'cancelled') {
      return false;
    }
    if (_recordType != null && record.kind != _recordType) return false;
    return record.changes.any(_matchesChange);
  }).toList();

  bool _matchesChange(ActualLessonChange change) {
    if (_recordClass != null && change.before.item.classId != _recordClass) {
      return false;
    }
    if (_recordTeacher != null &&
        change.before.item.teacherId != _recordTeacher &&
        change.after.item.teacherId != _recordTeacher) {
      return false;
    }
    if (_recordDates != null &&
        (change.before.date.isBefore(_recordDates!.start) ||
            change.before.date.isAfter(_recordDates!.end)) &&
        (change.after.date.isBefore(_recordDates!.start) ||
            change.after.date.isAfter(_recordDates!.end))) {
      return false;
    }
    return true;
  }

  Future<void> _selectRecordDates() async {
    final term = _data!.snapshot.term;
    final range = await showDateRangePicker(
      context: context,
      firstDate: term.firstTeachingWeekStart!,
      lastDate: term.teachingWeekEnd(term.teachingWeekCount)!,
      initialDateRange: _recordDates,
    );
    if (range != null && mounted) setState(() => _recordDates = range);
  }

  Future<void> _export(TemporaryExportKind kind) async {
    final state = _data!;
    final title = switch (kind) {
      TemporaryExportKind.teacher => '教师通知',
      TemporaryExportKind.schoolClass => '班级通知',
      TemporaryExportKind.details => '调整明细',
    };
    try {
      final location = await ref.read(temporaryExportSaveLocationProvider)(
        '$title.xlsx',
      );
      if (location == null) return;
      final bytes = buildTemporaryAdjustmentWorkbook(
        state.snapshot,
        _filteredRecords(state),
        kind,
        teacherId: _recordTeacher,
        includeChange: _matchesChange,
        includeCancelled: _showCancelled || _recordStatus == 'cancelled',
      );
      await XFile.fromData(
        Uint8List.fromList(bytes),
        name: '$title.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ).saveTo(location.path);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$title 已导出')));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '导出失败：$error');
    }
  }

  Future<void> _cancel(TemporaryAdjustmentRecord record) async {
    final state = _data!;
    final colors = context.appColors;
    final index = state.records.indexWhere((item) => item.id == record.id);
    final keys = record.changes.map((change) => change.before.key).toSet();
    final dependencies = index < 0
        ? <TemporaryAdjustmentRecord>[]
        : state.records
              .skip(index + 1)
              .where(
                (later) =>
                    later.cancelledAt == null &&
                    later.changes.any(
                      (change) => keys.contains(change.before.key),
                    ),
              )
              .toList();
    final className = record.changes.isEmpty
        ? ''
        : _className(record.changes.first.before.item.classId);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 470,
        padding: EdgeInsets.zero,
        titleGap: 0,
        actionsGap: 0,
        title: _dialogHeader(
          '取消调整',
          sub:
              '${_kindLabel(record.kind)} · $className · ${_recordDateSummary(record)}',
          onClose: () => Navigator.pop(dialogContext, false),
        ),
        content: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (record.needsAttention)
                _hintBox(
                  const Text('此调整已失效，当前没有应用到实际课表。取消后保留历史记录。'),
                  tone: 'amber',
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final change in record.changes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                color: colors.successSurface,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '✓',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.success,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                '${_dateLabel(change.after.date)}（${_weekdayLabel(change.after.date)}）'
                                '${_slotLabel(change.after.item.position)} 恢复为 '
                                '${_subject(change.after.item.subjectId)}·${_teacher(change.before.item.teacherId)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: colors.inkSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              if (dependencies.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.warningSurface,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '存在依赖此结果的后续调整：',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: dependencies
                              .map(
                                (later) =>
                                    '${_kindLabel(later.kind)} · ${_recordDateSummary(later)}',
                              )
                              .join('；'),
                        ),
                        const TextSpan(text: '。建议先取消后续调整，再取消本条。'),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: _amberText,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _hintBox(const Text('取消后实际课表将恢复原安排，常规周课表不受影响。')),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Row(
              children: [
                AppGhostButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('关闭'),
                ),
                const Spacer(),
                if (dependencies.isNotEmpty)
                  AppGhostButton(onPressed: null, child: const Text('先取消后续调整')),
                const SizedBox(width: 8),
                AppDestructiveButton(
                  onPressed: dependencies.isEmpty
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('取消调整'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(schoolRepositoryProvider)
          .cancelTemporaryAdjustment(
            termId: widget.termId,
            adjustmentId: record.id,
            expectedRevision: state.revision,
          );
      if (!mounted) return;
      await _load();
    } on Object catch (error) {
      if (error.toString().contains('已改变')) await _load();
      if (mounted) setState(() => _error = '取消失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
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
