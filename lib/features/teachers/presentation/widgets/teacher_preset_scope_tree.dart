part of '../teachers_page.dart';

class TeacherPresetScopeNode {
  const TeacherPresetScopeNode({
    required this.id,
    required this.label,
    this.children = const [],
  });

  final String id;
  final String label;
  final List<TeacherPresetScopeNode> children;
}

class TeacherPresetScopeTree extends StatefulWidget {
  const TeacherPresetScopeTree({
    required this.nodes,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final List<TeacherPresetScopeNode> nodes;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  State<TeacherPresetScopeTree> createState() => _TeacherPresetScopeTreeState();
}

class _TeacherPresetScopeTreeState extends State<TeacherPresetScopeTree> {
  late final Set<String> _expandedIds = _expandedPath(
    widget.nodes,
    widget.selectedId,
  );

  @override
  void didUpdateWidget(covariant TeacherPresetScopeTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.nodes != widget.nodes) {
      _expandedIds.addAll(_expandedPath(widget.nodes, widget.selectedId));
    }
  }

  Set<String> _expandedPath(
    List<TeacherPresetScopeNode> nodes,
    String selectedId,
  ) {
    final expanded = <String>{};
    bool visit(TeacherPresetScopeNode node) {
      if (node.id == selectedId) {
        if (node.children.isNotEmpty) expanded.add(node.id);
        return true;
      }
      for (final child in node.children) {
        if (visit(child)) {
          expanded.add(node.id);
          return true;
        }
      }
      return false;
    }

    for (final node in nodes) {
      visit(node);
    }
    return expanded;
  }

  List<({TeacherPresetScopeNode node, int depth})> _visibleNodes() {
    final visible = <({TeacherPresetScopeNode node, int depth})>[];
    void append(TeacherPresetScopeNode node, int depth) {
      visible.add((node: node, depth: depth));
      if (_expandedIds.contains(node.id)) {
        for (final child in node.children) {
          append(child, depth + 1);
        }
      }
    }

    for (final node in widget.nodes) {
      append(node, 0);
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleNodes();
    return AppSectionPanel(
      title: '应用范围',
      padding: const EdgeInsets.only(bottom: 8),
      expandChild: true,
      child: ListView.builder(
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final item = visible[index];
          final node = item.node;
          final expanded = _expandedIds.contains(node.id);
          return AppTreeTile(
            key: ValueKey('teacher-preset-scope-${node.id}'),
            height: item.depth == 0
                ? 30
                : item.depth == 1
                ? 28
                : 26,
            contentPadding: EdgeInsets.only(
              left: 8 + item.depth * 12,
              right: 8,
            ),
            isSelected: node.id == widget.selectedId,
            title: Text(
              node.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.ink,
                fontSize: item.depth == 0 ? 13 : 12,
              ),
            ),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  child: node.children.isEmpty
                      ? null
                      : FTappable(
                          key: ValueKey('scope-expand-${node.id}'),
                          semanticsLabel:
                              '${expanded ? '收起' : '展开'}${node.label}',
                          onPress: () => setState(() {
                            if (expanded) {
                              _expandedIds.remove(node.id);
                            } else {
                              _expandedIds.add(node.id);
                            }
                          }),
                          child: Icon(
                            expanded ? Icons.expand_more : Icons.chevron_right,
                            size: 14,
                            color: AppTheme.muted,
                          ),
                        ),
                ),
                const SizedBox(width: 2),
                Icon(
                  item.depth == 0
                      ? Icons.layers_outlined
                      : item.depth == 1
                      ? Icons.school_outlined
                      : Icons.class_outlined,
                  size: 15,
                  color: AppTheme.sidebarMuted,
                ),
              ],
            ),
            onTap: () => widget.onSelected(node.id),
          );
        },
      ),
    );
  }
}
