part of 'supervision_page.dart';

enum _DutyView { week, schoolClass, teacher }

class _DutySegments<T> extends StatelessWidget {
  const _DutySegments({
    required this.items,
    required this.value,
    required this.onChanged,
    this.itemKey,
    this.pills = false,
    this.counts = const {},
  });
  final Map<T, String> items;
  final T value;
  final ValueChanged<T> onChanged;
  final Key Function(T)? itemKey;
  final bool pills;
  final Map<T, int> counts;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _headerCanvas(context),
      border: Border.all(color: _headerBorder(context)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (final entry in items.entries)
            f.FTappable(
              key: itemKey?.call(entry.key),
              selected: value == entry.key,
              onPress: () => onChanged(entry.key),
              builder: (context, variants, child) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: value == entry.key
                      ? context.appColors.cardShadow
                      : null,
                  color: value == entry.key
                      ? context.appColors.surface
                      : variants.contains(f.FTappableVariant.hovered)
                      ? context.appColors.surface
                      : null,
                  border: variants.contains(f.FTappableVariant.focused)
                      ? Border.all(color: _headerBlue(context))
                      : null,
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: entry.value),
                      if (counts.containsKey(entry.key))
                        TextSpan(
                          text: ' ${counts[entry.key]}',
                          style: TextStyle(
                            color: _headerSecondary(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: value == entry.key
                        ? pills
                              ? _headerBlue(context)
                              : _headerInk(context)
                        : _headerText(context),
                    fontWeight: value == entry.key
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _DutyHeaderSearchField extends StatefulWidget {
  const _DutyHeaderSearchField({
    required this.onChanged,
    this.value = '',
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_DutyHeaderSearchField> createState() => _DutyHeaderSearchFieldState();
}

class _DutyHeaderSearchFieldState extends State<_DutyHeaderSearchField> {
  final FocusNode _focusNode = FocusNode();
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _DutyHeaderSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  void _onFocusChanged() => setState(() => _focused = _focusNode.hasFocus);

  void _clear() {
    _controller.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: _focused || hasText ? 224 : 176,
      height: 30,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: (value) {
          setState(() {});
          widget.onChanged(value);
        },
        cursorColor: _headerBlue(context),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: _headerInput(context),
          hintText: '搜索班级或教师...',
          hintStyle: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: _headerMuted(context), fontSize: 12),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 15,
            color: _headerMuted(context),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 30,
            minHeight: 30,
          ),
          suffixIcon: hasText
              ? Tooltip(
                  message: '清空搜索',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _clear,
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: _headerMuted(context),
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 26,
            minHeight: 30,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _headerBorder(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _headerBlue(context)),
          ),
        ),
      ),
    );
  }
}

class _DutyToolbarField extends StatelessWidget {
  const _DutyToolbarField({
    required this.label,
    required this.child,
    this.labelColor,
  });
  final String label;
  final Widget child;
  final Color? labelColor;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: labelColor ?? _headerMuted(context)),
      ),
      child,
    ],
  );
}

Color _dutyColor(BuildContext context, SupervisionKind kind) => switch (kind) {
  SupervisionKind.afterSchool => context.appColors.success,
  SupervisionKind.custom => context.appColors.warning,
  SupervisionKind.morningStudy ||
  SupervisionKind.eveningStudy => context.appColors.blue,
};

/// 页面工具行：宽窗口左右分居两端；窄窗口合并为一条自然换行的 Wrap，
/// 避免两组控件各自成行、左对齐散落。
class _DutyToolbarRow extends StatelessWidget {
  const _DutyToolbarRow({required this.leading, required this.trailing});
  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 980) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: leading,
              ),
            ),
            const SizedBox(width: 20),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: trailing,
            ),
          ],
        );
      }
      return Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...leading,
          Container(width: 1, height: 18, color: _headerBorder(context)),
          ...trailing,
        ],
      );
    },
  );
}

class _DutyLegend extends StatelessWidget {
  const _DutyLegend({required this.activities});
  final Map<String, SupervisionKind> activities;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      for (final entry in activities.entries.take(4))
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _dutyColor(context, entry.value),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              entry.key,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: _headerSecondary(context)),
            ),
          ],
        ),
      if (activities.length > 4)
        Tooltip(
          message: activities.keys.skip(4).join('、'),
          child: Text(
            '其他 ${activities.length - 4} 项',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );
}

