import 'package:class_set/domain/models/public_room.dart';
import 'package:excel/excel.dart';

class PublicRoomImportError {
  const PublicRoomImportError(this.rowNumber, this.message);
  final int rowNumber;
  final String message;

  @override
  String toString() => '第 $rowNumber 行：$message';
}

class PublicRoomImportResult {
  const PublicRoomImportResult({this.rooms = const [], this.errors = const []});
  final List<PublicRoom> rooms;
  final List<PublicRoomImportError> errors;
}

PublicRoomImportResult parsePublicRoomsWorkbook(
  List<int> bytes, {
  required List<PublicRoom> existingRooms,
  required String Function(int index) idForIndex,
}) {
  try {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty || book.tables.values.first.rows.isEmpty) {
      return const PublicRoomImportResult(
        errors: [PublicRoomImportError(1, '工作表为空，请使用列：场室、个数、容量（班）')],
      );
    }
    final rows = book.tables.values.first.rows;
    final headers = rows.first.map((cell) => _cellText(cell?.value)).toList();
    const requiredHeaders = ['场室', '个数', '容量（班）'];
    if (requiredHeaders.any(
      (header) => headers.where((h) => h == header).length != 1,
    )) {
      return const PublicRoomImportResult(
        errors: [PublicRoomImportError(1, '表头必须各包含一列：场室、个数、容量（班）')],
      );
    }
    final nameColumn = headers.indexOf('场室');
    final countColumn = headers.indexOf('个数');
    final capacityColumn = headers.indexOf('容量（班）');
    final seen = existingRooms
        .map((room) => room.name.trim().toLowerCase())
        .toSet();
    final errors = <PublicRoomImportError>[];
    final parsed = <({String name, int count, int capacity})>[];
    for (var index = 1; index < rows.length; index++) {
      final cells = rows[index];
      // Completely blank spreadsheet rows are formatting, not catalog entries.
      if (cells.every((cell) => _cellText(cell?.value).isEmpty)) continue;
      CellValue? valueAt(int column) =>
          column < cells.length ? cells[column]?.value : null;
      final name = _cellText(valueAt(nameColumn));
      final count = _positiveInteger(valueAt(countColumn));
      final capacity = _positiveInteger(valueAt(capacityColumn));
      if (name.isEmpty) {
        errors.add(PublicRoomImportError(index + 1, '场室名称不能为空'));
      } else if (!seen.add(name.toLowerCase())) {
        errors.add(PublicRoomImportError(index + 1, '场室“$name”名称重复'));
      }
      if (count == null) {
        errors.add(PublicRoomImportError(index + 1, '个数必须为正整数'));
      }
      if (capacity == null) {
        errors.add(PublicRoomImportError(index + 1, '容量（班）必须为正整数'));
      }
      if (name.isNotEmpty && count != null && capacity != null) {
        parsed.add((name: name, count: count, capacity: capacity));
      }
    }
    if (errors.isNotEmpty) return PublicRoomImportResult(errors: errors);
    if (parsed.isEmpty) {
      return const PublicRoomImportResult(
        errors: [PublicRoomImportError(2, '没有可导入的场室数据')],
      );
    }
    var nextOrder =
        existingRooms.fold<int>(
          -1,
          (max, room) => room.sortOrder > max ? room.sortOrder : max,
        ) +
        1;
    return PublicRoomImportResult(
      rooms: [
        for (var index = 0; index < parsed.length; index++)
          PublicRoom(
            id: idForIndex(index),
            name: parsed[index].name,
            roomCount: parsed[index].count,
            capacityPerRoom: parsed[index].capacity,
            sortOrder: nextOrder++,
          ),
      ],
    );
  } catch (_) {
    return const PublicRoomImportResult(
      errors: [PublicRoomImportError(1, '无法读取 Excel 文件，请选择有效的 .xlsx 文件')],
    );
  }
}

String _cellText(CellValue? value) => value?.toString().trim() ?? '';

int? _positiveInteger(CellValue? value) {
  final int? number;
  if (value is IntCellValue) {
    number = value.value;
  } else if (value is DoubleCellValue &&
      value.value.isFinite &&
      value.value == value.value.truncateToDouble()) {
    number = value.value.toInt();
  } else if (value is TextCellValue) {
    number = int.tryParse(value.value.toString().trim());
  } else {
    return null;
  }
  return number != null && number > 0 ? number : null;
}
