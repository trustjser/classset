import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_lesson_constraint.dart';
import 'package:class_set/domain/models/teacher_preset.dart';
import 'package:class_set/domain/scheduling/manual_schedule_editor.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = SchedulePosition(
  stageId: 'stage',
  weekday: 1,
  periodTypeId: 'morning',
  lessonIndex: 1,
  startMinute: 480,
  endMinute: 525,
);
const _second = SchedulePosition(
  stageId: 'stage',
  weekday: 1,
  periodTypeId: 'morning',
  lessonIndex: 2,
  startMinute: 530,
  endMinute: 575,
);
const _afternoon = SchedulePosition(
  stageId: 'stage',
  weekday: 1,
  periodTypeId: 'afternoon',
  lessonIndex: 1,
  startMinute: 810,
  endMinute: 855,
);

void main() {
  const editor = ManualScheduleEditor();

  test('大批互不冲突的暂放课不会把搜索预算全部耗在候选计数上', () {
    final classes = [
      for (var i = 0; i < 600; i++)
        ClassGroup(
          id: 'class-$i',
          gradeId: 'grade',
          name: '$i 班',
          sortOrder: i,
        ),
    ];
    final items = [
      for (var i = 0; i < classes.length; i++)
        _item('item-$i', classes[i].id, 'teacher-$i', _first).at(null),
    ];
    final snapshot = _snapshot(items: items, classes: classes);
    final positions = [
      for (var day = 1; day <= 5; day++)
        for (var lesson = 1; lesson <= 8; lesson++)
          SchedulePosition(
            stageId: 'stage',
            weekday: day,
            periodTypeId: 'morning',
            lessonIndex: lesson,
            startMinute: 480 + lesson * 50,
            endMinute: 520 + lesson * 50,
          ),
    ];
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: items.map((item) => item.id).toSet(),
      problem: SchedulingProblem(
        snapshot: snapshot,
        selectedClassIds: classes.map((item) => item.id).toSet(),
        positionsByClass: {for (final group in classes) group.id: positions},
        fixedItems: const [],
        units: const [],
        checks: const [],
      ),
    );
    expect(result.items.where((item) => item.isPlaced), hasLength(600));
    expect(result.changedItemIds, hasLength(600));
  });

  test('一键放入只使用合法空位并保留现有课程', () {
    final items = [
      _item('placed', 'class-a', 'teacher-a', _first),
      _item('waiting', 'class-a', 'teacher-b', _first).at(null),
      _item('other', 'class-b', 'teacher-b', _second),
    ];
    final snapshot = _snapshot(items: items);
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'waiting'},
      problem: _problem(snapshot),
    );
    expect(result.changedItemIds, {'waiting'});
    expect(result.items.first.position?.cellKey, _first.cellKey);
    expect(result.items.last.position?.cellKey, _second.cellKey);
    expect(result.items[1].position?.cellKey, _afternoon.cellKey);
  });

  test('回溯调整暂放课程的选择，可填满贪心算法遗漏的空位', () {
    final items = [
      _item('existing', 'class-b', 'teacher-z', _first),
      _item('a', 'class-a', 'teacher-a', _first).at(null),
      _item('b', 'class-a', 'teacher-b', _first).at(null),
      _item('c', 'class-a', 'teacher-b', _first).at(null),
    ];
    final snapshot = _snapshot(
      items: items,
      teacherPresets: const [
        TeacherPreset(
          id: 'a-no-afternoon',
          teacherId: 'teacher-a',
          scope: TeacherPresetScope.school,
          scopeId: 'term',
          stageId: 'stage',
          weekday: 1,
          periodTypeId: 'afternoon',
          lessonIndex: 1,
          value: PresetValue.forbid,
        ),
        TeacherPreset(
          id: 'b-no-second',
          teacherId: 'teacher-b',
          scope: TeacherPresetScope.school,
          scopeId: 'term',
          stageId: 'stage',
          weekday: 1,
          periodTypeId: 'morning',
          lessonIndex: 2,
          value: PresetValue.forbid,
        ),
      ],
    );
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'a', 'b', 'c'},
      problem: _problem(snapshot),
    );
    expect(result.changedItemIds, {'a', 'b', 'c'});
    expect(result.items.first.position?.cellKey, _first.cellKey);
    expect(result.items[1].position?.cellKey, _second.cellKey);
  });

  test('没有空位时保留暂放课且不影响其他课程', () {
    final items = [
      _item('a', 'class-a', 'teacher-a', _first),
      _item('b', 'class-a', 'teacher-a', _second),
      _item('c', 'class-a', 'teacher-a', _afternoon),
      _item('waiting', 'class-a', 'teacher-b', _first).at(null),
    ];
    final snapshot = _snapshot(items: items);
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'waiting'},
      problem: _problem(snapshot),
    );
    expect(result.changedItemIds, isEmpty);
    expect(result.items.last.isPlaced, isFalse);
    expect(result.items.first.position?.cellKey, _first.cellKey);
  });

  test('暂放课只能用被占位置时，把原课程腾挪到合法空位', () {
    final items = [
      _item('existing', 'class-a', 'teacher-a', _first),
      _item('waiting', 'class-a', 'teacher-b', _first).at(null),
    ];
    final snapshot = _snapshot(
      items: items,
      teacherPresets: [
        _forbid('teacher-b', _second),
        _forbid('teacher-b', _afternoon),
      ],
    );
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'waiting'},
      problem: _problem(snapshot),
    );
    expect(result.changedItemIds, {'existing', 'waiting'});
    expect(result.items[1].position?.cellKey, _first.cellKey);
    expect(result.items[0].position?.cellKey, _second.cellKey);
    expect(
      editor.detectAll(
        snapshot: snapshot,
        items: result.items,
        problem: _problem(snapshot),
      ),
      isEmpty,
    );
    expect(items[0].position?.cellKey, _first.cellKey);
    expect(items[1].isPlaced, isFalse);
  });

  test('跨班教师占用可以通过两级腾挪解开', () {
    final items = [
      _item('teacher-conflict', 'class-b', 'teacher-a', _first),
      _item('next', 'class-b', 'teacher-b', _second),
      _item('waiting', 'class-a', 'teacher-a', _first).at(null),
    ];
    final snapshot = _snapshot(
      items: items,
      teacherPresets: [
        _forbid('teacher-a', _afternoon),
        _forbid('teacher-b', _first),
      ],
    );
    final base = _problem(snapshot);
    final problem = SchedulingProblem(
      snapshot: snapshot,
      selectedClassIds: base.selectedClassIds,
      positionsByClass: {
        'class-a': [_first],
        'class-b': [_first, _second, _afternoon],
      },
      fixedItems: const [],
      units: const [],
      checks: const [],
    );
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'waiting'},
      problem: problem,
    );
    expect(result.changedItemIds, {'teacher-conflict', 'next', 'waiting'});
    expect(result.items.map((item) => item.position?.cellKey), [
      _second.cellKey,
      _afternoon.cellKey,
      _first.cellKey,
    ]);
    expect(
      editor.detectAll(
        snapshot: snapshot,
        items: result.items,
        problem: problem,
      ),
      isEmpty,
    );
  });

  test('整周课程可腾挪同格的单双周课程，保留周次', () {
    ScheduleItem single(String id, WeekMode week) => ScheduleItem(
      id: id,
      termId: 'term',
      assignmentId: id,
      classId: 'class-a',
      teacherId: 'teacher-a',
      subjectId: 'subject',
      weekMode: week,
      position: _first,
    );
    final items = [
      single('odd', WeekMode.odd),
      single('even', WeekMode.even),
      _item('waiting', 'class-a', 'teacher-b', _first).at(null),
    ];
    final snapshot = _snapshot(
      items: items,
      teacherPresets: [
        _forbid('teacher-b', _second),
        _forbid('teacher-b', _afternoon),
      ],
    );
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'waiting'},
      problem: _problem(snapshot),
    );
    expect(result.items.every((item) => item.isPlaced), isTrue);
    expect(result.items.last.position?.cellKey, _first.cellKey);
    expect(result.items[0].position?.cellKey, _second.cellKey);
    expect(result.items[1].position?.cellKey, _second.cellKey);
    expect(result.items.map((item) => item.weekMode), [
      WeekMode.odd,
      WeekMode.even,
      WeekMode.weekly,
    ]);
  });

  test('腾挪不会移动锁定教师或把原课程留在暂放区', () {
    final items = [
      _item('existing', 'class-a', 'teacher-a', _first),
      _item('waiting', 'class-a', 'teacher-b', _first).at(null),
    ];
    final snapshot = _snapshot(
      items: items,
      teacherPresets: [
        _forbid('teacher-b', _second),
        _forbid('teacher-b', _afternoon),
      ],
      locks: const [
        ScheduleLock(
          termId: 'term',
          scope: ScheduleLockScope.teacher,
          targetId: 'teacher-a',
        ),
      ],
    );
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'waiting'},
      problem: _problem(snapshot),
    );
    expect(result.changedItemIds, isEmpty);
    expect(result.items.first.position?.cellKey, _first.cellKey);
    expect(result.items.last.isPlaced, isFalse);
    expect(
      result.unplaced.single.blockers.any(
        (blocker) => blocker.code == 'locked',
      ),
      isTrue,
    );
  });

  test('腾挪失败不会破坏原有的硬性最低节数', () {
    final items = [
      _item('existing', 'class-a', 'teacher-a', _first),
      _item('waiting', 'class-a', 'teacher-b', _first).at(null),
    ];
    final snapshot = _snapshot(
      items: items,
      teacherPresets: [
        _forbid('teacher-b', _second),
        _forbid('teacher-b', _afternoon),
        _forbid('teacher-a', _second),
      ],
      conditions: const [
        ScheduleCondition(
          id: 'morning-minimum',
          termId: 'term',
          type: ScheduleConditionType.periodLimit,
          targetType: ScheduleConditionTarget.teacher,
          targetId: 'teacher-a',
          periodTypeId: 'morning',
          minimum: 1,
        ),
      ],
    );
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'waiting'},
      problem: _problem(snapshot),
    );
    expect(result.changedItemIds, isEmpty);
    expect(result.items.first.position?.cellKey, _first.cellKey);
    expect(result.items.last.isPlaced, isFalse);
  });

  test('锁定班级的暂放课不会自动放入', () {
    final waiting = _item('waiting', 'class-a', 'teacher-a', _first).at(null);
    final snapshot = _snapshot(
      items: [waiting],
      locks: const [
        ScheduleLock(
          termId: 'term',
          scope: ScheduleLockScope.schoolClass,
          targetId: 'class-a',
        ),
      ],
    );
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: [waiting],
      itemIds: {'waiting'},
      problem: _problem(snapshot),
    );
    expect(result.changedItemIds, isEmpty);
  });

  test('合班课组一起放入，不移动已排课程', () {
    ScheduleItem meeting(String id, String classId) => ScheduleItem(
      id: id,
      termId: 'term',
      assignmentId: 'assignment-$id',
      classId: classId,
      teacherId: 'teacher-a',
      subjectId: 'subject',
      weekMode: WeekMode.weekly,
      meetingId: 'meeting',
      combinedGroupId: 'combined',
    );
    final items = [meeting('a', 'class-a'), meeting('b', 'class-b')];
    final snapshot = _snapshot(items: items);
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'a'},
      problem: _problem(snapshot),
    );
    expect(result.changedItemIds, {'a', 'b'});
    expect(
      result.items[0].position?.cellKey,
      result.items[1].position?.cellKey,
    );
    expect(result.items.every((item) => item.isPlaced), isTrue);
  });

  test('腾挪合班课时所有班级一起移动', () {
    final items = [
      for (final classId in ['class-a', 'class-b'])
        ScheduleItem(
          id: classId,
          termId: 'term',
          assignmentId: 'assignment-$classId',
          classId: classId,
          teacherId: 'teacher-a',
          subjectId: 'subject',
          weekMode: WeekMode.weekly,
          meetingId: 'meeting',
          combinedGroupId: 'combined',
          position: _first,
        ),
      _item('waiting', 'class-a', 'teacher-b', _first).at(null),
    ];
    final snapshot = _snapshot(
      items: items,
      teacherPresets: [
        _forbid('teacher-b', _second),
        _forbid('teacher-b', _afternoon),
      ],
    );
    final result = editor.placeUnplaced(
      snapshot: snapshot,
      items: items,
      itemIds: {'waiting'},
      problem: _problem(snapshot),
    );
    expect(result.changedItemIds, {'class-a', 'class-b', 'waiting'});
    expect(result.items[0].position?.cellKey, _second.cellKey);
    expect(result.items[1].position?.cellKey, _second.cellKey);
    expect(result.items[2].position?.cellKey, _first.cellKey);
    expect(
      editor.detectAll(
        snapshot: snapshot,
        items: result.items,
        problem: _problem(snapshot),
      ),
      isEmpty,
    );
  });

  test('同班占用格可交换两节课', () {
    final items = [
      _item('a', 'class-a', 'teacher-a', _first),
      _item('b', 'class-a', 'teacher-b', _second),
    ];
    final snapshot = _snapshot(items: items);
    final result = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _second,
      problem: _problem(snapshot),
    );

    expect(result.allowed, isTrue);
    expect(result.changedItemIds, {'a', 'b'});
    expect(
      result.items.singleWhere((item) => item.id == 'a').position?.cellKey,
      _second.cellKey,
    );
    expect(
      result.items.singleWhere((item) => item.id == 'b').position?.cellKey,
      _first.cellKey,
    );
  });

  test('教师视图指定另一班课节后可交换', () {
    final items = [
      _item('a', 'class-a', 'teacher-a', _first),
      _item('b', 'class-b', 'teacher-a', _second),
    ];
    final snapshot = _snapshot(items: items);
    final problem = _problem(snapshot);

    final withoutTarget = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _second,
      problem: problem,
    );
    final withTarget = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _second,
      swapWithItemId: 'b',
      problem: problem,
    );

    expect(withoutTarget.allowed, isFalse);
    expect(withTarget.allowed, isTrue);
    expect(withTarget.changedItemIds, {'a', 'b'});
  });

  test('移出最低节数要求所在时段会被阻止', () {
    final items = [_item('a', 'class-a', 'teacher-a', _first)];
    final snapshot = _snapshot(
      items: items,
      conditions: const [
        ScheduleCondition(
          id: 'morning-minimum',
          termId: 'term',
          type: ScheduleConditionType.periodLimit,
          targetType: ScheduleConditionTarget.subject,
          targetId: 'subject',
          periodTypeId: 'morning',
          minimum: 1,
        ),
      ],
    );
    final result = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _afternoon,
      problem: _problem(snapshot),
    );

    expect(result.allowed, isFalse);
    expect(result.blockers.any((blocker) => blocker.code == 'minimum'), isTrue);
  });

  test('拖动到同一天超出科目节数上限时仍会阻止', () {
    const tuesday = SchedulePosition(
      stageId: 'stage',
      weekday: 2,
      periodTypeId: 'morning',
      lessonIndex: 1,
      startMinute: 480,
      endMinute: 525,
    );
    final items = [
      _item('a', 'class-a', 'teacher-a', tuesday),
      _item('b', 'class-a', 'teacher-b', _first),
    ];
    final snapshot = _snapshot(
      items: items,
      lessonConstraints: const [
        SubjectLessonConstraint(
          id: 'limit',
          subjectId: 'subject',
          scope: FreeSlotScope.grade,
          scopeId: 'grade',
          stageId: 'stage',
          weekday: null,
          maximumDailyLessons: 1,
        ),
      ],
    );
    final result = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _second,
      problem: _problem(snapshot),
    );
    expect(result.allowed, isFalse);
    expect(
      result.blockers.any((blocker) => blocker.code == 'subjectDailyMaximum'),
      isTrue,
    );
  });

  test('班级锁会阻止拖入暂放区', () {
    final items = [_item('a', 'class-a', 'teacher-a', _first)];
    final snapshot = _snapshot(
      items: items,
      locks: const [
        ScheduleLock(
          termId: 'term',
          scope: ScheduleLockScope.schoolClass,
          targetId: 'class-a',
        ),
      ],
    );
    final result = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: null,
      problem: _problem(snapshot),
    );

    expect(result.allowed, isFalse);
    expect(result.blockers.single.code, 'locked');
  });

  test('检测会列出跨学段时间缺失等预检阻断', () {
    final snapshot = _snapshot(items: const []);
    final problem = SchedulingProblem(
      snapshot: snapshot,
      selectedClassIds: const {'class-a', 'class-b'},
      positionsByClass: const {},
      fixedItems: const [],
      units: const [],
      checks: const [
        SchedulePreflightCheck(
          code: 'clock',
          message: '跨学段共用教师缺少时间',
          ready: false,
        ),
      ],
    );

    final issues = editor.detectAll(
      snapshot: snapshot,
      items: const [],
      problem: problem,
    );

    expect(issues.any((issue) => issue.code == 'clock'), isTrue);
  });
}