class _SupervisionWeek extends StatelessWidget {
  const _SupervisionWeek({
    required this.draft,
    required this.snapshot,
    required this.historical,
    required this.view,
    required this.day,
    required this.searchQuery,
    required this.missingOnly,
    required this.preferenceOnly,
    required this.preferenceMisses,
    required this.statuses,
    required this.selectedPostId,
    required this.onSelect,
    required this.onClear,
    required this.selection,
    this.onResetFilter,
  });
  final _DutySelectionRegionState selection;
  final SupervisionDraft draft;
  final SchedulingSnapshot snapshot;
  final SupervisionVersion? historical;
  final _DutyView view;
  final int? day;
  final String searchQuery;
  final bool missingOnly;
  final bool preferenceOnly;
  final Set<String> preferenceMisses;
  final Map<String, String> statuses;
  final String? selectedPostId;
  final ValueChanged<SupervisionPost>? onSelect;
  final ValueChanged<SupervisionPost>? onClear;
  final VoidCallback? onResetFilter;

  @override
  Widget build(BuildContext context) {
    final days = draft.posts.map((post) => post.weekday).toSet().toList()
      ..sort();
    final visibleDays = days.contains(day) ? [day!] : days;
    final history = {
      for (final occurrence
          in historical?.occurrences ?? const <SupervisionOccurrence>[])
        occurrence.post.id: occurrence,
    };
    final teachers = {
      for (final teacher in snapshot.teachers) teacher.id: teacher.displayName,
    };
    final classes = {
      for (final group in snapshot.classes) group.id: group.name,
    };
    final stages = {for (final stage in snapshot.stages) stage.id: stage.name};
    final normalizedQuery = searchQuery.trim().toLowerCase();
    bool matchesSearch(SupervisionPost post) {
      if (normalizedQuery.isEmpty) return true;
      final teacherName =
          history[post.id]?.teacherName ?? teachers[draft.assignments[post.id]];
      return post.groupName.toLowerCase().contains(normalizedQuery) ||
          post.classIds.any(
            (id) => (classes[id] ?? id).toLowerCase().contains(normalizedQuery),
          ) ||
          (teacherName?.toLowerCase().contains(normalizedQuery) ?? false);
    }

    final classOrder = {
      for (final entry in snapshot.classes.indexed) entry.$2.id: entry.$1,
    };
    final all = draft.posts.toList()
      ..sort((a, b) {
        final time = _postMinute(
          snapshot,
          a,
        ).compareTo(_postMinute(snapshot, b));
        if (time != 0) return time;
        final period = a.periodTypeId.compareTo(b.periodTypeId);
        if (period != 0) return period;
        final first = a.lessonIndices.first.compareTo(b.lessonIndices.first);
        if (first != 0) return first;
        final group = (classOrder[a.classIds.firstOrNull] ?? 999999).compareTo(
          classOrder[b.classIds.firstOrNull] ?? 999999,
        );
        return group != 0 ? group : a.id.compareTo(b.id);
      });
    final posts = all
        .where(
          (post) =>
              visibleDays.contains(post.weekday) &&
              matchesSearch(post) &&
              (!missingOnly || !draft.assignments.containsKey(post.id)) &&
              (!preferenceOnly || preferenceMisses.contains(post.id)),
        )
        .toList();
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                normalizedQuery.isNotEmpty
                    ? Icons.search_off_rounded
                    : Icons.check_circle_outline_rounded,
                size: 32,
                color: context.appColors.muted,
              ),
              const SizedBox(height: 10),
              Text(
                normalizedQuery.isNotEmpty
                    ? '没有匹配的班级或教师。'
                    : preferenceOnly
                    ? '当前范围没有偏好未满足的岗位。'
                    : missingOnly
                    ? '当前范围没有待安排岗位。'
                    : '当天没有带班岗位。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.appColors.muted),
              ),
              if (onResetFilter != null) ...[
                const SizedBox(height: 12),
                AppGhostButton(
                  onPressed: onResetFilter,
                  child: Text(
                    normalizedQuery.isNotEmpty ? '清空搜索条件' : '查看全部岗位',
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    Widget tile(
      SupervisionPost post, {
      bool compact = false,
      String? instance,
    }) => selection.item(
      post.id,
      instance: instance,
      child: _WeekPost(
        post: post,
        group: post.groupName.isNotEmpty
            ? post.groupName
            : (history[post.id]?.classNames ??
                      post.classIds.map((id) => classes[id] ?? id))
                  .join('、'),
        teacher:
            history[post.id]?.teacherName ??
            teachers[draft.assignments[post.id]],
        detail: compact
            ? '${post.name == _postPeriod(snapshot, post)?.name ? '' : '${post.name} · '}${_slotLabel(snapshot, post)}${post.location.isEmpty ? '' : ' · ${post.location}'}'
            : null,
        selected: selection.selectionMode
            ? selection.isSelected(post.id)
            : selectedPostId == post.id,
        selectionMode: selection.selectionMode,
        status: statuses[post.id],
        onToggleSelection: () => selection.toggle(post.id),
        onTap: selection.selectionMode
            ? () => selection.toggle(post.id)
            : onSelect == null
            ? null
            : () => onSelect!(post),
        onClear: onClear == null || !draft.assignments.containsKey(post.id)
            ? null
            : () => onClear!(post),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (view != _DutyView.week) {
          return _grouped(
            context,
            constraints,
            all,
            posts,
            tile,
            classes,
            teachers,
          );
        }
        final slots = <String, List<SupervisionPost>>{};
        for (final post in posts) {
          (slots[_dutySlotKey(post)] ??= []).add(post);
        }
        return _DutyTable(
          vertical: selection.vertical,
          horizontal: selection.horizontal,
          minWidth: 184 + visibleDays.length * 150.0,
          firstWidth: 184,
          headers: [
            const _WeekAxisLabel(label: '节次 / 时间'),
            for (final day in visibleDays)
              _WeekAxisLabel(label: _weekdays[day - 1], centered: true),
          ],
          rows: [
            for (final slot in slots.values)
              [
                _DutyPeriodCard(
                  title:
                      '${_postPeriod(snapshot, slot.first)?.name ?? slot.first.periodTypeId} · ${_weekIndexLabel(slot.first)}',
                  time: _weekTime(snapshot, slot.first),
                  stage: stages[slot.first.stageId],
                ),
                for (final day in visibleDays)
                  _postColumn(slot.where((post) => post.weekday == day), tile),
              ],
          ],
        );
      },
    );
  }

  Widget _postColumn(
    Iterable<SupervisionPost> posts,
    Widget Function(SupervisionPost, {bool compact, String? instance}) tile, {
    Key? key,
  }) => Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: posts.isEmpty
        ? [const _DutyEmptySlot()]
        : [
            for (final post in posts)
              tile(post, instance: key is ValueKey<String> ? key.value : null),
          ],
  );

  Widget _grouped(
    BuildContext context,
    BoxConstraints constraints,
    List<SupervisionPost> all,
    List<SupervisionPost> posts,
    Widget Function(SupervisionPost, {bool compact, String? instance}) tile,
    Map<String, String> classes,
    Map<String, String> teachers,
  ) {
    final byClass = view == _DutyView.schoolClass;
    final keys = <String>{
      for (final post in posts)
        if (byClass)
          ...post.classIds
        else
          draft.assignments[post.id] ?? '_unassigned',
    };
    bool matches(SupervisionPost post, String id) => byClass
        ? post.classIds.contains(id)
        : (draft.assignments[post.id] ?? '_unassigned') == id;
    String name(String id) => byClass
        ? classes[id] ?? id
        : id == '_unassigned'
        ? '待安排教师'
        : teachers[id] ??
              historical?.occurrences
                  .where((row) => row.teacherId == id)
                  .firstOrNull
                  ?.teacherName ??
              id;
    final order = byClass
        ? {for (final entry in snapshot.classes.indexed) entry.$2.id: entry.$1}
        : {
            for (final entry in snapshot.teachers.indexed)
              entry.$2.id: entry.$1,
          };
    final ids = keys.toList()
      ..sort((a, b) {
        final rank = (order[a] ?? 999999).compareTo(order[b] ?? 999999);
        return rank != 0 ? rank : name(a).compareTo(name(b));
      });
    final slots = <String, SupervisionPost>{
      for (final post in posts) _dutySlotKey(post): post,
    };
    Widget rowLabel(String id) => Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name(id),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            '本周 ${all.where((post) => matches(post, id)).fold(0, (sum, post) => sum + post.lessonIndices.length)} 节',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.muted),
          ),
        ],
      ),
    );
    return _DutyTable(
      vertical: selection.vertical,
      horizontal: selection.horizontal,
      firstWidth: 190,
      minWidth: 190 + slots.length * 160.0,
      headers: [
        _WeekAxisLabel(label: byClass ? '班级' : '教师'),
        for (final post in slots.values)
          _WeekAxisLabel(
            label:
                '${_postPeriod(snapshot, post)?.name ?? post.periodTypeId} · ${_weekIndexLabel(post)}',
            detail: _weekTime(snapshot, post),
            centered: true,
          ),
      ],
      rows: [
        for (final id in ids)
          [
            rowLabel(id),
            for (final entry in slots.entries)
              _postColumn(
                posts.where(
                  (post) =>
                      matches(post, id) && _dutySlotKey(post) == entry.key,
                ),
                tile,
                key: ValueKey(
                  'duty-${byClass ? 'class' : 'teacher'}-$id-${entry.value.periodTypeId}-${entry.value.lessonIndices.join(',')}',
                ),
              ),
          ],
      ],
    );
  }
}

