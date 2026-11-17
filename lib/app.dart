import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/theme/app_appearance.dart';
import 'package:class_set/core/widgets/appearance_settings_dialog.dart';
import 'package:class_set/core/navigation/draft_navigation_guard.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/core/widgets/app_page_layout.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/features/classes/classes_page.dart';
import 'package:class_set/features/routines/routine_page.dart';
import 'package:class_set/features/scheduling/scheduling_page.dart';
import 'package:class_set/features/supervision/supervision_page.dart';
import 'package:class_set/features/temporary_adjustments/temporary_adjustments_page.dart';
import 'package:class_set/features/public_rooms/public_rooms_page.dart';
import 'package:class_set/features/subjects/subjects_page.dart';
import 'package:class_set/features/teachers/teachers_page.dart';
import 'package:class_set/features/school/school_name_dialog.dart';
import 'package:class_set/features/setup/setup_wizard_page.dart';
import 'package:class_set/features/terms/term_page.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:class_set/features/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:forui/forui.dart' as f;

enum AppSection {
  workbench,
  terms,
  classes,
  routines,
  subjects,
  teachers,
  scheduling,
  supervision,
  temporaryAdjustments,
  publicRooms,
}

enum _DraftLeaveChoice { save, discard }

extension on AppAppearanceMode {
  IconData get icon => switch (this) {
    AppAppearanceMode.system => Icons.brightness_auto_rounded,
    AppAppearanceMode.light => Icons.light_mode_outlined,
    AppAppearanceMode.dark => Icons.dark_mode_outlined,
  };
}

final selectedSectionProvider = StateProvider<AppSection>(
  (ref) => AppSection.workbench,
);
final activeTermIdProvider = StateProvider<String?>((ref) => null);

/// 最近一次成功写入本地数据库的时间；侧栏本地数据卡据此展示保存状态。
final lastPersistedAtProvider = StateProvider<DateTime?>((ref) => null);

/// 保存时间的可读文案：当天只显示时分，跨天补月日。
String _savedTimeLabel(DateTime time) {
  final now = DateTime.now();
  final timeText =
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return timeText;
  }
  return '${time.month}/${time.day} $timeText';
}

/// 侧栏菜单门控：关键前置数据未就绪的菜单置灰并说明原因（返回
/// `(enabled, reason)`）。与工作台「接下来」卡片的级联语义一致：
/// 作息完成解锁科目节数与带班安排，科目节数完成解锁教师任课，
/// 教师任课齐备解锁排课与课表，已生成课表解锁调代课。
///
/// [summary] 为 null 表示学期汇总尚未加载完成或读取失败，此时不拦截，
/// 避免加载期间误伤可用入口；真正的数据问题由目标页面自行呈现。
(bool, String?) navSectionAvailability(
  AppSection section, {
  required bool hasTerm,
  WorkbenchSummary? summary,
}) {
  if (!hasTerm) {
    return switch (section) {
      AppSection.workbench ||
      AppSection.terms ||
      AppSection.publicRooms => (true, null),
      _ => (false, '请先创建学期'),
    };
  }
  final ready = summary;
  // 依赖作息的菜单：学段班级还没搭好时，先提示更前置的步骤。
  (bool, String?) routineGate() {
    if (ready == null || ready.routineDone) return (true, null);
    return ready.stagesDone ? (false, '请先完成各学段作息设置') : (false, '请先创建学段、年级与班级');
  }

  return switch (section) {
    AppSection.workbench ||
    AppSection.terms ||
    AppSection.publicRooms ||
    AppSection.classes ||
    AppSection.routines => (true, null),
    AppSection.subjects => routineGate(),
    AppSection.supervision => routineGate(),
    AppSection.teachers =>
      ready == null || ready.subjectLessonsReady
          ? (true, null)
          : (false, '请先填写各年级科目节数'),
    AppSection.scheduling =>
      ready == null || ready.teacherAssignmentsReady
          ? (true, null)
          : (false, '请先补齐各班教师任课'),
    AppSection.temporaryAdjustments =>
      ready == null || ready.hasSchedule
          ? (true, null)
          : (false, '请先在排课与课表中生成课表'),
  };
}

