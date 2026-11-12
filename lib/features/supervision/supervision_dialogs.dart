part of 'supervision_page.dart';

class _TeacherPickerDialog extends StatelessWidget {
  const _TeacherPickerDialog({
    required this.snapshot,
    required this.draft,
    required this.post,
    required this.onRemove,
  });

  final SchedulingSnapshot snapshot;
  final SupervisionDraft draft;
  final SupervisionPost post;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('选择带班教师'),
    maxWidth: 460,
    content: SizedBox(
      height: MediaQuery.sizeOf(context).height < 650 ? 330 : 400,
      child: _TeacherInspector(
        snapshot: snapshot,
        draft: draft,
        post: post,
        onPick: (teacher) => Navigator.pop(context, teacher),
        onRemove: onRemove,
        showTitle: false,
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}

class _TeacherInspector extends StatefulWidget {
  const _TeacherInspector({
    required this.snapshot,
    required this.draft,
    required this.post,
    required this.onPick,
    required this.onRemove,
    this.onClose,
    this.showTitle = true,
    super.key,
  });

  final SchedulingSnapshot snapshot;
  final SupervisionDraft draft;
  final SupervisionPost post;
  final ValueChanged<String>? onPick;
  final VoidCallback? onRemove;
  final VoidCallback? onClose;
  final bool showTitle;

  @override
  State<_TeacherInspector> createState() => _TeacherInspectorState();
}

class _TeacherInspectorState extends State<_TeacherInspector> {
  String _query = '';
  final _blockers = <String, List<String>>{};

  @override
  void didUpdateWidget(covariant _TeacherInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft ||
        oldWidget.snapshot != widget.snapshot) {
      _blockers.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.draft.assignments[widget.post.id];
    final teachers =
        widget.snapshot.teachers
            .where(
              (teacher) => teacher.searchText.toLowerCase().contains(_query),
            )
            .toList()
          ..sort((a, b) {
            int rank(Teacher teacher) => teacher.id == current
                ? 0
                : widget.draft.teacherIds.contains(teacher.id)
                ? 1
                : 2;
            final order = rank(a).compareTo(rank(b));
            return order != 0 ? order : a.sortOrder.compareTo(b.sortOrder);
          });
    final post = widget.post;
    final classes = {
      for (final group in widget.snapshot.classes) group.id: group.name,
    };
    final colors = context.appColors;
    final theme = Theme.of(context).textTheme;
    final group = post.groupName.isNotEmpty
        ? post.groupName
        : post.classIds.map((id) => classes[id] ?? id).join('、');
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: widget.showTitle
            ? const EdgeInsets.fromLTRB(14, 8, 14, 6)
            : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showTitle)
              Row(
                children: [
                  Expanded(child: Text('选择带班教师', style: theme.titleSmall)),
                  AppIconButton(
                    onPressed: widget.onClose,
                    tooltip: '关闭教师面板',
                    icon: Icons.close,
                    iconSize: 18,
                  ),
                ],
              ),
            Text(
              '${_weekdays[post.weekday - 1]} · ${post.name} · $group',
              style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              [
                _slotLabel(widget.snapshot, post),
                ?_weekTime(widget.snapshot, post),
                if (post.location.isNotEmpty) post.location,
              ].join(' · '),
              style: theme.bodySmall?.copyWith(color: colors.inkSecondary),
            ),
            const SizedBox(height: 12),
            AppTextFormField(
              decoration: const InputDecoration(
                hintText: '搜索教师姓名',
                prefixIcon: Icon(Icons.search, size: 17),
                isDense: true,
              ),
              onChanged: (text) =>
                  setState(() => _query = text.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: teachers.isEmpty
                  ? const Center(child: Text('没有符合搜索条件的教师。'))
                  : ListView.separated(
                      itemCount: teachers.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final teacher = teachers[index];
                        final existing = widget.draft.posts.where(
                          (other) =>
                              other.id != post.id &&
                              widget.draft.assignments[other.id] == teacher.id,
                        );
                        final lessons = existing.fold(
                          0,
                          (sum, other) => sum + other.lessonIndices.length,
                        );
                        final days = existing
                            .map((other) => other.weekday)
                            .toSet()
                            .length;
                        final blockers = _blockers.putIfAbsent(
                          teacher.id,
                          () => const SupervisionAllocator().teacherBlockers(
                            widget.snapshot,
                            widget.draft.copyWith(
                              teacherIds: {
                                ...widget.draft.teacherIds,
                                teacher.id,
                              },
                            ),
                            post,
                            teacher.id,
                          ),
                        );
                        return f.FItem(
                          title: Text(teacher.displayName),
                          subtitle: Text(
                            blockers.isEmpty
                                ? '其他岗位 $lessons 节 · $days 天'
                                : blockers.join(' · '),
                          ),
                          selected: teacher.id == current,
                          suffix: teacher.id == current
                              ? Icon(Icons.check, size: 16, color: colors.blue)
                              : null,
                          onPress: blockers.isEmpty && widget.onPick != null
                              ? () => widget.onPick!(teacher.id)
                              : null,
                          enabled: blockers.isEmpty,
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Wrap(
              spacing: 6,
              children: [
                if (current != null)
                  AppGhostButton(
                    onPressed: widget.onPick == null
                        ? null
                        : () => widget.onPick!(''),
                    child: const Text('清除指派'),
                  ),
                AppGhostButton(
                  onPressed: widget.onRemove,
                  child: Text(
                    '移除岗位',
                    style: TextStyle(color: colors.destructive),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherPoolDialog extends StatefulWidget {
  const _TeacherPoolDialog({
    required this.draft,
    required this.snapshot,
    required this.groups,
  });

  final SupervisionDraft draft;
  final SchedulingSnapshot snapshot;
  final List<TeacherGroup> groups;

  @override
  State<_TeacherPoolDialog> createState() => _TeacherPoolDialogState();
}

class _TeacherPoolDialogState extends State<_TeacherPoolDialog> {
  late final _teachers = {...widget.draft.teacherIds};
  late final _rules = {...widget.draft.rules};
  String _query = '';
  String? _expandedTeacher;
  final _limits = <String, TextEditingController>{};

  bool _invalidLimit(String text) =>
      text.trim().isNotEmpty &&
      (int.tryParse(text.trim()) == null || int.parse(text.trim()) < 0);
  bool get _hasInvalidLimits =>
      _limits.values.any((controller) => _invalidLimit(controller.text));

  @override
  void dispose() {
    for (final controller in _limits.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _editRule(Teacher teacher) async {
    final changed = await showAppDialog<SupervisionTeacherRule>(
      context: context,
      builder: (_) => _TeacherRuleDialog(
        teacher: teacher,
        snapshot: widget.snapshot,
        rule: _rules[teacher.id],
      ),
    );
    if (mounted && changed != null) {
      setState(() {
        _rules[teacher.id] = changed;
        _limits[teacher.id]?.text = changed.maxLessons?.toString() ?? '';
      });
    }
  }

  Widget _quickRule(Teacher teacher) {
    final controller = _limits.putIfAbsent(
      teacher.id,
      () => TextEditingController(
        text: _rules[teacher.id]?.maxLessons?.toString(),
      ),
    );
    final field = AppTextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: '每周带班上限', hintText: '留空不限'),
      onChanged: (text) => setState(() {
        if (!_invalidLimit(text)) {
          final rule = _rules[teacher.id];
          _rules[teacher.id] = SupervisionTeacherRule(
            maxLessons: int.tryParse(text.trim()),
            maxDays: rule?.maxDays,
            unavailable: rule?.unavailable ?? const [],
          );
        }
      }),
    );
    final forbidden = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('带班禁排与天数上限', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        _DutyOutlineButton(
          onPressed: () => _editRule(teacher),
          child: Text(
            '编辑禁排 · ${_rules[teacher.id]?.unavailable.length ?? 0} 格',
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 8, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.canvas,
          border: Border.all(color: context.appColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 460
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: field),
                          const SizedBox(width: 16),
                          Expanded(child: forbidden),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          field,
                          const SizedBox(height: 12),
                          forbidden,
                        ],
                      ),
              ),
              if (_invalidLimit(controller.text))
                Text(
                  '带班上限需填非负整数。',
                  style: TextStyle(color: context.appColors.destructive),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupNames = {
      for (final group in widget.groups) group.id: group.name,
    };
    List<String> groupsFor(String id) => widget.snapshot.teacherGroupMembers
        .where((member) => member.teacherId == id)
        .map((member) => groupNames[member.groupId])
        .whereType<String>()
        .toList();
    final teachers = widget.snapshot.teachers
        .where(
          (teacher) =>
              teacher.searchText.toLowerCase().contains(_query) ||
              groupsFor(teacher.id)
                  .any((group) => group.toLowerCase().contains(_query)),
        )
        .toList();
    return AppDialog(
      title: const Text('候选教师与带班规则'),
      maxWidth: 720,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '勾选的教师进入带班候选。带班禁排与每周上限仅用于带班，不影响课表。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.inkSecondary),
          ),
          const SizedBox(height: 12),
          AppTextFormField(
            decoration: const InputDecoration(
              hintText: '搜索教师姓名或教师组',
              prefixIcon: Icon(Icons.search, size: 16),
            ),
            onChanged: (text) =>
                setState(() => _query = text.trim().toLowerCase()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                AppCheckbox(
                  value:
                      teachers.isNotEmpty &&
                      teachers.every(
                        (teacher) => _teachers.contains(teacher.id),
                      ),
                  onChanged: (value) => setState(() {
                    final ids = teachers.map((teacher) => teacher.id);
                    value ? _teachers.addAll(ids) : _teachers.removeAll(ids);
                  }),
                ),
                const SizedBox(width: 8),
                const Text('全选搜索结果'),
                const Spacer(),
                Text(
                  '已选 ${_teachers.length} 人',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final group in widget.groups)
                AppGhostButton(
                  child: Text('+ ${group.name}'),
                  onPressed: () => setState(
                    () => _teachers.addAll(
                      widget.snapshot.teacherGroupMembers
                          .where((member) => member.groupId == group.id)
                          .map((member) => member.teacherId),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).height < 700 ? 240 : 360,
            child: ListView.builder(
              itemCount: teachers.length,
              itemBuilder: (context, index) {
                final teacher = teachers[index];
                final rule = _rules[teacher.id];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    f.FItem(
                      style: _dutyListStyle(context),
                      prefix: AppCheckbox(
                        value: _teachers.contains(teacher.id),
                        onChanged: (value) => setState(() {
                          value
                              ? _teachers.add(teacher.id)
                              : _teachers.remove(teacher.id);
                        }),
                      ),
                      onPress: () => setState(() {
                        _teachers.contains(teacher.id)
                            ? _teachers.remove(teacher.id)
                            : _teachers.add(teacher.id);
                      }),
                      title: Text(teacher.displayName),
                      subtitle: Text(
                        [
                          ...groupsFor(teacher.id),
                          rule == null
                              ? '未设置规则'
                              : '${rule.maxLessons ?? '不限'} 节 / ${rule.maxDays ?? '不限'} 天 · ${rule.unavailable.length} 格禁排',
                        ].join(' · '),
                      ),
                      suffix: _DutyOutlineButton(
                        onPressed: () => setState(
                          () =>
                              _expandedTeacher = _expandedTeacher == teacher.id
                              ? null
                              : teacher.id,
                        ),
                        child: Text(
                          _expandedTeacher == teacher.id ? '收起' : '设置',
                        ),
                      ),
                    ),
                    if (_expandedTeacher == teacher.id) _quickRule(teacher),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      actions: [
        if (_hasInvalidLimits)
          Text(
            '请先修正带班上限。',
            style: TextStyle(color: context.appColors.destructive),
          ),
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppPrimaryButton(
          onPressed: _hasInvalidLimits
              ? null
              : () => Navigator.pop(
                  context,
                  widget.draft.copyWith(teacherIds: _teachers, rules: _rules),
                ),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _TeacherRuleDialog extends StatefulWidget {
  const _TeacherRuleDialog({
    required this.teacher,
    required this.snapshot,
    required this.rule,
  });

  final Teacher teacher;
  final SchedulingSnapshot snapshot;
  final SupervisionTeacherRule? rule;

  @override
  State<_TeacherRuleDialog> createState() => _TeacherRuleDialogState();
}

class _TeacherRuleDialogState extends State<_TeacherRuleDialog> {
  late final _lessons = TextEditingController(
    text: widget.rule?.maxLessons?.toString(),
  );
  late final _days = TextEditingController(
    text: widget.rule?.maxDays?.toString(),
  );
  late final _forbidden = {
    for (final position
        in widget.rule?.unavailable ?? const <SchedulePosition>[])
      position.cellKey: position,
  };
  late String? _stageId = widget.snapshot.routines.firstOrNull?.stageId;
  int _weekday = 1;
  String? _error;

  @override
  void dispose() {
    _lessons.dispose();
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routine = widget.snapshot.routines
        .where((routine) => routine.stageId == _stageId)
        .firstOrNull;
    final slots = [
      for (final period in routine?.periodTypes ?? const <LessonPeriodType>[])
        for (
          var index = 1;
          index <= routine!.effectiveLessonCount(period.id, _weekday);
          index++
        )
          (
            period.name,
            SchedulePosition(
              stageId: routine.stageId,
              weekday: _weekday,
              periodTypeId: period.id,
              lessonIndex: index,
              startMinute: period.lessonTimes
                  .where((time) => time.lessonIndex == index)
                  .firstOrNull
                  ?.startMinute,
              endMinute: period.lessonTimes
                  .where((time) => time.lessonIndex == index)
                  .firstOrNull
                  ?.endMinute,
            ),
          ),
    ];
    return AppDialog(
      title: Text('${widget.teacher.displayName} · 带班规则'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextFormField(
            controller: _lessons,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每周最多带班节次（留空不限）'),
          ),
          AppTextFormField(
            controller: _days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每周最多带班天数（留空不限）'),
          ),
          const SizedBox(height: 12),
          Text('禁排时段 · 已选 ${_forbidden.length} 格'),
          AppSelectField<String>(
            value: _stageId,
            label: '学段',
            hint: '选择学段',
            items: {
              for (final stage in widget.snapshot.stages) stage.name: stage.id,
            },
            onChanged: (value) => setState(() => _stageId = value),
          ),
          AppSelectField<int>(
            value: _weekday,
            label: '星期',
            items: {for (var day = 1; day <= 7; day++) _weekdays[day - 1]: day},
            onChanged: (day) => setState(() => _weekday = day ?? _weekday),
          ),
          if (!(routine?.teachingWeekdays.contains(_weekday) ?? false))
            const Text('当天没有配置上课。')
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (label, position) in slots)
                  _SelectionOption(
                    label: Text('$label · 第 ${position.lessonIndex} 节'),
                    selected: _forbidden.containsKey(position.cellKey),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _forbidden[position.cellKey] = position;
                      } else {
                        _forbidden.remove(position.cellKey);
                      }
                    }),
                  ),
              ],
            ),
          if (_error case final error?)
            Text(error, style: TextStyle(color: context.appColors.destructive)),
        ],
      ),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppPrimaryButton(
          onPressed: () {
            final maxLessons = int.tryParse(_lessons.text.trim());
            final maxDays = int.tryParse(_days.text.trim());
            if ((_lessons.text.trim().isNotEmpty &&
                    (maxLessons == null || maxLessons < 0)) ||
                (_days.text.trim().isNotEmpty &&
                    (maxDays == null || maxDays < 0 || maxDays > 7))) {
              setState(() => _error = '带班上限需填非负整数，天数最多为 7。');
              return;
            }
            Navigator.pop(
              context,
              SupervisionTeacherRule(
                maxLessons: maxLessons,
                maxDays: maxDays,
                unavailable: _forbidden.values.toList(),
              ),
            );
          },
          child: const Text('应用规则'),
        ),
      ],
    );
  }
}

class _PublishDialog extends StatefulWidget {
  const _PublishDialog({
    required this.dates,
    required this.load,
    required this.snapshot,
    required this.repair,
  });

  final List<DateTime> dates;
  final Future<SupervisionPreview> Function(DateTime) load;
  final SchedulingSnapshot snapshot;
  final bool repair;

  @override
  State<_PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends State<_PublishDialog> {
  late DateTime _selected = widget.dates.first;
  late Future<SupervisionPreview> _future = widget.load(_selected);

  @override
  Widget build(BuildContext context) => FutureBuilder<SupervisionPreview>(
    future: _future,
    builder: (context, state) {
      final preview = state.connectionState == ConnectionState.done
          ? state.data
          : null;
      return AppDialog(
        title: Text(widget.repair ? '预览带班与课表协调' : '预览带班方案'),
        maxWidth: 920,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.repair)
              Text('生效日期 · ${_dateLabel(_selected)}')
            else
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 320,
                  child: AppSelectField<DateTime>(
                    value: _selected,
                    label: '生效日期',
                    items: {
                      for (final date in widget.dates) _dateLabel(date): date,
                    },
                    onChanged: (date) {
                      if (date == null || date == _selected) return;
                      setState(() {
                        _selected = date;
                        _future = widget.load(date);
                      });
                    },
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (state.connectionState != ConnectionState.done)
              const f.FProgress(semanticsLabel: '正在生成带班预览')
            else if (state.hasError)
              Text('生成预览失败：${state.error}')
            else if (preview != null)
              _PreviewDiff(snapshot: widget.snapshot, preview: preview),
          ],
        ),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回草稿'),
          ),
          AppPrimaryButton(
            onPressed: preview?.canPublish == true
                ? () => Navigator.pop(context, preview)
                : null,
            child: Text(widget.repair ? '确认并协调' : '确认生效'),
          ),
        ],
      );
    },
  );
}

class _PreviewDiff extends StatefulWidget {
  const _PreviewDiff({required this.snapshot, required this.preview});

  final SchedulingSnapshot snapshot;
  final SupervisionPreview preview;

  @override
  State<_PreviewDiff> createState() => _PreviewDiffState();
}

class _PreviewDiffState extends State<_PreviewDiff> {
  String _filter = 'all';
  SchedulingSnapshot get snapshot => widget.snapshot;
  SupervisionPreview get preview => widget.preview;

  @override
  void didUpdateWidget(covariant _PreviewDiff oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview != widget.preview) _filter = 'all';
  }

  @override
  Widget build(BuildContext context) {
    final before = preview.before?.draft;
    final after = preview.draft;
    final oldPosts = {
      for (final post in before?.posts ?? const <SupervisionPost>[])
        post.id: post,
    };
    final newPosts = {for (final post in after.posts) post.id: post};
    final teachers = {
      for (final teacher in snapshot.teachers) teacher.id: teacher.displayName,
    };
    final classes = {
      for (final group in snapshot.classes) group.id: group.name,
    };
    String teacherName(String? id) => id == null ? '待安排' : teachers[id] ?? id;
    String? describe(SupervisionPost? post, String? teacherId) => post == null
        ? null
        : [
            '${post.name} · ${teacherName(teacherId)}',
            [
              _weekdays[post.weekday - 1],
              _slotLabel(snapshot, post),
              post.groupName.isEmpty
                  ? post.classIds.map((id) => classes[id] ?? id).join('、')
                  : post.groupName,
              if (post.location.isNotEmpty) post.location,
            ].join(' · '),
          ].join('\n');
    final lines = <(String?, String?, SupervisionPost)>[];
    for (final id in {...oldPosts.keys, ...newPosts.keys}) {
      final oldLine = describe(oldPosts[id], before?.assignments[id]);
      final newLine = describe(newPosts[id], after.assignments[id]);
      if (oldLine != newLine) {
        lines.add((oldLine, newLine, newPosts[id] ?? oldPosts[id]!));
      }
    }
    Map<String, int> loads(SupervisionDraft? draft) {
      final result = <String, int>{};
      if (draft == null) return result;
      for (final post in draft.posts) {
        final teacherId = draft.assignments[post.id];
        if (teacherId == null) continue;
        result.update(
          teacherId,
          (count) => count + post.lessonIndices.length,
          ifAbsent: () => post.lessonIndices.length,
        );
      }
      return result;
    }

    String type((String?, String?, SupervisionPost) line) => line.$1 == null
        ? 'add'
        : line.$2 == null
        ? 'remove'
        : 'update';
    final shown = lines
        .where((line) => _filter == 'all' || type(line) == _filter)
        .toList();
    final oldLoads = loads(before);
    final newLoads = loads(after);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview.replacedFutureDate case final date?)
          Text('本次确认将替换原定 ${_dateLabel(date)} 生效的带班方案。'),
        Text('岗位变更', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _DutySegments<String>(
          items: {
            'all': '全部 ${lines.length}',
            'add': '新增 ${lines.where((line) => type(line) == 'add').length}',
            'update':
                '调整 ${lines.where((line) => type(line) == 'update').length}',
            'remove':
                '停排 ${lines.where((line) => type(line) == 'remove').length}',
          },
          value: _filter,
          itemKey: (type) => ValueKey('duty-preview-filter-$type'),
          onChanged: (type) => setState(() => _filter = type),
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(lines.isEmpty ? '岗位安排无变化。' : '该类型暂无变更。'),
          ),
        for (final line in shown)
          _PreviewChange(
            before: line.$1,
            after: line.$2,
            type: type(line),
            contextLabel:
                '${_weekdays[line.$3.weekday - 1]} · ${_slotLabel(snapshot, line.$3)}\n${line.$3.groupName.isEmpty ? line.$3.classIds.map((id) => classes[id] ?? id).join('、') : line.$3.groupName}',
          ),
        for (final id in {...oldLoads.keys, ...newLoads.keys})
          if (oldLoads[id] != newLoads[id])
            Text(
              '${teacherName(id)} · ${oldLoads[id] ?? 0} → ${newLoads[id] ?? 0} 节 / 周',
            ),
        if (preview.scheduleChanges.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('正课协调', style: Theme.of(context).textTheme.titleSmall),
          for (final change in preview.scheduleChanges) Text(change),
        ],
        if (preview.missingPostIds.isNotEmpty)
          Text(
            '仍有 ${preview.missingPostIds.length} 个岗位待安排。请返回草稿补齐。',
            style: TextStyle(color: context.appColors.destructive),
          ),
        for (final error in preview.errors)
          Text(error, style: TextStyle(color: context.appColors.destructive)),
      ],
    );
  }
}

class _PreviewChange extends StatelessWidget {
  const _PreviewChange({
    required this.before,
    required this.after,
    required this.type,
    required this.contextLabel,
  });
  final String? before;
  final String? after;
  final String type;
  final String contextLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context).textTheme;
    final badge = Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: type == 'add'
              ? colors.successSurface
              : type == 'remove'
              ? colors.destructiveSurface
              : colors.warningSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          type == 'add'
              ? '新增'
              : type == 'remove'
              ? '停排'
              : '调整',
          style: theme.bodySmall?.copyWith(
            color: type == 'add'
                ? colors.success
                : type == 'remove'
                ? colors.destructive
                : colors.warning,
          ),
        ),
      ),
    );
    Widget field(String label, String? value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.bodySmall?.copyWith(fontSize: 11, color: colors.muted),
        ),
        const SizedBox(height: 3),
        Text(
          value?.split('\n').first ?? '—',
          style: theme.bodyMedium?.copyWith(
            fontSize: 13,
            color: label == '变更前'
                ? colors.inkSecondary
                : type == 'remove'
                ? colors.destructive
                : colors.ink,
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 620) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 64, child: badge),
                  SizedBox(
                    width: 180,
                    child: Text(contextLabel, style: theme.bodySmall),
                  ),
                  Expanded(child: field('变更前', before)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 15,
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 15,
                      color: colors.muted,
                    ),
                  ),
                  Expanded(child: field('变更后', after)),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    badge,
                    const SizedBox(width: 10),
                    Expanded(child: Text(contextLabel, style: theme.bodySmall)),
                  ],
                ),
                const SizedBox(height: 8),
                field('变更前', before),
                const SizedBox(height: 6),
                field('变更后', after),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SelectionOption extends StatelessWidget {
  const _SelectionOption({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: AppActionPill(
      selected: selected,
      onPressed: () => onSelected(!selected),
      child: label,
    ),
  );
}
