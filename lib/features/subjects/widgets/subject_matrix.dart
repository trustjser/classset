import 'dart:async';

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        HardwareKeyboard,
        KeyDownEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey;
import 'package:forui/forui.dart' as f;

/// 科目节数矩阵：行 = 科目，列 = 年级，末列 = 科目预设。
///
/// 视觉遵循 design/DESIGN.md：不用灰底色带与连续边框表格，
/// 以留白、细线和 hover 浅底组织层级。
class SubjectMatrix extends StatefulWidget {
  const SubjectMatrix({
    required this.subjects,
    required this.visibleGrades,
    required this.classesByGrade,
    required this.valuesFor,
    required this.summaries,
    required this.presetSummaries,
    required this.onCellTap,
    required this.onPresetTap,
    required this.visibleStages,
    required this.accentForStage,
    required this.onCellCommit,
    required this.onEditRequest,
    required this.onMessage,
    this.scrollable = true,
    super.key,
  });

  final List<Subject> subjects;
  final List<GradeGroup> visibleGrades;

  /// 年级 ID → 班级列表。
  final Map<String, List<ClassBrief>> classesByGrade;

  /// （科目 ID, 班级 ID）→ 三档节数（草稿值）。
  final ClassSubjectValues Function(String subjectId, String classId) valuesFor;

  /// 年级 ID → 容量概要。
  final Map<String, GradeCapacitySummary> summaries;

  /// 科目 ID → 预设摘要（null = 无预设）。
  final Map<String, String?> presetSummaries;

  final void Function(Subject subject, GradeGroup grade) onCellTap;

  /// 点击「科目预设」列（传入矩阵当前列年级）。
  final void Function(Subject subject, GradeGroup grade) onPresetTap;

  /// 当前可见年级涉及的学段（顺序与页面一致，用于分组行与配色）。
  final List<SchoolStage> visibleStages;

  /// 学段强调色（按全局学段序号取色，由页面注入）。
  final Color Function(SchoolStage stage) accentForStage;

  /// 内联编辑提交：values 单组 = 整年级生效，多组按班级顺序。
  final void Function(
    Subject subject,
    GradeGroup grade,
    List<ClassBrief> classes,
    List<ClassSubjectValues> values,
  )
  onCellCommit;

  /// 右键菜单「编辑」：打开该年级的设置表单。
  final void Function(Subject subject, GradeGroup grade) onEditRequest;

  /// 轻提示（复制 / 粘贴 / 格式错误）。
  final void Function(String message) onMessage;

  /// true（宽屏）：科目行在受限高度内内部滚动；false（窄屏整页滚动时）：
  /// 行自然铺开、不内部滚动，交给外层单一滚动容器。
  final bool scrollable;

  static const double _nameColumnWidth = 104;
  static const double _gradeColumnWidth = 92;
  static const double _presetColumnWidth = 104;

  @override
  State<SubjectMatrix> createState() => _SubjectMatrixState();
}

class _SubjectMatrixState extends State<SubjectMatrix> {
  /// 表头 / 各科目行 / 页脚 共用的横向滚动联动组：任一处滚动，
  /// 其余同步，保证列对齐。
  final Map<String, ScrollController> _horizontalControllers = {};
  bool _syncing = false;

  /// 当前选中 / 内联编辑中的单元格（'subjectId|gradeId'）。
  String? _selectedCell;
  String? _editingCell;
  TextEditingController? _editController;
  FocusNode? _editFocus;

  /// 选中单元格的键盘焦点节点：方向键切换、Ctrl/Cmd+C/V 复制粘贴。
  final FocusNode cellFocusNode = FocusNode(debugLabel: 'matrix-cell');

  /// 剪贴板预读缓存（选中或右键时刷新），用于决定「粘贴」是否可用。
  String? _clipboardText;
  bool _readingClipboard = false;

  String _cellKey(String subjectId, String gradeId) => '$subjectId|$gradeId';

