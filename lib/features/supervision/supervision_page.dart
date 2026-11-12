import 'dart:async';
import 'dart:isolate';

import 'package:class_set/app.dart';
import 'package:class_set/core/navigation/draft_navigation_guard.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/supervision_allocator.dart';
import 'package:class_set/domain/scheduling/supervision_validation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart' as f;

part 'supervision_dialogs.dart';
part 'supervision_post_dialog.dart';
part 'supervision_week.dart';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// The cell and scope selected in routine settings.
class SupervisionSeed {
  const SupervisionSeed({
    required this.stageId,
    required this.scope,
    required this.scopeId,
    required this.weekday,
    required this.periodTypeId,
    required this.lessonIndex,
  });

  final String stageId;
  final FreeSlotScope scope;
  final String scopeId;
  final int weekday;
  final String periodTypeId;
  final int lessonIndex;
}

final _snapshotProvider = FutureProvider.autoDispose
    .family<SchedulingSnapshot, String>(
      (ref, id) =>
          ref.watch(schoolRepositoryProvider).loadSchedulingSnapshot(id),
    );
final _pendingBaselineProvider = FutureProvider.autoDispose
    .family<bool, String>(
      (ref, id) async =>
          await ref
              .watch(schoolRepositoryProvider)
              .loadPendingSchedulingBaseline(id) !=
          null,
    );
final _draftProvider = StreamProvider.autoDispose
    .family<SupervisionDraft?, String>(
      (ref, id) =>
          ref.watch(schoolRepositoryProvider).watchSupervisionDraft(id),
    );
final _versionsProvider = StreamProvider.autoDispose
    .family<List<SupervisionVersion>, String>(
      (ref, id) =>
          ref.watch(schoolRepositoryProvider).watchSupervisionVersions(id),
    );

class SupervisionPage extends ConsumerWidget {
  const SupervisionPage({required this.termId, this.seed, super.key});

