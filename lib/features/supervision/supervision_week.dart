part of 'supervision_page.dart';

class _WeekFilter extends StatelessWidget {
  const _WeekFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => f.FTappable(
    selected: selected,
    onPress: onTap,
    builder: (context, variants, child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
      decoration: BoxDecoration(
        color:
            variants.contains(f.FTappableVariant.hovered) ||
                variants.contains(f.FTappableVariant.focused)
            ? context.appColors.tableHeader
            : null,
        border: Border(
          bottom: BorderSide(
            color: selected ? context.appColors.blue : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: selected
              ? context.appColors.ink
              : context.appColors.inkSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
  );
}

class _SupervisionWeek extends StatelessWidget {
  const _SupervisionWeek({
    required this.draft,
    required this.snapshot,
    required this.historical,
    required this.day,
    required this.missingOnly,
    required this.selectedPostId,
    required this.onSelect,
  });

  final SupervisionDraft draft;
  final SchedulingSnapshot snapshot;
  final SupervisionVersion? historical;
  final int? day;
  final bool missingOnly;
  final String? selectedPostId;
  final ValueChanged<SupervisionPost>? onSelect;

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
    final posts =
        draft.posts
            .where(
              (post) =>
                  visibleDays.contains(post.weekday) &&
                  (!missingOnly || !draft.assignments.containsKey(post.id)),
            )
            .toList()
          ..sort((a, b) {
            final time = _postMinute(
              snapshot,
              a,
            ).compareTo(_postMinute(snapshot, b));
            if (time != 0) return time;
            final period = a.periodTypeId.compareTo(b.periodTypeId);
            if (period != 0) return period;
            final first = a.lessonIndices.first.compareTo(
              b.lessonIndices.first,
            );
            return first != 0 ? first : a.id.compareTo(b.id);
          });
    if (posts.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('当前范围的岗位已全部安排。')),
      );
    }
    Widget tile(SupervisionPost post, {bool compact = false}) => _WeekPost(
      post: post,
      group: post.groupName.isNotEmpty
          ? post.groupName
          : (history[post.id]?.classNames ??
                    post.classIds.map((id) => classes[id] ?? id))
                .join('、'),
      teacher:
          history[post.id]?.teacherName ?? teachers[draft.assignments[post.id]],
      detail: compact
          ? [
              if (stages.length > 1) stages[post.stageId],
              _slotLabel(snapshot, post),
              if (post.location.isNotEmpty) post.location,
            ].whereType<String>().join(' · ')
          : null,
      selected: selectedPostId == post.id,
      onTap: onSelect == null ? null : () => onSelect!(post),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 750 || visibleDays.length == 1) {
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              for (final weekday in visibleDays)
                if (posts.any((post) => post.weekday == weekday)) ...[
                  _WeekAxisLabel(label: _weekdays[weekday - 1]),
                  for (final post in posts.where(
                    (post) => post.weekday == weekday,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: tile(post, compact: true),
                    ),
                ],
            ],
          );
        }

        final slots = <(String, String, String), List<SupervisionPost>>{};
        for (final post in posts) {
          final key = (
            post.stageId,
            post.periodTypeId,
            post.lessonIndices.join(','),
          );
          (slots[key] ??= []).add(post);
        }
        final minWidth = 138.0 + visibleDays.length * 106.0;
        final width = constraints.maxWidth < minWidth
            ? minWidth
            : constraints.maxWidth;
        final colors = context.appColors;
        final border = BorderSide(color: colors.border);
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Table(
                columnWidths: const {0: FixedColumnWidth(138)},
                border: TableBorder(
                  horizontalInside: border,
                  verticalInside: border,
                ),
                children: [
                  TableRow(
                    children: [
                      const _WeekAxisLabel(label: '作息节次'),
                      for (final weekday in visibleDays)
                        _WeekAxisLabel(label: _weekdays[weekday - 1]),
                    ],
                  ),
                  for (final slot in slots.values)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 11, 8, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _postPeriod(snapshot, slot.first)?.name ??
                                    slot.first.periodTypeId,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                _weekIndexLabel(slot.first),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (_weekTime(snapshot, slot.first)
                                  case final time?)
                                Text(
                                  time,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (stages.length > 1)
                                if (stages[slot.first.stageId]
                                    case final stage?)
                                  Text(
                                    stage,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                            ],
                          ),
                        ),
                        for (final weekday in visibleDays)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!slot.any((post) => post.weekday == weekday))
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    '—',
                                    style: TextStyle(color: colors.muted),
                                  ),
                                ),
                              for (final post in slot.where(
                                (post) => post.weekday == weekday,
                              ))
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    5,
                                    5,
                                    5,
                                    0,
                                  ),
                                  child: tile(post),
                                ),
                              const SizedBox(height: 5),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WeekAxisLabel extends StatelessWidget {
  const _WeekAxisLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.appColors.inkSecondary,
        fontWeight: FontWeight.w600,
      ),
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
    this.detail,
  });

  final SupervisionPost post;
  final String group;
  final String? teacher;
  final bool selected;
  final VoidCallback? onTap;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context).textTheme;
    final missing = teacher == null;
    final radius = BorderRadius.circular(7);
    final assignment = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (missing) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            teacher ?? '待安排',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          post.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          detail == null ? group : '$group · $detail',
          maxLines: detail == null ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: theme.bodySmall?.copyWith(color: colors.inkSecondary),
        ),
      ],
    );
    return f.FTappable(
      selected: selected,
      onPress: onTap,
      builder: (context, variants, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: selected
              ? colors.selectedBlue
              : missing
              ? colors.warningSurface
              : variants.contains(f.FTappableVariant.hovered)
              ? colors.tableHeader
              : colors.canvas,
          border: variants.contains(f.FTappableVariant.focused)
              ? Border.all(color: colors.blue)
              : null,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: detail == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [identity, const SizedBox(height: 4), assignment],
                  )
                : Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 112),
                        child: assignment,
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: 5),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: colors.inkSecondary,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
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
