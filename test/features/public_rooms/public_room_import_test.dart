import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/features/public_rooms/public_room_import.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> workbook(List<List<CellValue?>> rows) {
  final excel = Excel.createExcel();
  for (final row in rows) {
    excel[excel.getDefaultSheet()!].appendRow(row);
  }
  excel['ignored'].appendRow([TextCellValue('invalid second worksheet')]);
  return excel.encode()!;
}

List<CellValue?> row(String name, CellValue count, CellValue capacity) => [
  TextCellValue(name),
  count,
  capacity,
];

void main() {
  final headers = [
    TextCellValue(' 场室 '),
    TextCellValue('个数\n'),
    TextCellValue(' 容量（班） '),
  ];
  const existing = PublicRoom(
    id: 'old',
    name: ' Lab ',
    roomCount: 1,
    capacityPerRoom: 1,
    sortOrder: 7,
  );

  test(
    'imports first worksheet, trims names and appends stable IDs and order',
    () {
      final result = parsePublicRoomsWorkbook(
        workbook([
          headers,
          row(' 音乐室 ', const IntCellValue(2), const IntCellValue(3)),
        ]),
        existingRooms: [existing],
        idForIndex: (index) => 'import-$index',
      );
      expect(result.errors, isEmpty);
      expect(result.rooms, hasLength(1));
      expect(result.rooms.single.id, 'import-0');
      expect(result.rooms.single.name, '音乐室');
      expect(result.rooms.single.roomCount, 2);
      expect(result.rooms.single.capacityPerRoom, 3);
      expect(result.rooms.single.sortOrder, 8);
    },
  );

  test('rejects whole file for empty/duplicate names and invalid positive integers', () {
    final result = parsePublicRoomsWorkbook(
      workbook([
        headers,
        row('新场室', const IntCellValue(1), const IntCellValue(1)),
        row(' lab ', const IntCellValue(1), const IntCellValue(1)),
        row('新场室', const IntCellValue(1), const IntCellValue(1)),
        row(' ', const IntCellValue(1), const IntCellValue(1)),
        row('负数', const IntCellValue(0), const IntCellValue(-1)),
        row('小数', const DoubleCellValue(1.5), TextCellValue('2.5')),
      ]),
      existingRooms: [existing],
      idForIndex: (index) => '$index',
    );
    expect(result.rooms, isEmpty);
    expect(result.errors.map((e) => e.rowNumber).toSet(), {3, 4, 5, 6, 7});
    expect(result.errors.where((e) => e.rowNumber == 6), hasLength(2));
    expect(result.errors.where((e) => e.rowNumber == 7), hasLength(2));
  });

  test('reports missing headers, empty workbooks and corrupt bytes', () {
    for (final bytes in [
      workbook([]),
      workbook([row('wrong', const IntCellValue(1), const IntCellValue(1))]),
      <int>[1, 2, 3],
    ]) {
      final result = parsePublicRoomsWorkbook(
        bytes,
        existingRooms: [],
        idForIndex: (i) => '$i',
      );
      expect(result.errors, isNotEmpty);
      expect(result.rooms, isEmpty);
    }
  });
}
