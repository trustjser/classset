import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/features/classes/classes_page.dart';
import 'package:class_set/features/routines/routine_page.dart';
import 'package:class_set/features/terms/term_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart' as f;

enum AppSection { terms, classes, routines }

final selectedSectionProvider = StateProvider<AppSection>(
  (ref) => AppSection.terms,
);
final activeTermIdProvider = StateProvider<String?>((ref) => null);

/// 最近一次成功写入本地数据库的时间；顶栏「已自动暂存」据此展示。
final lastPersistedAtProvider = StateProvider<DateTime?>((ref) => null);

class ClassSetApp extends ConsumerWidget {
  const ClassSetApp({required this.databasePath, super.key});

  final String databasePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: '课集',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    builder: (context, child) => f.FTheme(
      data: AppTheme.forui,
      child: f.FToaster(child: child!),
    ),
    home: _AppShell(databasePath: databasePath),
  );
}

class _AppShell extends ConsumerWidget {
  const _AppShell({required this.databasePath});

  final String databasePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      backgroundColor: AppTheme.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compactNavigation = constraints.maxWidth < 1040;
          final pageTitle = switch (section) {
            AppSection.terms => '学期与日历',
            AppSection.classes => '班级与学段',
            AppSection.routines => '作息设置',
          };
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(
                section: section,
                databasePath: databasePath,
                isCompact: compactNavigation,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(pageTitle: pageTitle, databasePath: databasePath),
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
                            AppSection.terms => TermPage(
                              databasePath: databasePath,
                            ),
                            AppSection.classes =>
                              activeTermId == null
                                  ? const _ChooseTermMessage()
                                  : ClassesPage(termId: activeTermId),
                            AppSection.routines =>
                              activeTermId == null
                                  ? const _ChooseTermMessage()
                                  : RoutinePage(termId: activeTermId),
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
  const _Sidebar({
    required this.section,
    required this.databasePath,
    required this.isCompact,
  });

  final AppSection section;
  final String databasePath;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termsProvider).valueOrNull ?? const [];
    final selectedTermId = ref.watch(activeTermIdProvider);
    final selectedTerm = terms.where((term) => term.id == selectedTermId);
    final termTitle = selectedTerm.isEmpty ? '当前学期' : selectedTerm.first.title;

    return Container(
      width: isCompact ? 70 : 244,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppTheme.border)),
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
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '课集',
                        style: TextStyle(
                          color: AppTheme.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'CLASSSET',
                        style: TextStyle(
                          color: AppTheme.muted,
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
                  color: AppTheme.canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 31,
                      height: 31,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.selectedBlue,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Text(
                        '青',
                        style: TextStyle(
                          color: AppTheme.blue,
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
                          const Text(
                            '青木实验学校',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            termTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: AppTheme.muted,
                    ),
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
                _NavComingSoon(
                  label: '科目节数',
                  icon: Icons.calculate_outlined,
                  isCompact: isCompact,
                ),
                _NavComingSoon(
                  label: '教师任课',
                  icon: Icons.person_outline,
                  isCompact: isCompact,
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
                _NavComingSoon(
                  label: '公共场室',
                  icon: Icons.meeting_room_outlined,
                  isCompact: isCompact,
                ),
              ],
            ),
          ),
          if (!isCompact)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 0),
              child: Tooltip(
                message: databasePath,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.canvas,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '本地数据 · 离线可用',
                              style: TextStyle(
                                color: AppTheme.ink,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              databasePath.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.muted,
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
      style: const TextStyle(
        color: AppTheme.muted,
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
    child: Container(height: 1, color: AppTheme.border),
  );
}

/// 设计稿四色方块 Logo（2×2）。
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 20,
    height: 20,
    // ColoredBox 无子节点时不会撑开高度，必须用 Expanded 分配行列尺寸。
    child: Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _LogoCell(AppTheme.blue)),
              Expanded(child: _LogoCell(Color(0xFF366EF4))),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _LogoCell(Color(0xFF8EABFF))),
              Expanded(child: _LogoCell(Color(0xFF003CAB))),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LogoCell extends StatelessWidget {
  const _LogoCell(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(color: color);
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
            color: isSelected ? AppTheme.sidebarActive : Colors.transparent,
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
                color: isSelected ? AppTheme.blue : AppTheme.sidebarMuted,
              ),
              if (!isCompact) const SizedBox(width: 10),
              if (!isCompact)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? AppTheme.blue : AppTheme.sidebarText,
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '分学段',
                    style: TextStyle(color: AppTheme.muted, fontSize: 9),
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
              Icon(icon, size: 17, color: AppTheme.sidebarMuted),
              if (!isCompact) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.sidebarMuted,
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
  const _TopBar({required this.pageTitle, required this.databasePath});

  final String pageTitle;
  final String databasePath;

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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (constraints.maxWidth > 660) ...[
              const Text(
                '青木实验学校',
                style: TextStyle(
                  color: AppTheme.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: AppTheme.muted,
                ),
              ),
            ] else ...[
              Text(
                pageTitle,
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
            ],
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
                  color: AppTheme.canvas,
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
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: 15,
                      color: AppTheme.muted,
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (constraints.maxWidth > 860)
              Tooltip(
                message: databasePath,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    databasePath.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                  ),
                ),
              ),
            if (constraints.maxWidth > 720) ...[
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.successSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      lastPersistedAt == null
                          ? '本地自动保存'
                          : '已保存 ${_hhmm(lastPersistedAt)}',
                      style: const TextStyle(
                        color: AppTheme.success,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 8),
            if (constraints.maxWidth > 690)
              AppGhostButton(
                onPressed: () => _showHelp(context),
                child: const Text('F1 帮助'),
              )
            else
              AppIconButton(
                icon: Icons.help_outline_rounded,
                tooltip: '帮助',
                onPressed: () => _showHelp(context),
                iconSize: 17,
              ),
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) => showAppDialog<void>(
    context: context,
    builder: (context) => AppDialog(
      title: const Text('帮助'),
      content: const SelectableText(
        '课集把全部资料保存在本机 SQLite 数据文件中，离线可用。\n\n'
        '· 学期与日历：设置第 1 教学周起始日与教学周数，管理停课 / 补课等例外安排；'
        '第 1 教学周定义为单周，此后单双周交替。\n'
        '· 班级与学段：年级归属唯一学段，班级挂靠年级；支持批量填充名称。\n'
        '· 作息设置：按学段设置上课日、各时段节数与节次时间；'
        '在范围树选择全校 / 学段 / 年级 / 班级后，单击格子标记免任课。',
      ),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  static String _hhmm(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class _ChooseTermMessage extends ConsumerWidget {
  const _ChooseTermMessage();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.event_busy_outlined, size: 42, color: AppTheme.muted),
        const SizedBox(height: 12),
        const Text(
          '请先创建并选择一个学期',
          style: TextStyle(
            color: AppTheme.ink,
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