String _dutySlotKey(SupervisionPost post) =>
    '${post.stageId}|${post.periodTypeId}|${post.lessonIndices.join(',')}';

class _DutyTable extends StatelessWidget {
  const _DutyTable({
    required this.headers,
    required this.rows,
    required this.minWidth,
    required this.firstWidth,
    required this.vertical,
    required this.horizontal,
  });
  final List<Widget> headers;
  final List<List<Widget>> rows;
  final double minWidth;
  final double firstWidth;
  final ScrollController vertical;
  final ScrollController horizontal;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Scrollbar(
      controller: horizontal,
      thumbVisibility: true,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: horizontal,
        child: SizedBox(
          width: constraints.maxWidth < minWidth
              ? minWidth
              : constraints.maxWidth,
          height: constraints.maxHeight,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  border: Border(
                    bottom: BorderSide(color: context.appColors.border),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Table(
                  columnWidths: {0: FixedColumnWidth(firstWidth)},
                  children: [TableRow(children: headers)],
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: vertical,
                  child: SingleChildScrollView(
                    controller: vertical,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Table(
                      columnWidths: {0: FixedColumnWidth(firstWidth)},
                      children: [
                        for (final row in rows)
                          TableRow(
                            children: [
                              for (final cell in row.indexed)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    cell.$1 == 0 ? 0 : 4,
                                    0,
                                    cell.$1 == 0 ? 0 : 4,
                                    8,
                                  ),
                                  child: cell.$2,
                                ),
                            ],
                          ),
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
}

class _WeekAxisLabel extends StatelessWidget {
  const _WeekAxisLabel({
    required this.label,
    this.detail,
    this.centered = false,
  });
  final String label;
  final String? detail;
  final bool centered;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: centered ? 12 : 0, vertical: 8),
    child: Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: centered
                ? context.appColors.inkSecondary
                : context.appColors.muted,
            fontSize: centered ? 13 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detail != null)
          Text(
            detail!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 12, color: context.appColors.muted),
          ),
      ],
    ),
  );
}

