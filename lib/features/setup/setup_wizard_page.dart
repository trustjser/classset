import 'dart:ui' show FontFeature;

import 'package:class_set/app.dart';
import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 空数据创建向导：本地尚无任何学期时的全屏引导，不显示侧边栏与顶部栏。
///
/// 两步：填写学校名称（可留空跳过）→ 创建第一个学期；完成后写入本地数据并
/// 进入工作台。侧栏在关键数据就绪前也会对后续菜单置灰，见 `app.dart` 的
/// 菜单门控。
class SetupWizardPage extends ConsumerStatefulWidget {
  const SetupWizardPage({super.key});

  @override
  ConsumerState<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends ConsumerState<SetupWizardPage> {
  static const _totalSteps = 2;
  static const _schoolSuggestions = <String>[
    '青木实验小学',
    '青木初级中学',
    '第一高级中学',
    '实验学校',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _schoolNameController;
  late final TextEditingController _termTitleController;
  late final TextEditingController _weekCountController;
  int _step = 1;
  int _slideDirection = 1;
  AcademicTermCycle _cycleMode = AcademicTermCycle.alternating;
  DateTime? _firstTeachingWeekStart;
  String? _dateValidationError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _schoolNameController = TextEditingController()..addListener(_onFormChanged);
    final now = DateTime.now();
    final semesterLabel = now.month >= 7 ? '秋季学期' : '春季学期';
    _termTitleController = TextEditingController(
      text: '${now.year} 学年 · $semesterLabel',
    )..addListener(_onFormChanged);
    _weekCountController = TextEditingController(text: '20')
      ..addListener(_onFormChanged);
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _schoolNameController
      ..removeListener(_onFormChanged)
      ..dispose();
    _termTitleController
      ..removeListener(_onFormChanged)
      ..dispose();
    _weekCountController
      ..removeListener(_onFormChanged)
      ..dispose();
    super.dispose();
  }

  void _goToStep(int targetStep) {
    if (_saving || targetStep == _step) return;
    if (targetStep > 1 && _step < 1) return; // 严格遵守步骤级联顺序
    setState(() {
      _slideDirection = targetStep > _step ? 1 : -1;
      _step = targetStep;
    });
  }

  void _goToTermStep() => _goToStep(2);

  void _applySchoolSuggestion(String suggestion) {
    _schoolNameController.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  Future<void> _finish() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_firstTeachingWeekStart == null) {
      setState(() => _dateValidationError = '请选择第 1 教学周起始日期');
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final title = _termTitleController.text.trim();
    final yearMatch = RegExp(r'\d{4}(?:-\d{4})?').firstMatch(title);
    final term = AcademicTerm(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      academicYear: yearMatch?.group(0) ?? '${now.year}-${now.year + 1}',
      semesterLabel: title.contains('春')
          ? '春季学期'
          : title.contains('秋')
          ? '秋季学期'
          : now.month >= 7
          ? '秋季学期'
          : '春季学期',
      firstTeachingWeekStart: _firstTeachingWeekStart,
      teachingWeekCount: int.tryParse(_weekCountController.text) ?? 20,
      createdAt: now,
      cycleMode: _cycleMode,
    );
    try {
      final repository = ref.read(schoolRepositoryProvider);
      // 学校名称允许留空：侧栏会显示「未命名学校」，可稍后补填。
      await repository.saveSchoolName(_schoolNameController.text.trim());
      await repository.saveTerm(term);
      // 外壳监听 activeTermId 变化并持久化；学期流更新后自动切回正常框架。
      ref.read(activeTermIdProvider.notifier).state = term.id;
      ref.read(selectedSectionProvider.notifier).state = AppSection.workbench;
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('初始化保存失败：$error')));
      }
    }
  }

  Widget _buildStepTransition(Widget child, Animation<double> animation) {
    final isIncoming = child.key == ValueKey<int>(_step);
    final beginOffset = isIncoming
        ? Offset(0.05 * _slideDirection, 0)
        : Offset(-0.05 * _slideDirection, 0);
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppTheme.entranceCurve,
      reverseCurve: AppTheme.exitCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: beginOffset, end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final transitionDuration = AppTheme.motionDuration(
      context,
      AppTheme.transitionDuration,
    );
    final schoolRaw = _schoolNameController.text.trim();
    final schoolDisplay = schoolRaw.isEmpty ? '未命名学校' : schoolRaw;
    final termRaw = _termTitleController.text.trim();
    final termDisplay = termRaw.isEmpty ? '新建第一个学期' : termRaw;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            padding: const EdgeInsets.fromLTRB(40, 34, 40, 32),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(
                color: colors.border.withValues(alpha: 0.7),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderRow(context),
                const SizedBox(height: 22),
                _StepBadge(
                  step: _step,
                  totalSteps: _totalSteps,
                  schoolSummary: schoolDisplay,
                  termSummary: termDisplay,
                  onSelectStep: _goToStep,
                ),
                const SizedBox(height: 24),
                AnimatedSize(
                  duration: transitionDuration,
                  curve: AppTheme.entranceCurve,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: transitionDuration,
                    reverseDuration: AppTheme.motionDuration(
                      context,
                      AppTheme.exitDuration,
                    ),
                    switchInCurve: AppTheme.entranceCurve,
                    switchOutCurve: AppTheme.exitCurve,
                    transitionBuilder: _buildStepTransition,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previousChildren, ?currentChild],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_step),
                      child: _step == 1 ? _buildSchoolStep() : _buildTermStep(),
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

  Widget _buildHeaderRow(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        SvgPicture.asset(
          'design/icon/classset/classset-mark.svg',
          width: 36,
          height: 36,
          semanticsLabel: '课集 Logo',
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '课集',
              style: TextStyle(
                color: colors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'ClassSet.app',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: colors.tableHeader,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '本地数据 · 离线可用',
                style: TextStyle(
                  color: colors.inkSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolStep() {
    final colors = context.appColors;
    final schoolName = _schoolNameController.text.trim();
    final hasCustomName = schoolName.isNotEmpty;
    final displayName = hasCustomName ? schoolName : '未命名学校';
    final initial = hasCustomName
        ? String.fromCharCode(schoolName.runes.first)
        : '校';
    final termPreview = _termTitleController.text.trim().isEmpty
        ? '新建第一个学期'
        : _termTitleController.text.trim();

    return Column(
      key: const ValueKey('setup-wizard-school-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '欢迎使用课集',
          style: TextStyle(
            color: colors.ink,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '先告诉课集你的学校名称。也可以留空，稍后在左侧学校卡中补填。',
          style: TextStyle(
            color: colors.inkSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        _SchoolIdentityPreviewCard(
          initial: initial,
          displayName: displayName,
          hasCustomName: hasCustomName,
          termTitle: termPreview,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              '学校名称',
              style: TextStyle(
                color: colors.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            AppBadge(
              label: '选填',
              fontSize: 11,
              foreground: colors.muted,
              background: colors.tableHeader,
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppTextFormField(
          key: const ValueKey('wizard-school-name'),
          controller: _schoolNameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如：青木实验小学'),
          onFieldSubmitted: (_) => _goToTermStep(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '快捷示例：',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
            for (final item in _schoolSuggestions)
              _QuickSuggestionPill(
                label: item,
                isSelected: schoolName == item,
                onTap: () => _applySchoolSuggestion(item),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Text(
              hasCustomName ? '按回车或点击下一步继续' : '可留空直接进入下一步',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
            const Spacer(),
            AppPrimaryButton(
              onPressed: _goToTermStep,
              child: const Text('下一步'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTermStep() {
    final colors = context.appColors;
    final weekCount = (int.tryParse(_weekCountController.text) ?? 20).clamp(
      1,
      52,
    );
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('setup-wizard-term-step'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '创建第一个学期',
            style: TextStyle(
              color: colors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '学期决定教学周与课表范围。新建后会自动带一个默认学段，可随时调整。',
            style: TextStyle(
              color: colors.inkSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.canvas.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppLabeledFieldRow(
                  label: '学期名称',
                  child: AppTextFormField(
                    key: const ValueKey('wizard-term-title'),
                    size: .sm,
                    controller: _termTitleController,
                    decoration: const InputDecoration(
                      hintText: '如：2027 学年 · 春季学期',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入学期名称'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledFieldRow(
                  label: '第 1 教学周起始',
                  child: AppDateField(
                    value: _firstTeachingWeekStart,
                    hint: '选择日期',
                    firstDate: DateTime(DateTime.now().year - 10),
                    lastDate: DateTime(DateTime.now().year + 10),
                    format: formatDateYmdWithWeekday,
                    onChanged: (date) => setState(() {
                      _firstTeachingWeekStart = date;
                      _dateValidationError = null;
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                AppLabeledFieldRow(
                  label: '总周数',
                  child: AppNumberStepperField(
                    controller: _weekCountController,
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      final count = int.tryParse(value ?? '');
                      return count == null || count < 1 || count > 52
                          ? '请输入 1–52 之间的周数'
                          : null;
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppLabeledFieldRow(
            label: '课表周期',
            labelHelp: '单双周交替时第 1 教学周固定为单周；每周相同则所有周使用同一套周课表。',
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _CycleOptionCard(
                      value: AcademicTermCycle.everyWeek,
                      groupValue: _cycleMode,
                      title: '每周相同',
                      subtitle: '所有教学周共用同一套周课表',
                      icon: Icons.repeat_rounded,
                      onChanged: (value) => setState(() => _cycleMode = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CycleOptionCard(
                      value: AcademicTermCycle.alternating,
                      groupValue: _cycleMode,
                      title: '单双周交替',
                      subtitle: '第 1 周为单周，单双周按周次自动轮换',
                      icon: Icons.swap_horiz_rounded,
                      onChanged: (value) => setState(() => _cycleMode = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _TermRangePreviewBar(
            startDate: _firstTeachingWeekStart,
            weekCount: weekCount,
            cycleMode: _cycleMode,
          ),
          AnimatedSize(
            duration: AppTheme.motionDuration(
              context,
              AppTheme.feedbackDuration,
            ),
            curve: AppTheme.entranceCurve,
            child: _dateValidationError == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: colors.destructiveSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colors.destructive.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: colors.destructive,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _dateValidationError!,
                              style: TextStyle(
                                color: colors.destructive,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              AppSecondaryButton(
                onPressed: _saving ? null : () => _goToStep(1),
                child: const Text('上一步'),
              ),
              const Spacer(),
              AppPrimaryButton(
                onPressed: _saving ? null : _finish,
                isLoading: _saving,
                child: Text(_saving ? '正在创建…' : '完成设置，进入工作台'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 顶部步骤指示：文字 + 平滑动画进度条 + 两步交互式步骤卡（遵循步骤级联约束）。
class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.step,
    required this.totalSteps,
    required this.schoolSummary,
    required this.termSummary,
    required this.onSelectStep,
  });

  final int step;
  final int totalSteps;
  final String schoolSummary;
  final String termSummary;
  final ValueChanged<int> onSelectStep;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final feedbackDuration = AppTheme.motionDuration(
      context,
      AppTheme.feedbackDuration,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AnimatedSwitcher(
              duration: feedbackDuration,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Text(
                '初始设置 · 第 $step 步 / 共 $totalSteps 步',
                key: ValueKey<int>(step),
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            Text(
              step == 1 ? '填写学校信息' : '配置学期日历',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var index = 1; index <= totalSteps; index++) ...[
              if (index > 1) const SizedBox(width: 6),
              Expanded(
                child: _AnimatedProgressBarSegment(
                  active: index <= step,
                  isCompleted: index < step,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _WizardStepCard(
                  number: 1,
                  title: '学校信息',
                  subtitle: step > 1 ? schoolSummary : '当前步骤 · 可选填',
                  isCurrent: step == 1,
                  isCompleted: step > 1,
                  onTap: step > 1 ? () => onSelectStep(1) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WizardStepCard(
                  number: 2,
                  title: '第一个学期',
                  subtitle: step == 2 ? termSummary : '完成第 1 步后继续',
                  isCurrent: step == 2,
                  isCompleted: false,
                  onTap: null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnimatedProgressBarSegment extends StatelessWidget {
  const _AnimatedProgressBarSegment({
    required this.active,
    required this.isCompleted,
  });

  final bool active;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fillColor = isCompleted ? colors.success : colors.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.tableHeader),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: active ? 1.0 : 0.0),
              duration: AppTheme.motionDuration(
                context,
                AppTheme.transitionDuration,
              ),
              curve: AppTheme.entranceCurve,
              builder: (context, value, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value,
                child: AnimatedContainer(
                  duration: AppTheme.motionDuration(
                    context,
                    AppTheme.feedbackDuration,
                  ),
                  color: fillColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WizardStepCard extends StatefulWidget {
  const _WizardStepCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.isCurrent,
    required this.isCompleted,
    this.onTap,
  });

  final int number;
  final String title;
  final String subtitle;
  final bool isCurrent;
  final bool isCompleted;
  final VoidCallback? onTap;

  @override
  State<_WizardStepCard> createState() => _WizardStepCardState();
}

class _WizardStepCardState extends State<_WizardStepCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final canTap = widget.onTap != null;
    final transitionDuration = AppTheme.motionDuration(
      context,
      AppTheme.transitionDuration,
    );

    final baseBackground = widget.isCurrent
        ? colors.selection
        : widget.isCompleted
        ? Color.alphaBlend(
            colors.success.withValues(alpha: 0.05),
            colors.tableHeader,
          )
        : colors.tableHeader;
    final backgroundColor = canTap && _hovered
        ? Color.alphaBlend(
            colors.accent.withValues(alpha: 0.06),
            baseBackground,
          )
        : baseBackground;
    final borderColor = widget.isCurrent
        ? colors.accent.withValues(alpha: 0.32)
        : widget.isCompleted
        ? colors.success.withValues(alpha: canTap && _hovered ? 0.4 : 0.22)
        : colors.border.withValues(alpha: 0.4);

    final badgeBg = widget.isCompleted
        ? colors.success
        : widget.isCurrent
        ? colors.accent
        : colors.surface;
    final badgeBorder = widget.isCompleted
        ? colors.success
        : widget.isCurrent
        ? colors.accent
        : colors.border;

    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: canTap ? (_) => setState(() => _hovered = true) : null,
      onExit: canTap ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: transitionDuration,
          curve: AppTheme.entranceCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: transitionDuration,
                curve: AppTheme.entranceCurve,
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: badgeBorder),
                ),
                child: AnimatedSwitcher(
                  duration: AppTheme.motionDuration(
                    context,
                    AppTheme.feedbackDuration,
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.72, end: 1.0).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: AppTheme.entranceCurve,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  child: widget.isCompleted
                      ? Icon(
                          Icons.check_rounded,
                          key: const ValueKey('done'),
                          size: 13,
                          color: colors.onAccent,
                        )
                      : Text(
                          '${widget.number}',
                          key: ValueKey('num-${widget.number}-${widget.isCurrent}'),
                          style: TextStyle(
                            color: widget.isCurrent
                                ? colors.onAccent
                                : colors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.isCurrent || widget.isCompleted
                                  ? colors.ink
                                  : colors.muted,
                              fontSize: 12.5,
                              fontWeight: widget.isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (canTap)
                          Text(
                            '修改',
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isCompleted
                            ? colors.success
                            : widget.isCurrent
                            ? colors.accent
                            : colors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 第 1 步实时学校名片预览：与工作台左侧学校名片同构，输入校名时实时反馈首字徽章与学校名称。
class _SchoolIdentityPreviewCard extends StatelessWidget {
  const _SchoolIdentityPreviewCard({
    required this.initial,
    required this.displayName,
    required this.hasCustomName,
    required this.termTitle,
  });

  final String initial;
  final String displayName;
  final bool hasCustomName;
  final String termTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final feedbackDuration = AppTheme.motionDuration(
      context,
      AppTheme.feedbackDuration,
    );
    return AnimatedContainer(
      duration: feedbackDuration,
      curve: AppTheme.entranceCurve,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: hasCustomName
            ? Color.alphaBlend(
                colors.accent.withValues(alpha: 0.04),
                colors.canvas,
              )
            : colors.canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasCustomName
              ? colors.accent.withValues(alpha: 0.28)
              : colors.border,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: feedbackDuration,
            curve: AppTheme.entranceCurve,
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hasCustomName ? colors.accent : colors.selection,
              borderRadius: BorderRadius.circular(11),
            ),
            child: AnimatedSwitcher(
              duration: feedbackDuration,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.78, end: 1.0).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: AppTheme.entranceCurve,
                    ),
                  ),
                  child: child,
                ),
              ),
              child: Text(
                initial,
                key: ValueKey<String>('$initial-$hasCustomName'),
                style: TextStyle(
                  color: hasCustomName ? colors.onAccent : colors.accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: feedbackDuration,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previousChildren, ?currentChild],
                  ),
                  child: Text(
                    displayName,
                    key: ValueKey<String>(displayName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasCustomName ? colors.ink : colors.inkSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$termTitle · 侧栏学校卡预览',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppBadge(
            label: hasCustomName ? '已填写' : '默认占位',
            fontSize: 11,
            foreground: hasCustomName ? colors.accent : colors.muted,
            background: hasCustomName ? colors.selection : colors.tableHeader,
          ),
        ],
      ),
    );
  }
}

class _QuickSuggestionPill extends StatefulWidget {
  const _QuickSuggestionPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_QuickSuggestionPill> createState() => _QuickSuggestionPillState();
}

class _QuickSuggestionPillState extends State<_QuickSuggestionPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.motionDuration(context, AppTheme.feedbackDuration),
          curve: AppTheme.entranceCurve,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? colors.selection
                : _hovered
                ? Color.alphaBlend(
                    colors.accent.withValues(alpha: 0.05),
                    colors.tableHeader,
                  )
                : colors.tableHeader,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isSelected
                  ? colors.accent.withValues(alpha: 0.45)
                  : _hovered
                  ? colors.controlBorder.withValues(alpha: 0.45)
                  : colors.border,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected ? colors.accent : colors.inkSecondary,
              fontSize: 12,
              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// 课表周期可视化选择卡：在保留 `AppRadioOption`（兼容语义与测试查找）的同时提供更清晰的卡片反馈与说明。
class _CycleOptionCard extends StatefulWidget {
  const _CycleOptionCard({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  final AcademicTermCycle value;
  final AcademicTermCycle groupValue;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<AcademicTermCycle> onChanged;

  @override
  State<_CycleOptionCard> createState() => _CycleOptionCardState();
}

class _CycleOptionCardState extends State<_CycleOptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = widget.value == widget.groupValue;
    final duration = AppTheme.motionDuration(
      context,
      AppTheme.feedbackDuration,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(widget.value),
        child: AnimatedContainer(
          duration: duration,
          curve: AppTheme.entranceCurve,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected
                ? colors.selection
                : _hovered
                ? Color.alphaBlend(
                    colors.accent.withValues(alpha: 0.04),
                    colors.tableHeader,
                  )
                : colors.tableHeader,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? colors.accent
                  : _hovered
                  ? colors.controlBorder.withValues(alpha: 0.5)
                  : colors.border,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppRadioOption<AcademicTermCycle>(
                      value: widget.value,
                      groupValue: widget.groupValue,
                      label: widget.title,
                      compact: true,
                      onChanged: widget.onChanged,
                    ),
                  ),
                  Icon(
                    widget.icon,
                    size: 15,
                    color: selected ? colors.accent : colors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: TextStyle(
                  color: selected ? colors.inkSecondary : colors.muted,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 第 2 步底部教学周历实时预览条：根据选择的起始日、总周数和周期模式实时计算学期范围。
class _TermRangePreviewBar extends StatelessWidget {
  const _TermRangePreviewBar({
    required this.startDate,
    required this.weekCount,
    required this.cycleMode,
  });

  final DateTime? startDate;
  final int weekCount;
  final AcademicTermCycle cycleMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final feedbackDuration = AppTheme.motionDuration(
      context,
      AppTheme.feedbackDuration,
    );
    final hasDate = startDate != null;
    final endDate = hasDate
        ? DateTime(
            startDate!.year,
            startDate!.month,
            startDate!.day,
          ).add(Duration(days: weekCount * 7 - 1))
        : null;
    final cycleText = cycleMode == AcademicTermCycle.alternating
        ? '单双周交替（第 1 周为单周）'
        : '每周使用同一套课表';

    return AnimatedContainer(
      duration: feedbackDuration,
      curve: AppTheme.entranceCurve,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: hasDate ? colors.selection : colors.tableHeader,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasDate
              ? colors.accent.withValues(alpha: 0.25)
              : colors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hasDate ? colors.surface : colors.canvas,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              hasDate
                  ? Icons.calendar_month_rounded
                  : Icons.event_note_outlined,
              size: 17,
              color: hasDate ? colors.accent : colors.muted,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: feedbackDuration,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previousChildren, ?currentChild],
                  ),
                  child: Text(
                    hasDate
                        ? '${formatDateYmd(startDate!)} 至 ${formatDateYmd(endDate!)}'
                        : '选择第 1 教学周起始日后自动推算学期范围',
                    key: ValueKey<String>('${startDate?.toIso8601String()}-$weekCount'),
                    style: TextStyle(
                      color: hasDate ? colors.ink : colors.inkSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '共 $weekCount 个教学周 · $cycleText · 默认创建 1 个学段',
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
