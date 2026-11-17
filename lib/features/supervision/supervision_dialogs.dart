part of 'supervision_page.dart';

/// 「选择带班教师」浮层面板 —— 全站唯一的一套设置界面。
///
/// 由页面以 [Stack] + [Positioned] 浮在周网格之上（不挤压布局、不进路由），
/// 所有窗口宽度共用同一份实现；窄屏时由外层改为贴底全宽面板。
/// 所有操作通过回调直接落到页面，不依赖 Navigator 返回值。
class _TeacherPickerPanel extends StatefulWidget {
  const _TeacherPickerPanel({
    required this.snapshot,
    required this.draft,
    required this.post,
    this.onRemove,
    this.editable = true,
    this.onConfirm,
    this.onSettings,
    this.onManagePool,
    this.onClose,
    super.key,
  });

  final SchedulingSnapshot snapshot;
  final SupervisionDraft draft;
  final SupervisionPost post;
  final VoidCallback? onRemove;
  final bool editable;
  final ValueChanged<String>? onConfirm;
  final VoidCallback? onSettings;
  final VoidCallback? onManagePool;
  final VoidCallback? onClose;

  @override
  State<_TeacherPickerPanel> createState() => _TeacherPickerPanelState();
}

enum _PickFilter { recommend, available, load, all }

enum _PickBadge {
  current,
  recommended,
  limit,
  conflict,
  outside,
  blocked,
  none,
}

/// 列表中的一行：分组标题或一位候选教师。
class _PickRow {
  _PickRow.group(this.label, this.count) : candidate = null, rank = 0;
  _PickRow.teacher(this.candidate, this.rank) : label = null, count = 0;

  final String? label;
  final int count;
  final _PickCandidate? candidate;
  final int rank;
}

class _PickCandidate {
  const _PickCandidate({
    required this.teacher,
    required this.inPool,
    required this.blockers,
    required this.reasons,
    required this.preferenceUnmet,
    required this.lessons,
    required this.days,
    required this.maxLessons,
    required this.isCurrent,
  });

  final Teacher teacher;
  final bool inPool;
  final List<String> blockers;
  final List<String> reasons;
  final bool preferenceUnmet;

  /// 指派该教师后的本周带班节数与天数，口径与 [SupervisionAllocator]
  /// 的硬约束计算保持一致（本岗位 + 其他已指派岗位）。
  final int lessons;
  final int days;
  final int? maxLessons;
  final bool isCurrent;

  bool get available => inPool && blockers.isEmpty;

  _PickBadge get badge {
    if (!inPool) return _PickBadge.outside;
    if (blockers.isEmpty) {
      if (isCurrent) return _PickBadge.current;
      if (reasons.isNotEmpty && !preferenceUnmet) {
        return _PickBadge.recommended;
      }
      return _PickBadge.none;
    }
    if (blockers.any((reason) => reason.contains('上限'))) {
      return _PickBadge.limit;
    }
    if (blockers.any(
      (reason) =>
          reason.contains('已有') ||
          reason.contains('禁排') ||
          reason.contains('正课') ||
          reason.contains('冲突'),
    )) {
      return _PickBadge.conflict;
    }
    return _PickBadge.blocked;
  }
}