  bool isSelected(Subject subject, GradeGroup grade) =>
      _selectedCell == _cellKey(subject.id, grade.id);

  bool isEditing(Subject subject, GradeGroup grade) =>
      _editingCell == _cellKey(subject.id, grade.id);

  bool get clipboardHasValidInput =>
      _clipboardText != null &&
      _clipboardText!.trim().isNotEmpty &&
      parseLessonInput(_clipboardText!) != null;

  Future<void> prefetchClipboard() async {
    if (_readingClipboard) return;
    _readingClipboard = true;
    final text = (await Clipboard.getData('text/plain'))?.text ?? '';
    _readingClipboard = false;
    if (mounted) setState(() => _clipboardText = text);
  }

  /// 单击：选中单元格（无弹窗）。
  void selectCell(Subject subject, GradeGroup grade) {
    _cancelEdit();
    setState(() => _selectedCell = _cellKey(subject.id, grade.id));
    _focusSelectedCell();
    unawaited(prefetchClipboard());
  }

  /// 键盘方向键移动选中：上下换科目行、左右换年级列。
  void moveSelection(
    Subject subject,
    GradeGroup grade,
    int dSubject,
    int dGrade,
  ) {
    final subjectIndex = widget.subjects.indexOf(subject);
    final gradeIndex = widget.visibleGrades.indexOf(grade);
    final newSubjectIndex = (subjectIndex + dSubject).clamp(
      0,
      widget.subjects.length - 1,
    );
    final newGradeIndex = (gradeIndex + dGrade).clamp(
      0,
      widget.visibleGrades.length - 1,
    );
    if (newSubjectIndex == subjectIndex && newGradeIndex == gradeIndex) return;
    if (newSubjectIndex == subjectIndex && newGradeIndex == gradeIndex) return;
    _cancelEdit();
    setState(() {
      _selectedCell = _cellKey(
        widget.subjects[newSubjectIndex].id,
        widget.visibleGrades[newGradeIndex].id,
      );
    });
    _focusSelectedCell(ensureVisible: true);
    unawaited(prefetchClipboard());
  }

