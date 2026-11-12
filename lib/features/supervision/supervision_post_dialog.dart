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
  late final _expandedGrades = <String>{
    for (final grade in widget.snapshot.grades)
      if (grade.stageId == _stageId) grade.id,
  };
  final _name = TextEditingController();
  final _groupName = TextEditingController();
  final _location = TextEditingController();
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  late SupervisionKind _kind = _initialKind();
  bool _merged = false;
  bool _continuous = false;
  List<String> _errors = const [];
  final _slotReasons = <_PostSlot, String?>{};

  @override
  void initState() {
    super.initState();
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
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _toggleScope(String stageId, List<String> ids) => setState(() {
    if (_stageId != stageId) {
      _stageId = stageId;
      _classes.clear();
      _slots.clear();
      _errors = const [];
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
    }
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
      setState(() => _errors = ['请选择班级，并在作息周表中选择课节。']);
      return;
    }
    final name = _kind == SupervisionKind.custom
        ? _name.text.trim()
        : _kind.label;
    if (name.isEmpty ||
        (_merged &&
            (_classes.length < 2 ||
                _groupName.text.trim().isEmpty ||
                _location.text.trim().isEmpty))) {
      setState(
        () => _errors = [
          if (name.isEmpty) '请输入活动名称。',
          if (_merged && _classes.length < 2) '实际合班至少选择两个来源班。',
          if (_merged && _groupName.text.trim().isEmpty) '请输入活动组名称。',
          if (_merged && _location.text.trim().isEmpty) '请输入活动地点。',
        ],
      );
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
      setState(() => _errors = errors);
      return;
    }
    Navigator.pop(context, posts);
  }

  @override
  Widget build(BuildContext context) {
    final count =
        (_merged ? (_classes.isEmpty ? 0 : 1) : _classes.length) *
        _blocks.length;
    Widget options() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text('排班方式', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _DutyOption(
          child: f.FSwitch(
            label: const Text('连续节次由同一老师负责'),
            description: Text(
              '只合并同一天、同一时段内相邻的已选课节，减少频繁换人。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.appColors.inkSecondary),
            ),
            value: _continuous,
            onChange: (value) => setState(() => _continuous = value),
          ),
        ),
        const SizedBox(height: 10),
        _DutyOption(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              f.FSwitch(
                label: const Text('实际合班'),
                description: Text(
                  '所选班级集中到同一地点，由同一名老师统一负责。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.appColors.inkSecondary),
                ),
                value: _merged,
                onChange: (value) => setState(() => _merged = value),
              ),
              if (_merged) ...[
                const SizedBox(height: 10),
                AppTextFormField(
                  controller: _groupName,
                  decoration: const InputDecoration(labelText: '活动组名称'),
                ),
                const SizedBox(height: 8),
                AppTextFormField(
                  controller: _location,
                  decoration: const InputDecoration(labelText: '活动地点'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return AppDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('创建带班岗位'),
          const SizedBox(height: 4),
          Text(
            '先选班级范围，再从作息中勾选课节；正课、无课与不上课不可选。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.inkSecondary),
          ),
        ],
      ),
      maxWidth: 1000,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('活动类型'),
              SizedBox(
                width: 200,
                child: AppSelectField<SupervisionKind>(
                  compact: true,
                  value: _kind,
                  hint: '选择活动类型',
                  items: {
                    for (final kind in SupervisionKind.values) kind.label: kind,
                  },
                  onChanged: (kind) => setState(() => _kind = kind ?? _kind),
                ),
              ),
            ],
          ),
          if (_kind == SupervisionKind.custom) ...[
            const SizedBox(height: 8),
            AppTextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '活动名称'),
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 780;
              final scope = _scopeTree(scrollable: wide);
              final editor = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_routineGrid(), options()],
              );
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 260, child: scope),
                        const SizedBox(width: 20),
                        Expanded(child: editor),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [scope, const SizedBox(height: 16), editor],
                    );
            },
          ),
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final error in _errors)
              Text(
                error,
                style: TextStyle(color: context.appColors.destructive),
              ),
          ],
        ],
      ),
      actions: [
        Text(
          '将创建 $count 个岗位 · ${_slots.length} 个课格',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppPrimaryButton(
          onPressed: count == 0 ? null : _submit,
          child: const Text('添加岗位'),
        ),
      ],
    );
  }

  Widget _scopeTree({required bool scrollable}) {
    final stages = widget.snapshot.stages.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final stage in stages) ...[
          _scopeRow(
            id: 'stage-${stage.id}',
            label: stage.name,
            stageId: stage.id,
            ids: [
              for (final group in widget.snapshot.classes)
                if (widget.snapshot.grades.any(
                  (grade) =>
                      grade.id == group.gradeId && grade.stageId == stage.id,
                ))
                  group.id,
            ],
            expanded: _expandedStages.contains(stage.id),
            onExpand: () => setState(
              () => _expandedStages.contains(stage.id)
                  ? _expandedStages.remove(stage.id)
                  : _expandedStages.add(stage.id),
            ),
          ),
          if (_expandedStages.contains(stage.id))
            for (final grade
                in (widget.snapshot.grades
                    .where((grade) => grade.stageId == stage.id)
                    .toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))) ...[
              _scopeRow(
                id: 'grade-${grade.id}',
                label: grade.name,
                stageId: stage.id,
                indent: 12,
                ids: [
                  for (final group in widget.snapshot.classes)
                    if (group.gradeId == grade.id) group.id,
                ],
                expanded: _expandedGrades.contains(grade.id),
                onExpand: () => setState(
                  () => _expandedGrades.contains(grade.id)
                      ? _expandedGrades.remove(grade.id)
                      : _expandedGrades.add(grade.id),
                ),
              ),
              if (_expandedGrades.contains(grade.id))
                for (final group
                    in (widget.snapshot.classes
                        .where((group) => group.gradeId == grade.id)
                        .toList()
                      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))))
                  _scopeRow(
                    id: 'class-${group.id}',
                    label: group.name,
                    stageId: stage.id,
                    ids: [group.id],
                    indent: 24,
                  ),
            ],
        ],
        if (stages.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('尚未设置学段和班级。')),
      ],
    );
    return AppSectionPanel(
      title: '班级范围',
      useShadow: false,
      showBorder: true,
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      trailing: Text(
        '已选 ${_classes.length} 个班级',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: scrollable ? 370 : 240),
        child: SingleChildScrollView(primary: false, child: rows),
      ),
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
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: f.FItem(
        key: ValueKey('post-scope-$id'),
        style: _dutyListStyle(context),
        onPress: () => _toggleScope(stageId, ids),
        prefix: AppCheckbox(
          value: all,
          enabled: ids.isNotEmpty,
          onChanged: (_) => _toggleScope(stageId, ids),
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        suffix: expanded == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$selected/${ids.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  AppIconButton(
                    icon: expanded ? Icons.expand_more : Icons.chevron_right,
                    onPressed: onExpand,
                    tooltip: '${expanded ? '收起' : '展开'}$label',
                    iconSize: 14,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _routineGrid() {
    final routine = _routine;
    final days = routine?.teachingWeekdays.toList() ?? <int>[];
    days.sort();
    final periods = routine?.periodTypes.toList() ?? <LessonPeriodType>[];
    periods.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final available = _availableSlots;
    final stage = widget.snapshot.stages
        .where((stage) => stage.id == _stageId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '作息课节${stage == null ? '' : ' · ${stage.name}'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '已选 ${_slots.length} 个课格',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            AppGhostButton(
              onPressed: available.isEmpty
                  ? null
                  : () => setState(() => _slots.addAll(available)),
              child: const Text('全选课节'),
            ),
            AppGhostButton(
              onPressed: _slots.isEmpty ? null : () => setState(_slots.clear),
              child: const Text('清空课节'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _classes.isEmpty ? '先选择班级，再选择带班课节。' : '正课、无课和不上课不可选，其他免任课均可安排带班。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (routine == null || _routineSlots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('该学段尚未配置可用的作息课节。'),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const labelWidth = 112.0;
              final dayWidth =
                  ((constraints.maxWidth - labelWidth) / days.length).clamp(
                    76.0,
                    128.0,
                  );
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
              final height = (36 + periods.length * 28 + rowCount * 56)
                  .clamp(0, 402)
                  .toDouble();
              return DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: context.appColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      height: height + 8,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _PostGridCell(
                                width: labelWidth,
                                height: 36,
                                label: '节次 / 时间',
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
                          Expanded(
                            child: Scrollbar(
                              controller: _vertical,
                              child: SingleChildScrollView(
                                controller: _vertical,
                                child: Column(
                                  children: [
                                    for (final period in periods) ...[
                                      Container(
                                        width: tableWidth,
                                        height: 28,
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.only(
                                          left: 10,
                                        ),
                                        color: context.appColors.tableHeader,
                                        child: Text(
                                          period.name,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      for (
                                        var index = 1;
                                        index <=
                                            days
                                                .map(
                                                  (day) => routine
                                                      .effectiveLessonCount(
                                                        period.id,
                                                        day,
                                                      ),
                                                )
                                                .reduce(
                                                  (a, b) => a > b ? a : b,
                                                );
                                        index++
                                      )
                                        Row(
                                          children: [
                                            _batchCell(
                                              key: ValueKey(
                                                'post-row-${period.id}-$index',
                                              ),
                                              width: labelWidth,
                                              label: '第 $index 节',
                                              detail: _lessonTime(
                                                period,
                                                index,
                                              ),
                                              slots: available.where(
                                                (slot) =>
                                                    slot.periodId ==
                                                        period.id &&
                                                    slot.index == index,
                                              ),
                                            ),
                                            for (final day in days)
                                              _slotCell(
                                                day,
                                                period,
                                                index,
                                                dayWidth,
                                              ),
                                          ],
                                        ),
                                    ],
                                  ],
                                ),
                              ),
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final (label, color) in [
              ('不可选', context.appColors.border),
              ('可选课节', context.appColors.surface),
              ('已选', context.appColors.selectedBlue),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(color: context.appColors.border),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
          ],
        ),
      ],
    );
  }

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
    height: header ? 36 : 56,
    label: label,
    detail: detail,
    header: header,
    onPressed: slots.isEmpty ? null : () => _toggleSlots(slots),
  );

  Widget _slotCell(int day, LessonPeriodType period, int index, double width) {
    final slot = (weekday: day, periodId: period.id, index: index);
    final reason = _slotReason(slot);
    final label = reason ?? (_slots.contains(slot) ? '已选' : '选择');
    return _PostGridCell(
      cellKey: ValueKey('post-slot-$day-${period.id}-$index'),
      width: width,
      selected: _slots.contains(slot),
      label: label,
      semanticsLabel:
          '${_weekdays[day - 1]} ${period.name} 第 $index 节 · $label',
      onPressed: reason == null ? () => _toggleSlots([slot]) : null,
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

class _PostGridCell extends StatelessWidget {
  const _PostGridCell({
    required this.width,
    required this.label,
    this.detail,
    this.height = 56,
    this.selected = false,
    this.header = false,
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
      builder: (context, variants, child) => Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onPressed == null && !header
              ? context.appColors.border
              : selected
              ? context.appColors.selectedBlue
              : variants.contains(f.FTappableVariant.hovered)
              ? context.appColors.tableHeader
              : null,
          border: Border(
            right: BorderSide(color: context.appColors.tableDivider),
            bottom: BorderSide(color: context.appColors.tableDivider),
          ),
          boxShadow: variants.contains(f.FTappableVariant.focused)
              ? [BoxShadow(color: context.appColors.blue, spreadRadius: 1)]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: header ? 12 : 13,
                fontWeight: selected || header
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: selected
                    ? context.appColors.blue
                    : onPressed == null && !header
                    ? context.appColors.muted
                    : null,
              ),
            ),
            if (detail != null)
              Text(
                detail!,
                style: TextStyle(
                  fontSize: 11,
                  color: context.appColors.inkSecondary,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _DutyOption extends StatelessWidget {
  const _DutyOption({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  );
}
