part of 'supervision_page.dart';

typedef _PostSlot = ({int weekday, String periodId, int index});
typedef _PostBlock = ({int weekday, String periodId, List<int> indices});

class _PostDialog extends StatefulWidget {
  const _PostDialog({
    required this.snapshot,
    required this.draft,
    required this.seed,
  });

  final SchedulingSnapshot snapshot;
  final SupervisionDraft draft;
  final SupervisionSeed? seed;

  @override
  State<_PostDialog> createState() => _PostDialogState();
}

class _PostDialogState extends State<_PostDialog> {
  late String? _stageId =
      widget.seed?.stageId ?? widget.snapshot.stages.firstOrNull?.id;
  late final _slots = <_PostSlot>{
    if (widget.seed case final seed?)
      (
        weekday: seed.weekday,
        periodId: seed.periodTypeId,
        index: seed.lessonIndex,
      ),
  };
  late final _classes = <String>{
    for (final group in widget.snapshot.classes)
      if (_seedIncludes(group.id, group.gradeId)) group.id,
  };
  late final _expandedStages = <String>{?_stageId};
  late final _expandedGrades = <String>{};
  final _classSearch = TextEditingController();
  final _name = TextEditingController();
  final _groupName = TextEditingController();
  final _location = TextEditingController();
  final _horizontal = ScrollController();
  late SupervisionKind _kind = _initialKind();
  _PersonnelSettings _personnel = (
    poolId: null,
    preferences: null,
    subjects: <String>{},
  );
  bool _merged = false;
  bool _continuous = false;
  String? _classError;
  String? _slotError;
  String? _activityNameError;
  String? _groupNameError;
  String? _locationError;
  List<String> _scheduleErrors = const [];
  final _slotReasons = <_PostSlot, String?>{};
  final _occupiedByClass = <String, List<SchedulePosition>>{};

  @override
  void initState() {
    super.initState();
    const validator = SupervisionValidation();
    for (final post in widget.draft.posts) {
      final positions = validator.positions(widget.snapshot, post);
      for (final id in post.classIds) {
        (_occupiedByClass[id] ??= []).addAll(positions);
      }
    }
    _pruneSlots();
  }

  StageRoutine? get _routine => widget.snapshot.routines
      .where((routine) => routine.stageId == _stageId)
      .firstOrNull;

  bool _seedIncludes(String classId, String gradeId) {
    final seed = widget.seed;
    if (seed == null ||
        !widget.snapshot.grades.any(
          (grade) => grade.id == gradeId && grade.stageId == seed.stageId,
        )) {
      return false;
    }
    return switch (seed.scope) {
      FreeSlotScope.school || FreeSlotScope.stage => true,
      FreeSlotScope.grade => gradeId == seed.scopeId,
      FreeSlotScope.schoolClass => classId == seed.scopeId,
    };
  }

  SupervisionKind _initialKind() {
    final name = _routine?.periodTypes
        .where((period) => period.id == widget.seed?.periodTypeId)
        .firstOrNull
        ?.name;
    if (name?.contains('晚') ?? false) return SupervisionKind.eveningStudy;
    if (name?.contains('早') ?? false) return SupervisionKind.morningStudy;
    return SupervisionKind.afterSchool;
  }

  @override
  void dispose() {
    _name.dispose();
    _groupName.dispose();
    _location.dispose();
    _classSearch.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Widget _validationMessage(String message) => Text(
    message,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.appColors.destructive, fontSize: 11),
  );

  void _clearSelectionErrors() {
    _classError = null;
    _slotError = null;
    _scheduleErrors = const [];
  }

  void _toggleScope(String stageId, List<String> ids) => setState(() {
    if (_stageId != stageId) {
      _stageId = stageId;
      _classes.clear();
      _slots.clear();
      _clearSelectionErrors();
      _expandedStages.add(stageId);
      _expandedGrades.addAll(
        widget.snapshot.grades
            .where((grade) => grade.stageId == stageId)
            .map((grade) => grade.id),
      );
    }
    if (ids.isNotEmpty && ids.every(_classes.contains)) {
      _classes.removeAll(ids);
    } else {
      _classes.addAll(ids);
      _expandedGrades.addAll(
        widget.snapshot.grades
            .where(
              (grade) =>
                  grade.stageId == stageId &&
                  widget.snapshot.classes.any(
                    (group) =>
                        group.gradeId == grade.id && ids.contains(group.id),
                  ),
            )
            .map((grade) => grade.id),
      );
    }
    _clearSelectionErrors();
    _pruneSlots();
  });

  void _toggleSlots(Iterable<_PostSlot> slots) => setState(() {
    final available = _availableSlots.toSet();
    final values = slots.where(available.contains).toList();
    if (values.every(_slots.contains)) {
      _slots.removeAll(values);
    } else {
      _slots.addAll(values);
    }
    _slotError = null;
    _scheduleErrors = const [];
  });