  /// 焦点跟随选中格：键盘/点击移动选中后，rebuild 会把共享焦点节点从
  /// 旧格 detach（primary 短暂回落到 scope），故 postFrame 二次确保焦点
  /// 挂回新选中格；键盘移动时再把格子滚入可视区。
  void _focusSelectedCell({bool ensureVisible = false}) {
    cellFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 编辑态由输入框持有焦点，回调不得抢回。
      if (!mounted || _editingCell != null) return;
      cellFocusNode.requestFocus();
      final context = cellFocusNode.context;
      if (ensureVisible && context != null) {
        Scrollable.ensureVisible(context, alignment: 0.3);
      }
    });
  }

  /// 双击：进入内联编辑，预填整格格式化文本。
  void startEdit(Subject subject, GradeGroup grade, List<ClassBrief> classes) {
    final text = formatLessonInput(
      classes.map((classBrief) => widget.valuesFor(subject.id, classBrief.id)),
    );
    _editController?.dispose();
    _editFocus?.dispose();
    _editController = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    _editFocus = FocusNode();
    setState(() {
      _selectedCell = _cellKey(subject.id, grade.id);
      _editingCell = _cellKey(subject.id, grade.id);
    });
    // autofocus 在路由 scope 已有聚焦子节点（选中格）时是空操作，
    // 须等编辑框挂载后显式 requestFocus 抢回。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingCell != null) _editFocus?.requestFocus();
    });
    unawaited(prefetchClipboard());
  }

  void _cancelEdit() {
    _editController?.dispose();
    _editController = null;
    _editFocus?.dispose();
    _editFocus = null;
    if (_editingCell != null && mounted) {
      setState(() => _editingCell = null);
      // 编辑框卸载后焦点回落到路由 scope，下一帧拉回选中格。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cellFocusNode.requestFocus();
      });
    }
  }

  /// 提交内联编辑：合法则交页面写入草稿，否则提示格式。
  void commitEdit(Subject subject, GradeGroup grade, List<ClassBrief> classes) {
    final text = _editController?.text ?? '';
    _editController = null;
    _editFocus = null;
    setState(() => _editingCell = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cellFocusNode.requestFocus();
    });
    final parsed = parseLessonInput(text);
    if (parsed == null) {
      widget.onMessage('节数格式不正确：单班用 3 或 3|1|1，多班用半角逗号分隔');
      return;
    }
    widget.onCellCommit(subject, grade, classes, parsed);
  }

  void copyCell(Subject subject, GradeGroup grade, List<ClassBrief> classes) {
    final text = formatLessonInput(
      classes.map((classBrief) => widget.valuesFor(subject.id, classBrief.id)),
    );
    _clipboardText = text;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    widget.onMessage('已复制节数：$text');
  }

  Future<void> pasteCell(
    Subject subject,
    GradeGroup grade,
    List<ClassBrief> classes,
  ) async {
    final text =
        _clipboardText ?? (await Clipboard.getData('text/plain'))?.text ?? '';
    final parsed = parseLessonInput(text);
    if (parsed == null || parsed.isEmpty) {
      widget.onMessage('剪贴板没有合法的节数内容');
      return;
    }
    widget.onCellCommit(subject, grade, classes, parsed);
  }

  ScrollController _horizontal(String key) =>
      _horizontalControllers.putIfAbsent(key, () {
        final controller = ScrollController();
        controller.addListener(() => _syncFrom(controller));
        return controller;
      });

  void _syncFrom(ScrollController source) {
    if (_syncing) return;
    _syncing = true;
    for (final controller in _horizontalControllers.values) {
      if (controller == source || !controller.hasClients) continue;
      final target = source.offset.clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      if (controller.offset != target) controller.jumpTo(target);
    }
    _syncing = false;
  }

  /// 横向滚动容器：隐藏每行的横向滚动条（联动后一条就够），滚动体验交给
  /// 触控板 / 滚轮。
  Widget _horizontalScrollArea({required String key, required Widget child}) =>
      ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _horizontal(key),
          child: child,
        ),
      );

  @override
  void dispose() {
    _editController?.dispose();
    _editFocus?.dispose();
    cellFocusNode.dispose();
    for (final controller in _horizontalControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MatrixHeaderRow(
              visibleGrades: widget.visibleGrades,
              visibleStages: widget.visibleStages,
              accentForStage: widget.accentForStage,
              horizontal: _horizontalScrollArea,
            ),
            const Divider(height: 1, color: AppTheme.border),
            if (widget.scrollable)
              Expanded(
                child: ListView.builder(
                  itemCount: widget.subjects.length,
                  itemBuilder: (context, index) => _SubjectRow(
                    subject: widget.subjects[index],
                    visibleGrades: widget.visibleGrades,
                    classesByGrade: widget.classesByGrade,
                    valuesFor: widget.valuesFor,
                    presetSummary:
                        widget.presetSummaries[widget.subjects[index].id],
                    onCellTap: widget.onCellTap,
                    onPresetTap: widget.onPresetTap,
                    horizontal: _horizontalScrollArea,
                    state: this,
                  ),
                ),
              )
            else if (widget.subjects.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final subject in widget.subjects)
                    _SubjectRow(
                      subject: subject,
                      visibleGrades: widget.visibleGrades,
                      classesByGrade: widget.classesByGrade,
                      valuesFor: widget.valuesFor,
                      presetSummary: widget.presetSummaries[subject.id],
                      onCellTap: widget.onCellTap,
                      onPresetTap: widget.onPresetTap,
                      horizontal: _horizontalScrollArea,
                      state: this,
                    ),
                ],
              ),
            // 「班级周课时」固定在表格底部，不随行滚动。
            _CapacityFooterRow(
              visibleGrades: widget.visibleGrades,
              summaries: widget.summaries,
              horizontal: _horizontalScrollArea,
            ),
          ],
        ),
      ),
    );
  }
}

