import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/features/public_rooms/public_rooms_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PublicRoomsPage extends ConsumerStatefulWidget {
  const PublicRoomsPage({this.termId, super.key});
  final String? termId;

  @override
  ConsumerState<PublicRoomsPage> createState() => _PublicRoomsPageState();
}

class _PublicRoomsPageState extends ConsumerState<PublicRoomsPage> {
  bool _busy = false;
  int _idSequence = 0;
  String _newId() =>
      'room_${DateTime.now().microsecondsSinceEpoch}_${_idSequence++}';

  void _notice(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save(List<PublicRoom> rooms, String message) async {
    setState(() => _busy = true);
    try {
      await ref.read(schoolRepositoryProvider).savePublicRooms(rooms);
      if (!mounted) return;
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      _notice(message);
    } catch (error) {
      if (mounted) _notice('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(List<PublicRoom> rooms, [PublicRoom? room]) async {
    final result = await showAppDialog<PublicRoom>(
      context: context,
      builder: (_) => _RoomEditor(room: room, rooms: rooms, newId: _newId),
    );
    if (result == null || !mounted) return;
    await _save([result], '场室已保存');
  }

  Future<void> _delete(PublicRoom room) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (_) => _DeleteRoomDialog(room: room),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(schoolRepositoryProvider).deletePublicRoom(room.id);
      if (!mounted) return;
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      _notice('场室已删除');
    } catch (error) {
      if (mounted) _notice('删除失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<({String label, String tooltip})> _roomAssociations(
    String roomId,
    PublicRoomTermData? data,
  ) {
    if (data == null) return const [];
    final grouped = <String, List<SubjectRoomAssignment>>{};
    for (final row in data.assignments.where((row) => row.roomId == roomId)) {
      grouped.putIfAbsent(row.subjectId, () => []).add(row);
    }
    final labels = <({String label, String tooltip})>[];
    for (final entry in grouped.entries) {
      final subject = data.subjects
          .where((item) => item.id == entry.key)
          .firstOrNull;
      final stageNames = entry.value
          .map(
            (row) =>
                data.stages
                    .where((stage) => stage.id == row.stageId)
                    .firstOrNull
                    ?.name ??
                '已移除学段',
          )
          .toSet()
          .toList();
      final scopeNames = entry.value
          .map((row) => _roomScopeLabel(row, data))
          .whereType<String>()
          .toSet()
          .toList();
      final suffix = stageNames.length > 1
          ? '（${stageNames.join('+')}）'
          : scopeNames.isEmpty
          ? ''
          : '（${scopeNames.join('、')}）';
      labels.add((
        label: '${subject?.name ?? '已移除科目'}$suffix',
        tooltip: entry.value.map(data.bindingLabel).toSet().join('\n'),
      ));
    }
    return labels;
  }

  String? _roomScopeLabel(SubjectRoomAssignment row, PublicRoomTermData data) =>
      switch (row.scope) {
        FreeSlotScope.stage || FreeSlotScope.school => null,
        FreeSlotScope.grade =>
          data.grades
              .where((grade) => grade.id == row.scopeId)
              .firstOrNull
              ?.name,
        FreeSlotScope.schoolClass =>
          data.classes
              .where((schoolClass) => schoolClass.id == row.scopeId)
              .firstOrNull
              ?.name,
      };

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(publicRoomsProvider);
    final termId = widget.termId ?? ref.watch(activeTermIdProvider);
    final termData = termId == null
        ? null
        : ref.watch(publicRoomTermDataProvider(termId));
    return Material(
      color: context.appColors.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final padding = AppTheme.pagePaddingForWidth(constraints.maxWidth);
          const header = AppPageHeader(
            title: '公共场室',
            subtitle: '维护全校共用的行课场室，容量单位为班。',
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: AppTheme.pageInsetsForWidth(constraints.maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    if (termId == null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '选择学期后显示关联科目',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.muted,
                        ),
                      ),
                    ],
                    if (termData?.hasError == true)
                      Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          '当前学期科目关联读取失败，请稍后重试。',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.appColors.destructive,
                          ),
                        ),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
              Expanded(
                child: rooms.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('读取场室失败：$error')),
                  data: (items) => SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(padding, 4, padding, padding),
                    child: compact
                        ? _buildCompactRoomList(items, termData)
                        : _buildRoomTable(
                            items,
                            termData,
                            constraints.maxWidth - padding * 2,
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRoomTable(
    List<PublicRoom> rooms,
    AsyncValue<PublicRoomTermData>? termData,
    double availableWidth,
  ) {
    final tableWidth = availableWidth < 1000 ? 1000.0 : availableWidth;

    Widget cell(
      int flex,
      Widget child, {
      Alignment alignment = Alignment.centerLeft,
    }) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Align(alignment: alignment, child: child),
      ),
    );

    Widget headerCell(
      int flex,
      String label, {
      Alignment alignment = Alignment.centerLeft,
    }) => cell(
      flex,
      Text(
        label,
        style: TextStyle(
          color: context.appColors.inkSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      alignment: alignment,
    );

    final children = <Widget>[
      Container(
        color: context.appColors.tableHeader,
        child: Row(
          children: [
            headerCell(26, '场室'),
            headerCell(9, '个数', alignment: Alignment.center),
            headerCell(15, '容量（班）', alignment: Alignment.center),
            headerCell(22, '同时段上限（个班）', alignment: Alignment.center),
            headerCell(23, '关联科目'),
            headerCell(12, '操作', alignment: Alignment.center),
          ],
        ),
      ),
      if (rooms.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Center(
            child: Text(
              '暂无公共场室，添加后即可为科目设置行课场室。',
              style: TextStyle(fontSize: 13, color: context.appColors.muted),
            ),
          ),
        )
      else
        for (final room in rooms) ...[
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.appColors.tableDivider),
              ),
            ),
            child: Row(
              children: [
                cell(
                  26,
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        room.name,
                        style: TextStyle(
                          color: context.appColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (termData?.valueOrNull?.isSharedAcrossStages(
                            room.id,
                          ) ==
                          true)
                        _roomTag('跨学段共用'),
                    ],
                  ),
                ),
                cell(
                  9,
                  Text('${room.roomCount}', textAlign: TextAlign.center),
                  alignment: Alignment.center,
                ),
                cell(
                  15,
                  Text(
                    '${room.capacityPerRoom} 班',
                    textAlign: TextAlign.center,
                  ),
                  alignment: Alignment.center,
                ),
                cell(
                  22,
                  Text(
                    '${room.roomCount} × ${room.capacityPerRoom} = ${room.roomCount * room.capacityPerRoom} 班',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.appColors.inkSecondary),
                  ),
                  alignment: Alignment.center,
                ),
                cell(23, _buildRoomAssociationCell(room, termData)),
                cell(
                  12,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _roomAction(
                        key: ValueKey('edit-room-${room.id}'),
                        label: '编辑',
                        onPressed: _busy ? null : () => _edit(rooms, room),
                      ),
                      _roomAction(
                        key: ValueKey('delete-room-${room.id}'),
                        label: '删除',
                        destructive: true,
                        onPressed: _busy ? null : () => _delete(room),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                ),
              ],
            ),
          ),
        ],
      _buildAddRoomAction(rooms, compact: false),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: AppSurface(child: Column(children: children)),
      ),
    );
  }

  Widget _buildCompactRoomList(
    List<PublicRoom> rooms,
    AsyncValue<PublicRoomTermData>? termData,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (rooms.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              '暂无公共场室，添加后即可为科目设置行课场室。',
              style: TextStyle(fontSize: 13, color: context.appColors.muted),
            ),
          ),
        )
      else
        for (final room in rooms) ...[
          AppSurface(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              room.name,
                              style: TextStyle(
                                color: context.appColors.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (termData?.valueOrNull?.isSharedAcrossStages(
                                  room.id,
                                ) ==
                                true)
                              _roomTag('跨学段共用'),
                          ],
                        ),
                      ),
                      _roomAction(
                        key: ValueKey('edit-room-${room.id}'),
                        label: '编辑',
                        onPressed: _busy ? null : () => _edit(rooms, room),
                      ),
                      _roomAction(
                        key: ValueKey('delete-room-${room.id}'),
                        label: '删除',
                        destructive: true,
                        onPressed: _busy ? null : () => _delete(room),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _roomMetric('个数', '${room.roomCount}'),
                      _roomMetric('每间容量', '${room.capacityPerRoom} 班'),
                      _roomMetric(
                        '同时段上限',
                        '${room.roomCount * room.capacityPerRoom} 班',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildRoomAssociationCell(room, termData),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      _buildAddRoomAction(rooms, compact: true),
    ],
  );

  Widget _buildRoomAssociationCell(
    PublicRoom room,
    AsyncValue<PublicRoomTermData>? termData,
  ) {
    final data = termData?.valueOrNull;
    if (data == null) {
      return Text(
        termData?.hasError == true ? '读取失败' : '暂无科目关联',
        style: TextStyle(fontSize: 12, color: context.appColors.muted),
      );
    }
    final associations = _roomAssociations(room.id, data);
    if (associations.isEmpty) {
      return Text(
        '暂无关联科目',
        style: TextStyle(fontSize: 12, color: context.appColors.muted),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: [
        for (final association in associations)
          Tooltip(
            message: association.tooltip,
            child: _roomTag(association.label),
          ),
      ],
    );
  }

  Widget _roomTag(String label) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.appColors.selectedBlue,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Text(
        label,
        style: TextStyle(
          color: context.appColors.blue,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );

  Widget _roomMetric(String label, String value) => RichText(
    text: TextSpan(
      style: TextStyle(fontSize: 12, color: context.appColors.inkSecondary),
      children: [
        TextSpan(
          text: '$label  ',
          style: TextStyle(color: context.appColors.muted),
        ),
        TextSpan(
          text: value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _roomAction({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) => TextButton(
    key: key,
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: destructive
          ? context.appColors.destructive
          : context.appColors.blue,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      minimumSize: const Size(36, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
    child: Text(label),
  );

  Widget _buildAddRoomAction(List<PublicRoom> rooms, {required bool compact}) {
    if (compact) {
      return Align(
        alignment: Alignment.centerLeft,
        child: AppPrimaryButton(
          onPressed: _busy ? null : () => _edit(rooms),
          child: const Text('添加场室'),
        ),
      );
    }
    return Material(
      color: context.appColors.tableHeader,
      child: InkWell(
        onTap: _busy ? null : () => _edit(rooms),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: Center(
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.add, size: 17, color: context.appColors.blue),
                Text(
                  '添加场室',
                  style: TextStyle(
                    color: context.appColors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '（名称 / 个数 / 容量，容量单位为“班”）',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appColors.inkSecondary,
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

class _RoomEditor extends StatefulWidget {
  const _RoomEditor({
    required this.room,
    required this.rooms,
    required this.newId,
  });
  final PublicRoom? room;
  final List<PublicRoom> rooms;
  final String Function() newId;
  @override
  State<_RoomEditor> createState() => _RoomEditorState();
}

class _RoomEditorState extends State<_RoomEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.room?.name ?? '');
  late final _count = TextEditingController(
    text: '${widget.room?.roomCount ?? 1}',
  );
  late final _capacity = TextEditingController(
    text: '${widget.room?.capacityPerRoom ?? 1}',
  );

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    _capacity.dispose();
    super.dispose();
  }

  String? _integerError(String? value) =>
      (int.tryParse(value?.trim() ?? '') ?? 0) > 0 ? null : '请输入正整数';

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final nextOrder =
        widget.rooms.fold<int>(
          -1,
          (max, room) => room.sortOrder > max ? room.sortOrder : max,
        ) +
        1;
    Navigator.pop(
      context,
      PublicRoom(
        id: widget.room?.id ?? widget.newId(),
        name: _name.text.trim(),
        roomCount: int.parse(_count.text.trim()),
        capacityPerRoom: int.parse(_capacity.text.trim()),
        sortOrder: widget.room?.sortOrder ?? nextOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(widget.room == null ? '添加场室' : '编辑场室'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextFormField(
            key: const ValueKey('room-name'),
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '场室名称'),
            validator: (value) {
              final name = value?.trim() ?? '';
              if (name.isEmpty) return '请输入场室名称';
              if (widget.rooms.any(
                (room) =>
                    room.id != widget.room?.id &&
                    room.name.trim().toLowerCase() == name.toLowerCase(),
              )) {
                return '已存在同名场室';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          AppTextFormField(
            key: const ValueKey('room-count'),
            controller: _count,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '场室个数'),
            validator: _integerError,
          ),
          const SizedBox(height: 16),
          AppTextFormField(
            key: const ValueKey('room-capacity'),
            controller: _capacity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每间容量（班）'),
            validator: _integerError,
            onFieldSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(onPressed: _submit, child: const Text('保存')),
    ],
  );
}

class _DeleteRoomDialog extends ConsumerWidget {
  const _DeleteRoomDialog({required this.room});
  final PublicRoom room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final references = ref.watch(roomReferencesProvider(room.id));
    final terms = ref.watch(termsProvider);
    final termData = {
      for (final termId
          in (references.valueOrNull ?? []).map((row) => row.termId).toSet())
        termId: ref.watch(publicRoomTermDataProvider(termId)),
    };
    final ready =
        references.hasValue &&
        !references.isLoading &&
        !references.hasError &&
        terms.hasValue &&
        !terms.isLoading &&
        !terms.hasError &&
        termData.values.every(
          (data) => data.hasValue && !data.isLoading && !data.hasError,
        );
    final hasError =
        references.hasError ||
        terms.hasError ||
        termData.values.any((data) => data.hasError);
    return AppDialog(
      title: Text('删除“${room.name}”？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('此操作会同时移除所有学期中引用该场室的科目绑定。'),
          const SizedBox(height: 12),
          if (hasError)
            const Text('读取绑定失败，请关闭后重试。')
          else if (!ready)
            const Text('正在读取所有学期的引用…')
          else if (references.requireValue.isEmpty)
            const Text('此场室暂无科目绑定。')
          else
            for (final row in references.requireValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${terms.requireValue.where((term) => term.id == row.termId).firstOrNull?.title ?? '已移除学期'} · ${termData[row.termId]!.requireValue.bindingLabel(row)}',
                ),
              ),
        ],
      ),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppDestructiveButton(
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          child: const Text('删除场室及绑定'),
        ),
      ],
    );
  }
}