class ClassSetApp extends StatefulWidget {
  const ClassSetApp({
    required this.databasePath,
    this.initialAppearance = const AppAppearance(),
    this.onAppearanceChanged,
    super.key,
  });

  final String databasePath;
  final AppAppearance initialAppearance;
  final Future<void> Function(AppAppearance)? onAppearanceChanged;

  @override
  State<ClassSetApp> createState() => _ClassSetAppState();
}

class _ClassSetAppState extends State<ClassSetApp> with WidgetsBindingObserver {
  static const _windowAppearanceChannel = MethodChannel(
    'class_set/window_appearance',
  );

  late AppAppearance _appearance;
  AppAppearanceMode get _themeMode => _appearance.mode;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  bool get _isDarkMode => switch (_themeMode) {
    AppAppearanceMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark,
    AppAppearanceMode.light => false,
    AppAppearanceMode.dark => true,
  };

  @override
  void initState() {
    super.initState();
    _appearance = widget.initialAppearance;
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isMacOS) unawaited(_setNativeWindowAppearance(_themeMode));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (_themeMode == AppAppearanceMode.system) setState(() {});
  }

  void _setThemeMode(AppAppearanceMode mode) {
    _setAppearance(_appearance.copyWith(mode: mode));
  }

  void _setAppearance(AppAppearance next) {
    if (next == _appearance) return;
    final modeChanged = next.mode != _themeMode;
    setState(() => _appearance = next);
    if (modeChanged && Platform.isMacOS) {
      unawaited(_setNativeWindowAppearance(next.mode));
    }
    unawaited(_saveAppearance(next));
  }

  Future<void> _saveAppearance(AppAppearance next) async {
    try {
      await widget.onAppearanceChanged?.call(next);
    } on Object {
      if (mounted && next == _appearance) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: const Text('外观已切换，但偏好保存失败。'),
            action: SnackBarAction(
              label: '重试',
              onPressed: () => unawaited(_saveAppearance(_appearance)),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showAppearanceSettings(BuildContext context) =>
      showAppDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, updateDialog) => AppearanceSettingsDialog(
            appearance: _appearance,
            onChanged: (next) {
              _setAppearance(next);
              updateDialog(() {});
            },
          ),
        ),
      );

  void _cycleThemeMode() {
    final nextMode = switch (_themeMode) {
      AppAppearanceMode.light => AppAppearanceMode.dark,
      AppAppearanceMode.dark => AppAppearanceMode.system,
      AppAppearanceMode.system => AppAppearanceMode.light,
    };
    _setThemeMode(nextMode);
  }

  Future<void> _setNativeWindowAppearance(AppAppearanceMode mode) async {
    try {
      await _windowAppearanceChannel.invokeMethod<void>(
        'setAppearance',
        mode.name,
      );
    } on MissingPluginException {
      // Other macOS shells may not register the optional window appearance channel.
    } on PlatformException {
      // Flutter theme switching remains available if native appearance sync fails.
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '课集',
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: _messengerKey,
    theme: AppTheme.themeFor(false, palette: _appearance.palette),
    darkTheme: AppTheme.themeFor(true, palette: _appearance.palette),
    themeMode: switch (_themeMode) {
      AppAppearanceMode.system => ThemeMode.system,
      AppAppearanceMode.light => ThemeMode.light,
      AppAppearanceMode.dark => ThemeMode.dark,
    },
    themeAnimationDuration:
        MediaQueryData.fromView(View.of(context)).disableAnimations
        ? Duration.zero
        : AppTheme.transitionDuration,
    builder: (context, child) => f.FTheme(
      data: AppTheme.foruiFor(_isDarkMode, palette: _appearance.palette),
      child: f.FToaster(child: child!),
    ),
    home: _AppShell(
      databasePath: widget.databasePath,
      themeMode: _themeMode,
      palette: _appearance.palette,
      onAppearanceSettings: _showAppearanceSettings,
      onCycleThemeMode: _cycleThemeMode,
    ),
  );
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell({
    required this.databasePath,
    required this.themeMode,
    required this.palette,
    required this.onAppearanceSettings,
    required this.onCycleThemeMode,
  });

  final String databasePath;
  final AppAppearanceMode themeMode;
  final AppPalette palette;
  final void Function(BuildContext) onAppearanceSettings;
  final VoidCallback onCycleThemeMode;

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  static const _compactNavigationBreakpoint = 1040.0;
  bool _sidebarExpanded = true;
  Future<void> _pendingTermSave = Future<void>.value();
  bool _navigationPending = false;
  SupervisionSeed? _supervisionSeed;

  String? _currentDraftPageKey() {
    final termId = ref.read(activeTermIdProvider);
    if (termId == null) return null;
    return switch (ref.read(selectedSectionProvider)) {
      AppSection.routines => 'routines:$termId',
      AppSection.subjects => 'subjects:$termId',
      AppSection.supervision => 'supervision:$termId',
      _ => null,
    };
  }

  Future<bool> _canLeaveCurrentPage() async {
    final pageKey = _currentDraftPageKey();
    if (pageKey == null) return true;
    final guard = ref.read(draftNavigationGuardProvider);
    if (guard.isSavingFor(pageKey)) return guard.saveFor(pageKey);
    if (!guard.hasChangesFor(pageKey)) return true;
    final choice = await showAppDialog<_DraftLeaveChoice>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: const Text('尚有未保存的修改'),
        content: const Text('当前页面的草稿尚未保存。离开前要保存吗？'),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('继续编辑'),
          ),
          AppSecondaryButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _DraftLeaveChoice.discard),
            child: const Text('不保存并离开'),
          ),
          AppPrimaryButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _DraftLeaveChoice.save),
            child: const Text('保存并离开'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return false;
    if (choice == _DraftLeaveChoice.discard) return true;
    return guard.saveFor(pageKey);
  }

  Future<void> _requestSection(
    AppSection section, {
    SupervisionSeed? supervisionSeed,
  }) async {
    if (_navigationPending || section == ref.read(selectedSectionProvider)) {
      return;
    }
    _navigationPending = true;
    try {
      if (await _canLeaveCurrentPage() && mounted) {
        _supervisionSeed = supervisionSeed;
        ref.read(selectedSectionProvider.notifier).state = section;
      }
    } finally {
      _navigationPending = false;
    }
  }

  Future<void> _requestTerm(String termId) async {
    if (_navigationPending || termId == ref.read(activeTermIdProvider)) return;
    _navigationPending = true;
    try {
      if (await _canLeaveCurrentPage() && mounted) {
        _supervisionSeed = null;
        ref.read(activeTermIdProvider.notifier).state = termId;
      }
    } finally {
      _navigationPending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(activeTermIdProvider, (_, next) {
      final repository = ref.read(schoolRepositoryProvider);
      _pendingTermSave = _pendingTermSave.then((_) async {
        try {
          await repository.saveActiveTermId(next);
          if (mounted) {
            ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
          }
        } on Object catch (error) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(this.context)
                ?.showSnackBar(SnackBar(content: Text('保存当前学期失败：$error')));
          }
        }
      });
    });
    final section = ref.watch(selectedSectionProvider);
    final activeTermId = ref.watch(activeTermIdProvider);
    final terms = ref.watch(termsProvider);
    final availableTerms = terms.valueOrNull ?? const [];
    if (terms.hasValue &&
        availableTerms.isNotEmpty &&
        !availableTerms.any((term) => term.id == activeTermId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final latestTerms = ref.read(termsProvider).valueOrNull ?? const [];
        final currentId = ref.read(activeTermIdProvider);
        if (latestTerms.isNotEmpty &&
            !latestTerms.any((term) => term.id == currentId)) {
          ref.read(activeTermIdProvider.notifier).state = latestTerms.first.id;
        }
      });
    }

    Widget shellBody;
    if (terms.hasError) {
      shellBody = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: SelectableText(
            '读取本地学期数据失败：${terms.error}',
            style: TextStyle(
              color: context.appColors.destructive,
              fontSize: 13,
            ),
          ),
        ),
      );
    } else if (terms.hasValue && availableTerms.isEmpty) {
      // 本地还没有任何学期：进入全屏创建向导，不展示侧边栏与顶部栏。
      shellBody = const SetupWizardPage();
    } else if (!terms.hasValue) {
      shellBody = const Center(child: CircularProgressIndicator());
    } else {
      shellBody = LayoutBuilder(
        builder: (context, constraints) {
          final compactNavigation =
              constraints.maxWidth < _compactNavigationBreakpoint ||
              !_sidebarExpanded;
          final pageTitle = switch (section) {
            AppSection.workbench => '工作台',
            AppSection.terms => '学期与日历',
            AppSection.classes => '班级与学段',
            AppSection.routines => '作息设置',
            AppSection.subjects => '科目节数',
            AppSection.teachers => '教师任课',
            AppSection.scheduling => '排课与课表',
            AppSection.supervision => '带班安排',
            AppSection.temporaryAdjustments => '调代课',
            AppSection.publicRooms => '公共场室',
          };
          return AppPageLayout(
            availableWidth:
                constraints.maxWidth - (compactNavigation ? 70 : 244),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  section: section,
                  isCompact: compactNavigation,
                  onNavigate: (value) => unawaited(_requestSection(value)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopBar(
                        pageTitle: pageTitle,
                        isSidebarExpanded: !compactNavigation,
                        themeMode: widget.themeMode,
                        palette: widget.palette,
                        onAppearanceSettings: widget.onAppearanceSettings,
                        onCycleThemeMode: widget.onCycleThemeMode,
                        onSelectTerm: (value) => unawaited(_requestTerm(value)),
                        onToggleSidebar:
                            constraints.maxWidth < _compactNavigationBreakpoint
                            ? null
                            : () => setState(
                                () => _sidebarExpanded = !_sidebarExpanded,
                              ),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: AppTheme.motionDuration(
                            context,
                            AppTheme.transitionDuration,
                          ),
                          reverseDuration: AppTheme.motionDuration(
                            context,
                            AppTheme.exitDuration,
                          ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                alignment: Alignment.topLeft,
                                fit: StackFit.expand,
                                clipBehavior: Clip.hardEdge,
                                children: [...previousChildren, ?currentChild],
                              ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.012),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: KeyedSubtree(
                            key: ValueKey((section, activeTermId)),
                            child: switch (section) {
                              AppSection.workbench => const WorkbenchPage(),
                              AppSection.publicRooms => const PublicRoomsPage(),
                              AppSection.terms => TermPage(
                                databasePath: widget.databasePath,
                              ),
                              AppSection.classes =>
                                activeTermId == null
                                    ? const _ChooseTermMessage()
                                    : ClassesPage(termId: activeTermId),
                              AppSection.routines =>
                                activeTermId == null
                                    ? const _ChooseTermMessage()
                                    : RoutinePage(
                                        termId: activeTermId,
                                        onArrangeSupervision: (seed) =>
                                            unawaited(
                                              _requestSection(
                                                AppSection.supervision,
                                                supervisionSeed: seed,
                                              ),
                                            ),
                                      ),
                              AppSection.subjects =>
                                activeTermId == null
                                    ? const _ChooseTermMessage()
                                    : SubjectsPage(termId: activeTermId),
                              AppSection.teachers =>
                                activeTermId == null
                                    ? const _ChooseTermMessage()
                                    : TeachersPage(termId: activeTermId),
                              AppSection.scheduling =>
                                activeTermId == null
                                    ? const _ChooseTermMessage()
                                    : SchedulingPage(termId: activeTermId),
                              AppSection.supervision =>
                                activeTermId == null
                                    ? const _ChooseTermMessage()
                                    : SupervisionPage(
                                        termId: activeTermId,
                                        seed: _supervisionSeed,
                                      ),
                              AppSection.temporaryAdjustments =>
                                activeTermId == null
                                    ? const _ChooseTermMessage()
                                    : TemporaryAdjustmentsPage(
                                        termId: activeTermId,
                                      ),
                            },
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
      );
    }
    return Scaffold(backgroundColor: context.appColors.canvas, body: shellBody);
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.section,
    required this.isCompact,
    required this.onNavigate,
  });

  final AppSection section;
  final bool isCompact;
  final ValueChanged<AppSection> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termsProvider).valueOrNull ?? const [];
    final selectedTermId = ref.watch(activeTermIdProvider);
    final lastPersistedAt = ref.watch(lastPersistedAtProvider);
    final selectedTerm = terms.where((term) => term.id == selectedTermId);
    final termTitle = selectedTerm.isEmpty ? '当前学期' : selectedTerm.first.title;
    // 菜单门控依据：学期汇总（加载中/失败时为 null，不拦截导航）。
    final summary = selectedTermId == null
        ? null
        : ref.watch(workbenchSummaryProvider(selectedTermId)).valueOrNull;
    (bool, String?) gate(AppSection target) => navSectionAvailability(
      target,
      hasTerm: selectedTermId != null,
      summary: summary,
    );

    return AnimatedContainer(
      duration: AppTheme.motionDuration(context, AppTheme.transitionDuration),
      curve: Curves.easeInOutCubic,
      width: isCompact ? 70 : 244,
      decoration: BoxDecoration(color: context.appColors.surface),
      padding: EdgeInsets.fromLTRB(0, 0, 0, isCompact ? 10 : 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Keep expanded-only rows out of the sidebar while its width is
          // animating through a size that cannot fit them yet.
          final compactContents = isCompact || constraints.maxWidth < 160;
          final sidebarInset = AppTheme.sidebarPaddingForWidth(
            AppPageLayout.widthOf(context),
          );
          Widget navItem(AppSection target, IconData icon, String label) {
            final (enabled, reason) = gate(target);
            return _NavItem(
              isCompact: compactContents,
              icon: icon,
              label: label,
              isSelected: target == section,
              enabled: enabled,
              disabledReason: reason,
              onTap: () => onNavigate(target),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compactContents ? 0 : sidebarInset,
                  17,
                  compactContents ? 0 : sidebarInset,
                  16,
                ),
                child: Row(
                  mainAxisAlignment: compactContents
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    const _BrandLogo(),
                    if (!compactContents) const SizedBox(width: 10),
                    if (!compactContents)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '课集',
                            style: TextStyle(
                              color: context.appColors.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'ClassSet.app',
                            style: TextStyle(
                              color: context.appColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compactContents ? 7 : sidebarInset,
                  0,
                  compactContents ? 7 : sidebarInset,
                  13,
                ),
                child: _SchoolIdentityCard(
                  isCompact: compactContents,
                  termTitle: termTitle,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: compactContents ? 7 : sidebarInset,
                  ),
                  children: [
                    navItem(
                      AppSection.workbench,
                      Icons.space_dashboard_outlined,
                      '工作台',
                    ),
                    if (!compactContents) const _NavGroupLabel('基础设置'),
                    navItem(
                      AppSection.terms,
                      Icons.event_note_rounded,
                      '学期与日历',
                    ),
                    navItem(
                      AppSection.classes,
                      Icons.account_tree_outlined,
                      '班级与学段',
                    ),
                    navItem(
                      AppSection.routines,
                      Icons.view_week_outlined,
                      '作息设置',
                    ),
                    navItem(
                      AppSection.publicRooms,
                      Icons.meeting_room_outlined,
                      '公共场室',
                    ),
                    if (!compactContents) const _NavDivider(),
                    if (!compactContents) const _NavGroupLabel('排课准备'),
                    navItem(
                      AppSection.subjects,
                      Icons.calculate_outlined,
                      '科目节数',
                    ),
                    navItem(AppSection.teachers, Icons.person_outline, '教师任课'),
                    if (!compactContents) const _NavDivider(),
                    if (!compactContents) const _NavGroupLabel('课表与课务'),
                    navItem(
                      AppSection.scheduling,
                      Icons.auto_awesome_outlined,
                      '排课与课表',
                    ),
                    navItem(
                      AppSection.supervision,
                      Icons.groups_outlined,
                      '带班安排',
                    ),
                    navItem(
                      AppSection.temporaryAdjustments,
                      Icons.swap_horiz_rounded,
                      '调代课',
                    ),
                  ],
                ),
              ),
              if (!compactContents)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    sidebarInset,
                    10,
                    sidebarInset,
                    0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: context.appColors.canvas,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: context.appColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '本地数据 · 离线可用',
                                style: TextStyle(
                                  color: context.appColors.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '数据保存在这台设备',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.appColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (lastPersistedAt != null) ...[
                                const SizedBox(height: 1),
                                Text(
                                  '最近保存 ${_savedTimeLabel(lastPersistedAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.appColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SchoolIdentityCard extends ConsumerWidget {
  const _SchoolIdentityCard({required this.isCompact, required this.termTitle});

  final bool isCompact;
  final String termTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolName = ref.watch(schoolNameProvider).valueOrNull ?? '';
    final displayName = ref.watch(schoolDisplayNameProvider);
    final initial = schoolName.trim().isEmpty
        ? '校'
        : String.fromCharCode(schoolName.trim().runes.first);

    return Tooltip(
      message: '编辑学校名称',
      child: f.FTappable(
        semanticsLabel: '编辑学校名称，当前为$displayName',
        onPress: () => _editSchoolName(context, ref, schoolName),
        child: Container(
          padding: EdgeInsets.all(isCompact ? 8 : 10),
          decoration: BoxDecoration(
            color: context.appColors.canvas,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: isCompact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Container(
                width: 31,
                height: 31,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.appColors.selectedBlue,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: context.appColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!isCompact) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        termTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editSchoolName(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (context) => SchoolNameDialog(initialName: currentName),
    );
    if (name == null || !context.mounted || name.trim() == currentName.trim()) {
      return;
    }
    try {
      await ref.read(schoolRepositoryProvider).saveSchoolName(name);
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('保存学校名称失败：$error')));
      }
    }
  }
}

class _NavGroupLabel extends StatelessWidget {
  const _NavGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 13, 0, 6),
    child: Text(
      label,
      style: TextStyle(
        color: context.appColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _NavDivider extends StatelessWidget {
  const _NavDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Container(height: 1, color: context.appColors.border),
  );
}

/// 侧栏品牌 Logo。
///
/// 用小尺寸专用的精简标（蓝底 + 叠卡 + 橙格），而非完整应用图标：
/// 完整图标的三张浅色卡与折角在 32px 下会糊成一团、且在暖白侧栏上几乎无对比。
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'design/icon/classset/classset-mark.svg',
    width: 36,
    height: 36,
    semanticsLabel: '课集 Logo',
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.isCompact,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.enabled = true,
    this.disabledReason,
  });

  final IconData icon;
  final String label;
  final bool isCompact;
  final bool isSelected;

  /// 关键数据未就绪时置灰；此时 Tooltip 展示 [disabledReason]。
  final bool enabled;
  final String? disabledReason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = !enabled;
    // 禁用态在正常弱化色上再降低强调，与可用项区分且不当作辅助文字使用。
    final disabledColor = context.appColors.sidebarMuted.withValues(
      alpha: 0.55,
    );
    final iconColor = disabled
        ? disabledColor
        : isSelected
        ? context.appColors.accent
        : context.appColors.sidebarMuted;
    final textColor = disabled
        ? disabledColor
        : isSelected
        ? context.appColors.accent
        : context.appColors.sidebarText;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 0),
      child: Tooltip(
        message: disabled
            ? (disabledReason ?? '暂不可用')
            : (isCompact ? label : ''),
        child: f.FTappable(
          semanticsLabel: label,
          selected: isSelected,
          onPress: disabled ? null : onTap,
          child: Container(
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 0 : 11),
            decoration: BoxDecoration(
              color: isSelected && !disabled
                  ? context.appColors.sidebarActive
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: isCompact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(icon, size: 17, color: iconColor),
                if (!isCompact) const SizedBox(width: 10),
                if (!isCompact)
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: isSelected && !disabled
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                if (!isCompact && label == '作息设置')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '分学段',
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
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
}

/// 尚未实现的导航项：置灰并提示后续版本提供。
class _NavComingSoon extends StatelessWidget {
  const _NavComingSoon({
    required this.label,
    required this.icon,
    this.isCompact = false,
  });

  final String label;
  final IconData icon;
  final bool isCompact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Tooltip(
      message: '「$label」将在后续版本提供',
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 0 : 11),
          child: Row(
            mainAxisAlignment: isCompact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: context.appColors.sidebarMuted),
              if (!isCompact) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.sidebarMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.pageTitle,
    required this.isSidebarExpanded,
    required this.themeMode,
    required this.palette,
    required this.onAppearanceSettings,
    required this.onCycleThemeMode,
    required this.onSelectTerm,
    required this.onToggleSidebar,
  });

  final String pageTitle;
  final bool isSidebarExpanded;
  final AppAppearanceMode themeMode;
  final AppPalette palette;
  final void Function(BuildContext) onAppearanceSettings;
  final VoidCallback onCycleThemeMode;
  final ValueChanged<String> onSelectTerm;
  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termsProvider).valueOrNull ?? const [];
    final activeId = ref.watch(activeTermIdProvider);
    final activeTerm = terms.where((term) => term.id == activeId);
    final activeTitle = activeTerm.isEmpty ? '选择学期' : activeTerm.first.title;

    return Container(
      height: 62,
      padding: EdgeInsets.symmetric(
        horizontal: AppPageLayout.gutterOf(context),
      ),
      decoration: BoxDecoration(color: context.appColors.canvas),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (onToggleSidebar != null) ...[
              AppIconButton(
                icon: isSidebarExpanded
                    ? Icons.menu_open_rounded
                    : Icons.menu_rounded,
                tooltip: isSidebarExpanded ? '收起侧边栏' : '展开侧边栏',
                onPressed: onToggleSidebar!,
                iconSize: 18,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              pageTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            AppMenuButton(
              items: [
                for (final term in terms)
                  AppMenuItem(
                    label: term.title,
                    selected: term.id == activeId,
                    onPressed: () => onSelectTerm(term.id),
                  ),
              ],
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth < 800 ? 220 : 320,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: context.appColors.canvas,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        activeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 15,
                      color: context.appColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            AppIconButton(
              key: const Key('appearance-settings-button'),
              icon: Icons.palette_outlined,
              tooltip: '主题与外观：${palette.label}',
              onPressed: () => onAppearanceSettings(context),
              iconSize: 18,
            ),
            const SizedBox(width: 8),
            AppIconButton(
              icon: themeMode.icon,
              tooltip: '当前主题：${themeMode.label}，点击切换',
              onPressed: onCycleThemeMode,
              iconSize: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChooseTermMessage extends ConsumerWidget {
  const _ChooseTermMessage();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.event_busy_outlined,
          size: 42,
          color: context.appColors.muted,
        ),
        const SizedBox(height: 12),
        Text(
          '请先创建并选择一个学期',
          style: TextStyle(
            color: context.appColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        AppPrimaryButton(
          onPressed: () => ref.read(selectedSectionProvider.notifier).state =
              AppSection.terms,
          child: const Text('前往学期管理'),
        ),
      ],
    ),
  );
}
