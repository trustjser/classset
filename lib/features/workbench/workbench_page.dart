import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:class_set/features/workbench/widgets/completed_preparations_card.dart';
import 'package:class_set/features/workbench/widgets/current_term_card.dart';
import 'package:class_set/features/workbench/widgets/local_data_card.dart';
import 'package:class_set/features/workbench/widgets/next_step_card.dart';
import 'package:class_set/features/workbench/widgets/preparation_steps_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 工作台：新学期排课准备的引导首页。
class WorkbenchPage extends ConsumerWidget {
  const WorkbenchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termsProvider);
    return terms.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _ErrorPanel(message: '读取本地学期数据失败：$error'),
      data: (items) {
        if (items.isEmpty) return const _EmptyWorkbench();
        final activeTermId = ref.watch(activeTermIdProvider);
        final selected = items.where((item) => item.id == activeTermId);
        final term = selected.isEmpty ? items.first : selected.first;
        final summary = ref.watch(workbenchSummaryProvider(term.id));
        return summary.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => _ErrorPanel(message: '读取准备进度失败：$error'),
          data: (data) => _WorkbenchContent(term: term, summary: data),
        );
      },
    );
  }
}

class _WorkbenchContent extends ConsumerStatefulWidget {
  const _WorkbenchContent({required this.term, required this.summary});

  final AcademicTerm term;
  final WorkbenchSummary summary;

  @override
  ConsumerState<_WorkbenchContent> createState() => _WorkbenchContentState();
}

class _WorkbenchContentState extends ConsumerState<_WorkbenchContent> {
  bool _seeding = false;

  @override
  Widget build(BuildContext context) {
    final step = currentPreparationStep(widget.summary);
    final copy = stepCopyFor(step, widget.summary);
    final onAction = switch (step) {
      PreparationStep.stagesAndClasses => () => _navigate(AppSection.classes),
      PreparationStep.routine => () => _navigate(AppSection.routines),
      PreparationStep.subjectLessons => () => _navigate(AppSection.subjects),
      _ => null,
    };
    final comingSoonHint = onAction == null ? '「${step.title}」将在后续版本提供' : null;
    final pagePadding = AppTheme.pagePaddingForWidth(
      MediaQuery.sizeOf(context).width,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: pagePadding, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: '先把新学期的基础搭起来',
            subtitle: '跟着步骤完成准备，课集会在合适的时候解锁下一步。',
            actions: [
              AppOutlineButton(
                onPressed: _seeding ? null : _seedDemoData,
                child: const Text('演示数据'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          PreparationStepsCard(summary: widget.summary),
          const SizedBox(height: AppTheme.pageSectionGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final hero = NextStepCard(
                step: step,
                copy: copy,
                onAction: onAction,
                comingSoonHint: comingSoonHint,
              );
              final termCard = CurrentTermCard(
                term: widget.term,
                now: DateTime.now(),
                onOpenTerms: () => _navigate(AppSection.terms),
              );
              final wide = constraints.maxWidth >= 940;
              if (wide) {
                // IntrinsicHeight：滚动容器内 stretch 前需定高。
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: hero),
                      const SizedBox(width: AppTheme.pageSectionGap),
                      Expanded(flex: 4, child: termCard),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  const SizedBox(height: AppTheme.pageSectionGap),
                  termCard,
                ],
              );
            },
          ),
          const SizedBox(height: AppTheme.pageSectionGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final completed = CompletedPreparationsCard(
                summary: widget.summary,
              );
              final localData = LocalDataCard(
                onOpenGuide: () => showGettingStartedGuide(context),
              );
              if (constraints.maxWidth >= 940) {
                // IntrinsicHeight：滚动容器内 stretch 前需定高。
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: completed),
                      const SizedBox(width: AppTheme.pageSectionGap),
                      Expanded(flex: 4, child: localData),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  completed,
                  const SizedBox(height: AppTheme.pageSectionGap),
                  localData,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _navigate(AppSection section) =>
      ref.read(selectedSectionProvider.notifier).state = section;

  Future<void> _seedDemoData() async {
    // 新建学期会自动创建一个默认学段，因此以「还没有年级」判断能否播种。
    if (widget.summary.gradeCount > 0) {
      _showMessage('当前学期已有年级数据，未生成演示数据。');
      return;
    }
    setState(() => _seeding = true);
    try {
      final repository = ref.read(schoolRepositoryProvider);
      await seedDemoData(repository: repository, term: widget.term);
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      _showMessage('已生成演示数据：2 个学段，各 3 个年级、3 个班。');
    } on Object catch (error) {
      _showMessage('生成演示数据失败：$error');
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyWorkbench extends ConsumerWidget {
  const _EmptyWorkbench();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
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
            '先创建一个学期',
            style: TextStyle(
              color: context.appColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '排课准备从学期开始：设置学年学期与教学日历。',
            style: TextStyle(color: context.appColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          AppPrimaryButton(
            onPressed: () => ref.read(selectedSectionProvider.notifier).state =
                AppSection.terms,
            child: const Text('前往学期与日历'),
          ),
        ],
      ),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: SelectableText(
        message,
        style: TextStyle(color: context.appColors.destructive, fontSize: 13),
      ),
    ),
  );
}
