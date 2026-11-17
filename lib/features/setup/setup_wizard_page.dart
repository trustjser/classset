import 'package:class_set/app.dart';
import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
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

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _schoolNameController;
  late final TextEditingController _termTitleController;
  int _step = 1;
  int _weekCount = 20;
  AcademicTermCycle _cycleMode = AcademicTermCycle.alternating;
  DateTime? _firstTeachingWeekStart;
  String? _dateValidationError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _schoolNameController = TextEditingController();
    final now = DateTime.now();
    final semesterLabel = now.month >= 7 ? '秋季学期' : '春季学期';
    _termTitleController = TextEditingController(
      text: '${now.year} 学年 · $semesterLabel',
    );
  }

  @override
  void dispose() {
    _schoolNameController.dispose();
    _termTitleController.dispose();
    super.dispose();
  }

  void _goToTermStep() {
    setState(() => _step = 2);
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
      teachingWeekCount: _weekCount,
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.fromLTRB(40, 34, 40, 32),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
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
                  ],
                ),
                const SizedBox(height: 24),
                _StepBadge(step: _step, totalSteps: _totalSteps),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: AppTheme.motionDuration(
                    context,
                    AppTheme.transitionDuration,
                  ),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _step == 1 ? _buildSchoolStep() : _buildTermStep(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolStep() {
    final colors = context.appColors;
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
          style: TextStyle(color: colors.muted, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),
        Text('学校名称', style: TextStyle(color: colors.ink, fontSize: 14)),
        const SizedBox(height: 8),
        AppTextFormField(
          key: const ValueKey('wizard-school-name'),
          controller: _schoolNameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如：青木实验小学'),
          onFieldSubmitted: (_) => _goToTermStep(),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
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
            style: TextStyle(color: colors.muted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          AppLabeledFieldRow(
            label: '学期名称',
            child: AppTextFormField(
              key: const ValueKey('wizard-term-title'),
              size: .sm,
              controller: _termTitleController,
              decoration: const InputDecoration(hintText: '如：2027 学年 · 春季学期'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入学期名称' : null,
            ),
          ),
          const SizedBox(height: 13),
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
          const SizedBox(height: 13),
          AppLabeledFieldRow(
            label: '总周数',
            child: AppNumberStepper(
              value: _weekCount,
              min: 1,
              max: 52,
              suffix: '周',
              onChanged: (value) => _weekCount = value,
            ),
          ),
          const SizedBox(height: 13),
          AppLabeledFieldRow(
            label: '课表周期',
            labelHelp: '单双周交替时第 1 教学周固定为单周；每周相同则所有周使用同一套周课表。',
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                AppRadioOption<AcademicTermCycle>(
                  value: AcademicTermCycle.everyWeek,
                  groupValue: _cycleMode,
                  label: '每周相同',
                  compact: true,
                  onChanged: (value) => setState(() => _cycleMode = value),
                ),
                AppRadioOption<AcademicTermCycle>(
                  value: AcademicTermCycle.alternating,
                  groupValue: _cycleMode,
                  label: '单双周交替',
                  compact: true,
                  onChanged: (value) => setState(() => _cycleMode = value),
                ),
              ],
            ),
          ),
          if (_dateValidationError != null) ...[
            const SizedBox(height: 12),
            Text(
              _dateValidationError!,
              style: TextStyle(color: colors.destructive, fontSize: 12),
            ),
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              AppSecondaryButton(
                onPressed: _saving ? null : () => setState(() => _step = 1),
                child: const Text('上一步'),
              ),
              const Spacer(),
              AppPrimaryButton(
                onPressed: _saving ? null : _finish,
                child: Text(_saving ? '正在创建…' : '完成设置，进入工作台'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 顶部步骤指示：文字 + 两段式进度条。
class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.step, required this.totalSteps});

  final int step;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '初始设置 · 第 $step 步 / 共 $totalSteps 步',
          style: TextStyle(
            color: colors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var index = 1; index <= totalSteps; index++) ...[
              if (index > 1) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: index <= step ? colors.accent : colors.tableHeader,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
