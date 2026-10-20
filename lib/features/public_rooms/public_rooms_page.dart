import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/features/public_rooms/public_room_import.dart';
import 'package:class_set/features/public_rooms/public_rooms_data.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final publicRoomWorkbookPickerProvider =
    Provider<Future<List<int>?> Function()>(
      (ref) => () async {
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Excel 工作簿',
              extensions: ['xlsx'],
              uniformTypeIdentifiers: [
                'org.openxmlformats.spreadsheetml.sheet',
              ],
            ),
          ],
        );
        return file?.readAsBytes();
      },
    );

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

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(publicRoomWorkbookPickerProvider)();
      if (bytes == null || !mounted) return;
      final currentRooms = await ref.read(publicRoomsProvider.future);
      if (!mounted) return;
      final result = parsePublicRoomsWorkbook(
        bytes,
        existingRooms: currentRooms,
        idForIndex: (_) => _newId(),
      );
      if (result.errors.isNotEmpty) {
        setState(() => _busy = false);
        await showAppDialog<void>(
          context: context,
          builder: (context) => AppDialog(
            title: const Text('导入未保存'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('请修正以下问题后重新导入。'),
                const SizedBox(height: 12),
                for (final error in result.errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('$error'),
                  ),
              ],
            ),
            actions: [
              AppPrimaryButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      } else {
        await _save(result.rooms, '已导入 ${result.rooms.length} 个场室');
      }
    } catch (error) {
      if (mounted) _notice('导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(publicRoomsProvider);
    final termId = widget.termId ?? ref.watch(activeTermIdProvider);
    final termData = termId == null
        ? null
        : ref.watch(publicRoomTermDataProvider(termId));
    return Material(
      color: AppTheme.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final padding = AppTheme.pagePaddingForWidth(constraints.maxWidth);
          final items = rooms.valueOrNull ?? const <PublicRoom>[];
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppOutlineButton(
                onPressed: _busy || !rooms.hasValue ? null : _import,
                child: const Text('导入 Excel'),
              ),
              AppPrimaryButton(
                onPressed: _busy || !rooms.hasValue ? null : () => _edit(items),
                child: const Text('添加场室'),
              ),
            ],
          );
          final header = AppPageHeader(
            title: '公共场室',
            subtitle: '所有学期共用，修改后立即保存。容量单位为班。',
            actions: compact ? [] : [actions],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    if (compact) ...[const SizedBox(height: 16), actions],
                    const SizedBox(height: 12),
                    const Text(
                      'Excel 首个工作表需包含：场室、个数、容量（班）',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkSecondary,
                      ),
                    ),
                    if (termId == null) const Text('选择学期后显示科目绑定范围。'),
                    if (termData?.isLoading == true) const Text('正在读取当前学期绑定…'),
                    if (termData?.hasError == true)
                      const Text('当前学期绑定读取失败，请稍后重试。'),
                    if (_busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
              Expanded(
                child: rooms.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('读取场室失败：$error')),
                  data: (items) => items.isEmpty
                      ? const Center(child: Text('暂无公共场室，添加或导入后即可为科目设置行课场室。'))
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            padding,
                            0,
                            padding,
                            padding,
                          ),
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final room = items[index];
                            final data = termData?.valueOrNull;
                            final bindings =
                                data?.assignments
                                    .where((row) => row.roomId == room.id)
                                    .toList() ??
                                [];
                            return AppSurface(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            room.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ),
                                        AppIconButton(
                                          key: ValueKey('edit-room-${room.id}'),
                                          icon: Icons.edit_outlined,
                                          tooltip: '编辑${room.name}',
                                          onPressed: _busy
                                              ? null
                                              : () => _edit(items, room),
                                        ),
                                        AppIconButton(
                                          key: ValueKey(
                                            'delete-room-${room.id}',
                                          ),
                                          icon: Icons.delete_outline,
                                          tooltip: '删除${room.name}',
                                          foregroundColor: AppTheme.destructive,
                                          onPressed: _busy
                                              ? null
                                              : () => _delete(room),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 8,
                                      children: [
                                        Text('场室个数 ${room.roomCount}'),
                                        Text('每间容量 ${room.capacityPerRoom} 班'),
                                        Text(
                                          '总容量 ${room.roomCount * room.capacityPerRoom} 班',
                                        ),
                                      ],
                                    ),
                                    if (data?.isSharedAcrossStages(room.id) ==
                                        true) ...[
                                      const SizedBox(height: 10),
                                      const Chip(
                                        label: Text('跨学段共用'),
                                        backgroundColor: AppTheme.selectedBlue,
                                        side: BorderSide.none,
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    const Text(
                                      '当前学期科目绑定',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.inkSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (data != null && bindings.isEmpty)
                                      const Text(
                                        '暂无直接绑定',
                                        style: TextStyle(color: AppTheme.muted),
                                      ),
                                    for (final binding in bindings)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          data!.bindingLabel(binding),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
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