class _TeacherPickerPanelState extends State<_TeacherPickerPanel> {
  final _search = TextEditingController();
  String _query = '';
  _PickFilter _filter = _PickFilter.recommend;
  late String? _selected = widget.draft.assignments[widget.post.id];
  bool _pendingClear = false;
  bool _confirmRemove = false;
  final _blockers = <String, List<String>>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TeacherPickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft ||
        oldWidget.snapshot != widget.snapshot ||
        oldWidget.post != widget.post) {
      _blockers.clear();
      _selected = widget.draft.assignments[widget.post.id];
      _pendingClear = false;
    }
  }

  List<String> _blockersFor(String id, SupervisionMatching matching) =>
      _blockers.putIfAbsent(
        id,
        () => const SupervisionAllocator().teacherBlockers(
          widget.snapshot,
          widget.draft,
          widget.post,
          id,
          matching: matching,
        ),
      );

  List<_PickCandidate> _candidates(SupervisionMatching matching) {
    final draft = widget.draft;
    final post = widget.post;
    final current = draft.assignments[post.id];
    final pool = draft.teachersFor(post);
    final result = <_PickCandidate>[];
    for (final teacher in widget.snapshot.teachers) {
      final others = draft.posts.where(
        (other) =>
            other.id != post.id && draft.assignments[other.id] == teacher.id,
      );
      result.add(
        _PickCandidate(
          teacher: teacher,
          inPool: pool.contains(teacher.id),
          blockers: _blockersFor(teacher.id, matching),
          reasons: matching.reasons(post, teacher.id),
          preferenceUnmet: matching.hasUnmetPreferences(
            draft,
            post,
            teacher.id,
          ),
          lessons:
              post.lessonIndices.length +
              others.fold<int>(
                0,
                (sum, other) => sum + other.lessonIndices.length,
              ),
          days: {post.weekday, ...others.map((other) => other.weekday)}.length,
          maxLessons: draft.rules[teacher.id]?.maxLessons,
          isCurrent: teacher.id == current,
        ),
      );
    }
    result.sort((a, b) {
      int rank(_PickCandidate item) => item.isCurrent
          ? 0
          : item.inPool
          ? 1
          : 2;
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byAvailable = (a.available ? 0 : 1).compareTo(b.available ? 0 : 1);
      if (byAvailable != 0) return byAvailable;
      return matching.compare(draft, post, a.teacher.id, b.teacher.id);
    });
    return result;
  }

  bool _matches(_PickCandidate candidate, String query) {
    if (query.isEmpty) return true;
    final subjects = candidate.teacher.subjectIds
        .map(
          (id) =>
              widget.snapshot.subjects
                  .where((subject) => subject.id == id)
                  .firstOrNull
                  ?.name ??
              '',
        )
        .join(' ');
    return '${candidate.teacher.searchText} $subjects '
            '${candidate.reasons.join(' ')}'
        .toLowerCase()
        .contains(query);
  }

  List<_PickCandidate> _shown(List<_PickCandidate> all) {
    final query = _query.trim().toLowerCase();
    final list = all.where((item) => _matches(item, query)).toList();
    if (_filter == _PickFilter.recommend) {
      return list.where((item) => item.inPool).toList();
    }
    if (_filter == _PickFilter.available) {
      return list.where((item) => item.available).toList();
    }
    if (_filter == _PickFilter.load) {
      return list.where((item) => item.inPool).toList()
        ..sort((a, b) => a.lessons.compareTo(b.lessons));
    }
    return list;
  }

  String _teacherName(String id) =>
      widget.snapshot.teachers
          .where((teacher) => teacher.id == id)
          .firstOrNull
          ?.displayName ??
      id;

  void _select(_PickCandidate candidate) {
    if (!widget.editable || !candidate.available) return;
    setState(() {
      _selected = candidate.teacher.id;
      _pendingClear = false;
    });
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _filter = _PickFilter.recommend;
    });
  }

  /// 操作直接落到页面：确认后浮层保留，草稿状态行与主按钮即时反馈，
  /// 与 HTML 设计稿一致（关闭由右上角 × 完成）。
  void _finish(String picked) => widget.onConfirm?.call(picked);
  void _openSettings() => widget.onSettings?.call();
  void _openPool() => widget.onManagePool?.call();
  void _close() => widget.onClose?.call();

  bool _canConfirm(String? current) =>
      widget.editable &&
      (_pendingClear || (_selected != null && _selected != current));

  String _confirmLabel(String? current) {
    if (_pendingClear) return '确认清除';
    if (!_canConfirm(current)) {
      return current == null ? '无需变更' : '已是指派教师';
    }
    return '确认指派';
  }

  void _confirm(String? current) {
    if (!widget.editable) return;
    if (_pendingClear) {
      _finish('');
      return;
    }
    final selected = _selected;
    if (selected == null || selected == current) return;
    _finish(selected);
  }

  @override
  Widget build(BuildContext context) {
    final matching = SupervisionMatching(widget.snapshot);
    final all = _candidates(matching);
    final shown = _shown(all);
    final assignable = shown.where((item) => item.available).toList();
    final blocked = shown.where((item) => !item.available).toList();
    final rows = <_PickRow>[
      if (assignable.isNotEmpty) ...[
        _PickRow.group('推荐与可安排', assignable.length),
        for (var i = 0; i < assignable.length; i++)
          _PickRow.teacher(assignable[i], i + 1),
      ],
      if (blocked.isNotEmpty) ...[
        _PickRow.group('不可指派', blocked.length),
        for (var i = 0; i < blocked.length; i++)
          _PickRow.teacher(blocked[i], assignable.length + i + 1),
      ],
    ];
    // 唯一的呈现形态：全高右侧抽屉，贴边、左侧描边与左向投影，
    // 由页面级 Stack 承载，不再受周表工作区高度限制。
    return Material(
      key: const ValueKey('duty-teacher-panel'),
      type: MaterialType.transparency,
      child: SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.appColors.surface,
            border: Border(left: BorderSide(color: context.appColors.border)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                offset: Offset(-12, 0),
                blurRadius: 32,
              ),
            ],
          ),
          child: _body(matching, all, rows, shown.length, assignable.length),
        ),
      ),
    );
  }

  Widget _candidateList(List<_PickRow> rows) {
    if (rows.isEmpty) return _emptyState();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final label = row.label;
        if (label != null) return _groupLabel(label, row.count);
        return _candidateCard(row.candidate!, row.rank);
      },
    );
  }

  Widget _body(
    SupervisionMatching matching,
    List<_PickCandidate> all,
    List<_PickRow> rows,
    int shownCount,
    int assignableCount,
  ) {
    final current = widget.draft.assignments[widget.post.id];
    final fixed = <Widget>[
      _header(),
      _poolBar(matching, all),
      _tools(),
      _statusLine(shownCount, assignableCount),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // 底部操作区始终固定可见；矮窗口只让上半部分整体滚动。
        // 空态不进滚动裁剪，否则「清除筛选」可能被挤出可点击区域。
        final cramped =
            constraints.maxHeight.isFinite && constraints.maxHeight < 420;
        Widget scrollArea;
        if (rows.isEmpty || !cramped) {
          scrollArea = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...fixed,
              Expanded(child: _candidateList(rows)),
            ],
          );
        } else {
          scrollArea = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...fixed,
                SizedBox(height: 200, child: _candidateList(rows)),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: scrollArea),
            _footer(current),
          ],
        );
      },
    );
  }

  Widget _header() {
    final colors = context.appColors;
    final post = widget.post;
    final classes = {
      for (final group in widget.snapshot.classes) group.id: group.name,
    };
    final group = post.groupName.isNotEmpty
        ? post.groupName
        : post.classIds.map((id) => classes[id] ?? id).join('、');
    final time = _weekTime(widget.snapshot, post);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '带班岗位 · 人员指派',
                style: TextStyle(fontSize: 11, color: colors.muted),
              ),
              const Spacer(),
              AppMenuButton(
                items: [
                  AppMenuItem(
                    label: '岗位人员设置',
                    enabled: widget.editable,
                    onPressed: _openSettings,
                  ),
                  AppMenuItem(
                    label: '移除岗位',
                    destructive: true,
                    enabled: widget.onRemove != null,
                    onPressed: () => setState(() => _confirmRemove = true),
                  ),
                ],
                child: SizedBox(
                  key: const ValueKey('duty-teacher-more'),
                  width: 28,
                  height: 28,
                  child: Icon(Icons.more_horiz, size: 18, color: colors.muted),
                ),
              ),
              const SizedBox(width: 2),
              AppIconButton(
                key: const ValueKey('duty-teacher-close'),
                icon: Icons.close,
                iconSize: 18,
                tooltip: '关闭教师面板',
                onPressed: _close,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '选择带班教师',
            style: TextStyle(
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$group · ${post.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip(_weekdays[post.weekday - 1], primary: true),
              _chip(_slotLabel(widget.snapshot, post)),
              if (time != null) _chip(time),
              _chip(
                post.classIds.length == 1
                    ? '单班岗位'
                    : '合班 · ${post.classIds.length} 个班',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, {bool primary = false}) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: primary ? colors.selectedBlue : colors.canvas,
        border: primary ? null : Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
          fontWeight: primary ? FontWeight.w500 : FontWeight.normal,
          color: primary ? colors.blue : colors.inkSecondary,
        ),
      ),
    );
  }

  Widget _poolBar(SupervisionMatching matching, List<_PickCandidate> all) {
    final colors = context.appColors;
    final post = widget.post;
    final pool = widget.draft.teachersFor(post);
    final candidateCount = widget.snapshot.teachers
        .where((teacher) => pool.contains(teacher.id))
        .length;
    final availableCount = all.where((item) => item.available).length;
    String label(SupervisionPreference preference) => switch (preference) {
      SupervisionPreference.classTeacher => '本班',
      SupervisionPreference.gradeTeacher => '本年级',
      SupervisionPreference.subjectTeacher => '学科',
    };
    final order = [
      ...matching.activePreferences(widget.draft, post).map(label),
      widget.draft.preferencesFor(post).mode ==
              SupervisionMatchMode.balanceFirst
          ? '负载优先'
          : '负载',
    ].join(' › ');
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined, size: 15, color: colors.blue),
              const SizedBox(width: 8),
              Text(
                widget.draft.poolNameFor(post),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
              Text(
                ' · $candidateCount 人',
                style: TextStyle(fontSize: 11, color: colors.inkSecondary),
              ),
              const Spacer(),
              _link('管理 ›', _openPool),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '本时段可安排 $availableCount 人 · 排序 $order',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: colors.inkSecondary),
          ),
        ],
      ),
    );
  }

  Widget _link(String label, VoidCallback onPressed) {
    final colors = context.appColors;
    return f.FTappable(
      onPress: onPressed,
      builder: (context, variants, _) => Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: colors.blue,
          decoration: variants.contains(f.FTappableVariant.hovered)
              ? TextDecoration.underline
              : null,
        ),
      ),
    );
  }

  Widget _tools() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _DutySearchField(
              controller: _search,
              hint: '搜索姓名、任教学科',
              onChanged: (text) =>
                  setState(() => _query = text.trim().toLowerCase()),
              onClear: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 116,
            child: AppSelectField<_PickFilter>(
              compact: true,
              value: _filter,
              items: const {
                '推荐优先': _PickFilter.recommend,
                '仅看可安排': _PickFilter.available,
                '按负载排序': _PickFilter.load,
                '显示全部': _PickFilter.all,
              },
              onChanged: (value) {
                if (value != null) setState(() => _filter = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(int shown, int assignable) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          Text(
            '显示 $shown 位 · 其中 $assignable 位可指派',
            style: TextStyle(fontSize: 11, color: colors.muted),
          ),
          const Spacer(),
          Text(
            _filter == _PickFilter.load ? '按负载排序' : '按推荐度排序',
            style: TextStyle(fontSize: 11, color: colors.muted),
          ),
        ],
      ),
    );
  }

  Widget _groupLabel(String label, int count) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 8, 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.muted,
            ),
          ),
          const SizedBox(width: 6),
          Text('$count', style: TextStyle(fontSize: 11, color: colors.muted)),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: colors.border)),
        ],
      ),
    );
  }

  ({String label, Color text, Color background})? _badgeStyle(
    _PickBadge badge,
  ) {
    final colors = context.appColors;
    return switch (badge) {
      _PickBadge.current => (
        label: '当前指派',
        text: colors.blue,
        background: colors.selectedBlue,
      ),
      _PickBadge.recommended => (
        label: '推荐',
        text: colors.success,
        background: colors.successSurface,
      ),
      _PickBadge.limit => (
        label: '已达上限',
        text: colors.warning,
        background: colors.warningSurface,
      ),
      _PickBadge.conflict => (
        label: '时间冲突',
        text: colors.destructive,
        background: colors.destructiveSurface,
      ),
      _PickBadge.outside => (
        label: '不在候选池',
        text: colors.inkSecondary,
        background: colors.border,
      ),
      _PickBadge.blocked => (
        label: '不可指派',
        text: colors.destructive,
        background: colors.destructiveSurface,
      ),
      _PickBadge.none => null,
    };
  }

  Widget _whyChip(String label, {bool hit = true}) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: hit ? colors.selectedBlue : colors.canvas,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.4,
          fontWeight: hit ? FontWeight.w500 : FontWeight.normal,
          color: hit ? colors.blue : colors.inkSecondary,
        ),
      ),
    );
  }

  Widget _candidateCard(_PickCandidate candidate, int rank) {
    final colors = context.appColors;
    final enabled = candidate.available;
    final selected = !_pendingClear && _selected == candidate.teacher.id;
    final badge = _badgeStyle(candidate.badge);
    final chips = <Widget>[
      for (final reason in candidate.reasons) _whyChip(reason),
      if (candidate.reasons.isEmpty &&
          candidate.blockers.isEmpty &&
          !candidate.preferenceUnmet)
        _whyChip('无匹配偏好', hit: false),
      if (candidate.blockers.isEmpty && candidate.preferenceUnmet)
        _whyChip('偏好未满足', hit: false),
    ];
    final note = !candidate.inPool
        ? '加入「${widget.draft.poolNameFor(widget.post)}」后才能指派'
        : candidate.blockers.join(' · ');
    final noteColor = !candidate.inPool
        ? colors.muted
        : candidate.badge == _PickBadge.limit
        ? colors.warning
        : colors.destructive;
    final ratio = candidate.maxLessons == null
        ? null
        : (candidate.lessons / candidate.maxLessons!).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: f.FTappable(
        onPress: widget.editable && enabled ? () => _select(candidate) : null,
        builder: (context, variants, _) {
          final hovered = variants.contains(f.FTappableVariant.hovered);
          final focused = variants.contains(f.FTappableVariant.focused);
          final background = selected
              ? colors.selectedBlue
              : enabled
              ? (hovered ? colors.tableHeader : colors.surface)
              : colors.canvas;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected || focused ? colors.blue : colors.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.blue
                            : enabled
                            ? colors.canvas
                            : colors.border,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? colors.onAccent
                              : enabled
                              ? colors.inkSecondary
                              : colors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            candidate.teacher.displayName,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: enabled ? colors.ink : colors.inkSecondary,
                            ),
                          ),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: badge.background,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                badge.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                  color: badge.text,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? colors.blue : null,
                        border: Border.all(
                          color: selected ? colors.blue : colors.border,
                        ),
                      ),
                      child: selected
                          ? Icon(Icons.check, size: 13, color: colors.onAccent)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Wrap(spacing: 4, runSpacing: 4, children: chips),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Row(
                    children: [
                      Text(
                        '本周带班',
                        style: TextStyle(fontSize: 11, color: colors.muted),
                      ),
                      const SizedBox(width: 8),
                      if (ratio != null)
                        Expanded(
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: colors.canvas,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: ratio,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: ratio >= 1
                                      ? colors.warning
                                      : colors.blue,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      const SizedBox(width: 8),
                      Text(
                        candidate.maxLessons == null
                            ? '${candidate.lessons} 节 · ${candidate.days} 天'
                            : '${candidate.lessons} / ${candidate.maxLessons} 节 · ${candidate.days} 天',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: enabled ? colors.inkSecondary : colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (candidate.blockers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 30, top: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          candidate.inPool
                              ? Icons.error_outline
                              : Icons.info_outline,
                          size: 13,
                          color: noteColor,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            note,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              color: noteColor,
                            ),
                          ),
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

  Widget _emptyState() {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 32, color: colors.muted),
            const SizedBox(height: 10),
            Text(
              '没有找到匹配的教师',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '试试其他姓名或学科，也可清除筛选查看全部候选。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.inkSecondary),
            ),
            const SizedBox(height: 12),
            AppGhostButton(onPressed: _clearFilters, child: const Text('清除筛选')),
          ],
        ),
      ),
    );
  }

  Widget _footer(String? current) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: _confirmRemove ? _removeConfirm() : _normalFooter(current),
    );
  }

  Widget _removeConfirm() {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.destructiveSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 14, color: colors.destructive),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '移除后该岗位与指派将一并删除',
              style: TextStyle(fontSize: 12, color: colors.destructive),
            ),
          ),
          const SizedBox(width: 8),
          AppGhostButton(
            onPressed: () => setState(() => _confirmRemove = false),
            child: const Text('取消'),
          ),
          const SizedBox(width: 6),
          AppDestructiveButton(
            onPressed: widget.onRemove,
            child: const Text('确认移除'),
          ),
        ],
      ),
    );
  }

  Widget _normalFooter(String? current) {
    final colors = context.appColors;
    final changed =
        _pendingClear || (_selected != null && _selected != current);
    String draft;
    if (_pendingClear) {
      draft = '将清除当前指派，岗位变为「待安排」';
    } else if (changed) {
      draft = '草稿将更新为：${_teacherName(_selected!)} · 确认后仍需「保存草稿」';
    } else {
      draft = '当前指派：${current == null ? '待安排' : _teacherName(current)} · 无需变更';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: changed ? colors.selectedBlue : colors.canvas,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                changed ? Icons.edit_outlined : Icons.info_outline,
                size: 13,
                color: changed ? colors.blue : colors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  draft,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: changed ? colors.blue : colors.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            AppGhostButton(
              onPressed: !widget.editable || current == null
                  ? null
                  : () => setState(() {
                      _pendingClear = true;
                      _selected = null;
                    }),
              child: const Text('清除指派'),
            ),
            const Spacer(),
            _DutyOutlineButton(onPressed: _close, child: const Text('取消')),
            const SizedBox(width: 8),
            AppPrimaryButton(
              onPressed: _canConfirm(current) ? () => _confirm(current) : null,
              child: Text(_confirmLabel(current)),
            ),
          ],
        ),
      ],
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
  late final _members = <String, Set<String>>{
    SupervisionDraft.basePoolId: {...widget.draft.teacherIds},
    for (final pool in widget.draft.teacherPools) pool.id: {...pool.teacherIds},
  };
  late final _names = {
    for (final pool in widget.draft.teacherPools) pool.id: pool.name,
  };
  String _activePool = SupervisionDraft.basePoolId;
  late String _defaultPool =
      widget.draft.defaultTeacherPoolId ?? SupervisionDraft.basePoolId;
  Set<String> get _teachers => _members[_activePool]!;
  bool get _referenced =>
      _activePool == _defaultPool ||
      widget.draft.posts.any((post) => post.teacherPoolId == _activePool);

  Future<void> _namePool({bool rename = false}) async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (_) => _PoolNameDialog(
        names: {
          '基础候选池',
          for (final entry in _names.entries)
            if (!rename || entry.key != _activePool) entry.value,
        },
        initial: rename ? _names[_activePool] : null,
      ),
    );
    if (!mounted || name == null) return;
    setState(() {
      if (!rename) {
        _activePool = 'pool-${DateTime.now().microsecondsSinceEpoch}';
        _members[_activePool] = {};
      }
      _names[_activePool] = name;
    });
  }

  Future<void> _deletePool() async {
    if (_referenced || _activePool == SupervisionDraft.basePoolId) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('删除候选池'),
        content: Text('删除「${_names[_activePool]}」？教师和带班规则会保留。'),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          AppDestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      setState(() {
        _members.remove(_activePool);
        _names.remove(_activePool);
        _activePool = SupervisionDraft.basePoolId;
      });
    }
  }

  Set<String> _groupTeacherIds(String groupId) => widget
      .snapshot
      .teacherGroupMembers
      .where((member) => member.groupId == groupId)
      .map((member) => member.teacherId)
      .toSet();

  Widget _menuTrigger({required IconData icon, required String label}) {
    final colors = context.appColors;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.inkSecondary),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, color: colors.ink)),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 16, color: colors.muted),
        ],
      ),
    );
  }

  Widget _poolActionsMenu() {
    final colors = context.appColors;
    final isBasePool = _activePool == SupervisionDraft.basePoolId;
    final canDelete = !isBasePool && !_referenced;
    final deleteLabel = isBasePool
        ? '基础候选池不可删除'
        : _activePool == _defaultPool
        ? '默认候选池不可删除'
        : _referenced
        ? '已有岗位使用，无法删除'
        : '删除候选池';
    return f.FPopoverMenu(
      menuBuilder: (context, controller, menu) => [
        f.FItemGroup(
          divider: .none,
          children: [
            AppMenuTile(
              item: AppMenuItem(
                label: '重命名候选池',
                enabled: !isBasePool,
                onPressed: () {
                  unawaited(controller.hide());
                  unawaited(_namePool(rename: true));
                },
              ),
            ),
            AppMenuTile(
              item: AppMenuItem(
                label: _activePool == _defaultPool ? '默认候选池' : '设为默认候选池',
                selected: _activePool == _defaultPool,
                enabled: _activePool != _defaultPool,
                onPressed: () {
                  unawaited(controller.hide());
                  setState(() => _defaultPool = _activePool);
                },
              ),
            ),
            AppMenuTile(
              item: AppMenuItem(
                label: deleteLabel,
                destructive: canDelete,
                enabled: canDelete,
                onPressed: () {
                  unawaited(controller.hide());
                  unawaited(_deletePool());
                },
              ),
            ),
          ],
        ),
      ],
      builder: (context, controller, child) => f.FTappable(
        semanticsLabel: '候选池操作',
        onPress: () => unawaited(controller.toggle()),
        child: child!,
      ),
      child: Tooltip(
        message: '候选池操作',
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(Icons.more_horiz, size: 18, color: colors.inkSecondary),
          ),
        ),
      ),
    );
  }

  Widget _groupAddMenu() {
    final colors = context.appColors;
    return f.FPopoverMenu(
      menuBuilder: (context, controller, menu) => [
        f.FItemGroup(
          divider: .none,
          children: [
            ...widget.groups.map((group) {
              final teacherIds = _groupTeacherIds(group.id);
              return AppMenuTile(
                key: ValueKey('pool-group-${group.id}'),
                item: AppMenuItem(
                  label: '${group.name} · ${teacherIds.length} 人',
                  enabled: teacherIds.isNotEmpty,
                  onPressed: () {
                    unawaited(controller.hide());
                    setState(() => _teachers.addAll(teacherIds));
                  },
                ),
              );
            }),
          ],
        ),
      ],
      builder: (context, controller, child) => f.FTappable(
        semanticsLabel: '从教师组添加候选教师',
        onPress: () => unawaited(controller.toggle()),
        child: child!,
      ),
      child: _menuTrigger(icon: Icons.group_add_outlined, label: '从教师组添加'),
    );
  }

  String get _activePoolName => _activePool == SupervisionDraft.basePoolId
      ? '基础候选池'
      : _names[_activePool] ?? '候选池';

  Widget _poolTile(String id, String name) {
    final colors = context.appColors;
    final selected = id == _activePool;
    final isDefault = id == _defaultPool;
    final count = _members[id]?.length ?? 0;
    return AppTreeTile(
      key: ValueKey('pool-item-$id'),
      leading: Icon(
        Icons.groups_outlined,
        size: 16,
        color: selected ? colors.blue : colors.inkSecondary,
      ),
      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected ? colors.blue : colors.ink,
                  ),
                ),
              ),
              if (isDefault) ...[
                const SizedBox(width: 8),
                Text(
                  '默认',
                  style: TextStyle(fontSize: 11, color: colors.inkSecondary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$count 位教师',
            style: TextStyle(
              fontSize: 12,
              color: colors.inkSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      isSelected: selected,
      selectedBackground: colors.selectedBlue,
      selectedForeground: colors.blue,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      height: 56,
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        _activePool = id;
      }),
    );
  }

  Widget _poolSidebar(double height) {
    final colors = context.appColors;
    final pools = <String, String>{
      SupervisionDraft.basePoolId: '基础候选池',
      ..._names,
    }.entries.toList(growable: false);
    return SizedBox(
      width: 232,
      height: height,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.canvas,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '候选池',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${pools.length} 个',
                  style: TextStyle(fontSize: 12, color: colors.inkSecondary),
                ),
                const SizedBox(width: 4),
                _poolActionsMenu(),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: pools.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final pool = pools[index];
                  return _poolTile(pool.key, pool.value);
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: AppGhostButton(
                onPressed: _namePool,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 16, color: colors.inkSecondary),
                    const SizedBox(width: 8),
                    const Text('新建候选池'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactPoolControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final selector = AppSelectField<String>(
          key: const ValueKey('pool-manager-select'),
          label: '当前候选池',
          value: _activePool,
          items: {
            '基础候选池${_defaultPool == SupervisionDraft.basePoolId ? ' · 默认' : ''}':
                SupervisionDraft.basePoolId,
            for (final entry in _names.entries)
              '${entry.value}${_defaultPool == entry.key ? ' · 默认' : ''}':
                  entry.key,
          },
          onChanged: (id) {
            if (id != null) {
              setState(() {
                _activePool = id;
              });
            }
          },
        );
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppGhostButton(onPressed: _namePool, child: const Text('新建候选池')),
            const SizedBox(width: 4),
            _poolActionsMenu(),
          ],
        );
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              selector,
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: selector),
            const SizedBox(width: 8),
            actions,
          ],
        );
      },
    );
  }

  Widget _teacherWorkspace({
    required List<Teacher> teachers,
    required List<String> Function(String id) groupsFor,
    required double height,
  }) {
    final colors = context.appColors;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '教师名单',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                '本池 ${_teachers.length} 人',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.inkSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DutySearchField(
            controller: _search,
            hint: '搜索教师姓名或教师组',
            onChanged: (text) =>
                setState(() => _query = text.trim().toLowerCase()),
            onClear: () {
              _search.clear();
              setState(() => _query = '');
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final selectAll = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppCheckbox(
                      value:
                          teachers.isNotEmpty &&
                          teachers.every(
                            (teacher) => _teachers.contains(teacher.id),
                          ),
                      onChanged: (value) => setState(() {
                        final ids = teachers.map((teacher) => teacher.id);
                        value
                            ? _teachers.addAll(ids)
                            : _teachers.removeAll(ids);
                      }),
                    ),
                    const SizedBox(width: 8),
                    const Text('全选搜索结果'),
                  ],
                );
                final searchCount = Text(
                  '搜索结果 ${teachers.length} 人',
                  style: TextStyle(fontSize: 12, color: colors.inkSecondary),
                );
                if (constraints.maxWidth >= 560) {
                  return Row(
                    children: [
                      selectAll,
                      const SizedBox(width: 12),
                      searchCount,
                      const Spacer(),
                      if (widget.groups.isNotEmpty) _groupAddMenu(),
                    ],
                  );
                }
                return Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    selectAll,
                    searchCount,
                    if (widget.groups.isNotEmpty) _groupAddMenu(),
                  ],
                );
              },
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          Expanded(
            child: teachers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '没有找到教师',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '试试教师姓名或教师组，或清空搜索条件。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.inkSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(top: 4),
                    itemCount: teachers.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, thickness: 1, color: colors.border),
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
                            suffix: AppGhostButton(
                              onPressed: () => _editRule(teacher),
                              child: const Text('编辑规则'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  late final _rules = {...widget.draft.rules};
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceHeight = (MediaQuery.sizeOf(context).height * 0.62)
        .clamp(360.0, 580.0)
        .toDouble();
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
      title: const Text('候选池管理'),
      maxWidth: 1040,
      content: LayoutBuilder(
        builder: (context, constraints) {
          final wideLayout = constraints.maxWidth >= 760;
          final description = Text(
            '岗位分别使用候选池；教师的带班上限和禁排规则在所有池共享。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.inkSecondary),
          );
          final teacherWorkspace = _teacherWorkspace(
            teachers: teachers,
            groupsFor: groupsFor,
            height: workspaceHeight,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              description,
              const SizedBox(height: 16),
              if (wideLayout)
                SizedBox(
                  height: workspaceHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _poolSidebar(workspaceHeight),
                      const SizedBox(width: 16),
                      Expanded(child: teacherWorkspace),
                    ],
                  ),
                )
              else ...[
                _compactPoolControls(),
                const SizedBox(height: 12),
                teacherWorkspace,
              ],
            ],
          );
        },
      ),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppPrimaryButton(
          onPressed: () => Navigator.pop(
            context,
            widget.draft.copyWith(
              teacherIds: _members[SupervisionDraft.basePoolId],
              rules: _rules,
              teacherPools: [
                for (final entry in _names.entries)
                  SupervisionTeacherPool(
                    id: entry.key,
                    name: entry.value,
                    teacherIds: _members[entry.key]!,
                  ),
              ],
              defaultTeacherPoolId: _defaultPool == SupervisionDraft.basePoolId
                  ? null
                  : _defaultPool,
              resetDefaultPool: _defaultPool == SupervisionDraft.basePoolId,
            ),
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
    final colors = context.appColors;
    final lessonLimit = AppTextFormField(
      controller: _lessons,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '每周最多带班节次',
        hintText: '留空不限',
      ),
    );
    final dayLimit = AppTextFormField(
      controller: _days,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '每周最多带班天数',
        hintText: '留空不限',
      ),
    );
    return AppDialog(
      title: Text('${widget.teacher.displayName} · 带班规则'),
      maxWidth: 760,
      titleGap: 12,
      actionsGap: 16,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '设置每周带班上限，并标记不能安排带班的课节。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 16),
          Text('带班上限', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 560
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: lessonLimit),
                      const SizedBox(width: 16),
                      Expanded(child: dayLimit),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      lessonLimit,
                      const SizedBox(height: 8),
                      dayLimit,
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          Divider(height: 1, thickness: 1, color: colors.border),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '禁排时段',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.canvas,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '已选 ${_forbidden.length} 格',
                  style: TextStyle(fontSize: 12, color: colors.inkSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '点击“＋”设为禁排，再次点击可取消；“—”表示该时段没有课程。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 12),
          Text('学段', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final stage in widget.snapshot.stages)
                _SelectionOption(
                  label: Text(stage.name),
                  selected: _stageId == stage.id,
                  onSelected: (_) => setState(() => _stageId = stage.id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (routine == null)
            _emptyForbiddenSlots('该学段尚未配置作息。')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final rows = <TableRow>[
                  TableRow(
                    children: [
                      _matrixHeader('节次'),
                      for (final day in _weekdays) _matrixHeader(day),
                    ],
                  ),
                ];
                for (final period in routine.periodTypes) {
                  final maxCount = List.generate(
                    7,
                    (index) =>
                        routine.effectiveLessonCount(period.id, index + 1),
                  ).fold<int>(0, (a, b) => a > b ? a : b);
                  for (var index = 1; index <= maxCount; index++) {
                    final time = period.lessonTimes
                        .where((time) => time.lessonIndex == index)
                        .firstOrNull;
                    rows.add(
                      TableRow(
                        children: [
                          _matrixRowLabel(period.name, index),
                          for (var day = 1; day <= 7; day++)
                            if (!routine.teachingWeekdays.contains(day) ||
                                index >
                                    routine.effectiveLessonCount(
                                      period.id,
                                      day,
                                    ))
                              SizedBox(
                                height: 42,
                                child: Center(
                                  child: Text(
                                    '—',
                                    style: TextStyle(color: colors.muted),
                                  ),
                                ),
                              )
                            else
                              Builder(
                                builder: (context) {
                                  final position = SchedulePosition(
                                    stageId: routine.stageId,
                                    weekday: day,
                                    periodTypeId: period.id,
                                    lessonIndex: index,
                                    startMinute: time?.startMinute,
                                    endMinute: time?.endMinute,
                                  );
                                  final selected = _forbidden.containsKey(
                                    position.cellKey,
                                  );
                                  return _forbiddenCell(
                                    label:
                                        '${_weekdays[day - 1]} ${period.name} 第 $index 节',
                                    selected: selected,
                                    onPressed: () => setState(() {
                                      if (selected) {
                                        _forbidden.remove(position.cellKey);
                                      } else {
                                        _forbidden[position.cellKey] = position;
                                      }
                                    }),
                                  );
                                },
                              ),
                        ],
                      ),
                    );
                  }
                }
                if (rows.length == 1) return _emptyForbiddenSlots('该学段没有可选课节。');
                final table = SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(620.0, constraints.maxWidth),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Table(
                        border: TableBorder.all(
                          color: colors.border,
                          width: 0.7,
                        ),
                        columnWidths: const {0: FixedColumnWidth(110)},
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: rows,
                      ),
                    ),
                  ),
                );
                if (constraints.maxWidth >= 620) return table;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '左右滚动查看完整作息表',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    table,
                  ],
                );
              },
            ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error, style: TextStyle(color: colors.destructive)),
            ),
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

  Widget _matrixHeader(String text) => Container(
    height: 36,
    alignment: Alignment.center,
    color: context.appColors.tableHeader,
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.appColors.inkSecondary,
      ),
    ),
  );

  Widget _matrixRowLabel(String period, int index) => Container(
    height: 42,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    color: context.appColors.canvas,
    child: Text(
      '$period · $index',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: context.appColors.inkSecondary),
    ),
  );

  Widget _forbiddenCell({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final colors = context.appColors;
    return Semantics(
      label: '$label，${selected ? '禁排' : '可安排'}',
      selected: selected,
      button: true,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const RoundedRectangleBorder(),
            backgroundColor: selected
                ? colors.destructiveSurface
                : colors.surface,
            foregroundColor: selected
                ? colors.destructive
                : colors.inkSecondary,
          ),
          child: selected
              ? const Text(
                  '禁排',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                )
              : const Icon(Icons.add_rounded, size: 16),
        ),
      ),
    );
  }

  Widget _emptyForbiddenSlots(String message) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: colors.inkSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: colors.inkSecondary),
            ),
          ),
        ],
      ),
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

class _DutySearchField extends StatelessWidget {
  const _DutySearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: AppTextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search, size: 16),
          ),
          onChanged: onChanged,
        ),
      ),
      if (controller.text.isNotEmpty) ...[
        const SizedBox(width: 4),
        f.FTooltip(
          tipBuilder: (context, control) => const Text('清空教师搜索'),
          child: AppIconButton(
            icon: Icons.close,
            tooltip: '清空教师搜索',
            onPressed: onClear,
            foregroundColor: context.appColors.inkSecondary,
          ),
        ),
      ],
    ],
  );
}
