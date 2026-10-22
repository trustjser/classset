part of '../teachers_page.dart';

class _TeacherFormField extends StatelessWidget {
  const _TeacherFormField({
    required this.label,
    required this.child,
    this.isRequired = false,
    this.help,
  });

  final String label;
  final Widget child;
  final bool isRequired;
  final String? help;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isRequired) ...[
            const SizedBox(width: 4),
            const Text(
              '*',
              semanticsLabel: '必填',
              style: TextStyle(color: AppTheme.destructive, fontSize: 13),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      child,
      if (help != null) ...[
        const SizedBox(height: 6),
        Text(
          help!,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    ],
  );
}

class _TeacherSubjectPicker extends StatelessWidget {
  const _TeacherSubjectPicker({
    required this.subjects,
    required this.selected,
    required this.onChanged,
  });

  final List<Subject> subjects;
  final Set<String> selected;
  final void Function(String id, bool selected) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              '任课科目',
              style: TextStyle(
                color: AppTheme.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '已选 ${selected.length} 项',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 6),
      const Text(
        '可多选，用于任课提示，不限制分配。',
        style: TextStyle(color: AppTheme.muted, fontSize: 12),
      ),
      const SizedBox(height: 12),
      if (subjects.isEmpty)
        const Text(
          '请先添加科目',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 420 ? 3 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final subject in subjects)
                  Container(
                    width: width,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected.contains(subject.id)
                          ? AppTheme.selectedBlue
                          : Colors.white,
                      border: Border.all(
                        color: selected.contains(subject.id)
                            ? AppTheme.blue.withValues(alpha: 0.3)
                            : AppTheme.border,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: AppCheckbox(
                      label: Text(
                        subject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      value: selected.contains(subject.id),
                      onChanged: (value) => onChanged(subject.id, value),
                    ),
                  ),
              ],
            );
          },
        ),
    ],
  );
}