  void _pruneSlots() {
    _slotReasons.clear();
    _slots.removeWhere((slot) => _slotReason(slot) != null);
  }

  // A period name does not determine eligibility. Resolve each selected class's
  // effective routine marker, including school/grade defaults and class overrides.
  String? _slotReason(_PostSlot slot) => _slotReasons.putIfAbsent(slot, () {
    final routine = _routine;
    if (routine == null ||
        !routine.teachingWeekdays.contains(slot.weekday) ||
        !routine.periodTypes.any((period) => period.id == slot.periodId) ||
        slot.index < 1 ||
        slot.index >
            routine.effectiveLessonCount(slot.periodId, slot.weekday)) {
      return '—';
    }
    if (_classes.isEmpty) return '—';
    var regular = 0;
    final otherLabels = <String>{};
    final markers = widget.snapshot.freeSlots
        .where(
          (marker) =>
              marker.stageId == _stageId &&
              marker.weekday == slot.weekday &&
              marker.periodTypeId == slot.periodId &&
              marker.lessonIndex == slot.index,
        )
        .toList();
    for (final classId in _classes) {
      final marker = resolveFreeSlotsForView(
        markers,
        viewScope: FreeSlotScope.schoolClass,
        viewScopeId: classId,
        termId: widget.draft.termId,
        stageId: _stageId!,
        weekday: slot.weekday,
        periodTypeId: slot.periodId,
        lessonIndex: slot.index,
        classGradeId: widget.snapshot.gradeIdForClass(classId),
      ).full;
      if (marker == null) {
        regular++;
      } else if (!marker.allowsSupervision) {
        otherLabels.add(marker.label);
      }
    }
    if (regular > 0) return regular == _classes.length ? '正课' : '含正课';
    if (otherLabels.isNotEmpty) {
      return otherLabels.join(' / ');
    }
    final position = const SupervisionValidation().withRoutineClock(
      widget.snapshot,
      SchedulePosition(
        stageId: _stageId!,
        weekday: slot.weekday,
        periodTypeId: slot.periodId,
        lessonIndex: slot.index,
      ),
    );
    final occupied = _classes
        .where((id) => _occupiedByClass[id]?.any(position.overlaps) ?? false)
        .length;
    if (occupied > 0) return occupied == _classes.length ? '已有岗位' : '含已有岗位';
    return null;
  });

  List<_PostSlot> get _availableSlots =>
      _routineSlots.where((slot) => _slotReason(slot) == null).toList();