  final String termId;
  final SupervisionSeed? seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(_snapshotProvider(termId));
    final draft = ref.watch(_draftProvider(termId));
    final versions = ref.watch(_versionsProvider(termId));
    if (snapshot.hasError || draft.hasError || versions.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('读取带班安排失败：${snapshot.error ?? draft.error ?? versions.error}'),
            AppSecondaryButton(
              onPressed: () {
                ref.invalidate(_snapshotProvider(termId));
                ref.invalidate(_draftProvider(termId));
                ref.invalidate(_versionsProvider(termId));
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (!snapshot.hasValue || !draft.hasValue || !versions.hasValue) {
      return const Center(
        child: f.FCircularProgress(semanticsLabel: '正在读取带班安排'),
      );
    }
    return _SupervisionEditor(
      key: ValueKey(termId),
      snapshot: snapshot.requireValue,
      draft: draft.requireValue,
      versions: versions.requireValue,
      canRepair:
          versions.requireValue.isNotEmpty &&
          ref.watch(_pendingBaselineProvider(termId)).valueOrNull == true,
      seed: seed,
    );
  }
}

class _SupervisionEditor extends ConsumerStatefulWidget {
  const _SupervisionEditor({
    required this.snapshot,
    required this.draft,
    required this.versions,
    required this.canRepair,
    required this.seed,
    super.key,
  });

  final SchedulingSnapshot snapshot;
  final SupervisionDraft? draft;
  final List<SupervisionVersion> versions;
  final bool canRepair;
  final SupervisionSeed? seed;

  @override
  ConsumerState<_SupervisionEditor> createState() => _SupervisionEditorState();
}

class _SupervisionEditorState extends ConsumerState<_SupervisionEditor> {
  late SupervisionDraft _draft = _initialDraft();
  late final DraftNavigationGuard _guard;
  bool _dirty = false;
  bool _publishing = false;
  Future<bool>? _saveInFlight;
  ReceivePort? _fillPort;
  Isolate? _fillIsolate;
  DateTime? _viewVersionDate;
  int? _filterDay;
  String? _selectedPostId;
  bool _missingOnly = false;

  String get _termId => widget.snapshot.term.id;
  bool get _busy => _saveInFlight != null || _publishing;
  bool get _filling => _fillPort != null;
  bool get _editable => _viewVersionDate == null && !_busy && !_filling;

  SupervisionDraft _initialDraft() =>
      widget.draft ??
      _latestVersion(widget.versions)?.draft.copyWith(revision: 0) ??
      SupervisionDraft(termId: _termId);

  @override
  void initState() {
    super.initState();
    _guard = ref.read(draftNavigationGuardProvider);
    _guard.register(
      owner: this,
      pageKey: 'supervision:$_termId',
      hasChanges: () => _dirty,
      isSaving: () => _saveInFlight != null,
      save: _save,
    );
    final seed = widget.seed;
    if (seed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_addPosts(seed));
      });
    }
  }

  @override
  void didUpdateWidget(covariant _SupervisionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.draft != widget.draft ||
        (widget.draft == null && oldWidget.versions != widget.versions);
    if (!_dirty && !_busy && !_filling && sourceChanged) {
      _draft = _initialDraft();
    }
  }

  @override
  void dispose() {
    _guard.unregister(this);
    _stopFill();
    super.dispose();
  }

  void _replaceDraft(SupervisionDraft next) {
    setState(() {
      _draft = next;
      _dirty = true;
    });
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<bool> _save() {
    if (_saveInFlight case final existing?) return existing;
    if (!_dirty && _draft.revision == widget.draft?.revision) {
      return Future.value(true);
    }
    final operation = _persist();
    setState(() {
      _saveInFlight = operation;
    });
    return operation;
  }

  Future<bool> _persist() async {
    try {
      final repository = ref.read(schoolRepositoryProvider);
      final saved = await repository.saveSupervisionDraft(
        _draft,
        expectedRevision: _draft.revision,
      );
      if (!mounted) return false;
      setState(() {
        _draft = saved;
        _dirty = false;
      });
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      _message('草稿已保存');
      return true;
    } on Object catch (error) {
      _message('保存草稿失败：$error');
      return false;
    } finally {
      if (mounted) setState(() => _saveInFlight = null);
    }
  }

  Future<void> _addPosts([SupervisionSeed? seed]) async {
    final posts = await showAppDialog<List<SupervisionPost>>(
      context: context,
      builder: (_) =>
          _PostDialog(snapshot: widget.snapshot, draft: _draft, seed: seed),
    );
    if (!mounted || posts == null) return;
    _replaceDraft(_draft.copyWith(posts: [..._draft.posts, ...posts]));
  }

  Future<void> _removePost(SupervisionPost post) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: const Text('移除带班岗位'),
        content: Text('从草稿移除「${post.name}」？已生效的安排会继续显示，直到确认新版本。'),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          AppPrimaryButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _replaceDraft(
      _draft.copyWith(
        posts: _draft.posts.where((item) => item.id != post.id).toList(),
        assignments: {..._draft.assignments}..remove(post.id),
        manualPostIds: {..._draft.manualPostIds}..remove(post.id),
      ),
    );
  }

  Future<void> _selectTeacher(SupervisionPost post) async {
    final picked = await showAppDialog<String>(
      context: context,
      builder: (dialogContext) => _TeacherPickerDialog(
        snapshot: widget.snapshot,
        draft: _draft,
        post: post,
        onRemove: () {
          Navigator.pop(dialogContext);
          unawaited(_removePost(post));
        },
      ),
    );
    if (!mounted || picked == null) return;
    _assignTeacher(post, picked);
  }

  void _assignTeacher(SupervisionPost post, String picked) {
    final assignments = {..._draft.assignments};
    final manualPostIds = {..._draft.manualPostIds};
    final teacherIds = {..._draft.teacherIds};
    if (picked.isEmpty) {
      assignments.remove(post.id);
      manualPostIds.remove(post.id);
    } else {
      teacherIds.add(picked);
      assignments[post.id] = picked;
      manualPostIds.add(post.id);
    }
    _replaceDraft(
      _draft.copyWith(
        assignments: assignments,
        manualPostIds: manualPostIds,
        teacherIds: teacherIds,
      ),
    );
  }

  Future<void> _editTeacherPool() async {
    final groups = await ref
        .read(schoolRepositoryProvider)
        .watchTeacherGroups(_termId)
        .first
        .catchError((Object error) {
          _message('读取教师组失败：$error');
          return <TeacherGroup>[];
        });
    if (!mounted) return;
    final revised = await showAppDialog<SupervisionDraft>(
      context: context,
      builder: (_) => _TeacherPoolDialog(
        draft: _draft,
        snapshot: widget.snapshot,
        groups: groups,
      ),
    );
    if (mounted && revised != null) _replaceDraft(revised);
  }

  Future<void> _smartFill() async {
    final port = ReceivePort();
    setState(() => _fillPort = port);
    try {
      final snapshot = await ref
          .read(schoolRepositoryProvider)
          .loadSchedulingSnapshot(_termId);
      if (!mounted || _fillPort != port) return;
      final input = _draft;
      if (kIsWeb) {
        _replaceDraft(const SupervisionAllocator().fill(snapshot, input));
        return;
      }
      final output = port.first;
      final isolate = await Isolate.spawn(_fillSupervision, (
        port.sendPort,
        snapshot,
        input,
      ), onError: port.sendPort);
      if (!mounted || _fillPort != port) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      _fillIsolate = isolate;
      final result = await output;
      if (!mounted || _fillPort != port || result == null) return;
      if (result is SupervisionDraft) {
        _replaceDraft(result);
      } else {
        _message('智能补齐失败：$result');
      }
    } on Object catch (error) {
      if (_fillPort == port) _message('智能补齐失败：$error');
    } finally {
      if (mounted && _fillPort == port) setState(_stopFill);
    }
  }

  void _stopFill() {
    _fillIsolate?.kill(priority: Isolate.immediate);
    _fillPort?.close();
    _fillIsolate = null;
    _fillPort = null;
  }

  Future<void> _publish({bool repair = false}) async {
    final dates = repair
        ? [DateUtils.dateOnly(DateTime.now())]
        : _publishDates(widget.snapshot.term);
    if (dates.isEmpty) return;
    if (!await _save() || !mounted) return;
    setState(() => _publishing = true);
    try {
      final repository = ref.read(schoolRepositoryProvider);
      final preview = await showAppDialog<SupervisionPreview>(
        context: context,
        builder: (_) => _PublishDialog(
          dates: dates,
          load: (date) => repository.previewSupervisionPublish(_termId, date),
          snapshot: widget.snapshot,
          repair: repair,
        ),
      );
      if (!mounted || preview == null) return;
      await repository.publishSupervision(_termId, preview);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _draft = preview.draft.copyWith(revision: 0);
        _viewVersionDate = preview.effectiveDate;
      });
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      ref.invalidate(_pendingBaselineProvider(_termId));
      ref.invalidate(_snapshotProvider(_termId));
      _message(
        repair ? '带班与课表已协调' : '已确认，${_dateLabel(preview.effectiveDate)} 起生效',
      );
    } on Object catch (error) {
      _message('确认带班方案失败：$error');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final versions = [...widget.versions]
      ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
    final selected = versions
        .where((version) => version.effectiveDate == _viewVersionDate)
        .firstOrNull;
    final current = versions
        .where((version) => !version.effectiveDate.isAfter(DateTime.now()))
        .firstOrNull;
    final draft = selected?.draft ?? _draft;
    final days = draft.posts.map((post) => post.weekday).toSet().toList()
      ..sort();
    final missing = draft.posts
        .where((post) => !draft.assignments.containsKey(post.id))
        .length;
    final focused = selected == null
        ? draft.posts.where((post) => post.id == _selectedPostId).firstOrNull
        : null;
    final canPreview =
        _editable &&
        (versions.isNotEmpty || _draft.posts.isNotEmpty) &&
        _publishDates(widget.snapshot.term).isNotEmpty;
    final colors = context.appColors;
    final theme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth < 560 ? 16.0 : 24.0;
        final inline =
            constraints.maxWidth >= 1120 && constraints.maxHeight >= 520;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('带班安排', style: theme.headlineSmall),
            const SizedBox(height: 5),
            Text(
              widget.snapshot.term.title,
              style: theme.bodySmall?.copyWith(color: colors.inkSecondary),
            ),
          ],
        );
        final add = AppPrimaryButton.icon(
          onPressed: _editable ? _addPosts : null,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('创建岗位'),
        );
        final picker = SizedBox(
          width: versions.isEmpty ? 112 : 218,
          child: AppSelectField<String>(
            compact: true,
            items: {
              '编辑草稿': '',
              for (final version in versions)
                '${identical(version, current)
                    ? '当前生效'
                    : version.effectiveDate.isAfter(DateTime.now())
                    ? '待生效'
                    : '历史方案'} · ${_dateLabel(version.effectiveDate)}': version
                    .effectiveDate
                    .toIso8601String(),
            },
            value: selected?.effectiveDate.toIso8601String() ?? '',
            enabled: !_busy && !_filling,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _viewVersionDate = value.isEmpty ? null : DateTime.parse(value);
                _selectedPostId = null;
                _filterDay = null;
                _missingOnly = false;
              });
            },
          ),
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (days.length > 1)
              SizedBox(
                width: 88,
                child: AppSelectField<int>(
                  compact: true,
                  items: {
                    '整周': 0,
                    for (final day in days) _weekdays[day - 1]: day,
                  },
                  value: days.contains(_filterDay) ? _filterDay : 0,
                  onChanged: (day) => setState(() {
                    _filterDay = day == 0 ? null : day;
                    _selectedPostId = null;
                  }),
                ),
              ),
            if (selected == null) ...[
              AppGhostButton(
                onPressed: _editable ? _editTeacherPool : null,
                child: Text('候选教师 · ${_draft.teacherIds.length}'),
              ),
              AppSecondaryButton(
                onPressed: _filling
                    ? () => setState(_stopFill)
                    : _editable && missing > 0 && _draft.teacherIds.isNotEmpty
                    ? _smartFill
                    : null,
                child: Text(_filling ? '取消补齐' : '智能补齐'),
              ),
            ],
          ],
        );
        final body = _SupervisionWeek(
          draft: draft,
          snapshot: widget.snapshot,
          historical: selected,
          day: _filterDay,
          missingOnly: _missingOnly,
          selectedPostId: inline ? focused?.id : null,
          onSelect: !_editable
              ? null
              : inline
              ? (post) => setState(() => _selectedPostId = post.id)
              : _selectTeacher,
        );
        final weekBody = draft.posts.isEmpty
            ? SizedBox(
                height: 150,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      selected == null
                          ? '周表还是空的。创建岗位后，即可按节次安排老师。'
                          : '此版本没有带班岗位。',
                      style: theme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            : body;
        return Padding(
          padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: title),
                  if (selected == null) add,
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            runSpacing: 6,
                            spacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('带班周表', style: theme.titleSmall),
                                  const SizedBox(width: 12),
                                  picker,
                                ],
                              ),
                              actions,
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                          child: Wrap(
                            spacing: 14,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _WeekFilter(
                                label: '全部岗位',
                                selected: !_missingOnly,
                                onTap: () =>
                                    setState(() => _missingOnly = false),
                              ),
                              _WeekFilter(
                                label: '待安排 $missing',
                                selected: _missingOnly,
                                onTap: () => setState(() {
                                  _missingOnly = true;
                                  _selectedPostId = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                        if (_filling)
                          const f.FProgress(semanticsLabel: '正在智能补齐带班')
                        else
                          const Divider(height: 1),
                        Flexible(
                          child: inline && focused != null
                              ? LayoutBuilder(
                                  builder: (context, constraints) => SizedBox(
                                    height: constraints.maxHeight,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: weekBody),
                                        VerticalDivider(
                                          width: 1,
                                          color: colors.border,
                                        ),
                                        SizedBox(
                                          width: 272,
                                          child: _TeacherInspector(
                                            key: ValueKey(focused.id),
                                            snapshot: widget.snapshot,
                                            draft: _draft,
                                            post: focused,
                                            onPick: _editable
                                                ? (teacher) => _assignTeacher(
                                                    focused,
                                                    teacher,
                                                  )
                                                : null,
                                            onClose: () => setState(
                                              () => _selectedPostId = null,
                                            ),
                                            onRemove: _editable
                                                ? () => _removePost(focused)
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : weekBody,
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Text(
                                '${draft.posts.length - missing} / ${draft.posts.length} 个岗位已安排'
                                '${selected == null && _dirty ? ' · 有未保存的修改' : ''}',
                                style: theme.bodySmall?.copyWith(
                                  color: colors.inkSecondary,
                                ),
                              ),
                              if (selected == null)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    AppGhostButton(
                                      onPressed: _editable
                                          ? () => unawaited(_save())
                                          : null,
                                      child: const Text('保存草稿'),
                                    ),
                                    if (widget.canRepair)
                                      AppSecondaryButton(
                                        onPressed: _editable
                                            ? () => _publish(repair: true)
                                            : null,
                                        child: const Text('修正带班并协调'),
                                      ),
                                    AppSecondaryButton(
                                      onPressed: canPreview ? _publish : null,
                                      child: const Text('预览并确认'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

void _fillSupervision((SendPort, SchedulingSnapshot, SupervisionDraft) input) {
  final (port, snapshot, draft) = input;
  port.send(const SupervisionAllocator().fill(snapshot, draft));
}

SupervisionVersion? _latestVersion(List<SupervisionVersion> versions) => ([
  ...versions,
]..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate))).firstOrNull;

String _dateLabel(DateTime date) => '${date.year}年${date.month}月${date.day}日';

List<DateTime> _publishDates(AcademicTerm term) {
  final now = DateUtils.dateOnly(DateTime.now());
  return [
    for (var week = 1; week <= term.teachingWeekCount; week++)
      if (term.teachingWeekStart(week) case final start?)
        if (DateUtils.addDaysToDate(
              start,
              (DateTime.daysPerWeek + DateTime.monday - start.weekday) %
                  DateTime.daysPerWeek,
            )
            case final monday when monday.isAfter(now))
          monday,
  ];
}

LessonPeriodType? _postPeriod(
  SchedulingSnapshot snapshot,
  SupervisionPost post,
) => snapshot.routines
    .where((routine) => routine.stageId == post.stageId)
    .firstOrNull
    ?.periodTypes
    .where((period) => period.id == post.periodTypeId)
    .firstOrNull;

int _postMinute(SchedulingSnapshot snapshot, SupervisionPost post) =>
    _postPeriod(snapshot, post)?.lessonTimes
        .where((time) => time.lessonIndex == post.lessonIndices.first)
        .firstOrNull
        ?.startMinute ??
    1440;

String _slotLabel(SchedulingSnapshot snapshot, SupervisionPost post) {
  final period = _postPeriod(snapshot, post);
  return '${period?.name ?? post.periodTypeId} · 第 ${post.lessonIndices.join('、')} 节';
}
