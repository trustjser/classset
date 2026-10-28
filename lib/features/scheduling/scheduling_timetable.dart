import 'dart:async';
import 'dart:math' as math;

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/theme/subject_colors.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/manual_schedule_editor.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

enum _ScheduleView { schoolClass, teacher, all, room }

enum _WeekView { merged, odd, even }

enum _AllScheduleLayout { timetable, classes }

abstract final class _SchedulePalette {
  static BoxDecoration panel(BuildContext context) => BoxDecoration(
    color: context.appColors.surface,
    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
    boxShadow: context.appColors.cardShadow,
  );
}

/// The timetable remains visible while the solver runs, matching the design's
/// toolbar, right rail and bottom task bar.
class SchedulingTimetable extends StatefulWidget {
  const SchedulingTimetable({
    required this.snapshot,
    this.commonPeriods = const {},
    required this.state,
    required this.onStart,
    required this.onRefresh,
    required this.onRules,
    required this.onReport,
    required this.onDetectionReport,
    required this.onCancel,
    required this.onDone,
    required this.onExport,
    required this.onPreviewMove,
    required this.onMove,
    this.onPlaceUnplaced,
    required this.onUndo,
    required this.onRedo,
    required this.onSetLock,
    required this.onSetAllLocks,
    this.onSetClassLocks,
    super.key,
  });

  final SchedulingSnapshot snapshot;
  final Map<String, List<CommonPeriod>> commonPeriods;
  final SchedulingState state;
  final VoidCallback onStart;
  final VoidCallback onRefresh;
  final VoidCallback onRules;
  final VoidCallback onReport;
  final VoidCallback onDetectionReport;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final void Function(List<ScheduleItem> items, String title) onExport;
  final ManualMoveResult Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onPreviewMove;
  final Future<ManualMoveResult> Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onMove;
  final Future<int?> Function(Set<String>)? onPlaceUnplaced;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final Future<void> Function(ScheduleLock lock, bool enabled) onSetLock;
  final Future<void> Function(bool enabled) onSetAllLocks;
  final Future<void> Function(Set<String> classIds, bool enabled)?
  onSetClassLocks;

  @override
  State<SchedulingTimetable> createState() => _SchedulingTimetableState();
}

class _SchedulingTimetableState extends State<SchedulingTimetable> {
  _ScheduleView _view = _ScheduleView.schoolClass;
  _WeekView _week = _WeekView.merged;
  _AllScheduleLayout _allLayout = _AllScheduleLayout.timetable;
  String? _stageId;
  int _weekday = DateTime.monday;
  String? _classId;
  String? _teacherId;
  String? _roomId;
  bool _groupUnplacedBySubject = false;
  final ValueNotifier<String?> _draggedItemId = ValueNotifier(null);
  final ScrollController _pageScrollController = ScrollController();
  final ScrollController _gridScrollController = ScrollController();
  final GlobalKey _pageViewportKey = GlobalKey();
  final GlobalKey _gridViewportKey = GlobalKey();
  Timer? _dragScrollTimer;
  Offset? _dragPointer;

  @override
  void initState() {
    super.initState();
    _draggedItemId.addListener(_onDragStateChanged);
  }

