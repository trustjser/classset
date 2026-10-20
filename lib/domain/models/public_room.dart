class PublicRoom {
  const PublicRoom({
    required this.id,
    required this.name,
    required this.roomCount,
    required this.capacityPerRoom,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int roomCount;
  final int capacityPerRoom;
  final int sortOrder;

  void validate() {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('公共教室 ID 和名称不能为空');
    }
    if (roomCount <= 0 || capacityPerRoom <= 0) {
      throw ArgumentError('教室数量和每间容纳班数必须大于零');
    }
  }
}