TeacherPreset _forbid(String teacherId, SchedulePosition position) =>
    TeacherPreset(
      id: '$teacherId-${position.cellKey}',
      teacherId: teacherId,
      scope: TeacherPresetScope.school,
      scopeId: 'term',
      stageId: 'stage',
      weekday: position.weekday,
      periodTypeId: position.periodTypeId,
      lessonIndex: position.lessonIndex,
      value: PresetValue.forbid,
    );

ScheduleItem _item(
  String id,
  String classId,
  String teacherId,
  SchedulePosition position,
) => ScheduleItem(
  id: id,
  termId: 'term',
  assignmentId: 'assignment-$id',
  classId: classId,
  teacherId: teacherId,
  subjectId: 'subject',
  weekMode: WeekMode.weekly,
  position: position,
);

SchedulingSnapshot _snapshot({
  required List<ScheduleItem> items,
  List<ClassGroup> classes = const [
    ClassGroup(id: 'class-a', gradeId: 'grade', name: '一班', sortOrder: 0),
    ClassGroup(id: 'class-b', gradeId: 'grade', name: '二班', sortOrder: 1),
  ],
  List<ScheduleCondition> conditions = const [],
  List<ScheduleLock> locks = const [],
  List<SubjectLessonConstraint> lessonConstraints = const [],
  List<TeacherPreset> teacherPresets = const [],
}) => SchedulingSnapshot(
  term: AcademicTerm(
    id: 'term',
    title: '2026 秋季',
    academicYear: '2026-2027',
    semesterLabel: '秋季学期',
    firstTeachingWeekStart: DateTime(2026, 9, 1),
    teachingWeekCount: 20,
    createdAt: DateTime(2026, 8, 1),
  ),
  inputFingerprint: 'fixture',
  stages: const [
    SchoolStage(id: 'stage', termId: 'term', name: '小学', sortOrder: 0),
  ],
  grades: const [
    GradeGroup(id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0),
  ],
  classes: classes,
  conditions: conditions,
  lessonConstraints: lessonConstraints,
  teacherPresets: teacherPresets,
  locks: locks,
  existingItems: items,
);

SchedulingProblem _problem(SchedulingSnapshot snapshot) => SchedulingProblem(
  snapshot: snapshot,
  selectedClassIds: const {'class-a', 'class-b'},
  positionsByClass: const {
    'class-a': [_first, _second, _afternoon],
    'class-b': [_first, _second, _afternoon],
  },
  fixedItems: const [],
  units: const [],
  checks: const [],
);
