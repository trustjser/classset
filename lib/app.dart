import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/features/classes/classes_page.dart';
import 'package:class_set/features/routines/routine_page.dart';
import 'package:class_set/features/public_rooms/public_rooms_page.dart';
import 'package:class_set/features/subjects/subjects_page.dart';
import 'package:class_set/features/teachers/teachers_page.dart';
import 'package:class_set/features/terms/term_page.dart';
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
  publicRooms,
}

enum _AppThemeMode {
  system('跟随系统', Icons.brightness_auto_rounded),
  light('浅色模式', Icons.light_mode_outlined),
  dark('暗色模式', Icons.dark_mode_outlined);

  const _AppThemeMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

final selectedSectionProvider = StateProvider<AppSection>(
  (ref) => AppSection.workbench,
);
final activeTermIdProvider = StateProvider<String?>((ref) => null);

/// 最近一次成功写入本地数据库的时间；顶栏据此展示最近保存时间。
final lastPersistedAtProvider = StateProvider<DateTime?>((ref) => null);

class ClassSetApp extends StatefulWidget {
  const ClassSetApp({required this.databasePath, super.key});

  final String databasePath;

  @override
  State<ClassSetApp> createState() => _ClassSetAppState();
}

class _ClassSetAppState extends State<ClassSetApp> with WidgetsBindingObserver {
  static const _windowAppearanceChannel = MethodChannel(
    'class_set/window_appearance',
  );

  _AppThemeMode _themeMode = _AppThemeMode.light;

  bool get _isDarkMode => switch (_themeMode) {
    _AppThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark,
    _AppThemeMode.light => false,
    _AppThemeMode.dark => true,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (_themeMode == _AppThemeMode.system) setState(() {});
  }

  void _setThemeMode(_AppThemeMode mode) {
    setState(() => _themeMode = mode);
    if (Platform.isMacOS) unawaited(_setNativeWindowAppearance(mode));
  }

  void _cycleThemeMode() {
    final nextMode = switch (_themeMode) {
      _AppThemeMode.light => _AppThemeMode.dark,
      _AppThemeMode.dark => _AppThemeMode.system,
      _AppThemeMode.system => _AppThemeMode.light,
    };
    _setThemeMode(nextMode);
  }

  Future<void> _setNativeWindowAppearance(_AppThemeMode mode) async {
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
    theme: AppTheme.themeFor(_isDarkMode),
    builder: (context, child) => f.FTheme(
      data: AppTheme.foruiFor(_isDarkMode),
      child: f.FToaster(child: child!),
    ),
    home: _AppShell(
      databasePath: widget.databasePath,
      themeMode: _themeMode,
      onCycleThemeMode: _cycleThemeMode,
    ),
  );
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell({
    required this.databasePath,
    required this.themeMode,
    required this.onCycleThemeMode,
  });

  final String databasePath;
  final _AppThemeMode themeMode;
  final VoidCallback onCycleThemeMode;

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  static const _compactNavigationBreakpoint = 1040.0;
  bool _sidebarExpanded = true;