  List<_PostSlot> get _routineSlots {
    final routine = _routine;
    if (routine == null) return const [];
    return [
      for (final day in (routine.teachingWeekdays.toList()..sort()))
        for (final period
            in (routine.periodTypes.toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))))
          for (
            var index = 1;
            index <= routine.effectiveLessonCount(period.id, day);
            index++
          )
            (weekday: day, periodId: period.id, index: index),
    ];
  }

  List<_PostBlock> get _blocks {
    final blocks = <_PostBlock>[];
    for (final day
        in (_slots.map((slot) => slot.weekday).toSet().toList()..sort())) {
      for (final period
          in (_routine?.periodTypes.toList() ?? <LessonPeriodType>[])
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))) {
        final indices =
            _slots
                .where(
                  (slot) => slot.weekday == day && slot.periodId == period.id,
                )
                .map((slot) => slot.index)
                .toList()
              ..sort();
        for (final index in indices) {
          if (_continuous &&
              blocks.isNotEmpty &&
              blocks.last.weekday == day &&
              blocks.last.periodId == period.id &&
              blocks.last.indices.last + 1 == index) {
            blocks.last.indices.add(index);
          } else {
            blocks.add((weekday: day, periodId: period.id, indices: [index]));
          }
        }
      }
    }
    return blocks;
  }

  void _submit() {
    _pruneSlots();
    final stageId = _stageId;
    if (stageId == null || _slots.isEmpty || _classes.isEmpty) {
      setState(() {
        _classError = stageId == null || _classes.isEmpty ? '请选择班级。' : null;
        _slotError = _slots.isEmpty ? '请选择带班课节。' : null;
        _activityNameError = null;
        _groupNameError = null;
        _locationError = null;
        _scheduleErrors = const [];
      });
      return;
    }
    final name = _kind == SupervisionKind.custom
        ? _name.text.trim()
        : _kind.label;
    final activityNameError = name.isEmpty ? '请输入活动名称。' : null;
    final classError = _merged && _classes.length < 2 ? '实际合班至少选择两个来源班。' : null;
    final groupNameError = _merged && _groupName.text.trim().isEmpty
        ? '请输入活动组名称。'
        : null;
    final locationError = _merged && _location.text.trim().isEmpty
        ? '请输入活动地点。'
        : null;
    if (activityNameError != null ||
        classError != null ||
        groupNameError != null ||
        locationError != null) {
      setState(() {
        _activityNameError = activityNameError;
        _classError = classError;
        _groupNameError = groupNameError;
        _locationError = locationError;
        _slotError = null;
        _scheduleErrors = const [];
      });
      return;
    }
    final classList = [
      for (final group in widget.snapshot.classes)
        if (_classes.contains(group.id)) group.id,
    ];
    final coverage = _merged ? [classList] : classList.map((id) => [id]);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    var serial = 0;
    final posts = [
      for (final block in _blocks)
        for (final members in coverage)
          SupervisionPost(
            id: 'post-$timestamp-${serial++}',
            kind: _kind,
            name: name,
            groupName: _merged ? _groupName.text.trim() : '',
            location: _merged ? _location.text.trim() : '',
            stageId: stageId,
            weekday: block.weekday,
            periodTypeId: block.periodId,
            lessonIndices: block.indices,
            classIds: members,
            teacherPoolId: _personnel.poolId,
            matchingPreferences: _personnel.preferences,
            targetSubjectIds: _personnel.subjects ?? const {},
          ),
    ];
    const validator = SupervisionValidation();
    final original = validator
        .postErrors(widget.snapshot, widget.draft)
        .toSet();
    final next = widget.draft.copyWith(
      posts: [...widget.draft.posts, ...posts],
    );
    final errors = validator
        .postErrors(widget.snapshot, next)
        .where((error) => !original.contains(error))
        .toList();
    if (errors.isNotEmpty) {
      setState(() => _scheduleErrors = errors);
      return;
    }
    Navigator.pop(context, posts);
  }

  @override
  Widget build(BuildContext context) {
    final count =
        (_merged ? (_classes.isEmpty ? 0 : 1) : _classes.length) *
        _blocks.length;
    final colors = context.appColors;
    final stageName = widget.snapshot.stages
        .where((stage) => stage.id == _stageId)
        .firstOrNull
        ?.name;
    final personnelSummary =
        '${_personnel.poolId == null ? '默认候选池' : widget.draft.teacherPools.where((pool) => pool.id == _personnel.poolId).firstOrNull?.name ?? '基础候选池'} · ${_personnel.preferences == null ? '跟随全局偏好' : '单独匹配偏好'}';

    Future<void> configurePersonnel() async {
      final value = await showAppDialog<_PersonnelSettings>(
        context: context,
        builder: (_) => _PostPersonnelDialog(
          draft: widget.draft,
          snapshot: widget.snapshot,
          initial: _personnel,
        ),
      );
      if (mounted && value != null) {
        setState(() {
          _personnel = value;
          _scheduleErrors = const [];
        });
      }
    }

    Widget controlBox(Widget child) => Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );

    Widget activityControl() => controlBox(
      Row(
        children: [
          Text(
            '活动类型',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 22, color: colors.border),
          const SizedBox(width: 8),
          Expanded(
            child: AppSelectField<SupervisionKind>(
              compact: true,
              value: _kind,
              hint: '选择活动类型',
              items: {
                for (final kind in SupervisionKind.values) kind.label: kind,
              },
              onChanged: (kind) => setState(() {
                _kind = kind ?? _kind;
                _activityNameError = null;
                _scheduleErrors = const [];
              }),
            ),
          ),
        ],
      ),
    );

    Widget personnelControl() => controlBox(
      Row(
        children: [
          Text(
            '人员规则',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 22, color: colors.border),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              personnelSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.ink),
            ),
          ),
          TextButton(
            onPressed: configurePersonnel,
            style: TextButton.styleFrom(
              foregroundColor: colors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('修改'), Icon(Icons.keyboard_arrow_down, size: 16)],
            ),
          ),
        ],
      ),
    );

    Widget modeCard({
      required bool value,
      required ValueChanged<bool> onChanged,
      required String title,
      required String description,
      Widget? extra,
    }) => _DutyOption(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: title,
                toggled: value,
                child: InkWell(
                  onTap: () => onChanged(!value),
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 44,
                    height: 28,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 36,
                        height: 20,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: value ? colors.blue : colors.border,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 140),
                          alignment: value
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: colors.surface,
                              shape: BoxShape.circle,
                              boxShadow: colors.cardShadow,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: colors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (extra != null) ...[const SizedBox(height: 10), extra],
        ],
      ),
    );

    Widget options() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Text(
          '排班方式',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final continuous = modeCard(
              value: _continuous,
              onChanged: (value) => setState(() {
                _continuous = value;
                _scheduleErrors = const [];
              }),
              title: '连续节次由同一老师负责',
              description: '合并同日同午相邻已选课节，减少频繁换人。',
            );
            final merged = modeCard(
              value: _merged,
              onChanged: (value) => setState(() {
                _merged = value;
                _classError = null;
                _groupNameError = null;
                _locationError = null;
                _scheduleErrors = const [];
              }),
              title: '实际合班教学',
              description: '将所选多个班级合并为一个共享带班岗位。',
              extra: _merged
                  ? Column(
                      children: [
                        AppTextFormField(
                          controller: _groupName,
                          onChanged: (_) {
                            if (_groupNameError != null) {
                              setState(() => _groupNameError = null);
                            }
                          },
                          decoration: const InputDecoration(labelText: '活动组名称'),
                        ),
                        if (_groupNameError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _validationMessage(_groupNameError!),
                            ),
                          ),
                        const SizedBox(height: 8),
                        AppTextFormField(
                          controller: _location,
                          onChanged: (_) {
                            if (_locationError != null) {
                              setState(() => _locationError = null);
                            }
                          },
                          decoration: const InputDecoration(labelText: '活动地点'),
                        ),
                        if (_locationError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _validationMessage(_locationError!),
                            ),
                          ),
                      ],
                    )
                  : null,
            );
            return constraints.maxWidth >= 560
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: continuous),
                      const SizedBox(width: 10),
                      Expanded(child: merged),
                    ],
                  )
                : Column(
                    children: [continuous, const SizedBox(height: 8), merged],
                  );
          },
        ),
      ],
    );

    final bodyHeight = (MediaQuery.sizeOf(context).height - 236)
        .clamp(280.0, 620.0)
        .toDouble();

    return AppDialog(
      title: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '创建带班岗位',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (stageName != null) ...[
                  const SizedBox(width: 9),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.selectedBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      child: Text(
                        '$stageName作息',
                        style: TextStyle(
                          color: colors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                AppIconButton(
                  icon: Icons.close,
                  iconSize: 16,
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '选择适用班级与带班课节，系统已自动过滤正课及不可带班时段。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.inkSecondary),
            ),
          ],
        ),
      ),
      maxWidth: 920,
      padding: EdgeInsets.zero,
      titleGap: 0,
      actionsGap: 0,
      clipBehavior: Clip.antiAlias,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final activity = activityControl();
                final personnel = personnelControl();
                return constraints.maxWidth >= 620
                    ? Row(
                        children: [
                          SizedBox(width: 240, child: activity),
                          const SizedBox(width: 10),
                          Expanded(child: personnel),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          activity,
                          const SizedBox(height: 8),
                          personnel,
                        ],
                      );
              },
            ),
          ),
          if (_kind == SupervisionKind.custom) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextFormField(
                    controller: _name,
                    onChanged: (_) {
                      if (_activityNameError != null) {
                        setState(() => _activityNameError = null);
                      }
                    },
                    decoration: const InputDecoration(labelText: '活动名称'),
                  ),
                  if (_activityNameError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _validationMessage(_activityNameError!),
                    ),
                ],
              ),
            ),
          ],
          Divider(height: 1, thickness: 1, color: colors.border),
          SizedBox(
            height: bodyHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scope = _scopeTree();
                final editor = Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [_routineGrid(), options()],
                  ),
                );
                final wide = constraints.maxWidth >= 780;
                return wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 276,
                            child: ColoredBox(
                              color: colors.canvas,
                              child: scope,
                            ),
                          ),
                          VerticalDivider(width: 1, color: colors.border),
                          Expanded(
                            child: SingleChildScrollView(
                              primary: false,
                              child: editor,
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        primary: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 220, child: scope),
                            const SizedBox(height: 12),
                            editor,
                          ],
                        ),
                      );
              },
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final summary = Text(
                '已选 ${_classes.length} 个班级 × ${_slots.length} 个课格 = 将创建 $count 个带班岗位',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.appColors.inkSecondary),
              );
              final buttons = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppGhostButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  AppPrimaryButton(
                    onPressed: count == 0 ? null : _submit,
                    child: const Text('添加岗位'),
                  ),
                ],
              );
              return constraints.maxWidth >= 520
                  ? Container(
                      decoration: BoxDecoration(
                        color: context.appColors.canvas,
                        border: Border(
                          top: BorderSide(color: context.appColors.border),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: summary),
                          const SizedBox(width: 16),
                          buttons,
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: context.appColors.canvas,
                            border: Border(
                              top: BorderSide(color: context.appColors.border),
                            ),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              summary,
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: buttons,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
            },
          ),
        ),
      ],
    );
  }

  Widget _scopeTree() {
    final stages = widget.snapshot.stages.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final query = _classSearch.text.trim().toLowerCase();
    final rows = <Widget>[];
    for (final stage in stages) {
      final stageGrades =
          widget.snapshot.grades
              .where((grade) => grade.stageId == stage.id)
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final stageMatches =
          query.isEmpty || stage.name.toLowerCase().contains(query);
      final visibleGrades = stageGrades.where((grade) {
        if (stageMatches) return true;
        if (grade.name.toLowerCase().contains(query)) return true;
        return widget.snapshot.classes.any(
          (group) =>
              group.gradeId == grade.id &&
              group.name.toLowerCase().contains(query),
        );
      }).toList();
      if (query.isNotEmpty && visibleGrades.isEmpty) continue;
      final stageIds = [
        for (final group in widget.snapshot.classes)
          if (stageGrades.any((grade) => grade.id == group.gradeId)) group.id,
      ];
      rows.add(
        _scopeRow(
          id: 'stage-${stage.id}',
          label: stage.name,
          stageId: stage.id,
          ids: stageIds,
          expanded: _expandedStages.contains(stage.id) || query.isNotEmpty,
          onExpand: () => setState(
            () => _expandedStages.contains(stage.id)
                ? _expandedStages.remove(stage.id)
                : _expandedStages.add(stage.id),
          ),
        ),
      );
      if (_expandedStages.contains(stage.id) || query.isNotEmpty) {
        for (final grade in visibleGrades) {
          final gradeGroups =
              widget.snapshot.classes
                  .where((group) => group.gradeId == grade.id)
                  .toList()
                ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          final gradeMatches =
              query.isNotEmpty && grade.name.toLowerCase().contains(query);
          final visibleGroups = query.isEmpty || gradeMatches
              ? gradeGroups
              : gradeGroups
                    .where((group) => group.name.toLowerCase().contains(query))
                    .toList();
          final gradeExpanded =
              _expandedGrades.contains(grade.id) ||
              (query.isNotEmpty && visibleGroups.isNotEmpty);
          rows.add(
            _scopeRow(
              id: 'grade-${grade.id}',
              label: grade.name,
              stageId: stage.id,
              indent: 14,
              ids: [for (final group in gradeGroups) group.id],
              expanded: gradeExpanded,
              onExpand: () => setState(
                () => _expandedGrades.contains(grade.id)
                    ? _expandedGrades.remove(grade.id)
                    : _expandedGrades.add(grade.id),
              ),
            ),
          );
          if (gradeExpanded) {
            for (final group in visibleGroups) {
              rows.add(
                _scopeRow(
                  id: 'class-${group.id}',
                  label: group.name,
                  stageId: stage.id,
                  ids: [group.id],
                  indent: 30,
                ),
              );
            }
          }
        }
      }
    }
    if (stages.isEmpty) {
      rows.add(
        const Padding(padding: EdgeInsets.all(12), child: Text('尚未设置学段和班级。')),
      );
    } else if (query.isNotEmpty && rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '没有找到匹配的年级或班级。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.muted),
          ),
        ),
      );
    }

    final stageIds = [
      for (final group in widget.snapshot.classes)
        if (widget.snapshot.grades.any(
          (grade) => grade.id == group.gradeId && grade.stageId == _stageId,
        ))
          group.id,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Row(
            children: [
              Text(
                '班级范围',
                style: TextStyle(
                  color: context.appColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.appColors.selectedBlue,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Text(
                    '已选 ${_classes.length} 班',
                    style: TextStyle(
                      color: context.appColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: stageIds.isEmpty
                    ? null
                    : () => setState(() {
                        _classes.addAll(stageIds);
                        _expandedGrades.addAll(
                          widget.snapshot.grades
                              .where((grade) => grade.stageId == _stageId)
                              .map((grade) => grade.id),
                        );
                        _clearSelectionErrors();
                        _pruneSlots();
                      }),
                style: TextButton.styleFrom(
                  foregroundColor: context.appColors.inkSecondary,
                  textStyle: const TextStyle(fontSize: 11),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('全选'),
              ),
              Text('|', style: TextStyle(color: context.appColors.border)),
              TextButton(
                onPressed: _classes.isEmpty
                    ? null
                    : () => setState(() {
                        _classes.clear();
                        _slots.clear();
                        _clearSelectionErrors();
                        _slotReasons.clear();
                      }),
                style: TextButton.styleFrom(
                  foregroundColor: context.appColors.inkSecondary,
                  textStyle: const TextStyle(fontSize: 11),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        if (_classError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
            child: _validationMessage(_classError!),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: _classSearch,
              onChanged: (_) => setState(() {}),
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: '搜索年级或班级…',
                hintStyle: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.appColors.muted),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: context.appColors.muted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                suffixIcon: _classSearch.text.isEmpty
                    ? null
                    : Tooltip(
                        message: '清空搜索',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(99),
                          onTap: () => setState(_classSearch.clear),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: context.appColors.muted,
                          ),
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: true,
                fillColor: context.appColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(color: context.appColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(color: context.appColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(color: context.appColors.blue),
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: context.appColors.border),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              primary: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scopeRow({
    required String id,
    required String label,
    required String stageId,
    required List<String> ids,
    double indent = 0,
    bool? expanded,
    VoidCallback? onExpand,
  }) {
    final selected = ids.where(_classes.contains).length;
    final all = ids.isNotEmpty && selected == ids.length;
    final partial = selected > 0 && !all;
    final isClass = id.startsWith('class-');
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: SizedBox(
        height: isClass ? 30 : 32,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('post-scope-$id'),
            borderRadius: BorderRadius.circular(8),
            onTap: ids.isEmpty ? null : () => _toggleScope(stageId, ids),
            child: Ink(
              decoration: BoxDecoration(
                color: isClass && all
                    ? colors.selectedBlue
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: isClass
                        ? 6
                        : expanded == null
                        ? 10
                        : 20,
                    child: expanded == null
                        ? null
                        : IconButton(
                            onPressed: onExpand,
                            tooltip: '${expanded ? '收起' : '展开'}$label',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            iconSize: 15,
                            icon: Icon(
                              expanded
                                  ? Icons.keyboard_arrow_down
                                  : Icons.chevron_right,
                              color: colors.muted,
                            ),
                          ),
                  ),
                  _scopeCheckbox(
                    label: label,
                    checked: all,
                    partiallyChecked: partial,
                    enabled: ids.isNotEmpty,
                    onTap: () => _toggleScope(stageId, ids),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected > 0 ? colors.blue : colors.ink,
                        fontSize: 12,
                        fontWeight: all ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (expanded != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: Text(
                        '$selected/${ids.length}',
                        style: TextStyle(
                          color: selected > 0 ? colors.blue : colors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scopeCheckbox({
    required String label,
    required bool checked,
    required bool partiallyChecked,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final colors = context.appColors;
    final selected = checked || partiallyChecked;
    return Semantics(
      label: '选择$label',
      checked: selected,
      value: partiallyChecked ? '部分选中' : null,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        child: SizedBox(
          width: 22,
          height: 30,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors.blue : colors.surface,
                border: Border.all(
                  color: selected ? colors.blue : colors.border,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: checked
                  ? Icon(
                      Icons.check,
                      size: 11,
                      color: context.theme.colors.primaryForeground,
                    )
                  : partiallyChecked
                  ? Container(
                      width: 7,
                      height: 1.5,
                      color: context.theme.colors.primaryForeground,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _routineGrid() {
    final routine = _routine;
    final days = routine?.teachingWeekdays.toList() ?? <int>[];
    days.sort();
    final periods =
        routine?.periodTypes
            .where(
              (period) => days.any(
                (day) => routine.effectiveLessonCount(period.id, day) > 0,
              ),
            )
            .toList() ??
        <LessonPeriodType>[];
    periods.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final available = _availableSlots;
    final stage = widget.snapshot.stages
        .where((stage) => stage.id == _stageId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '作息课节${stage == null ? '' : ' · ${stage.name}'}',
                  style: TextStyle(
                    color: context.appColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.appColors.selectedBlue,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Text(
                      '已选 ${_slots.length} 个课格',
                      style: TextStyle(
                        color: context.appColors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: available.isEmpty
                      ? null
                      : () => setState(() {
                          _slots.addAll(available);
                          _slotError = null;
                          _scheduleErrors = const [];
                        }),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('全选可用课节'),
                ),
                TextButton(
                  onPressed: _slots.isEmpty
                      ? null
                      : () => setState(() {
                          _slots.clear();
                          _slotError = null;
                          _scheduleErrors = const [];
                        }),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('清空'),
                ),
              ],
            );
            return constraints.maxWidth >= 500
                ? Row(children: [title, const Spacer(), actions])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
          },
        ),
        if (_slotError != null || _scheduleErrors.isNotEmpty) ...[
          const SizedBox(height: 4),
          if (_slotError != null) _validationMessage(_slotError!),
          for (final error in _scheduleErrors) _validationMessage(error),
        ],
        if (_classes.isEmpty &&
            routine != null &&
            _routineSlots.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: context.appColors.selectedBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: context.appColors.blue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '请先在左侧勾选适用班级，即可查看并点选可安排带班的课节。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.appColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        if (routine == null || _routineSlots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('该学段尚未配置可用的作息课节。'),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const labelWidth = 108.0;
              final dayWidth =
                  ((constraints.maxWidth - labelWidth) / days.length)
                      .clamp(76.0, 128.0)
                      .toDouble();
              final tableWidth = labelWidth + dayWidth * days.length;
              final rowCount = periods.fold(
                0,
                (sum, period) =>
                    sum +
                    days
                        .map(
                          (day) => routine.effectiveLessonCount(period.id, day),
                        )
                        .reduce((a, b) => a > b ? a : b),
              );
              final gridRows = <Widget>[];
              var lunchBreakCount = 0;
              var lessonSequence = 0;
              LessonPeriodType? previousPeriod;
              for (final period in periods) {
                final periodRowCount = days
                    .map((day) => routine.effectiveLessonCount(period.id, day))
                    .fold<int>(
                      0,
                      (count, value) => value > count ? value : count,
                    );
                for (var index = 1; index <= periodRowCount; index++) {
                  int? previousEnd;
                  if (index > 1) {
                    previousEnd = period.lessonTimes
                        .where((time) => time.lessonIndex == index - 1)
                        .firstOrNull
                        ?.endMinute;
                  } else if (previousPeriod != null) {
                    for (final time in previousPeriod.lessonTimes) {
                      final end = time.endMinute;
                      if (end != null &&
                          (previousEnd == null || end > previousEnd)) {
                        previousEnd = end;
                      }
                    }
                  }
                  final currentStart = period.lessonTimes
                      .where((time) => time.lessonIndex == index)
                      .firstOrNull
                      ?.startMinute;
                  if (_isLunchGap(previousEnd, currentStart)) {
                    lunchBreakCount++;
                    gridRows.add(_PostLunchDivider(width: tableWidth));
                  }
                  gridRows.add(
                    Row(
                      children: [
                        _batchCell(
                          key: ValueKey('post-row-${period.id}-$index'),
                          width: labelWidth,
                          label: period.name.contains('早')
                              ? '早$index'
                              : period.name.contains('晚')
                              ? '晚$index'
                              : '第 ${++lessonSequence} 节',
                          detail: _lessonTime(period, index),
                          slots: available.where(
                            (slot) =>
                                slot.periodId == period.id &&
                                slot.index == index,
                          ),
                        ),
                        for (final day in days)
                          _slotCell(day, period, index, dayWidth),
                      ],
                    ),
                  );
                }
                previousPeriod = period;
              }
              final height = (32 + rowCount * 48 + lunchBreakCount * 22)
                  .toDouble();
              return Scrollbar(
                controller: _horizontal,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    width: tableWidth,
                    height: height,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    foregroundDecoration: BoxDecoration(
                      border: Border.all(color: context.appColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _PostGridCell(
                              width: labelWidth,
                              height: 32,
                              label: '点击表头批量选',
                              header: true,
                            ),
                            for (final day in days)
                              _batchCell(
                                key: ValueKey('post-day-$day'),
                                width: dayWidth,
                                label: _weekdays[day - 1],
                                header: true,
                                slots: available.where(
                                  (slot) => slot.weekday == day,
                                ),
                              ),
                          ],
                        ),
                        ...gridRows,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final legend = Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _PostGridLegend(
                  label: '正课 / 不可用',
                  color: _postDisabledFill(context),
                  hatched: true,
                ),
                _PostGridLegend(
                  label: '可安排带班',
                  color: context.appColors.successSurface,
                  borderColor: context.appColors.success,
                ),
                _PostGridLegend(
                  label: '已选课节',
                  color: context.appColors.blue,
                  checked: true,
                ),
              ],
            );
            final hint = Text(
              '提示：点击行首节次或列首星期可快速反选',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.appColors.muted, fontSize: 10),
            );
            return constraints.maxWidth >= 580
                ? Row(
                    children: [
                      legend,
                      const Spacer(),
                      const SizedBox(width: 8),
                      Flexible(child: hint),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      legend,
                      const SizedBox(height: 2),
                      Align(alignment: Alignment.centerRight, child: hint),
                    ],
                  );
          },
        ),
      ],
    );
  }

  bool _isLunchGap(int? previousEnd, int? currentStart) =>
      previousEnd != null &&
      currentStart != null &&
      previousEnd < 12 * 60 + 30 &&
      currentStart >= 13 * 60 &&
      currentStart - previousEnd >= 60;

  Widget _batchCell({
    required Key key,
    required double width,
    required String label,
    required Iterable<_PostSlot> slots,
    String? detail,
    bool header = false,
  }) => _PostGridCell(
    cellKey: key,
    width: width,
    height: header ? 32 : 48,
    label: label,
    detail: detail,
    header: header,
    axis: !header,
    onPressed: slots.isEmpty ? null : () => _toggleSlots(slots),
  );

  Widget _slotCell(int day, LessonPeriodType period, int index, double width) {
    final slot = (weekday: day, periodId: period.id, index: index);
    final reason = _slotReason(slot);
    final label = reason ?? (_slots.contains(slot) ? '' : '选择');
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: _PostGridCell(
          cellKey: ValueKey('post-slot-$day-${period.id}-$index'),
          width: width - 6,
          height: 42,
          selected: _slots.contains(slot),
          rounded: true,
          label: label,
          semanticsLabel:
              '${_weekdays[day - 1]} ${period.name} 第 $index 节 · ${reason ?? (_slots.contains(slot) ? '已选' : '可安排带班')}',
          onPressed: reason == null ? () => _toggleSlots([slot]) : null,
        ),
      ),
    );
  }

  String _lessonTime(LessonPeriodType period, int index) {
    final time = period.lessonTimes
        .where((time) => time.lessonIndex == index)
        .firstOrNull;
    return time?.startLabel != null && time?.endLabel != null
        ? '${time!.startLabel}–${time.endLabel}'
        : '时间未设置';
  }
}

Color _postDisabledFill(BuildContext context) {
  final colors = context.appColors;
  return Color.alphaBlend(colors.border.withValues(alpha: .18), colors.canvas);
}

class _PostGridCell extends StatelessWidget {
  const _PostGridCell({
    required this.width,
    required this.label,
    this.detail,
    this.height = 48,
    this.selected = false,
    this.header = false,
    this.axis = false,
    this.rounded = false,
    this.onPressed,
    this.cellKey,
    this.semanticsLabel,
  });
  final double width;
  final double height;
  final String label;
  final String? detail;
  final bool selected;
  final bool header;
  final bool axis;
  final bool rounded;
  final VoidCallback? onPressed;
  final Key? cellKey;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    selected: selected,
    child: f.FTappable(
      key: cellKey,
      selected: selected,
      onPress: onPressed,
      builder: (context, variants, child) {
        final colors = context.appColors;
        final disabled = onPressed == null && !header && !axis;
        final available = !disabled && !header && !axis && !selected;
        final hovered =
            variants.contains(f.FTappableVariant.hovered) && onPressed != null;
        final fill = header
            ? colors.tableHeader
            : axis
            ? colors.surface
            : selected
            ? colors.blue
            : disabled
            ? _postDisabledFill(context)
            : hovered
            ? Color.alphaBlend(
                colors.success.withValues(alpha: .12),
                colors.successSurface,
              )
            : colors.successSurface;
        final foreground = selected
            ? context.theme.colors.primaryForeground
            : header
            ? colors.inkSecondary
            : axis
            ? colors.inkSecondary
            : disabled
            ? colors.muted
            : colors.success;
        final displayedLabel = label == '选择' ? (hovered ? '+' : '') : label;
        return Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            border: rounded
                ? Border.all(
                    color: selected
                        ? colors.blue
                        : disabled
                        ? colors.border
                        : available
                        ? colors.success.withValues(alpha: .35)
                        : colors.tableDivider,
                  )
                : Border(
                    right: BorderSide(color: colors.border),
                    bottom: BorderSide(color: colors.border),
                  ),
            borderRadius: rounded ? BorderRadius.circular(8) : null,
            boxShadow: variants.contains(f.FTappableVariant.focused)
                ? [BoxShadow(color: colors.blue, spreadRadius: 1)]
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (disabled)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PostHatchPainter(
                      colors.muted.withValues(alpha: .08),
                    ),
                  ),
                ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (selected && !header && !axis)
                          Icon(
                            Icons.check,
                            size: 14,
                            color: context.theme.colors.primaryForeground,
                          ),
                        if (displayedLabel.isNotEmpty)
                          Flexible(
                            child: Text(
                              displayedLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: header
                                    ? 11
                                    : disabled
                                    ? 10
                                    : 12,
                                fontWeight: selected || header || axis
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: foreground,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: TextStyle(fontSize: 10, color: colors.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _PostLunchDivider extends StatelessWidget {
  const _PostLunchDivider({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 22,
    color: context.appColors.tableHeader,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      children: [
        Expanded(child: Divider(height: 1, color: context.appColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '午休分隔 · 下午时段',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 10, color: context.appColors.muted),
          ),
        ),
        Expanded(child: Divider(height: 1, color: context.appColors.border)),
      ],
    ),
  );
}

class _PostGridLegend extends StatelessWidget {
  const _PostGridLegend({
    required this.label,
    required this.color,
    this.borderColor,
    this.hatched = false,
    this.checked = false,
  });

  final String label;
  final Color color;
  final Color? borderColor;
  final bool hatched;
  final bool checked;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: borderColor ?? context.appColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hatched)
              CustomPaint(
                painter: _PostHatchPainter(
                  context.appColors.muted.withValues(alpha: .08),
                ),
              ),
            if (checked)
              Icon(
                Icons.check,
                size: 11,
                color: context.theme.colors.primaryForeground,
              ),
          ],
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.appColors.inkSecondary, fontSize: 11),
      ),
    ],
  );
}

class _PostHatchPainter extends CustomPainter {
  const _PostHatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PostHatchPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DutyOption extends StatelessWidget {
  const _DutyOption({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.appColors.surface,
      border: Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  );
}
