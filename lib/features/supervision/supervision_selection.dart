part of 'supervision_page.dart';

/// Mouse marquee selection uses content coordinates so scrolling does not lose
/// the selection anchor. Different appearances of a merged post share its ID.
class _DutySelectionRegion extends StatefulWidget {
  const _DutySelectionRegion({
    required this.enabled,
    required this.selectedIds,
    required this.onChanged,
    required this.onFinished,
    required this.builder,
    super.key,
  });

  final bool enabled;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;
  final VoidCallback onFinished;
  final Widget Function(BuildContext, _DutySelectionRegionState) builder;

  @override
  State<_DutySelectionRegion> createState() => _DutySelectionRegionState();
}

class _DutySelectionRegionState extends State<_DutySelectionRegion> {
  final vertical = ScrollController();
  final horizontal = ScrollController();
  final _focus = FocusNode(debugLabel: '带班岗位框选');
  final _surface = GlobalKey();
  final _targets = <String, ({String id, GlobalKey key})>{};
  final _contentRects = <String, ({String id, Rect rect})>{};
  Timer? _scrollTimer;
  Offset? _anchor;
  Offset? _pointer;
  Set<String> _baseline = {};
  Set<String> _liveSelection = {};
  bool _dragging = false;
  bool _refreshPending = false;

  bool get selectionMode =>
      widget.enabled && (_dragging || widget.selectedIds.isNotEmpty);
  bool isSelected(String id) =>
      widget.enabled &&
      (_dragging ? _liveSelection : widget.selectedIds).contains(id);

  @override
  void initState() {
    super.initState();
    vertical.addListener(_onScroll);
    horizontal.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _DutySelectionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _scrollTimer?.cancel();
      _dragging = false;
      _anchor = null;
      _pointer = null;
    }
  }

  @override
  void dispose() {
    _dragging = false;
    _scrollTimer?.cancel();
    vertical.dispose();
    horizontal.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget item(String id, {String? instance, required Widget child}) {
    final target = _targets.putIfAbsent(
      '${instance ?? 'week'}|$id',
      () => (id: id, key: GlobalKey()),
    );
    return KeyedSubtree(
      key: target.key,
      child: KeyedSubtree(
        key: ValueKey('duty-post-$id${instance == null ? '' : '|$instance'}'),
        child: child,
      ),
    );
  }

  void toggle(String id) {
    if (!mounted || !widget.enabled) return;
    final next = {...widget.selectedIds};
    next.contains(id) ? next.remove(id) : next.add(id);
    widget.onChanged(next);
    widget.onFinished();
  }

  RenderBox? get _box {
    final object = _surface.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  double _offset(ScrollController controller) =>
      controller.positions.length == 1 ? controller.offset : 0;
  Offset get _scrollOffset => Offset(_offset(horizontal), _offset(vertical));

  Offset _clampPointer(Offset pointer, Size size) => Offset(
    pointer.dx.clamp(0, size.width).toDouble(),
    pointer.dy.clamp(0, size.height).toDouble(),
  );

  void _start(DragStartDetails details) {
    if (!mounted || !widget.enabled || _box == null) return;
    _focus.requestFocus();
    _contentRects.clear();
    final additive =
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    _baseline = additive ? {...widget.selectedIds} : {};
    _pointer = details.localPosition;
    _anchor = _clampPointer(details.localPosition, _box!.size) + _scrollOffset;
    _dragging = true;
    _liveSelection = {..._baseline};
    setState(_refreshSelection);
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScroll(),
    );
  }

  void _update(DragUpdateDetails details) {
    if (!mounted || !_dragging) return;
    _pointer = details.localPosition;
    setState(_refreshSelection);
  }

  void _finish() {
    if (!mounted || !_dragging) return;
    _scrollTimer?.cancel();
    setState(() {
      _refreshSelection();
      _dragging = false;
      _anchor = null;
      _pointer = null;
    });
    widget.onFinished();
  }

  void _clear() {
    if (!mounted) return;
    _scrollTimer?.cancel();
    setState(() {
      _dragging = false;
      _anchor = null;
      _pointer = null;
      _liveSelection = {};
    });
    widget.onChanged({});
    widget.onFinished();
  }

  void _refreshSelection() {
    final box = _box;
    if (!_dragging || box == null || _anchor == null || _pointer == null) {
      return;
    }
    final offset = _scrollOffset;
    for (final entry in _targets.entries) {
      final object = entry.value.key.currentContext?.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) continue;
      final topLeft =
          box.globalToLocal(object.localToGlobal(Offset.zero)) + offset;
      _contentRects[entry.key] = (
        id: entry.value.id,
        rect: topLeft & object.size,
      );
    }
    final rect = Rect.fromPoints(
      _anchor!,
      _clampPointer(_pointer!, box.size) + offset,
    );
    final next = {
      ..._baseline,
      for (final target in _contentRects.values)
        if (target.rect.overlaps(rect)) target.id,
    };
    if (!setEquals(next, _liveSelection) ||
        !setEquals(next, widget.selectedIds)) {
      _liveSelection = next;
      widget.onChanged(next);
    }
  }

  void _onScroll() {
    if (!_dragging || _refreshPending) return;
    _refreshPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPending = false;
      if (mounted && _dragging) setState(_refreshSelection);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _scrollNearEdge(
    ScrollController controller,
    double pointer,
    double extent,
  ) {
    if (controller.positions.length != 1) return false;
    const edge = 40.0;
    final velocity = pointer < edge
        ? -((edge - pointer) / edge).clamp(0, 1) * 18
        : pointer > extent - edge
        ? ((pointer - extent + edge) / edge).clamp(0, 1) * 18
        : 0.0;
    final position = controller.position;
    final next = (position.pixels + velocity)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next == position.pixels) return false;
    controller.jumpTo(next);
    return true;
  }

  void _autoScroll() {
    final box = _box;
    if (!_dragging || box == null || _pointer == null) return;
    _scrollNearEdge(vertical, _pointer!.dy, box.size.height);
    _scrollNearEdge(horizontal, _pointer!.dx, box.size.width);
  }

  @override
  Widget build(BuildContext context) {
    Rect? marquee;
    final box = _box;
    if (_dragging && box != null && _anchor != null && _pointer != null) {
      marquee = Rect.fromPoints(
        _anchor! - _scrollOffset,
        _clampPointer(_pointer!, box.size),
      ).intersect(Offset.zero & box.size);
    }
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            selectionMode) {
          _clear();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        key: const ValueKey('duty-selection-region'),
        supportedDevices: const {PointerDeviceKind.mouse},
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: widget.enabled ? _start : null,
        onPanUpdate: widget.enabled ? _update : null,
        onPanEnd: widget.enabled ? (_) => _finish() : null,
        onPanCancel: widget.enabled
            ? () {
                if (_dragging) _clear();
              }
            : null,
        child: Stack(
          key: _surface,
          fit: StackFit.expand,
          children: [
            widget.builder(context, this),
            if (marquee != null && !marquee.isEmpty)
              Positioned.fromRect(
                rect: marquee,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.appColors.blue.withValues(alpha: 0.10),
                      border: Border.all(color: context.appColors.blue),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
