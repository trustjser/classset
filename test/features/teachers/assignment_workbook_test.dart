import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/features/teachers/io/assignment_workbook.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('template round trips assignment rows and ignores empty rows', () {
    final bytes = buildAssignmentWorkbook(const [
      AssignmentWorkbookRow(
        stage: '小学部',
        grade: '一年级',
        schoolClass: '1班',
        subject: '语文',
        teacher: '王老师',
        weekMode: WeekMode.weekly,
        lessonCount: 4,
        rowNumber: 2,
      ),
    ]);
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, ['导入说明', '数据源', '任课分配']);
    final sheet = book.tables['任课分配']!;
    expect(sheet.rows.first.map((cell) => cell?.value.toString()), [
      '学段',
      '年级',
      '班级',
      '科目',
      '教师',
      '周模式',
      '节数',
    ]);
    final result = parseAssignmentWorkbook(bytes);
    expect(result.errors, isEmpty);
    expect(result.rows.single.teacher, '王老师');
    expect(result.rows.single.weekMode, WeekMode.weekly);
    expect(result.rows.single.lessonCount, 4);
  });

  test('template explains columns and lists current term choices', () {
    final bytes = buildAssignmentWorkbook(
      const [],
      stages: const [
        SchoolStage(id: 's', termId: 't', name: '小学部', sortOrder: 0),
      ],
      grades: const [
        GradeGroup(id: 'g', stageId: 's', name: '一年级', sortOrder: 0),
      ],
      classes: const [
        ClassBrief(id: 'c', stageId: 's', gradeId: 'g', name: '1班'),
      ],
      subjects: const [
        Subject(id: 'u', name: '语文', shortName: '语', sortOrder: 0),
      ],
      teachers: const [
        Teacher(
          id: 'a',
          name: '王老师',
          shortName: '王',
          displayQualifier: '小学部',
          sortOrder: 0,
        ),
      ],
      requirements: const [
        SubjectRequirement(
          id: 'r',
          subjectId: 'u',
          gradeId: 'g',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
      existingAssignments: const [
        TeacherAssignment(
          id: 'old',
          termId: 't',
          teacherId: 'a',
          classId: 'c',
          subjectId: 'u',
          weekMode: WeekMode.weekly,
          lessonCount: 1,
          sortOrder: 0,
        ),
      ],
    );
    final book = Excel.decodeBytes(bytes);
    final instructions = book.tables['导入说明']!.rows
        .expand((row) => row.map((cell) => cell?.value?.toString() ?? ''))
        .join(' ');
    expect(instructions, contains('任课分配'));
    expect(instructions, contains('每周'));
    final sourceRows = book.tables['数据源']!.rows;
    expect(sourceRows[1].map((cell) => cell?.value?.toString()), [
      '小学部',
      '一年级',
      '1班',
      '语文',
      '每周',
      '4',
      '3',
      '王老师（小学部）',
    ]);
    expect(book.tables['任课分配']!.rows, hasLength(1));
  });

  test('malformed row blocks the entire workbook', () {
    final book = Excel.createExcel();
    final sheet = book[book.getDefaultSheet()!];
    sheet.appendRow(
      [
        '学段',
        '年级',
        '班级',
        '科目',
        '教师',
        '周模式',
        '节数',
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow(
      [
        '小学部',
        '一年级',
        '1班',
        '语文',
        '王老师',
        '每周',
        '4',
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow(
      [
        '小学部',
        '一年级',
        '1班',
        '语文',
        '李老师',
        '单周',
        '0',
      ].map(TextCellValue.new).toList(),
    );
    final result = parseAssignmentWorkbook(book.encode()!);
    expect(result.rows, isEmpty);
    expect(result.errors.single.rowNumber, 3);
  });

  test('resolution rejects ambiguous teachers and over capacity', () {
    const row = AssignmentWorkbookRow(
      stage: '小学部',
      grade: '一年级',
      schoolClass: '1班',
      subject: '语文',
      teacher: '王老师',
      weekMode: WeekMode.weekly,
      lessonCount: 4,
      rowNumber: 2,
    );
    const stages = [
      SchoolStage(id: 's', termId: 't', name: '小学部', sortOrder: 0),
    ];
    const grades = [
      GradeGroup(id: 'g', stageId: 's', name: '一年级', sortOrder: 0),
    ];
    const classes = [
      ClassBrief(id: 'c', stageId: 's', gradeId: 'g', name: '1班'),
    ];
    const subjects = [
      Subject(id: 'u', name: '语文', shortName: '语', sortOrder: 0),
    ];
    const requirement = [
      SubjectRequirement(
        id: 'r',
        subjectId: 'u',
        gradeId: 'g',
        weekMode: WeekMode.weekly,
        lessonCount: 3,
      ),
    ];
    AssignmentImportPlan resolve(List<Teacher> teachers) =>
        resolveAssignmentWorkbook(
          rows: [row],
          stages: stages,
          grades: grades,
          classes: classes,
          subjects: subjects,
          teachers: teachers,
          requirements: requirement,
          existingAssignments: const [],
        );
    expect(
      resolve(const [
        Teacher(id: 'a', name: '王老师', shortName: '', sortOrder: 0),
        Teacher(id: 'b', name: '王老师', shortName: '', sortOrder: 1),
      ]).errors.single.message,
      contains('重复'),
    );
    expect(
      resolve(const [
        Teacher(id: 'a', name: '王老师', shortName: '', sortOrder: 0),
      ]).errors.single.message,
      contains('超过需求'),
    );
  });

  test('resolution maps unique names and counts existing lessons', () {
    const row = AssignmentWorkbookRow(
      stage: '小学部',
      grade: '一年级',
      schoolClass: '1班',
      subject: '语文',
      teacher: '王老师（小学部）',
      weekMode: WeekMode.weekly,
      lessonCount: 2,
      rowNumber: 2,
    );
    AssignmentImportPlan resolve(int existingCount) =>
        resolveAssignmentWorkbook(
          rows: [row],
          stages: const [
            SchoolStage(id: 's', termId: 't', name: '小学部', sortOrder: 0),
          ],
          grades: const [
            GradeGroup(id: 'g', stageId: 's', name: '一年级', sortOrder: 0),
          ],
          classes: const [
            ClassBrief(id: 'c', stageId: 's', gradeId: 'g', name: '1班'),
          ],
          subjects: const [
            Subject(id: 'u', name: '语文', shortName: '语', sortOrder: 0),
          ],
          teachers: const [
            Teacher(
              id: 'a',
              name: '王老师',
              shortName: '王',
              displayQualifier: '小学部',
              sortOrder: 0,
            ),
          ],
          requirements: const [
            SubjectRequirement(
              id: 'r',
              subjectId: 'u',
              gradeId: 'g',
              weekMode: WeekMode.weekly,
              lessonCount: 3,
            ),
          ],
          existingAssignments: [
            TeacherAssignment(
              id: 'old',
              termId: 't',
              teacherId: 'a',
              classId: 'c',
              subjectId: 'u',
              weekMode: WeekMode.weekly,
              lessonCount: existingCount,
              sortOrder: 0,
            ),
          ],
        );
    final valid = resolve(1);
    expect(valid.errors, isEmpty);
    expect(valid.rows.single.teacherId, 'a');
    expect(valid.rows.single.classId, 'c');
    expect(valid.rows.single.subjectId, 'u');
    expect(resolve(2).errors.single.message, contains('超过需求'));
  });
}