class _WeekPost extends StatelessWidget {
  const _WeekPost({
    required this.post,
    required this.group,
    required this.teacher,
    required this.selected,
    required this.onTap,
    required this.onClear,
    required this.selectionMode,
    required this.onToggleSelection,
    this.status,
    this.detail,
  });
  final SupervisionPost post;
  final String group;
  final String? teacher;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final String? detail;
  final bool selectionMode;
  final String? status;
  final VoidCallback onToggleSelection;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: selectionMode ? '' : '${post.name} · $group · ${teacher ?? '待安排'}',
    child: f.FTappable(
      selected: selected,
      onPress: onTap,
      builder: (context, variants, child) {
        final hovered =
            variants.contains(f.FTappableVariant.hovered) ||
            variants.contains(f.FTappableVariant.focused);
        final colors = context.appColors;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: selected
                ? colors.selectedBlue
                : hovered
                ? colors.tableHeader
                : colors.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: colors.cardShadow,
            border: selected || hovered
                ? Border.all(color: colors.blue, width: selected ? 1.5 : 1)
                : null,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 9,
                bottom: 9,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: selected || hovered
                        ? colors.blue
                        : teacher == null
                        ? colors.warning.withValues(alpha: .35)
                        : _dutyColor(context, post.kind).withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12, 9, selectionMode ? 32 : 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (teacher == null) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: selected ? colors.blue : colors.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            teacher ?? '待安排',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 12,
                                  color: selected
                                      ? colors.blue
                                      : teacher == null
                                      ? colors.warning
                                      : colors.inkSecondary,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: AppBadge(
                          label: status!,
                          foreground: status == '指派需调整'
                              ? colors.destructive
                              : colors.warning,
                          background: status == '指派需调整'
                              ? colors.destructiveSurface
                              : colors.warningSurface,
                        ),
                      ),
                    if (detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontSize: 12, color: colors.muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (selectionMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: AppCheckbox(
                    value: selected,
                    onChanged: (_) => onToggleSelection(),
                  ),
                ),
              if (hovered && onTap != null && !selectionMode)
                Positioned(
                  top: 3,
                  right: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIconButton(
                          icon: Icons.swap_horiz,
                          onPressed: onTap,
                          tooltip: '更换教师',
                          iconSize: 14,
                        ),
                        if (onClear != null)
                          AppIconButton(
                            icon: Icons.person_remove_outlined,
                            onPressed: onClear,
                            tooltip: '清除指派',
                            iconSize: 14,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

String? _weekTime(SchedulingSnapshot snapshot, SupervisionPost post) {
  final times = _postPeriod(snapshot, post)?.lessonTimes;
  final start = times
      ?.where((time) => time.lessonIndex == post.lessonIndices.first)
      .firstOrNull
      ?.startLabel;
  final end = times
      ?.where((time) => time.lessonIndex == post.lessonIndices.last)
      .firstOrNull
      ?.endLabel;
  return start == null || end == null ? null : '$start–$end';
}

String _weekIndexLabel(SupervisionPost post) => post.lessonIndices.length == 1
    ? '第 ${post.lessonIndices.first} 节'
    : '第 ${post.lessonIndices.first}–${post.lessonIndices.last} 节';

/// 空岗位占位：虚线框 + 「暂无岗位」，表达该时段此天没有岗位，
/// 与待安排（有岗位但未指派教师的橙色提示）区分开。
class _DutyEmptySlot extends StatelessWidget {
  const _DutyEmptySlot();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    constraints: const BoxConstraints(minHeight: 64),
    child: CustomPaint(
      painter: _DashedSlotPainter(color: context.appColors.border),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        child: Text(
          '暂无岗位',
          style: TextStyle(fontSize: 12, color: context.appColors.muted),
        ),
      ),
    ),
  );
}

class _DashedSlotPainter extends CustomPainter {
  const _DashedSlotPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 4, metric.length);
        final tangent = metric.getTangentForOffset(distance)!;
        final endTangent = metric.getTangentForOffset(next)!;
        canvas.drawLine(tangent.position, endTangent.position, paint);
        distance = next + 3;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedSlotPainter old) => old.color != color;
}

class _DutyOutlineButton extends StatelessWidget {
  const _DutyOutlineButton({required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;
  @override
  Widget build(BuildContext context) => f.FButton(
    size: f.FButtonSizeVariant.sm,
    variant: f.FButtonVariant.outline,
    mainAxisSize: MainAxisSize.min,
    onPress: onPressed,
    child: child,
  );
}

f.FItemStyleDelta _dutyListStyle(BuildContext context) =>
    f.FItemStyleDelta.delta(
      backgroundColor: f.FVariantsValueDelta.delta([
        f.FVariantValueDeltaOperation.base(context.appColors.surface),
      ]),
      contentDecoration: f.FVariantsDelta.delta([
        f.FVariantOperation.base(
          f.DecorationDelta.shapeDelta(color: context.appColors.surface),
        ),
      ]),
    );