  void _onDragStateChanged() {
    if (_draggedItemId.value == null) {
      _dragPointer = null;
      _dragScrollTimer?.cancel();
      _dragScrollTimer = null;
    } else {
      _dragScrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _scrollNearDragEdge(),
      );
    }
  }

  void _scrollNearDragEdge() {
    final pointer = _dragPointer;
    if (pointer == null) return;
    _scrollAtEdge(
      pointer: pointer,
      viewportKey: _pageViewportKey,
      controller: _pageScrollController,
      axis: Axis.vertical,
    );
    _scrollAtEdge(
      pointer: pointer,
      viewportKey: _gridViewportKey,
      controller: _gridScrollController,
      axis: Axis.horizontal,
    );
  }

  void _scrollAtEdge({
    required Offset pointer,
    required GlobalKey viewportKey,
    required ScrollController controller,
    required Axis axis,
  }) {
    if (!controller.hasClients) return;
    final renderObject = viewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final local = renderObject.globalToLocal(pointer);
    final crossPosition = axis == Axis.vertical ? local.dx : local.dy;
    final crossSize = axis == Axis.vertical
        ? renderObject.size.width
        : renderObject.size.height;
    if (crossPosition < 0 || crossPosition > crossSize) return;
    final position = axis == Axis.vertical ? local.dy : local.dx;
    final size = axis == Axis.vertical
        ? renderObject.size.height
        : renderObject.size.width;
    final edge = math.min(80.0, size / 4);
    if (edge <= 0) return;
    if (axis == Axis.horizontal && (position < -24 || position > size + 24)) {
      return;
    }
    final proximity = position < edge
        ? -(edge - position) / edge
        : position > size - edge
        ? (position - (size - edge)) / edge
        : 0.0;
    if (proximity == 0) return;
    final scrollPosition = controller.position;
    final delta = proximity.clamp(-1.0, 1.0) * 22;
    final next = (scrollPosition.pixels + delta).clamp(
      scrollPosition.minScrollExtent,
      scrollPosition.maxScrollExtent,
    );
    if ((next - scrollPosition.pixels).abs() >= 0.5) {
      controller.jumpTo(next);
    }
  }

  @override
  void dispose() {
    _dragScrollTimer?.cancel();
    _draggedItemId.removeListener(_onDragStateChanged);
    _draggedItemId.dispose();
    _pageScrollController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final stageId = snapshot.stages.any((stage) => stage.id == _stageId)
        ? _stageId
        : null;
    final classIds = snapshot.classes.map((item) => item.id).toSet();
    final teacherIds = snapshot.teachers.map((item) => item.id).toSet();
    final roomIds = snapshot.rooms.map((item) => item.id).toSet();
    final classId = classIds.contains(_classId)
        ? _classId
        : snapshot.classes.firstOrNull?.id;
    final teacherId = teacherIds.contains(_teacherId)
        ? _teacherId
        : snapshot.teachers.firstOrNull?.id;
    final roomId = roomIds.contains(_roomId)
        ? _roomId
        : snapshot.rooms.firstOrNull?.id;
    final items = widget.state.items;
    final visible = items.where((item) {
      if (item.position == null || !_matchesWeek(item)) return false;
      if (_view != _ScheduleView.schoolClass &&
          stageId != null &&
          snapshot.stageIdForClass(item.classId) != stageId) {
        return false;
      }
      if (_view == _ScheduleView.all &&
          _allLayout == _AllScheduleLayout.classes &&
          item.position!.weekday != _weekday) {
        return false;
      }
      return switch (_view) {
        _ScheduleView.schoolClass => item.classId == classId,
        _ScheduleView.teacher => item.teacherId == teacherId,
        _ScheduleView.all => true,
        _ScheduleView.room => _roomIdFor(snapshot, item) == roomId,
      };
    }).toList();
    final solving =
        widget.state.status == SchedulingStatus.solving ||
        widget.state.status == SchedulingStatus.committing ||
        widget.state.status == SchedulingStatus.savingEdit;
    final editable =
        widget.state.pendingBaseline == null &&
        (widget.state.status == SchedulingStatus.ready ||
            widget.state.status == SchedulingStatus.completed);

    return Listener(
      onPointerMove: (event) {
        if (_draggedItemId.value != null) _dragPointer = event.position;
      },
      onPointerUp: (_) => _dragPointer = null,
      onPointerCancel: (_) => _dragPointer = null,
      child: ColoredBox(
        color: context.appColors.canvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                key: _pageViewportKey,
                builder: (context, viewport) {
                  final horizontalInset = viewport.maxWidth < 700 ? 16.0 : 24.0;
                  return ListView(
                    controller: _pageScrollController,
                    padding: EdgeInsets.fromLTRB(
                      horizontalInset,
                      20,
                      horizontalInset,
                      32,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1440),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _toolbar(
                                context,
                                classId,
                                teacherId,
                                roomId,
                                visible,
                                solving,
                              ),
                              const SizedBox(height: 16),
                              if (widget.state.error case final error?) ...[
                                AppInlineMessage(
                                  message: error,
                                  icon: Icons.error_outline,
                                ),
                                const SizedBox(height: 20),
                              ],
                              if (widget.state.backupWarning
                                  case final warning?) ...[
                                AppInlineMessage(
                                  message: warning,
                                  icon: Icons.warning_amber_outlined,
                                ),
                                const SizedBox(height: 20),
                              ],
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final grid = _TimetableGrid(
                                    snapshot: snapshot,
                                    commonPeriods: widget.commonPeriods,
                                    items: visible,
                                    allItems: items,
                                    view: _view,
                                    stageId: _view == _ScheduleView.schoolClass
                                        ? null
                                        : stageId,
                                    classOverview:
                                        _view == _ScheduleView.all &&
                                        _allLayout ==
                                            _AllScheduleLayout.classes,
                                    weekday: _weekday,
                                    week: _week,
                                    selectedClassId: classId,
                                    editable: editable,
                                    draggedItemId: _draggedItemId,
                                    scrollController: _gridScrollController,
                                    viewportKey: _gridViewportKey,
                                    onPreviewMove: widget.onPreviewMove,
                                    onMove: widget.onMove,
                                  );
                                  final rail = _RightRail(
                                    snapshot: snapshot,
                                    stageId: _view == _ScheduleView.schoolClass
                                        ? null
                                        : stageId,
                                    state: widget.state,
                                    week: _week,
                                    onRefresh: widget.onRefresh,
                                    onReport: widget.onReport,
                                    onDetectionReport: widget.onDetectionReport,
                                    editable: editable,
                                    draggedItemId: _draggedItemId,
                                    groupBySubject: _groupUnplacedBySubject,
                                    onToggleGrouping: () => setState(
                                      () => _groupUnplacedBySubject =
                                          !_groupUnplacedBySubject,
                                    ),
                                    onPreviewMove: widget.onPreviewMove,
                                    onMove: widget.onMove,
                                    onPlaceUnplaced: widget.onPlaceUnplaced,
                                  );
                                  if (constraints.maxWidth < 1100) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        grid,
                                        const SizedBox(height: 16),
                                        rail,
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: grid),
                                      const SizedBox(width: 16),
                                      SizedBox(width: 264, child: rail),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (solving || widget.state.status == SchedulingStatus.completed)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: _taskBar(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _matchesWeek(ScheduleItem item) => switch (_week) {
    _WeekView.merged => true,
    _WeekView.odd => item.weekMode != WeekMode.even,
    _WeekView.even => item.weekMode != WeekMode.odd,
  };

  Widget _toolbar(
    BuildContext context,
    String? classId,
    String? teacherId,
    String? roomId,
    List<ScheduleItem> visible,
    bool solving,
  ) {
    final snapshot = widget.snapshot;
    final selectedStage = snapshot.stages
        .where((stage) => stage.id == _stageId)
        .firstOrNull;
    final lockedClasses = snapshot.locks
        .where((lock) => lock.scope == ScheduleLockScope.schoolClass)
        .map((lock) => lock.targetId)
        .toSet();
    final lockedTeachers = snapshot.locks
        .where((lock) => lock.scope == ScheduleLockScope.teacher)
        .map((lock) => lock.targetId)
        .toSet();
    final filteredClasses = snapshot.classes
        .where(
          (item) =>
              selectedStage == null ||
              snapshot.stageIdForClass(item.id) == selectedStage.id,
        )
        .toList();
    final scopeLocked = switch (_view) {
      _ScheduleView.schoolClass => lockedClasses.contains(classId),
      _ScheduleView.teacher => lockedTeachers.contains(teacherId),
      _ScheduleView.all =>
        filteredClasses.isNotEmpty &&
            filteredClasses.every((item) => lockedClasses.contains(item.id)),
      _ScheduleView.room => false,
    };
    final selector = switch (_view) {
      _ScheduleView.schoolClass => AppSelectField<String>(
        key: const ValueKey('schedule-class-selector'),
        compact: true,
        items: _uniqueSelectorItems(
          snapshot.classes.map(
            (item) => (
              '${_stageName(snapshot, item.id)} · ${_gradeName(snapshot, item.id)} ${item.name}',
              item.id,
            ),
          ),
        ),
        value: classId,
        onChanged: (value) => setState(() => _classId = value),
        hint: '选择班级',
        searchable: true,
        searchHint: '搜索班级',
      ),
      _ScheduleView.teacher => AppSelectField<String>(
        key: const ValueKey('schedule-teacher-selector'),
        compact: true,
        items: _uniqueSelectorItems(
          snapshot.teachers.map((item) => (item.displayName, item.id)),
        ),
        value: teacherId,
        onChanged: (value) => setState(() => _teacherId = value),
        hint: '选择教师',
        searchable: true,
        searchHint: '搜索教师',
      ),
      _ScheduleView.room => AppSelectField<String>(
        key: const ValueKey('schedule-room-selector'),
        compact: true,
        items: _uniqueSelectorItems(
          snapshot.rooms.map((item) => (item.name, item.id)),
        ),
        value: roomId,
        onChanged: (value) => setState(() => _roomId = value),
        hint: '选择场室',
        searchable: true,
        searchHint: '搜索场室',
      ),
      _ScheduleView.all => const SizedBox.shrink(),
    };
    final navigation = Wrap(
      spacing: 2,
      runSpacing: 8,
      children: [
        for (final entry in const [
          (_ScheduleView.schoolClass, '班级课程表'),
          (_ScheduleView.teacher, '教师课程表'),
          (_ScheduleView.all, '总课程表'),
          (_ScheduleView.room, '场室课程表'),
        ])
          _viewTab(context, entry.$1, entry.$2),
      ],
    );
    final startButton = AppPrimaryButton.icon(
      onPressed: solving || widget.state.pendingBaseline != null
          ? null
          : widget.onStart,
      icon: const Icon(Icons.auto_awesome_outlined, size: 16),
      label: const Text('自动排课'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 820
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: navigation),
                    const SizedBox(width: 20),
                    startButton,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    navigation,
                    const SizedBox(height: 16),
                    startButton,
                  ],
                ),
        ),
        const SizedBox(height: 13),
        Divider(height: 1, color: context.appColors.border),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(10),
            boxShadow: context.appColors.cardShadow,
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              if (_view != _ScheduleView.schoolClass) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _controlLabel(context, '学段'),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 112,
                      child: AppSelectField<String>(
                        key: const ValueKey('schedule-stage-selector'),
                        compact: true,
                        items: _uniqueSelectorItems([
                          ('全部学段', ''),
                          ...snapshot.stages.map(
                            (stage) => (stage.name, stage.id),
                          ),
                        ]),
                        value:
                            snapshot.stages.any((stage) => stage.id == _stageId)
                            ? _stageId
                            : '',
                        onChanged: (value) => setState(
                          () => _stageId = value == '' ? null : value,
                        ),
                      ),
                    ),
                  ],
                ),
                _toolbarDivider(),
              ],
              if (_view == _ScheduleView.all) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in const [
                      (_AllScheduleLayout.timetable, '按课节'),
                      (_AllScheduleLayout.classes, '按班级'),
                    ])
                      TextButton(
                        onPressed: () => setState(() => _allLayout = entry.$1),
                        style: TextButton.styleFrom(
                          foregroundColor: _allLayout == entry.$1
                              ? context.appColors.blue
                              : context.appColors.inkSecondary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          textStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: _allLayout == entry.$1
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        child: Text(entry.$2),
                      ),
                  ],
                ),
                if (_allLayout == _AllScheduleLayout.classes)
                  SizedBox(
                    width: 96,
                    child: AppSelectField<int>(
                      key: const ValueKey('schedule-weekday-selector'),
                      compact: true,
                      items: {
                        for (var day = 1; day <= 7; day++) _dayLabel(day): day,
                      },
                      value: _weekday,
                      onChanged: (value) {
                        if (value != null) setState(() => _weekday = value);
                      },
                    ),
                  ),
                _toolbarDivider(),
              ],
              if (_view != _ScheduleView.all)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _controlLabel(context, switch (_view) {
                      _ScheduleView.schoolClass => '班级',
                      _ScheduleView.teacher => '教师',
                      _ScheduleView.room => '场室',
                      _ScheduleView.all => '',
                    }),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: _view == _ScheduleView.schoolClass ? 210 : 175,
                      child: selector,
                    ),
                  ],
                ),
              if (_view != _ScheduleView.all) _toolbarDivider(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _controlLabel(context, '周别'),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: context.appColors.tableHeader,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in const [
                          (_WeekView.merged, '合并'),
                          (_WeekView.odd, '单周'),
                          (_WeekView.even, '双周'),
                        ])
                          _weekSegment(entry.$1, entry.$2),
                      ],
                    ),
                  ),
                ],
              ),
              _toolbarDivider(),
              Wrap(
                spacing: 2,
                runSpacing: 4,
                children: [
                  AppGhostButton.icon(
                    onPressed:
                        solving ||
                            widget.state.pendingBaseline != null ||
                            widget.state.undoCount == 0
                        ? null
                        : widget.onUndo,
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('撤销'),
                  ),
                  AppGhostButton.icon(
                    onPressed:
                        solving ||
                            widget.state.pendingBaseline != null ||
                            widget.state.redoCount == 0
                        ? null
                        : widget.onRedo,
                    icon: const Icon(Icons.redo, size: 16),
                    label: const Text('重做'),
                  ),
                ],
              ),
              _toolbarDivider(),
              Wrap(
                spacing: 2,
                runSpacing: 4,
                children: [
                  if (_view != _ScheduleView.room)
                    AppGhostButton.icon(
                      onPressed: solving || widget.state.pendingBaseline != null
                          ? null
                          : () {
                              if (_view == _ScheduleView.all) {
                                if (selectedStage == null) {
                                  unawaited(widget.onSetAllLocks(!scopeLocked));
                                } else {
                                  final ids = filteredClasses
                                      .map((item) => item.id)
                                      .toSet();
                                  final bulk = widget.onSetClassLocks;
                                  if (bulk != null) {
                                    unawaited(bulk(ids, !scopeLocked));
                                  } else {
                                    unawaited(() async {
                                      for (final id in ids) {
                                        await widget.onSetLock(
                                          ScheduleLock(
                                            termId: snapshot.term.id,
                                            scope:
                                                ScheduleLockScope.schoolClass,
                                            targetId: id,
                                          ),
                                          !scopeLocked,
                                        );
                                      }
                                    }());
                                  }
                                }
                                return;
                              }
                              final id = _view == _ScheduleView.schoolClass
                                  ? classId
                                  : teacherId;
                              if (id == null) return;
                              unawaited(
                                widget.onSetLock(
                                  ScheduleLock(
                                    termId: snapshot.term.id,
                                    scope: _view == _ScheduleView.schoolClass
                                        ? ScheduleLockScope.schoolClass
                                        : ScheduleLockScope.teacher,
                                    targetId: id,
                                  ),
                                  !scopeLocked,
                                ),
                              );
                            },
                      icon: Icon(
                        scopeLocked
                            ? Icons.lock_outline
                            : Icons.lock_open_outlined,
                        size: 16,
                        color: scopeLocked ? context.appColors.warning : null,
                      ),
                      label: Text(
                        scopeLocked ? '已锁定' : '锁定',
                        style: TextStyle(
                          color: scopeLocked ? context.appColors.warning : null,
                        ),
                      ),
                    ),
                ],
              ),
              _toolbarDivider(),
              Wrap(
                spacing: 2,
                runSpacing: 4,
                children: [
                  AppGhostButton.icon(
                    onPressed: solving || widget.state.pendingBaseline != null
                        ? null
                        : widget.onRefresh,
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: const Text('检测'),
                  ),
                  AppGhostButton.icon(
                    onPressed: solving ? null : widget.onRules,
                    icon: const Icon(Icons.tune_outlined, size: 16),
                    label: const Text('规则'),
                  ),
                ],
              ),
              _toolbarDivider(),
              Wrap(
                spacing: 2,
                runSpacing: 4,
                children: [
                  AppGhostButton.icon(
                    onPressed:
                        visible.isEmpty || widget.state.pendingBaseline != null
                        ? null
                        : () => widget.onExport(
                            visible,
                            '${_viewLabel(_view)}${_view != _ScheduleView.schoolClass && selectedStage != null ? ' · ${selectedStage.name}' : ''} · ${_weekLabel(_week)}${_view == _ScheduleView.all && _allLayout == _AllScheduleLayout.classes ? ' · ${_dayLabel(_weekday)}' : ''}',
                          ),
                    icon: const Icon(Icons.ios_share_outlined, size: 16),
                    label: const Text('导出/打印'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _viewTab(BuildContext context, _ScheduleView view, String label) {
    final selected = _view == view;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppGhostButton(
          onPressed: () => setState(() => _view = view),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? context.appColors.ink
                  : context.appColors.inkSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          height: 3,
          width: 48,
          decoration: BoxDecoration(
            color: selected ? context.appColors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _controlLabel(BuildContext context, String label) => Text(
    label,
    style: TextStyle(
      color: context.appColors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  );

  Widget _toolbarDivider() =>
      Container(width: 1, height: 20, color: context.appColors.border);

  Widget _weekSegment(_WeekView value, String label) {
    final selected = _week == value;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _week = value),
      child: Container(
        height: 26,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? context.appColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1F1F1E1A),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? context.appColors.ink
                : context.appColors.inkSecondary,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _taskBar(BuildContext context) {
    final state = widget.state;
    final completed = state.status == SchedulingStatus.completed;
    final report = state.run?.report;
    final fraction = state.progress?.fraction.clamp(0.0, 1.0) ?? 0.0;
    final selected = state.selectedClassIds.length;
    final total = widget.snapshot.classes.length;
    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Icon(
              completed ? Icons.check_circle_outline : Icons.autorenew,
              color: completed
                  ? context.appColors.success
                  : context.appColors.blue,
              size: 20,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    completed
                        ? '排课完成 · 已选 $selected/$total 个班级'
                        : '正在自动排课 · 已选 $selected/$total 个班级',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (completed)
                    Text(
                      '已排 ${report?.placedItems ?? 0}/${report?.totalItems ?? 0} 节 · '
                      '未排 ${report?.unplaced.length ?? 0} 节进入暂放区',
                      style: TextStyle(
                        color: context.appColors.inkSecondary,
                        fontSize: 12,
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 170,
                          child: FDeterminateProgress(value: fraction),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(fraction * 100).toStringAsFixed(0)}% · '
                          '已检查 ${state.progress?.candidateChecks ?? 0} 个候选',
                          style: TextStyle(
                            color: context.appColors.inkSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (completed) ...[
              AppSecondaryButton(
                onPressed: widget.onReport,
                child: const Text('查看未排课程报告'),
              ),
              AppPrimaryButton(
                onPressed: widget.onDone,
                child: const Text('完成'),
              ),
            ] else
              AppSecondaryButton(
                onPressed: state.status == SchedulingStatus.solving
                    ? widget.onCancel
                    : null,
                child: const Text('取消排课'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimetableGrid extends StatelessWidget {
  const _TimetableGrid({
    required this.snapshot,
    required this.commonPeriods,
    required this.items,
    required this.allItems,
    required this.view,
    required this.stageId,
    required this.classOverview,
    required this.weekday,
    required this.week,
    required this.selectedClassId,
    required this.editable,
    required this.draggedItemId,
    required this.scrollController,
    required this.viewportKey,
    required this.onPreviewMove,
    required this.onMove,
  });

  final SchedulingSnapshot snapshot;
  final Map<String, List<CommonPeriod>> commonPeriods;
  final List<ScheduleItem> items;
  final List<ScheduleItem> allItems;
  final _ScheduleView view;
  final String? stageId;
  final bool classOverview;
  final int weekday;
  final _WeekView week;
  final String? selectedClassId;
  final bool editable;
  final ValueNotifier<String?> draggedItemId;
  final ScrollController scrollController;
  final GlobalKey viewportKey;
  final ManualMoveResult Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onPreviewMove;
  final Future<ManualMoveResult> Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onMove;

  @override
  Widget build(BuildContext context) {
    final currentStageId =
        view == _ScheduleView.schoolClass && selectedClassId != null
        ? snapshot.stageIdForClass(selectedClassId!)
        : stageId;
    final stageOrder = {
      for (final stage in snapshot.stages) stage.id: stage.sortOrder,
    };
    final routines =
        snapshot.routines
            .where(
              (routine) =>
                  currentStageId == null || routine.stageId == currentStageId,
            )
            .toList()
          ..sort(
            (a, b) => (stageOrder[a.stageId] ?? 0).compareTo(
              stageOrder[b.stageId] ?? 0,
            ),
          );
    if (classOverview) return _classOverview(context, routines);
    final days =
        routines.expand((routine) => routine.teachingWeekdays).toSet().toList()
          ..sort();
    final rows = <String, _GridRow>{};
    for (final routine in routines) {
      for (final period in routine.periodTypes) {
        for (final day in routine.teachingWeekdays) {
          final count = routine.effectiveLessonCount(period.id, day);
          for (var index = 1; index <= count; index++) {
            final key = '${routine.stageId}:${period.id}:$index';
            rows.putIfAbsent(
              key,
              () => _GridRow(
                routine.stageId,
                period.id,
                period.name,
                index,
                period.sortOrder,
                routines.indexOf(routine),
                period.lessonTimes
                    .where((time) => time.lessonIndex == index)
                    .firstOrNull
                    ?.startMinute,
              ),
            );
          }
        }
      }
    }
    final orderedRows = rows.values.toList()
      ..sort((a, b) {
        if (view == _ScheduleView.teacher || view == _ScheduleView.room) {
          final clockOrder = (a.startMinute ?? 1440).compareTo(
            b.startMinute ?? 1440,
          );
          if (clockOrder != 0) return clockOrder;
        }
        final stageOrder = a.stageOrder.compareTo(b.stageOrder);
        if (stageOrder != 0) return stageOrder;
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.lessonIndex.compareTo(b.lessonIndex);
      });
    final firstRowByStage = <String, int>{};
    final lastRowByStage = <String, int>{};
    final anchorsByStage = <String, Set<String>>{};
    for (var index = 0; index < orderedRows.length; index++) {
      final row = orderedRows[index];
      firstRowByStage.putIfAbsent(row.stageId, () => index);
      lastRowByStage[row.stageId] = index;
      anchorsByStage
          .putIfAbsent(row.stageId, () => {})
          .add('${row.periodTypeId}_${row.lessonIndex}');
    }
    final stageNames = {
      for (final stage in snapshot.stages) stage.id: stage.name,
    };
    final classNames = {
      for (final item in snapshot.classes) item.id: item.name,
    };
    final subjectNames = {
      for (final item in snapshot.subjects) item.id: item.name,
    };
    final teacherNames = {
      for (final item in snapshot.teachers) item.id: item.displayName,
    };
    final itemsByCell = <String, List<ScheduleItem>>{};
    for (final item in items) {
      final position = item.position!;
      final key =
          '${position.stageId}:${position.weekday}:${position.periodTypeId}:${position.lessonIndex}';
      itemsByCell.putIfAbsent(key, () => []).add(item);
    }
    return Container(
      decoration: _SchedulePalette.panel(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '课表安排',
                  style: TextStyle(
                    color: context.appColors.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '${_viewLabel(view)} · ${_weekLabel(week)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${items.length} 节课',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (days.isEmpty || orderedRows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('尚未设置可上课的节次。请先完成作息设置。'),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  key: viewportKey,
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(constraints.maxWidth, 680),
                    child: ValueListenableBuilder<String?>(
                      valueListenable: draggedItemId,
                      builder: (context, draggedId, _) {
                        final tableRows = <TableRow>[
                          TableRow(
                            children: [
                              _tableCell(context, '节次', header: true),
                              for (final day in days)
                                _tableCell(
                                  context,
                                  _dayLabel(day),
                                  header: true,
                                ),
                            ],
                          ),
                        ];
                        for (
                          var index = 0;
                          index < orderedRows.length;
                          index++
                        ) {
                          final row = orderedRows[index];
                          final stagePeriods =
                              commonPeriods[row.stageId] ??
                              const <CommonPeriod>[];
                          final firstStageRow =
                              firstRowByStage[row.stageId] == index;
                          final lastStageRow =
                              lastRowByStage[row.stageId] == index;
                          if (firstStageRow) {
                            for (final period in stagePeriods.where(
                              (period) => period.insertAfterLessonId == null,
                            )) {
                              tableRows.add(
                                _commonPeriodRow(
                                  context,
                                  period,
                                  days.length,
                                  routines.length > 1
                                      ? stageNames[row.stageId]
                                      : null,
                                ),
                              );
                            }
                          }
                          tableRows.add(
                            TableRow(
                              children: [
                                _periodCell(
                                  context,
                                  row,
                                  stageName: routines.length > 1
                                      ? stageNames[row.stageId]
                                      : null,
                                ),
                                for (final day in days)
                                  _dropCell(
                                    context,
                                    day,
                                    row,
                                    itemsByCell['${row.stageId}:$day:${row.periodTypeId}:${row.lessonIndex}'] ??
                                        const [],
                                    classNames,
                                    subjectNames,
                                    teacherNames,
                                    draggedId,
                                  ),
                              ],
                            ),
                          );
                          final anchor =
                              '${row.periodTypeId}_${row.lessonIndex}';
                          for (final period in stagePeriods.where(
                            (period) => period.insertAfterLessonId == anchor,
                          )) {
                            tableRows.add(
                              _commonPeriodRow(
                                context,
                                period,
                                days.length,
                                routines.length > 1
                                    ? stageNames[row.stageId]
                                    : null,
                              ),
                            );
                          }
                          if (lastStageRow) {
                            for (final period in stagePeriods.where(
                              (period) =>
                                  period.insertAfterLessonId != null &&
                                  !anchorsByStage[row.stageId]!.contains(
                                    period.insertAfterLessonId,
                                  ),
                            )) {
                              tableRows.add(
                                _commonPeriodRow(
                                  context,
                                  period,
                                  days.length,
                                  routines.length > 1
                                      ? stageNames[row.stageId]
                                      : null,
                                ),
                              );
                            }
                          }
                        }
                        return Table(
                          columnWidths: const {0: FixedColumnWidth(92)},
                          defaultColumnWidth: const FlexColumnWidth(),
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.top,
                          children: tableRows,
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tableCell(BuildContext context, String text, {bool header = false}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(3, 3, 3, 3),
        child: Container(
          constraints: BoxConstraints(minHeight: header ? 34 : 54),
          alignment: header ? Alignment.center : Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: header ? 4 : 2),
          child: Text(
            text,
            textAlign: header ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              height: 1.4,
              fontSize: header ? 12 : 11.5,
              color: header
                  ? context.appColors.inkSecondary
                  : context.appColors.ink,
              fontWeight: header ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );

  Widget _classOverview(BuildContext context, List<StageRoutine> routines) {
    final classNames = {
      for (final item in snapshot.classes) item.id: item.name,
    };
    final subjectNames = {
      for (final item in snapshot.subjects) item.id: item.name,
    };
    final teacherNames = {
      for (final item in snapshot.teachers) item.id: item.displayName,
    };
    final stageNames = {
      for (final stage in snapshot.stages) stage.id: stage.name,
    };
    final cells = <String, List<ScheduleItem>>{};
    for (final item in items) {
      final position = item.position;
      if (position == null) continue;
      final key =
          '${item.classId}:${position.periodTypeId}:${position.lessonIndex}';
      cells.putIfAbsent(key, () => []).add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final routine in routines) ...[
          Builder(
            builder: (context) {
              final classes = snapshot.classes
                  .where(
                    (item) =>
                        snapshot.stageIdForClass(item.id) == routine.stageId,
                  )
                  .toList();
              final periods = [...routine.periodTypes]
                ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
              final lessonLabels = <String, String>{};
              var daytimeCount = 0;
              for (final period in periods) {
                for (
                  var index = 1;
                  index <= period.defaultLessonCount;
                  index++
                ) {
                  final label = period.name.contains('早')
                      ? '早$index'
                      : period.name.contains('晚')
                      ? '晚$index'
                      : '第 ${++daytimeCount} 节';
                  lessonLabels['${period.id}_$index'] = label;
                }
              }
              final common =
                  commonPeriods[routine.stageId] ?? const <CommonPeriod>[];
              final columns = <({_GridRow? lesson, CommonPeriod? common})>[];
              for (final item in common.where(
                (item) => item.insertAfterLessonId == null,
              )) {
                columns.add((lesson: null, common: item));
              }
              if (routine.teachingWeekdays.contains(weekday)) {
                for (final period in periods) {
                  final count = routine.effectiveLessonCount(
                    period.id,
                    weekday,
                  );
                  for (var index = 1; index <= count; index++) {
                    final time = period.lessonTimes
                        .where((time) => time.lessonIndex == index)
                        .firstOrNull;
                    columns.add((
                      lesson: _GridRow(
                        routine.stageId,
                        period.id,
                        period.name,
                        index,
                        period.sortOrder,
                        0,
                        time?.startMinute,
                      ),
                      common: null,
                    ));
                    for (final item in common.where(
                      (item) =>
                          item.insertAfterLessonId == '${period.id}_$index',
                    )) {
                      columns.add((lesson: null, common: item));
                    }
                  }
                }
              }
              final gradeOrder = {
                for (final grade in snapshot.grades) grade.id: grade.sortOrder,
              };
              classes.sort((a, b) {
                final grade = (gradeOrder[a.gradeId] ?? 0).compareTo(
                  gradeOrder[b.gradeId] ?? 0,
                );
                return grade != 0 ? grade : a.sortOrder.compareTo(b.sortOrder);
              });
              return Container(
                key: ValueKey('schedule-stage-class-${routine.stageId}'),
                decoration: _SchedulePalette.panel(context),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stageNames[routine.stageId] ?? routine.stageId} · ${_dayLabel(weekday)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    if (columns.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('该学段当天没有课节'),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: math.max(
                              constraints.maxWidth,
                              150 + columns.length * 130.0,
                            ),
                            child: ValueListenableBuilder<String?>(
                              valueListenable: draggedItemId,
                              builder: (context, draggedId, _) => Table(
                                columnWidths: const {0: FixedColumnWidth(150)},
                                defaultColumnWidth: const FlexColumnWidth(),
                                defaultVerticalAlignment:
                                    TableCellVerticalAlignment.middle,
                                children: [
                                  TableRow(
                                    children: [
                                      _tableCell(context, '班级', header: true),
                                      for (final column in columns)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 4,
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                column.common?.name ??
                                                    lessonLabels['${column.lesson!.periodTypeId}_${column.lesson!.lessonIndex}'] ??
                                                    '第 ${column.lesson!.lessonIndex} 节',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: context
                                                      .appColors
                                                      .inkSecondary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (column.lesson?.startMinute
                                                  case final minute?)
                                                Text(
                                                  _minuteLabel(minute),
                                                  style: TextStyle(
                                                    color:
                                                        context.appColors.muted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              if (column.common?.startLabel
                                                  case final start?)
                                                Text(
                                                  start,
                                                  style: TextStyle(
                                                    color:
                                                        context.appColors.muted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  for (final schoolClass in classes)
                                    TableRow(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            schoolClass.name,
                                            style: TextStyle(
                                              color: context.appColors.ink,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        for (final column in columns)
                                          if (column.common
                                              case final commonPeriod?)
                                            Container(
                                              height: 60,
                                              alignment: Alignment.center,
                                              color:
                                                  context.appColors.tableHeader,
                                              child: Text(
                                                commonPeriod.name,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: context
                                                      .appColors
                                                      .inkSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          else if ((cells['${schoolClass.id}:${column.lesson!.periodTypeId}:${column.lesson!.lessonIndex}'] ??
                                                      const [])
                                                  .isEmpty &&
                                              _freeLabelForClass(
                                                    snapshot,
                                                    schoolClass,
                                                    routine.stageId,
                                                    weekday,
                                                    column.lesson!,
                                                  ) !=
                                                  null)
                                            Container(
                                              height: 60,
                                              alignment: Alignment.center,
                                              child: Text(
                                                _freeLabelForClass(
                                                  snapshot,
                                                  schoolClass,
                                                  routine.stageId,
                                                  weekday,
                                                  column.lesson!,
                                                )!,
                                                style: TextStyle(
                                                  color:
                                                      context.appColors.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          else
                                            _dropCell(
                                              context,
                                              weekday,
                                              column.lesson!,
                                              cells['${schoolClass.id}:${column.lesson!.periodTypeId}:${column.lesson!.lessonIndex}'] ??
                                                  const [],
                                              classNames,
                                              subjectNames,
                                              teacherNames,
                                              draggedId,
                                              classOverviewCell: true,
                                              targetClassId: schoolClass.id,
                                            ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (classes.isEmpty)
                      Text(
                        '该学段暂无班级',
                        style: TextStyle(color: context.appColors.muted),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        if (routines.isEmpty) const Text('尚未设置学段作息。'),
      ],
    );
  }

  String? _freeLabelForClass(
    SchedulingSnapshot snapshot,
    ClassGroup schoolClass,
    String stageId,
    int weekday,
    _GridRow row,
  ) {
    FreeSlot? best;
    var bestPriority = 0;
    for (final slot in snapshot.freeSlots) {
      if (slot.stageId != stageId ||
          slot.weekday != weekday ||
          slot.periodTypeId != row.periodTypeId ||
          slot.lessonIndex != row.lessonIndex) {
        continue;
      }
      final priority = switch (slot.scope) {
        FreeSlotScope.school => slot.scopeId == snapshot.term.id ? 1 : 0,
        FreeSlotScope.stage => slot.scopeId == stageId ? 2 : 0,
        FreeSlotScope.grade => slot.scopeId == schoolClass.gradeId ? 3 : 0,
        FreeSlotScope.schoolClass => slot.scopeId == schoolClass.id ? 4 : 0,
      };
      if (priority > bestPriority) {
        best = slot;
        bestPriority = priority;
      }
    }
    return best?.label;
  }

  Widget _periodCell(
    BuildContext context,
    _GridRow row, {
    String? stageName,
  }) => TableCell(
    verticalAlignment: TableCellVerticalAlignment.fill,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(2, 3, 8, 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stageName == null
                ? _shortPeriodName(row.periodName)
                : '$stageName · ${_shortPeriodName(row.periodName)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.appColors.ink,
              fontSize: stageName == null ? 12 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '第 ${row.lessonIndex} 节${row.startMinute == null ? '' : ' · ${_minuteLabel(row.startMinute!)}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.appColors.muted, fontSize: 11.5),
          ),
        ],
      ),
    ),
  );

  TableRow _commonPeriodRow(
    BuildContext context,
    CommonPeriod period,
    int dayCount,
    String? stageName,
  ) => TableRow(
    decoration: BoxDecoration(
      color: context.appColors.tableHeader,
      borderRadius: BorderRadius.circular(6),
    ),
    children: [
      SizedBox(
        height: 26,
        child: Center(
          child: Text(
            stageName ?? '',
            style: TextStyle(color: context.appColors.muted, fontSize: 11),
          ),
        ),
      ),
      for (var day = 0; day < dayCount; day++)
        SizedBox(
          height: 26,
          child: day == dayCount ~/ 2
              ? Center(
                  child: Text(
                    period.name,
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11.5,
                    ),
                  ),
                )
              : null,
        ),
    ],
  );

  Widget _dropCell(
    BuildContext context,
    int weekday,
    _GridRow row,
    List<ScheduleItem> cellItems,
    Map<String, String> classNames,
    Map<String, String> subjectNames,
    Map<String, String> teacherNames,
    String? draggedId, {
    bool classOverviewCell = false,
    String? targetClassId,
  }) {
    Widget content() => _lessonCell(
      context,
      cellItems,
      classNames,
      subjectNames,
      teacherNames,
      classOverviewCell: classOverviewCell,
    );
    if (!editable) return content();
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        if (targetClassId != null &&
            allItems
                    .where((item) => item.id == details.data)
                    .firstOrNull
                    ?.classId !=
                targetClassId) {
          return false;
        }
        final target = _targetFor(details.data, weekday, row);
        if (target == null) return false;
        final swapWithItemId = cellItems.length == 1
            ? cellItems.single.id
            : null;
        final preview = onPreviewMove(details.data, target, swapWithItemId);
        return preview.allowed && preview.changedItemIds.isNotEmpty;
      },
      onAcceptWithDetails: (details) {
        if (targetClassId != null &&
            allItems
                    .where((item) => item.id == details.data)
                    .firstOrNull
                    ?.classId !=
                targetClassId) {
          return;
        }
        final target = _targetFor(details.data, weekday, row);
        final swapWithItemId = cellItems.length == 1
            ? cellItems.single.id
            : null;
        if (target == null) return;
        final preview = onPreviewMove(details.data, target, swapWithItemId);
        if (preview.allowed && preview.changedItemIds.isNotEmpty) {
          unawaited(onMove(details.data, target, swapWithItemId));
        }
      },
      builder: (context, candidates, rejected) {
        final itemId = [...candidates, ...rejected].firstOrNull;
        final sourceId = itemId ?? draggedId;
        final differentClass =
            targetClassId != null &&
            sourceId != null &&
            allItems
                    .where((item) => item.id == sourceId)
                    .firstOrNull
                    ?.classId !=
                targetClassId;
        final target = sourceId == null || differentClass
            ? null
            : _targetFor(sourceId, weekday, row);
        final preview = sourceId == null || target == null
            ? null
            : onPreviewMove(
                sourceId,
                target,
                cellItems.length == 1 ? cellItems.single.id : null,
              );
        final canDrop =
            preview?.allowed == true && preview!.changedItemIds.isNotEmpty;
        final hint = target == null
            ? '该班级没有此节次'
            : canDrop
            ? '可以调入'
            : preview?.allowed == true
            ? '课程已在当前课位'
            : preview?.blockers.firstOrNull?.message ?? '此位置不可调入';
        return _DropCellFeedback(
          active: itemId != null,
          dragging: sourceId != null,
          allowed: canDrop,
          message: hint,
          child: content(),
        );
      },
    );
  }

  SchedulePosition? _targetFor(String itemId, int weekday, _GridRow row) {
    final source = allItems.where((item) => item.id == itemId).firstOrNull;
    if (source == null) return null;
    final routine = snapshot.routines
        .where((item) => item.stageId == row.stageId)
        .firstOrNull;
    if (routine == null || !routine.teachingWeekdays.contains(weekday)) {
      return null;
    }
    final period = routine.periodTypes
        .where((item) => item.id == row.periodTypeId)
        .firstOrNull;
    if (period == null ||
        row.lessonIndex > routine.effectiveLessonCount(period.id, weekday)) {
      return null;
    }
    final time = period.lessonTimes
        .where((item) => item.lessonIndex == row.lessonIndex)
        .firstOrNull;
    return SchedulePosition(
      stageId: row.stageId,
      weekday: weekday,
      periodTypeId: period.id,
      lessonIndex: row.lessonIndex,
      startMinute: time?.startMinute,
      endMinute: time?.endMinute,
    );
  }

  Widget _lessonCell(
    BuildContext context,
    List<ScheduleItem> cellItems,
    Map<String, String> classNames,
    Map<String, String> subjectNames,
    Map<String, String> teacherNames, {
    bool classOverviewCell = false,
  }) {
    if (cellItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(3),
        child: CustomPaint(
          painter: _DashedOutline(color: context.appColors.border),
          child: const SizedBox(height: 54),
        ),
      );
    }
    final first = cellItems.first;
    final subjectForeground = SubjectColors.of(context, first.subjectId);
    final subjectBackground = SubjectColors.cellBackground(
      context,
      first.subjectId,
    );
    final sameMeeting =
        first.meetingId != null &&
        cellItems.every((item) => item.meetingId == first.meetingId);
    final displayView = classOverviewCell ? _ScheduleView.schoolClass : view;
    final wholeCellDrag =
        displayView != _ScheduleView.all &&
        cellItems.length <= 3 &&
        (cellItems.length == 1 || sameMeeting);
    final card = Padding(
      padding: const EdgeInsets.all(3),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: subjectBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: displayView == _ScheduleView.all || cellItems.length > 3
              ? [
                  _AllLessonsCell(
                    items: cellItems,
                    classNames: classNames,
                    subjectNames: subjectNames,
                    teacherNames: teacherNames,
                    editable: editable,
                    draggedItemId: draggedItemId,
                    onPreviewMove: onPreviewMove,
                    onMove: onMove,
                  ),
                ]
              : [
                  for (final item in cellItems.take(3)) ...[
                    if (item != first) const SizedBox(height: 5),
                    if (wholeCellDrag)
                      _lessonSummary(
                        '${_weekPrefix(item)}${switch (displayView) {
                          _ScheduleView.schoolClass || _ScheduleView.room => subjectNames[item.subjectId] ?? item.subjectId,
                          _ScheduleView.teacher => classNames[item.classId] ?? item.classId,
                          _ScheduleView.all => '',
                        }}',
                        switch (displayView) {
                          _ScheduleView.schoolClass =>
                            teacherNames[item.teacherId] ?? item.teacherId,
                          _ScheduleView.teacher =>
                            subjectNames[item.subjectId] ?? item.subjectId,
                          _ScheduleView.room =>
                            classNames[item.classId] ?? item.classId,
                          _ScheduleView.all => '',
                        },
                        subjectForeground,
                      )
                    else
                      _draggableItem(
                        item,
                        '${classNames[item.classId] ?? item.classId} · ${subjectNames[item.subjectId] ?? item.subjectId}',
                        _lessonSummary(
                          '${_weekPrefix(item)}${switch (displayView) {
                            _ScheduleView.schoolClass || _ScheduleView.room => subjectNames[item.subjectId] ?? item.subjectId,
                            _ScheduleView.teacher => classNames[item.classId] ?? item.classId,
                            _ScheduleView.all => '',
                          }}',
                          switch (displayView) {
                            _ScheduleView.schoolClass =>
                              teacherNames[item.teacherId] ?? item.teacherId,
                            _ScheduleView.teacher =>
                              subjectNames[item.subjectId] ?? item.subjectId,
                            _ScheduleView.room =>
                              classNames[item.classId] ?? item.classId,
                            _ScheduleView.all => '',
                          },
                          subjectForeground,
                        ),
                        subjectBackground,
                      ),
                  ],
                ],
        ),
      ),
    );
    if (!wholeCellDrag || !editable) return card;
    return _draggableItem(
      first,
      '${classNames[first.classId] ?? first.classId} · ${subjectNames[first.subjectId] ?? first.subjectId}',
      card,
      subjectBackground,
    );
  }

  Widget _draggableItem(
    ScheduleItem item,
    String label,
    Widget child,
    Color feedbackColor,
  ) {
    if (!editable) return child;
    return _LessonDragHandle(
      item: item,
      label: label,
      feedbackColor: feedbackColor,
      draggedItemId: draggedItemId,
      onPreviewMove: onPreviewMove,
      onMove: onMove,
      child: SizedBox(width: double.infinity, child: child),
    );
  }

  Widget _lessonSummary(String headline, String detail, Color foreground) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground.withValues(alpha: .72),
              fontSize: 11.5,
            ),
          ),
        ],
      );
}

class _LessonDragHandle extends StatefulWidget {
  const _LessonDragHandle({
    required this.item,
    required this.label,
    required this.feedbackColor,
    required this.draggedItemId,
    required this.onPreviewMove,
    required this.onMove,
    required this.child,
  });

  final ScheduleItem item;
  final String label;
  final Color feedbackColor;
  final ValueNotifier<String?> draggedItemId;
  final ManualMoveResult Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onPreviewMove;
  final Future<ManualMoveResult> Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onMove;
  final Widget child;

  @override
  State<_LessonDragHandle> createState() => _LessonDragHandleState();
}

class _LessonDragHandleState extends State<_LessonDragHandle> {
  bool _hovered = false;
  Offset _menuOffset = Offset.zero;

  void _showContextMenu(TapDownDetails details, FPopoverController controller) {
    setState(() => _menuOffset = details.localPosition);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(controller.show());
    });
  }

  @override
  Widget build(BuildContext context) {
    final lesson = Container(
      decoration: BoxDecoration(
        color: _hovered ? context.appColors.blue.withValues(alpha: .08) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      foregroundDecoration: _hovered
          ? BoxDecoration(
              border: Border.all(
                color: context.appColors.blue.withValues(alpha: .72),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: widget.child,
    );
    return FPopoverMenu(
      menuAnchor: Alignment.topLeft,
      childAnchor: Alignment.topLeft,
      offset: _menuOffset,
      menuBuilder: (context, controller, menu) {
        final preview = widget.onPreviewMove(widget.item.id, null, null);
        return [
          FItemGroup(
            divider: .none,
            children: [
              AppMenuTile(
                item: AppMenuItem(
                  label: '移到暂放区',
                  enabled: preview.allowed,
                  onPressed: () {
                    unawaited(controller.hide());
                    unawaited(widget.onMove(widget.item.id, null, null));
                  },
                ),
              ),
              if (!preview.allowed)
                FItem.raw(
                  onPress: null,
                  child: SizedBox(
                    width: 220,
                    child: Text(
                      preview.blockers.firstOrNull?.message ?? '这节课不能暂放',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ];
      },
      builder: (context, controller, child) => MouseRegion(
        cursor: SystemMouseCursors.grab,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: widget.item.isPlaced
              ? (details) => _showContextMenu(details, controller)
              : null,
          child: Draggable<String>(
            data: widget.item.id,
            onDragStarted: () => widget.draggedItemId.value = widget.item.id,
            onDragEnd: (_) {
              if (widget.draggedItemId.value == widget.item.id) {
                widget.draggedItemId.value = null;
              }
            },
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: 176,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: widget.feedbackColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: .35, child: lesson),
            child: lesson,
          ),
        ),
      ),
    );
  }
}

class _DropCellFeedback extends StatefulWidget {
  const _DropCellFeedback({
    required this.active,
    required this.dragging,
    required this.allowed,
    required this.message,
    required this.child,
  });

  final bool active;
  final bool dragging;
  final bool allowed;
  final String message;
  final Widget child;

  @override
  State<_DropCellFeedback> createState() => _DropCellFeedbackState();
}

class _DropCellFeedbackState extends State<_DropCellFeedback> {
  final _layerLink = LayerLink();
  OverlayEntry? _hintEntry;

  @override
  void initState() {
    super.initState();
    if (widget.active) _scheduleOverlayUpdate();
  }

  @override
  void didUpdateWidget(covariant _DropCellFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active ||
        widget.allowed != oldWidget.allowed ||
        widget.message != oldWidget.message) {
      _scheduleOverlayUpdate();
    }
  }

  void _scheduleOverlayUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.active) {
        _showHint();
      } else {
        _hideHint();
      }
    });
  }

  void _showHint() {
    if (_hintEntry != null) {
      _hintEntry!.markNeedsBuild();
      return;
    }
    _hintEntry = OverlayEntry(
      builder: (context) {
        final color = widget.allowed
            ? context.appColors.success
            : context.appColors.warning;
        return Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: const Offset(0, -4),
              child: _DropHintBubble(
                message: widget.message,
                color: color,
                allowed: widget.allowed,
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_hintEntry!);
  }

  void _hideHint() {
    _hintEntry?.remove();
    _hintEntry?.dispose();
    _hintEntry = null;
  }

  @override
  void dispose() {
    _hideHint();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.allowed
        ? context.appColors.success
        : widget.active
        ? context.appColors.warning
        : context.appColors.border;
    return CompositedTransformTarget(
      link: _layerLink,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (widget.dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: widget.allowed
                        ? context.appColors.success.withValues(alpha: .08)
                        : context.appColors.tableHeader.withValues(alpha: .88),
                    border: Border.all(
                      color: color,
                      width: widget.active ? 1.8 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: widget.allowed
                      ? null
                      : Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Icon(
                              Icons.block_outlined,
                              size: 15,
                              color: context.appColors.muted.withValues(
                                alpha: .85,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DropHintBubble extends StatelessWidget {
  const _DropHintBubble({
    required this.message,
    required this.color,
    required this.allowed,
  });

  final String message;
  final Color color;
  final bool allowed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 250),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            border: Border.all(color: color.withValues(alpha: .55)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allowed ? Icons.check_circle_outline : Icons.info_outline,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  message,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appColors.ink,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(12, 7),
          painter: _BubbleTailPainter(color, context.appColors.surface),
        ),
      ],
    ),
  );
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter(this.color, this.surface);

  final Color color;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = surface);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .55)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      color != oldDelegate.color || surface != oldDelegate.surface;
}

class _GridRow {
  const _GridRow(
    this.stageId,
    this.periodTypeId,
    this.periodName,
    this.lessonIndex,
    this.sortOrder,
    this.stageOrder,
    this.startMinute,
  );
  final String stageId;
  final String periodTypeId;
  final String periodName;
  final int lessonIndex;
  final int sortOrder;
  final int stageOrder;
  final int? startMinute;
}

class _DashedOutline extends CustomPainter {
  const _DashedOutline({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    for (final metric in path.computeMetrics()) {
      var offset = 0.0;
      while (offset < metric.length) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + 5, metric.length)),
          paint,
        );
        offset += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedOutline oldDelegate) =>
      color != oldDelegate.color;
}

class _AllLessonsCell extends StatefulWidget {
  const _AllLessonsCell({
    required this.items,
    required this.classNames,
    required this.subjectNames,
    required this.teacherNames,
    required this.editable,
    required this.draggedItemId,
    required this.onPreviewMove,
    required this.onMove,
  });

  final List<ScheduleItem> items;
  final Map<String, String> classNames;
  final Map<String, String> subjectNames;
  final Map<String, String> teacherNames;
  final bool editable;
  final ValueNotifier<String?> draggedItemId;
  final ManualMoveResult Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onPreviewMove;
  final Future<ManualMoveResult> Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onMove;

  @override
  State<_AllLessonsCell> createState() => _AllLessonsCellState();
}

class _AllLessonsCellState extends State<_AllLessonsCell> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = _expanded
        ? widget.items.length
        : math.min(3, widget.items.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.items.length} 节课程',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: math.min(count * 38.0, 220.0),
          child: ListView.builder(
            itemCount: count,
            itemBuilder: (context, index) {
              final item = widget.items[index];
              final label =
                  '${_weekPrefix(item)}${widget.classNames[item.classId] ?? item.classId} · ${widget.subjectNames[item.subjectId] ?? item.subjectId}';
              final detail =
                  widget.teacherNames[item.teacherId] ?? item.teacherId;
              final child = Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appColors.inkSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
              if (!widget.editable) return child;
              return _LessonDragHandle(
                item: item,
                label: label,
                feedbackColor: SubjectColors.cellBackground(
                  context,
                  item.subjectId,
                ),
                draggedItemId: widget.draggedItemId,
                onPreviewMove: widget.onPreviewMove,
                onMove: widget.onMove,
                child: child,
              );
            },
          ),
        ),
        if (widget.items.length > 3)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.blue,
              padding: const EdgeInsets.symmetric(vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text(
              _expanded ? '收起' : '查看全部 ${widget.items.length} 节',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class _RightRail extends StatelessWidget {
  const _RightRail({
    required this.snapshot,
    required this.stageId,
    required this.state,
    required this.week,
    required this.onRefresh,
    required this.onReport,
    required this.onDetectionReport,
    required this.editable,
    required this.draggedItemId,
    required this.groupBySubject,
    required this.onToggleGrouping,
    required this.onPreviewMove,
    required this.onMove,
    required this.onPlaceUnplaced,
  });

  final SchedulingSnapshot snapshot;
  final String? stageId;
  final SchedulingState state;
  final _WeekView week;
  final VoidCallback onRefresh;
  final VoidCallback onReport;
  final VoidCallback onDetectionReport;
  final bool editable;
  final ValueNotifier<String?> draggedItemId;
  final bool groupBySubject;
  final VoidCallback onToggleGrouping;
  final Future<int?> Function(Set<String>)? onPlaceUnplaced;
  final ManualMoveResult Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onPreviewMove;
  final Future<ManualMoveResult> Function(
    String itemId,
    SchedulePosition? target,
    String? swapWithItemId,
  )
  onMove;

  @override
  Widget build(BuildContext context) {
    final unplaced = state.items
        .where(
          (item) =>
              !item.isPlaced &&
              (stageId == null ||
                  snapshot.stageIdForClass(item.classId) == stageId) &&
              (week == _WeekView.merged ||
                  (week == _WeekView.odd && item.weekMode != WeekMode.even) ||
                  (week == _WeekView.even && item.weekMode != WeekMode.odd)),
        )
        .toList();
    final blockers = {
      for (final entry in state.run?.report.unplaced ?? const [])
        entry.itemId: entry.blockers,
    };
    final classNames = {
      for (final item in snapshot.classes) item.id: item.name,
    };
    final subjectNames = {
      for (final item in snapshot.subjects) item.id: item.name,
    };
    final teacherNames = {
      for (final item in snapshot.teachers) item.id: item.displayName,
    };
    unplaced.sort((a, b) {
      final left = groupBySubject
          ? '${subjectNames[a.subjectId]}:${classNames[a.classId]}'
          : '${classNames[a.classId]}:${subjectNames[a.subjectId]}';
      final right = groupBySubject
          ? '${subjectNames[b.subjectId]}:${classNames[b.classId]}'
          : '${classNames[b.classId]}:${subjectNames[b.subjectId]}';
      return left.compareTo(right);
    });
    final preflightIssues = state.checks
        .where((check) => !check.ready || check.code == 'capacity')
        .toList();
    final detectionIssues = state.detectionIssues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DragTarget<String>(
          onWillAcceptWithDetails: (details) =>
              editable && onPreviewMove(details.data, null, null).allowed,
          onAcceptWithDetails: (details) {
            if (onPreviewMove(details.data, null, null).allowed) {
              unawaited(onMove(details.data, null, null));
            }
          },
          builder: (context, candidates, rejected) {
            final itemId = [...candidates, ...rejected].firstOrNull;
            final preview = itemId == null
                ? null
                : onPreviewMove(itemId, null, null);
            final canDrop = preview?.allowed == true;
            return _RailCard(
              title: '暂放区',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${unplaced.length} 节',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11.5,
                    ),
                  ),
                  if (unplaced.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: onToggleGrouping,
                      style: TextButton.styleFrom(
                        foregroundColor: context.appColors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        groupBySubject ? '按班级排列' : '按科目聚合',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (itemId != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            (canDrop
                                    ? context.appColors.success
                                    : context.appColors.warning)
                                .withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        canDrop
                            ? '松开后移入暂放区'
                            : preview?.blockers.firstOrNull?.message ??
                                  '这节课不能暂放',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (unplaced.isEmpty)
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 96),
                      decoration: BoxDecoration(
                        color: context.appColors.tableHeader,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CustomPaint(
                        painter: _DashedOutline(
                          color: context.appColors.border,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.file_upload_outlined,
                              size: 22,
                              color: context.appColors.muted,
                            ),
                            SizedBox(height: 6),
                            Text(
                              '拖拽课程卡片到此处暂存',
                              style: TextStyle(
                                color: context.appColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    SizedBox(
                      height: math.min(unplaced.length * 88.0, 320.0),
                      child: ListView.builder(
                        itemCount: unplaced.length,
                        itemBuilder: (context, index) {
                          final item = unplaced[index];
                          final title =
                              '${subjectNames[item.subjectId] ?? item.subjectId} · ${classNames[item.classId] ?? item.classId}';
                          final detail =
                              teacherNames[item.teacherId] ?? item.teacherId;
                          final subjectColor = SubjectColors.of(
                            context,
                            item.subjectId,
                          );
                          final lesson = Container(
                            key: ValueKey('unplaced-card-${item.id}'),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: SubjectColors.cellBackground(
                                context,
                                item.subjectId,
                              ),
                              border: Border.all(
                                color: subjectColor.withValues(alpha: .32),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.drag_indicator,
                                  size: 17,
                                  color: editable
                                      ? subjectColor.withValues(alpha: .75)
                                      : context.appColors.muted,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_weekPrefix(item)}$title',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: subjectColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$detail · ${blockers[item.id]?.firstOrNull == null ? '手工暂放或尚未安排' : '上次自动排课：${blockers[item.id]!.first.message}'}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: context.appColors.inkSecondary,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (!editable) return lesson;
                          return MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Draggable<String>(
                              data: item.id,
                              onDragStarted: () =>
                                  draggedItemId.value = item.id,
                              onDragEnd: (_) {
                                if (draggedItemId.value == item.id) {
                                  draggedItemId.value = null;
                                }
                              },
                              feedback: Material(
                                color: Colors.transparent,
                                child: Container(
                                  width: 200,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: context.appColors.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: .12,
                                        ),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                  child: Text(title),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: .35,
                                child: lesson,
                              ),
                              child: lesson,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (onPlaceUnplaced != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: context.appColors.blue,
                              backgroundColor: context.appColors.selectedBlue,
                              disabledForegroundColor: context.appColors.muted,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              minimumSize: const Size(0, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: !editable
                                ? null
                                : () async {
                                    final count = await onPlaceUnplaced!(
                                      unplaced.map((item) => item.id).toSet(),
                                    );
                                    if (!context.mounted) return;
                                    if (count == null) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text('一键放入失败，请刷新课表后重试。'),
                                            ),
                                          );
                                      return;
                                    }
                                    final remaining = unplaced.length - count;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          count == 0
                                              ? '没有找到符合条件的空位置，课程仍在暂放区。'
                                              : '已放入 $count 节，剩余 $remaining 节；已排课程位置保持不变。',
                                        ),
                                      ),
                                    );
                                  },
                            child: const Text('一键放入'),
                          ),
                        TextButton(
                          onPressed: onReport,
                          style: TextButton.styleFrom(
                            foregroundColor: context.appColors.inkSecondary,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: const Text('查看未排课程报告'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        _RailCard(
          title: '检测结果',
          trailing: AppGhostButton(
            onPressed: onRefresh,
            child: const Text('重新检测'),
          ),
          child: preflightIssues.isEmpty && detectionIssues.isEmpty
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: context.appColors.success,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.detectionRan ? '未发现课表硬约束冲突' : '点击检测，核对整张课表',
                        style: TextStyle(
                          color: context.appColors.inkSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final message in [
                      ...preflightIssues.map((check) => check.message),
                      ...detectionIssues.map((issue) => issue.message),
                    ].take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 17,
                              color: context.appColors.warning,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                message,
                                style: TextStyle(
                                  color: context.appColors.inkSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (preflightIssues.length + detectionIssues.length > 3)
                      Text(
                        '还有 ${preflightIssues.length + detectionIssues.length - 3} 项需要查看',
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    if (detectionIssues.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      AppGhostButton(
                        onPressed: onDetectionReport,
                        child: Text('查看全部 ${detectionIssues.length} 项检测结果'),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    decoration: _SchedulePalette.panel(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: context.appColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );
}

String? _roomIdFor(SchedulingSnapshot snapshot, ScheduleItem item) {
  final stageId = snapshot.stageIdForClass(item.classId);
  final gradeId = snapshot.gradeIdForClass(item.classId);
  if (stageId == null) return null;
  return resolveSubjectRoomAssignment(
    assignments: snapshot.roomAssignments,
    subjectId: item.subjectId,
    termId: snapshot.term.id,
    stageId: stageId,
    scope: FreeSlotScope.schoolClass,
    scopeId: item.classId,
    parentGradeId: gradeId,
  )?.roomId;
}

String _stageName(SchedulingSnapshot snapshot, String classId) {
  final stageId = snapshot.stageIdForClass(classId);
  for (final stage in snapshot.stages) {
    if (stage.id == stageId) return stage.name;
  }
  return '';
}

String _gradeName(SchedulingSnapshot snapshot, String classId) {
  final gradeId = snapshot.gradeIdForClass(classId);
  for (final grade in snapshot.grades) {
    if (grade.id == gradeId) return grade.name;
  }
  return '';
}

String _viewLabel(_ScheduleView view) => switch (view) {
  _ScheduleView.schoolClass => '班级课程表',
  _ScheduleView.teacher => '教师课程表',
  _ScheduleView.all => '总课程表',
  _ScheduleView.room => '场室课程表',
};

String _weekLabel(_WeekView week) => switch (week) {
  _WeekView.merged => '单双周合并',
  _WeekView.odd => '单周',
  _WeekView.even => '双周',
};

String _weekPrefix(ScheduleItem item) => switch (item.weekMode) {
  WeekMode.weekly => '',
  WeekMode.odd => '单周 · ',
  WeekMode.even => '双周 · ',
};

String _dayLabel(int day) => switch (day) {
  1 => '周一',
  2 => '周二',
  3 => '周三',
  4 => '周四',
  5 => '周五',
  6 => '周六',
  _ => '周日',
};

String _minuteLabel(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

String _shortPeriodName(String name) => name.endsWith('时段') && name.length > 2
    ? name.substring(0, name.length - 2)
    : name;

Map<String, String> _uniqueSelectorItems(Iterable<(String, String)> entries) {
  final items = <String, String>{};
  for (final (rawLabel, id) in entries) {
    final label = rawLabel.trim().isEmpty ? '未命名' : rawLabel.trim();
    var uniqueLabel = label;
    var number = 2;
    while (items.containsKey(uniqueLabel)) {
      uniqueLabel = '$label（$number）';
      number++;
    }
    items[uniqueLabel] = id;
  }
  return items;
}