/// 横向滚动区构建器：由矩阵状态提供联动 controller 并隐藏横向滚动条。
typedef HorizontalScrollAreaBuilder = Widget Function({
  required String key,
  required Widget child,
});

class _MatrixHeaderRow extends StatelessWidget {
  const _MatrixHeaderRow({
    required this.visibleGrades,
    required this.visibleStages,
    required this.accentForStage,
    required this.horizontal,
  });

  final List<GradeGroup> visibleGrades;
  final List<SchoolStage> visibleStages;

  /// 学段强调色（按全局学段序号取色，由页面注入）。
  final Color Function(SchoolStage stage) accentForStage;
  final HorizontalScrollAreaBuilder horizontal;

  @override
  Widget build(BuildContext context) {
    final accentByGrade = <String, Color>{
      for (final grade in visibleGrades)
        grade.id: accentForStage(
          visibleStages.firstWhere((stage) => stage.id == grade.stageId),
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: SubjectMatrix._nameColumnWidth,
            child: Padding(
              padding: EdgeInsets.only(left: 14),
              child: Text(
                '科目',
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .2,
                ),
              ),
            ),
          ),
          Expanded(
            child: horizontal(
              key: 'header',
              child: Row(
                children: [
                  for (final grade in visibleGrades)
                    SizedBox(
                      width: SubjectMatrix._gradeColumnWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Text(
                          grade.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accentByGrade[grade.id] ?? AppTheme.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(
            width: SubjectMatrix._presetColumnWidth,
            child: Padding(
              padding: EdgeInsets.only(left: 14),
              child: Text(
                '科目预设',
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({
    required this.subject,
    required this.visibleGrades,
    required this.classesByGrade,
    required this.valuesFor,
    required this.presetSummary,
    required this.onCellTap,
    required this.onPresetTap,
    required this.horizontal,
    required this.state,
  });

  final Subject subject;
  final List<GradeGroup> visibleGrades;
  final Map<String, List<ClassBrief>> classesByGrade;
  final ClassSubjectValues Function(String subjectId, String classId) valuesFor;

  /// 预设摘要（null = 无预设）。
  final String? presetSummary;
  final void Function(Subject subject, GradeGroup grade) onCellTap;
  final void Function(Subject subject, GradeGroup grade) onPresetTap;
  final HorizontalScrollAreaBuilder horizontal;
  final _SubjectMatrixState state;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: SubjectMatrix._nameColumnWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              subject.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Expanded(
          child: horizontal(
            key: 'subject-${subject.id}',
            child: Row(
              children: [
                for (final grade in visibleGrades) ...[
                  _MatrixCell(
                    subject: subject,
                    grade: grade,
                    classes: classesByGrade[grade.id] ?? const [],
                    valuesFor: valuesFor,
                    state: state,
                  ),
                ],
              ],
            ),
          ),
        ),
        // 科目预设列固定在右侧，不随横向滚动。
        SizedBox(
          width: SubjectMatrix._presetColumnWidth,
          height: 40,
          child: _PresetCell(
            key: ValueKey('preset-summary-${subject.id}'),
            subjectId: subject.id,
            summary: presetSummary,
            onTap: visibleGrades.isEmpty
                ? null
                : () => onPresetTap(subject, visibleGrades.first),
          ),
        ),
      ],
    ),
  );
}

/// 「科目预设」列：有预设显示摘要 chip，无预设显示「—」。
class _PresetCell extends StatelessWidget {
  const _PresetCell({
    required this.subjectId,
    required this.summary,
    required this.onTap,
    super.key,
  });

  final String subjectId;
  final String? summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = summary == null
        ? const Text('—', style: TextStyle(color: AppTheme.muted, fontSize: 12))
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.selectedBlue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              summary!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.blue,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(alignment: Alignment.centerLeft, child: content),
      ),
    );
  }
}

class _MatrixCell extends StatefulWidget {
  const _MatrixCell({
    required this.subject,
    required this.grade,
    required this.classes,
    required this.valuesFor,
    required this.state,
  });

  final Subject subject;
  final GradeGroup grade;
  final List<ClassBrief> classes;
  final ClassSubjectValues Function(String subjectId, String classId) valuesFor;
  final _SubjectMatrixState state;

  @override
  State<_MatrixCell> createState() => _MatrixCellState();
}

class _MatrixCellState extends State<_MatrixCell> {
  bool _hovering = false;

  /// 整格可编辑文本（各班一致 → 单组；否则逗号分隔）。
  String get _gradeText => formatLessonInput(
    widget.classes.map(
      (classBrief) => widget.valuesFor(widget.subject.id, classBrief.id),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final selected = state.isSelected(widget.subject, widget.grade);
    final editing = state.isEditing(widget.subject, widget.grade);
    // 不用 InkWell：其墨水 hover 高亮在快速移出时会残留灰底；
    // 这里用 MouseRegion + AnimatedContainer 自绘 hover（浅蓝底）。
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        // 选中用原始指针按下即时触发：TapGestureRecognizer 的 accept
        // 会被双击识别窗口延迟 300ms，期间键盘导航会被到期回调拉回旧格。
        onPointerDown: (event) {
          if (event.buttons == kPrimaryButton && !editing) {
            state.selectCell(widget.subject, widget.grade);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () =>
              state.startEdit(widget.subject, widget.grade, widget.classes),
          onSecondaryTapDown: (_) => unawaited(state.prefetchClipboard()),
          child: f.FContextMenu(
            menuBuilder: (context, controller, menu) => [
              f.FItemGroup(
                divider: .none,
                children: [
                  AppMenuTile(
                    item: AppMenuItem(
                      label: '复制',
                      onPressed: () {
                        unawaited(controller.hide());
                        state.copyCell(
                          widget.subject,
                          widget.grade,
                          widget.classes,
                        );
                      },
                    ),
                  ),
                  AppMenuTile(
                    item: AppMenuItem(
                      label: '粘贴',
                      enabled: state.clipboardHasValidInput,
                      onPressed: () {
                        unawaited(controller.hide());
                        unawaited(
                          state.pasteCell(
                            widget.subject,
                            widget.grade,
                            widget.classes,
                          ),
                        );
                      },
                    ),
                  ),
                  AppMenuTile(
                    item: AppMenuItem(
                      label: '编辑',
                      onPressed: () {
                        unawaited(controller.hide());
                        widget.state.widget.onEditRequest(
                          widget.subject,
                          widget.grade,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
            child: Focus(
              focusNode: selected ? state.cellFocusNode : null,
              onKeyEvent: _handleCellKey,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                key: ValueKey(
                  'subject-cell-${widget.subject.id}-${widget.grade.id}',
                ),
                width: SubjectMatrix._gradeColumnWidth,
                height: 40,
                padding: const EdgeInsets.only(left: 13, right: 4),
                decoration: BoxDecoration(
                  color: selected || _hovering
                      ? AppTheme.selectedBlue
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected || editing
                        ? AppTheme.blue
                        : Colors.transparent,
                  ),
                ),
                alignment: Alignment.centerLeft,
                child: editing ? _buildEditor() : _cellContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 选中格上的键盘操作：方向键移动选中，Ctrl/Cmd+C/V 复制粘贴。
  KeyEventResult _handleCellKey(FocusNode node, KeyEvent event) {
    // ignore: avoid_print
    print(
      'KEYDBG ${event.runtimeType} ${event.logicalKey.keyLabel} ctrl=${HardwareKeyboard.instance.isControlPressed}',
    );
    final state = widget.state;
    if (state.isEditing(widget.subject, widget.grade)) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        state.moveSelection(widget.subject, widget.grade, -1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        state.moveSelection(widget.subject, widget.grade, 1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        state.moveSelection(widget.subject, widget.grade, 0, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        state.moveSelection(widget.subject, widget.grade, 0, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.select ||
          LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter:
        // 选中态回车进入内联编辑（自动聚焦并全选已有内容）。
        state.startEdit(widget.subject, widget.grade, widget.classes);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        // 清空：整格节数归零。
        widget.state.widget.onCellCommit(
          widget.subject,
          widget.grade,
          widget.classes,
          const [],
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyC:
        state.copyCell(widget.subject, widget.grade, widget.classes);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyV:
        unawaited(
          state.pasteCell(widget.subject, widget.grade, widget.classes),
        );
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 内联编辑：数字 / 3|1|1 / 逗号分隔多组；回车或点击外部提交，Esc 取消。
  Widget _buildEditor() {
    final state = widget.state;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          state._cancelEdit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: state._editController,
        focusNode: state._editFocus,
        autofocus: true,
        style: const TextStyle(color: AppTheme.ink, fontSize: 12.5),
        // 显式覆盖全局 inputDecorationTheme（白底 + 描边），编辑框须无框。
        decoration: const InputDecoration(
          isCollapsed: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: '3 或 3|1|1',
        ),
        onSubmitted: (_) =>
            state.commitEdit(widget.subject, widget.grade, widget.classes),
        onTapOutside: (_) =>
            state.commitEdit(widget.subject, widget.grade, widget.classes),
      ),
    );
  }

  /// 展示：空或全零 → 「—」；各班不一致 → 「各班不同」徽标；否则格式化文本。
  Widget _cellContent() {
    final text = _gradeText;
    if (text.isEmpty || text == '0') {
      return const Text(
        '—',
        style: TextStyle(color: AppTheme.muted, fontSize: 12),
      );
    }
    if (text.contains(',')) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.selectedBlue,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '各班不同',
          style: TextStyle(
            color: AppTheme.blue,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return Text(
      text,
      style: const TextStyle(color: AppTheme.ink, fontSize: 13),
    );
  }
}

class _CapacityFooterRow extends StatelessWidget {
  const _CapacityFooterRow({
    required this.visibleGrades,
    required this.summaries,
    required this.horizontal,
  });

  final List<GradeGroup> visibleGrades;
  final Map<String, GradeCapacitySummary> summaries;
  final HorizontalScrollAreaBuilder horizontal;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppTheme.border)),
    ),
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        const SizedBox(
          width: SubjectMatrix._nameColumnWidth,
          child: Padding(
            padding: EdgeInsets.only(left: 14),
            child: Text(
              '班级周课时',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Expanded(
          child: horizontal(
            key: 'footer',
            child: Row(
              children: [
                for (final grade in visibleGrades) ...[
                  _FooterCell(summary: summaries[grade.id]),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: SubjectMatrix._presetColumnWidth),
      ],
    ),
  );
}

class _FooterCell extends StatelessWidget {
  const _FooterCell({required this.summary});

  final GradeCapacitySummary? summary;

  @override
  Widget build(BuildContext context) {
    final text = summary == null
        ? '—'
        : summary!.oddDemand == summary!.evenDemand
        ? '${summary!.oddDemand} / ${summary!.oddCapacity}'
        : '单 ${summary!.oddDemand}/${summary!.oddCapacity}'
              ' · 双 ${summary!.evenDemand}/${summary!.evenCapacity}';
    const style = TextStyle(
      color: AppTheme.inkSecondary,
      fontSize: 11.5,
      fontWeight: FontWeight.w400,
    );
    return SizedBox(
      width: SubjectMatrix._gradeColumnWidth,
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 仅在单行放不下、被省略号截断时，悬浮展示完整内容。
            final textPainter = TextPainter(
              text: TextSpan(text: text, style: style),
              maxLines: 1,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);
            final truncated = textPainter.didExceedMaxLines;
            final color = (summary?.isOver ?? false)
                ? AppTheme.destructive
                : AppTheme.inkSecondary;
            final body = Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(
                color: color,
                fontWeight: (summary?.isOver ?? false)
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            );
            if (!truncated) return body;
            return Tooltip(message: text, child: body);
          },
        ),
      ),
    );
  }
}
