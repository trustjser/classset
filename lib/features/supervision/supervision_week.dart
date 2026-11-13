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
      color: pills ? Colors.transparent : context.appColors.canvas,
      border: pills ? null : Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: EdgeInsets.all(pills ? 0 : 2),
      child: Wrap(
        spacing: pills ? 6 : 2,
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
                  borderRadius: BorderRadius.circular(pills ? 99 : 6),
                  boxShadow: !pills && value == entry.key
                      ? context.appColors.cardShadow
                      : null,
                  color: value == entry.key
                      ? pills
                            ? context.appColors.blue
                            : context.appColors.surface
                      : variants.contains(f.FTappableVariant.hovered)
                      ? context.appColors.surface
                      : null,
                  border: variants.contains(f.FTappableVariant.focused)
                      ? Border.all(color: context.appColors.blue)
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
                            color: value == entry.key
                                ? f.FTheme.of(context).colors.primaryForeground
                                : context.appColors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    color: value == entry.key
                        ? pills
                              ? f.FTheme.of(context).colors.primaryForeground
                              : context.appColors.ink
                        : context.appColors.inkSecondary,
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

class _DutyToolbarField extends StatelessWidget {
  const _DutyToolbarField({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.appColors.muted),
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

/// Keep version/configuration separate from filters/view controls.
class _DutyToolbarLine extends StatelessWidget {
  const _DutyToolbarLine({required this.leading, required this.trailing});
  final Widget leading;
  final Widget trailing;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 980
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: leading),
              const SizedBox(width: 20),
              trailing,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [leading, const SizedBox(height: 8), trailing],
          ),
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
                  ?.copyWith(color: context.appColors.inkSecondary),
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
    required this.missingOnly,
    required this.preferenceOnly,
    required this.preferenceMisses,
    required this.statuses,
    required this.selectedPostId,
    required this.onSelect,
    required this.onClear,
    required this.selection,
  });
  final _DutySelectionRegionState selection;
  final SupervisionDraft draft;
  final SchedulingSnapshot snapshot;
  final SupervisionVersion? historical;
  final _DutyView view;
  final int? day;
  final bool missingOnly;
  final bool preferenceOnly;
  final Set<String> preferenceMisses;
  final Map<String, String> statuses;
  final String? selectedPostId;
  final ValueChanged<SupervisionPost>? onSelect;
  final ValueChanged<SupervisionPost>? onClear;

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
              (!missingOnly || !draft.assignments.containsKey(post.id)) &&
              (!preferenceOnly || preferenceMisses.contains(post.id)),
        )
        .toList();
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            preferenceOnly
                ? '当前范围没有偏好未满足的岗位。'
                : missingOnly
                ? '当前范围没有待安排岗位。'
                : '当天没有带班岗位。',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.appColors.muted),
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
        ? [const Padding(padding: EdgeInsets.all(16), child: Text('—'))]
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
                ?.copyWith(fontSize: 11, color: context.appColors.muted),
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
                                  fontSize: 11.5,
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
                      Text(
                        status!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: status == '指派需调整'
                              ? colors.destructive
                              : colors.warning,
                        ),
                      ),
                    if (detail != null)
                      Text(
                        detail!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontSize: 11, color: colors.muted),
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