  @override
  Widget build(BuildContext context) {
    final section = ref.watch(selectedSectionProvider);
    final activeTermId = ref.watch(activeTermIdProvider);
    final terms = ref.watch(termsProvider);
    final availableTerms = terms.valueOrNull ?? const [];
    if (activeTermId == null && availableTerms.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ref.read(activeTermIdProvider) == null) {
          ref.read(activeTermIdProvider.notifier).state =
              availableTerms.first.id;
        }
      });
    }

    return Scaffold(
      backgroundColor: context.appColors.canvas,
      body: LayoutBuilder(
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
            AppSection.publicRooms => '公共场室',
          };
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(section: section, isCompact: compactNavigation),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      pageTitle: pageTitle,
                      isSidebarExpanded: !compactNavigation,
                      themeMode: widget.themeMode,
                      onCycleThemeMode: widget.onCycleThemeMode,
                      onToggleSidebar:
                          constraints.maxWidth < _compactNavigationBreakpoint
                          ? null
                          : () => setState(
                              () => _sidebarExpanded = !_sidebarExpanded,
                            ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        reverseDuration: const Duration(milliseconds: 140),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                              alignment: Alignment.topLeft,
                              fit: StackFit.expand,
                              clipBehavior: Clip.hardEdge,
                              children: [
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            ),
                        transitionBuilder: (child, animation) => FadeTransition(
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
                          key: ValueKey(section),
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
                                  : RoutinePage(termId: activeTermId),
                            AppSection.subjects =>
                              activeTermId == null
                                  ? const _ChooseTermMessage()
                                  : SubjectsPage(termId: activeTermId),
                            AppSection.teachers =>
                              activeTermId == null
                                  ? const _ChooseTermMessage()
                                  : TeachersPage(termId: activeTermId),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.section, required this.isCompact});

  final AppSection section;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termsProvider).valueOrNull ?? const [];
    final selectedTermId = ref.watch(activeTermIdProvider);
    final selectedTerm = terms.where((term) => term.id == selectedTermId);
    final termTitle = selectedTerm.isEmpty ? '当前学期' : selectedTerm.first.title;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      width: isCompact ? 70 : 244,
      decoration: BoxDecoration(
        color: context.appColors.surface,
        border: Border(right: BorderSide(color: context.appColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(0, 0, 0, isCompact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 0 : 18,
              17,
              isCompact ? 0 : 16,
              16,
            ),
            child: Row(
              mainAxisAlignment: isCompact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                const _BrandLogo(),
                if (!isCompact) const SizedBox(width: 10),
                if (!isCompact)
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
                        'CLASSSET',
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 9,
                          letterSpacing: .7,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (!isCompact)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.appColors.canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
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
                        '青',
                        style: TextStyle(
                          color: context.appColors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '青木实验学校',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.appColors.ink,
                              fontSize: 11,
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
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Icon(
                    //   Icons.expand_more_rounded,
                    //   size: 16,
                    //   color: context.appColors.muted,
                    // ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 7 : 10),
              children: [
                if (!isCompact) const _NavGroupLabel('排课准备'),
                _NavItem(
                  isCompact: isCompact,
                  icon: Icons.space_dashboard_outlined,
                  label: '工作台',
                  isSelected: section == AppSection.workbench,
                  onTap: () =>
                      ref.read(selectedSectionProvider.notifier).state =
                          AppSection.workbench,
                ),
                _NavItem(
                  isCompact: isCompact,
                  icon: Icons.event_note_rounded,
                  label: '学期与日历',
                  isSelected: section == AppSection.terms,
                  onTap: () =>
                      ref.read(selectedSectionProvider.notifier).state =
                          AppSection.terms,
                ),
                _NavItem(
                  isCompact: isCompact,
                  icon: Icons.account_tree_outlined,
                  label: '班级与学段',
                  isSelected: section == AppSection.classes,
                  onTap: () =>
                      ref.read(selectedSectionProvider.notifier).state =
                          AppSection.classes,
                ),
                _NavItem(
                  isCompact: isCompact,
                  icon: Icons.view_week_outlined,
                  label: '作息设置',
                  isSelected: section == AppSection.routines,
                  onTap: () =>
                      ref.read(selectedSectionProvider.notifier).state =
                          AppSection.routines,
                ),
                if (!isCompact) const _NavDivider(),
                if (!isCompact) const _NavGroupLabel('排课与课表'),
                _NavItem(
                  isCompact: isCompact,
                  icon: Icons.calculate_outlined,
                  label: '科目节数',
                  isSelected: section == AppSection.subjects,
                  onTap: () =>
                      ref.read(selectedSectionProvider.notifier).state =
                          AppSection.subjects,
                ),
                _NavItem(
                  label: '教师任课',
                  icon: Icons.person_outline,
                  isCompact: isCompact,
                  isSelected: section == AppSection.teachers,
                  onTap: () =>
                      ref.read(selectedSectionProvider.notifier).state =
                          AppSection.teachers,
                ),
                _NavComingSoon(
                  label: '自动排课',
                  icon: Icons.auto_awesome_outlined,
                  isCompact: isCompact,
                ),
                _NavComingSoon(
                  label: '课表编辑',
                  icon: Icons.calendar_view_week_outlined,
                  isCompact: isCompact,
                ),
                if (!isCompact) const _NavDivider(),
                if (!isCompact) const _NavGroupLabel('更多'),
                _NavItem(
                  label: '公共场室',
                  icon: Icons.meeting_room_outlined,
                  isCompact: isCompact,
                  isSelected: section == AppSection.publicRooms,
                  onTap: () =>
                      ref.read(selectedSectionProvider.notifier).state =
                          AppSection.publicRooms,
                ),
              ],
            ),
          ),
          if (!isCompact)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 0),
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
                              fontSize: 10,
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
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavGroupLabel extends StatelessWidget {
  const _NavGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 13, 10, 6),
    child: Text(
      label,
      style: TextStyle(
        color: context.appColors.muted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: .15,
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
  });

  final IconData icon;
  final bool isCompact;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Tooltip(
      message: isCompact ? label : '',
      child: f.FTappable(
        semanticsLabel: label,
        onPress: onTap,
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 0 : 11),
          decoration: BoxDecoration(
            color: isSelected
                ? context.appColors.sidebarActive
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: isCompact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? context.appColors.blue
                    : context.appColors.sidebarMuted,
              ),
              if (!isCompact) const SizedBox(width: 10),
              if (!isCompact)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? context.appColors.blue
                          : context.appColors.sidebarText,
                      fontSize: 12,
                      fontWeight: isSelected
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
                      fontSize: 9,
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
    required this.onCycleThemeMode,
    required this.onToggleSidebar,
  });

  final String pageTitle;
  final bool isSidebarExpanded;
  final _AppThemeMode themeMode;
  final VoidCallback onCycleThemeMode;
  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPersistedAt = ref.watch(lastPersistedAtProvider);
    final terms = ref.watch(termsProvider).valueOrNull ?? const [];
    final activeId = ref.watch(activeTermIdProvider);
    final activeTerm = terms.where((term) => term.id == activeId);
    final activeTitle = activeTerm.isEmpty ? '选择学期' : activeTerm.first.title;

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        border: Border(bottom: BorderSide(color: context.appColors.border)),
      ),
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
                    onPressed: () =>
                        ref.read(activeTermIdProvider.notifier).state = term.id,
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
                          fontSize: 11,
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
              icon: themeMode.icon,
              tooltip: '当前主题：${themeMode.label}，点击切换',
              onPressed: onCycleThemeMode,
              iconSize: 17,
            ),
            if (constraints.maxWidth > 720) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: context.appColors.successSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: context.appColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      lastPersistedAt == null
                          ? '上次保存：暂无'
                          : '上次保存：${_savedTime(lastPersistedAt)}',
                      style: TextStyle(
                        color: context.appColors.success,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _savedTime(DateTime time) {
    final now = DateTime.now();
    final timeText =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return timeText;
    }
    return '${time.month}/${time.day} $timeText';
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
