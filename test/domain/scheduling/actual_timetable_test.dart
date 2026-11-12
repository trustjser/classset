import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final snapshot = SchedulingSnapshot(
    term: AcademicTerm(
      id: 'term',
      title: '学期',
      academicYear: '2026',
      semesterLabel: '秋',
      firstTeachingWeekStart: DateTime(2026, 9, 7),
      teachingWeekCount: 4,
      createdAt: DateTime(2026, 9, 1),
    ),
    inputFingerprint: 'snapshot',
    grades: const [
      GradeGroup(id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0),
    ],
    classes: const [
      ClassGroup(id: 'class', gradeId: 'grade', name: '一班', sortOrder: 0),
    ],
    routines: const [
      StageRoutine(
        stageId: 'stage',
        teachingWeekdays: {1, 2},
        periodTypes: [
          LessonPeriodType(
            id: 'am',
            name: '上午',
            defaultLessonCount: 2,
            sortOrder: 0,
            lessonTimes: [],
          ),
        ],
        overrides: [],
      ),
    ],
    existingItems: const [
      ScheduleItem(
        id: 'lesson',
        termId: 'term',
        assignmentId: 'assignment',
        classId: 'class',
        teacherId: 'teacher',
        subjectId: 'subject',
        weekMode: WeekMode.odd,
        position: SchedulePosition(
          stageId: 'stage',
          weekday: 1,
          periodTypeId: 'am',
          lessonIndex: 1,
        ),
      ),
    ],
  );

  test('实际课次按单双周、停课和补课映射展开', () {
    final exceptions = [
      CalendarException(
        id: 'holiday',
        termId: 'term',
        date: DateTime(2026, 9, 7),
        kind: CalendarExceptionKind.holiday,
        makeupWeekday: null,
        note: '',
      ),
      CalendarException(
        id: 'makeup',
        termId: 'term',
        date: DateTime(2026, 9, 20),
        kind: CalendarExceptionKind.makeup,
        makeupWeekday: 1,
        makeupForDate: DateTime(2026, 9, 7),
        note: '',
      ),
    ];
    final occurrences = const ActualTimetable().expand(snapshot, exceptions);
    expect(occurrences.map((e) => e.date).toList(), [
      DateTime(2026, 9, 20),
      DateTime(2026, 9, 21),
    ]);
    expect(occurrences.first.item.id, 'lesson');
  });

  test('日期带班按周日补课来源展开并整岗替换', () {
    final date = DateTime(2026, 9, 13);
    const post = SupervisionPost(
      id: 'duty',
      kind: SupervisionKind.morningStudy,
      name: '晨读',
      stageId: 'stage',
      weekday: 1,
      periodTypeId: 'am',
      lessonIndices: [1, 2],
      classIds: ['class'],
    );
    final version = SupervisionVersion(
      termId: 'term',
      effectiveDate: DateTime(2026, 9, 7),
      draft: const SupervisionDraft(
        termId: 'term',
        posts: [post],
        teacherIds: {'teacher', 'substitute'},
        assignments: {'duty': 'teacher'},
      ),
      occurrences: [
        for (final index in post.lessonIndices)
          SupervisionOccurrence(
            post: post,
            teacherId: 'teacher',
            teacherName: '张老师',
            position: SchedulePosition(
              stageId: 'stage',
              weekday: 1,
              periodTypeId: 'am',
              lessonIndex: index,
            ),
            classNames: const ['一班'],
          ),
      ],
    );
    final occurrences = const ActualTimetable().expandSupervision(
      snapshot,
      [
        CalendarException(
          id: 'holiday',
          termId: 'term',
          date: DateTime(2026, 9, 7),
          kind: CalendarExceptionKind.holiday,
          makeupWeekday: null,
          note: '',
        ),
        CalendarException(
          id: 'makeup',
          termId: 'term',
          date: date,
          kind: CalendarExceptionKind.makeup,
          makeupWeekday: 1,
          makeupForDate: DateTime(2026, 9, 7),
          note: '',
        ),
      ],
      [version],
    );
    expect(occurrences.first.date, date);
    expect(occurrences.first.occurrences, hasLength(2));
    expect(
      occurrences.first.withTeacher('substitute', '李老师').teacherId,
      'substitute',
    );
    expect(version.occurrences.first.teacherId, 'teacher');
  });

  test('移课预览不会修改常规课表，并可在确认后投影到目标日期', () {
    final engine = const ActualTimetable();
    final lessons = engine.expand(snapshot, const []);
    final source = lessons.first;
    const destination = SchedulePosition(
      stageId: 'stage',
      weekday: 2,
      periodTypeId: 'am',
      lessonIndex: 2,
    );
    final preview = engine.previewMove(
      snapshot: snapshot,
      lessons: lessons,
      sourceKey: source.key,
      exceptions: const [],
      targetDate: DateTime(2026, 9, 8),
      targetPosition: destination,
    );
    expect(preview.errors, isEmpty);
    expect(source.date, DateTime(2026, 9, 7));
    expect(snapshot.existingItems.single.position!.weekday, 1);
    final projected = engine.apply(lessons, preview.changes);
    expect(projected.first.date, DateTime(2026, 9, 8));
    expect(projected.first.item.position!.lessonIndex, 2);
    expect(projected.first.key, source.key);
  });

  test('移课不得与教师同一实际日期的其他课程重叠', () {
    final engine = const ActualTimetable();
    final lessons = engine.expand(snapshot, const []);
    final occupied = ActualLesson(
      date: DateTime(2026, 9, 8),
      item: const ScheduleItem(
        id: 'other',
        termId: 'term',
        assignmentId: 'other',
        classId: 'other',
        teacherId: 'teacher',
        subjectId: 'other',
        weekMode: WeekMode.weekly,
        position: SchedulePosition(
          stageId: 'stage',
          weekday: 2,
          periodTypeId: 'am',
          lessonIndex: 2,
        ),
      ),
    );
    final preview = engine.previewMove(
      snapshot: snapshot,
      lessons: [...lessons, occupied],
      exceptions: const [],
      sourceKey: lessons.first.key,
      targetDate: occupied.date,
      targetPosition: occupied.item.position!,
    );
    expect(preview.errors, isNotEmpty);
    expect(preview.changes, isEmpty);
  });

  test('停课日不能作为移课目标', () {
    final engine = const ActualTimetable();
    final holiday = CalendarException(
      id: 'holiday',
      termId: 'term',
      date: DateTime(2026, 9, 8),
      kind: CalendarExceptionKind.holiday,
      makeupWeekday: null,
      note: '',
    );
    final lessons = engine.expand(snapshot, [holiday]);
    final result = engine.previewMove(
      snapshot: snapshot,
      lessons: lessons,
      exceptions: [holiday],
      sourceKey: lessons.first.key,
      targetDate: DateTime(2026, 9, 8),
      targetPosition: const SchedulePosition(
        stageId: 'stage',
        weekday: 2,
        periodTypeId: 'am',
        lessonIndex: 2,
      ),
    );
    expect(result.changes, isEmpty);
    expect(result.errors, isNotEmpty);
  });

  test('补课日与同周原教学日是不同自然日，不产生虚假冲突', () {
    final original = snapshot.existingItems.single;
    final other = ScheduleItem(
      id: 'other-slot',
      termId: original.termId,
      assignmentId: 'other',
      classId: original.classId,
      teacherId: 'another',
      subjectId: original.subjectId,
      weekMode: WeekMode.weekly,
      position: const SchedulePosition(
        stageId: 'stage',
        weekday: 1,
        periodTypeId: 'am',
        lessonIndex: 2,
      ),
    );
    final withOther = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: 'makeup',
      grades: snapshot.grades,
      classes: snapshot.classes,
      routines: snapshot.routines,
      existingItems: [original, other],
    );
    final makeup = CalendarException(
      id: 'makeup',
      termId: 'term',
      date: DateTime(2026, 9, 13),
      kind: CalendarExceptionKind.makeup,
      makeupWeekday: 1,
      makeupForDate: DateTime(2026, 9, 7),
      note: '',
    );
    final engine = const ActualTimetable();
    final lessons = engine
        .expand(withOther, [makeup])
        .where((lesson) => lesson.date != DateTime(2026, 9, 13))
        .toList();
    final source = lessons.firstWhere((lesson) => lesson.item.id == 'lesson');
    final preview = engine.previewMove(
      snapshot: withOther,
      lessons: lessons,
      exceptions: [makeup],
      sourceKey: source.key,
      targetDate: DateTime(2026, 9, 13),
      targetPosition: const SchedulePosition(
        stageId: 'stage',
        weekday: 1,
        periodTypeId: 'am',
        lessonIndex: 2,
      ),
    );
    expect(preview.errors, isEmpty);
    expect(preview.changes, hasLength(1));
  });

  test('换课作为一个整体同时交换两节课', () {
    final engine = const ActualTimetable();
    final first = engine.expand(snapshot, const []).first;
    final second = ActualLesson(
      date: DateTime(2026, 9, 8),
      item: const ScheduleItem(
        id: 'second',
        termId: 'term',
        assignmentId: 'second',
        classId: 'class',
        teacherId: 'other',
        subjectId: 'subject2',
        weekMode: WeekMode.weekly,
        position: SchedulePosition(
          stageId: 'stage',
          weekday: 2,
          periodTypeId: 'am',
          lessonIndex: 2,
        ),
      ),
    );
    final result = engine.previewSwap(
      snapshot: snapshot,
      lessons: [first, second],
      exceptions: const [],
      firstKey: first.key,
      secondKey: second.key,
    );
    expect(result.errors, isEmpty);
    expect(result.changes.length, 2);
    final updated = engine.apply([first, second], result.changes);
    expect(updated.first.date, DateTime(2026, 9, 8));
    expect(updated.last.date, DateTime(2026, 9, 7));

    final state = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: const [],
      records: const [],
      lessons: [first, second],
      revision: 'revision',
      reconciliationPending: false,
    );
    final stateResult = state.previewSwap(
      TemporarySwapRequest(firstKey: first.key, secondKey: second.key),
    );
    expect(stateResult.changes, hasLength(2));
    final nextFirst = engine.expand(snapshot, const []).last;
    final nextSecond = ActualLesson(
      date: DateTime(2026, 9, 22),
      item: second.item,
    );
    final rangeState = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: const [],
      records: const [],
      lessons: [first, second, nextFirst, nextSecond],
      revision: 'v',
      reconciliationPending: false,
    );
    final range = rangeState.previewSwap(
      TemporarySwapRequest(
        firstKey: first.key,
        secondKey: second.key,
        rangeStart: DateTime(2026, 9, 7),
        rangeEnd: DateTime(2026, 10, 4),
      ),
    );
    expect(range.errors, isEmpty);
    expect(range.changes, hasLength(4));
  });

  test('移课不能绕过科目不排预设', () {
    final restricted = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: snapshot.inputFingerprint,
      grades: snapshot.grades,
      classes: snapshot.classes,
      routines: snapshot.routines,
      existingItems: snapshot.existingItems,
      subjectPresets: const [
        SubjectPreset(
          id: 'forbid',
          subjectId: 'subject',
          scope: FreeSlotScope.schoolClass,
          scopeId: 'class',
          stageId: 'stage',
          weekday: 2,
          periodTypeId: 'am',
          lessonIndex: 2,
          value: PresetValue.forbid,
        ),
      ],
    );
    final engine = const ActualTimetable();
    final lessons = engine.expand(restricted, const []);
    final result = engine.previewMove(
      snapshot: restricted,
      lessons: lessons,
      exceptions: const [],
      sourceKey: lessons.first.key,
      targetDate: DateTime(2026, 9, 8),
      targetPosition: const SchedulePosition(
        stageId: 'stage',
        weekday: 2,
        periodTypeId: 'am',
        lessonIndex: 2,
      ),
    );
    expect(result.changes, isEmpty);
    expect(result.errors, isNotEmpty);
  });

  test('移课不能使原有一定排位置失效', () {
    final restricted = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: 'must',
      grades: snapshot.grades,
      classes: snapshot.classes,
      routines: snapshot.routines,
      existingItems: snapshot.existingItems,
      subjectPresets: const [
        SubjectPreset(
          id: 'must',
          subjectId: 'subject',
          scope: FreeSlotScope.schoolClass,
          scopeId: 'class',
          stageId: 'stage',
          weekday: 1,
          periodTypeId: 'am',
          lessonIndex: 1,
          value: PresetValue.must,
        ),
      ],
    );
    final engine = const ActualTimetable();
    final lessons = engine.expand(restricted, const []);
    final preview = engine.previewMove(
      snapshot: restricted,
      lessons: lessons,
      exceptions: const [],
      sourceKey: lessons.first.key,
      targetDate: DateTime(2026, 9, 8),
      targetPosition: const SchedulePosition(
        stageId: 'stage',
        weekday: 2,
        periodTypeId: 'am',
        lessonIndex: 2,
      ),
    );
    expect(preview.errors, isNotEmpty);
    expect(preview.changes, isEmpty);
  });

  test('代课只改变选定课次的教师，其他日期保持原教师', () {
    final withTeachers = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: snapshot.inputFingerprint,
      grades: snapshot.grades,
      classes: snapshot.classes,
      routines: snapshot.routines,
      existingItems: snapshot.existingItems,
      teachers: const [
        Teacher(id: 'teacher', name: '李', shortName: '李', sortOrder: 0),
        Teacher(id: 'substitute', name: '王', shortName: '王', sortOrder: 1),
      ],
    );
    final engine = const ActualTimetable();
    final lessons = engine.expand(withTeachers, const []);
    final result = engine.previewSubstitute(
      snapshot: withTeachers,
      lessons: lessons,
      exceptions: const [],
      sourceKey: lessons.first.key,
      teacherId: 'substitute',
    );
    expect(result.errors, isEmpty);
    final projected = engine.apply(lessons, result.changes);
    expect(projected.first.item.teacherId, 'substitute');
    expect(projected.last.item.teacherId, 'teacher');
    expect(projected.first.date, lessons.first.date);
    final state = TemporaryTimetableState(
      snapshot: withTeachers,
      exceptions: const [],
      records: const [],
      lessons: lessons,
      revision: 'v',
      reconciliationPending: false,
    );
    final range = state.previewSubstitute(
      TemporarySubstituteRequest(
        sourceKey: lessons.first.key,
        teacherId: 'substitute',
        rangeStart: DateTime(2026, 9, 7),
        rangeEnd: DateTime(2026, 10, 4),
      ),
    );
    expect(range.errors, isEmpty);
    expect(range.changes, hasLength(2));
  });

  test('日期范围展开实际出现的单周课次，停课日不会生成调整', () {
    final exception = CalendarException(
      id: 'closed',
      termId: 'term',
      date: DateTime(2026, 9, 21),
      kind: CalendarExceptionKind.holiday,
      makeupWeekday: null,
      note: '',
    );
    final engine = const ActualTimetable();
    final lessons = engine.expand(snapshot, [exception]);
    final state = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: [exception],
      records: const [],
      lessons: lessons,
      revision: 'v',
      reconciliationPending: false,
    );
    final preview = state.previewMove(
      TemporaryMoveRequest(
        sourceKey: lessons.first.key,
        targetDate: DateTime(2026, 9, 8),
        targetPosition: const SchedulePosition(
          stageId: 'stage',
          weekday: 2,
          periodTypeId: 'am',
          lessonIndex: 2,
        ),
        rangeStart: DateTime(2026, 9, 7),
        rangeEnd: DateTime(2026, 10, 4),
      ),
    );
    expect(preview.errors, isEmpty);
    expect(preview.changes, hasLength(1));
    expect(preview.skippedDates, contains(DateTime(2026, 9, 21)));
  });

  test('范围内冲突课次可显式移除后重新预览', () {
    final engine = const ActualTimetable();
    final lessons = engine.expand(snapshot, const []);
    final occupied = ActualLesson(
      date: DateTime(2026, 9, 22),
      item: const ScheduleItem(
        id: 'occupied',
        termId: 'term',
        assignmentId: 'a',
        classId: 'class',
        teacherId: 'teacher',
        subjectId: 'subject',
        weekMode: WeekMode.weekly,
        position: SchedulePosition(
          stageId: 'stage',
          weekday: 2,
          periodTypeId: 'am',
          lessonIndex: 2,
        ),
      ),
    );
    final state = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: const [],
      records: const [],
      lessons: [...lessons, occupied],
      revision: 'v',
      reconciliationPending: false,
    );
    TemporaryMoveRequest request(Set<DateTime> excluded) =>
        TemporaryMoveRequest(
          sourceKey: lessons.first.key,
          targetDate: DateTime(2026, 9, 8),
          targetPosition: occupied.item.position!,
          rangeStart: DateTime(2026, 9, 7),
          rangeEnd: DateTime(2026, 10, 4),
          excludedDates: excluded,
        );
    expect(state.previewMove(request({})).errors, isNotEmpty);
    final corrected = state.previewMove(request({DateTime(2026, 9, 21)}));
    expect(corrected.errors, isEmpty);
    expect(corrected.changes, hasLength(1));
  });

  test('跨周范围移课按原始课次定位，不会再次选中刚移入的课', () {
    final original = snapshot.existingItems.single;
    final weekly = ScheduleItem(
      id: original.id,
      termId: original.termId,
      assignmentId: original.assignmentId,
      classId: original.classId,
      teacherId: original.teacherId,
      subjectId: original.subjectId,
      weekMode: WeekMode.weekly,
      position: original.position,
    );
    final repeated = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: 'weekly',
      grades: snapshot.grades,
      classes: snapshot.classes,
      routines: snapshot.routines,
      existingItems: [weekly],
    );
    final engine = const ActualTimetable();
    final lessons = engine.expand(repeated, const []);
    final state = TemporaryTimetableState(
      snapshot: repeated,
      exceptions: const [],
      records: const [],
      lessons: lessons,
      revision: 'v',
      reconciliationPending: false,
    );
    final move = TemporaryMoveRequest(
      sourceKey: lessons.first.key,
      targetDate: DateTime(2026, 9, 14),
      targetPosition: const SchedulePosition(
        stageId: 'stage',
        weekday: 1,
        periodTypeId: 'am',
        lessonIndex: 2,
      ),
      rangeStart: DateTime(2026, 9, 7),
      rangeEnd: DateTime(2026, 10, 4),
      excludedDates: {DateTime(2026, 9, 28)},
    );
    final preview = state.previewMove(move);
    expect(preview.errors, isEmpty);
    expect(
      preview.changes.map((change) => change.before.key).toSet().length,
      3,
    );
    expect(preview.changes.map((change) => change.before.date).toList(), [
      DateTime(2026, 9, 7),
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 21),
    ]);
    final swap = state.previewSwap(
      TemporarySwapRequest(
        firstKey: lessons[0].key,
        secondKey: lessons[1].key,
        rangeStart: DateTime(2026, 9, 7),
        rangeEnd: DateTime(2026, 9, 27),
      ),
    );
    expect(swap.errors, isNotEmpty);
  });

  test('失效记录不阻塞其他班级和教师的不相关调整', () {
    final engine = const ActualTimetable();
    final lessons = engine.expand(snapshot, const []);
    final unrelated = ActualLesson(
      date: DateTime(2026, 9, 7),
      item: const ScheduleItem(
        id: 'unrelated',
        termId: 'term',
        assignmentId: 'a',
        classId: 'other-class',
        teacherId: 'other-teacher',
        subjectId: 's',
        weekMode: WeekMode.weekly,
        position: SchedulePosition(
          stageId: 'stage',
          weekday: 1,
          periodTypeId: 'am',
          lessonIndex: 1,
        ),
      ),
    );
    final invalid = TemporaryAdjustmentRecord(
      id: 'invalid',
      kind: 'move',
      changes: [ActualLessonChange(before: unrelated, after: unrelated)],
      reason: '',
      createdAt: DateTime(2026, 9, 1),
      needsAttention: true,
    );
    final state = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: const [],
      records: [invalid],
      lessons: lessons,
      revision: 'v',
      reconciliationPending: false,
    );
    final preview = state.previewMove(
      TemporaryMoveRequest(
        sourceKey: lessons.first.key,
        targetDate: DateTime(2026, 9, 8),
        targetPosition: const SchedulePosition(
          stageId: 'stage',
          weekday: 2,
          periodTypeId: 'am',
          lessonIndex: 2,
        ),
      ),
    );
    expect(preview.errors, isEmpty);
    final sameTeacher = ActualLesson(
      date: DateTime(2026, 9, 8),
      item: const ScheduleItem(
        id: 'related',
        termId: 'term',
        assignmentId: 'a',
        classId: 'other-class',
        teacherId: 'teacher',
        subjectId: 's',
        weekMode: WeekMode.weekly,
        position: SchedulePosition(
          stageId: 'stage',
          weekday: 2,
          periodTypeId: 'am',
          lessonIndex: 2,
        ),
      ),
    );
    final relatedState = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: const [],
      records: [
        TemporaryAdjustmentRecord(
          id: 'invalid-related',
          kind: 'move',
          changes: [
            ActualLessonChange(before: sameTeacher, after: sameTeacher),
          ],
          reason: '',
          createdAt: DateTime(2026, 9, 1),
          needsAttention: true,
        ),
      ],
      lessons: lessons,
      revision: 'v',
      reconciliationPending: false,
    );
    final related = relatedState.previewMove(
      TemporaryMoveRequest(
        sourceKey: lessons.first.key,
        targetDate: DateTime(2026, 9, 8),
        targetPosition: const SchedulePosition(
          stageId: 'stage',
          weekday: 2,
          periodTypeId: 'am',
          lessonIndex: 2,
        ),
      ),
    );
    expect(related.errors, isNotEmpty);
  });

  test('跨学段教师冲突从作息读取时间，不依赖传入位置包含时钟', () {
    final crossStage = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: 'cross-stage',
      grades: const [
        GradeGroup(id: 'grade', stageId: 'stage', name: '一', sortOrder: 0),
        GradeGroup(id: 'grade2', stageId: 'stage2', name: '二', sortOrder: 1),
      ],
      classes: const [
        ClassGroup(id: 'class', gradeId: 'grade', name: '一班', sortOrder: 0),
        ClassGroup(id: 'class2', gradeId: 'grade2', name: '二班', sortOrder: 0),
      ],
      routines: const [
        StageRoutine(
          stageId: 'stage',
          teachingWeekdays: {1, 2},
          periodTypes: [
            LessonPeriodType(
              id: 'am',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '',
                  startMinute: 480,
                  endMinute: 520,
                ),
              ],
            ),
          ],
          overrides: [],
        ),
        StageRoutine(
          stageId: 'stage2',
          teachingWeekdays: {2},
          periodTypes: [
            LessonPeriodType(
              id: 'am2',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '',
                  startMinute: 500,
                  endMinute: 540,
                ),
              ],
            ),
          ],
          overrides: [],
        ),
      ],
      existingItems: [
        snapshot.existingItems.single,
        const ScheduleItem(
          id: 'other',
          termId: 'term',
          assignmentId: 'other',
          classId: 'class2',
          teacherId: 'teacher',
          subjectId: 'subject',
          weekMode: WeekMode.weekly,
          position: SchedulePosition(
            stageId: 'stage2',
            weekday: 2,
            periodTypeId: 'am2',
            lessonIndex: 1,
          ),
        ),
      ],
    );
    final engine = const ActualTimetable();
    final lessons = engine.expand(crossStage, const []);
    final source = lessons.firstWhere((lesson) => lesson.item.id == 'lesson');
    final result = engine.previewMove(
      snapshot: crossStage,
      lessons: lessons,
      exceptions: const [],
      sourceKey: source.key,
      targetDate: DateTime(2026, 9, 8),
      targetPosition: const SchedulePosition(
        stageId: 'stage',
        weekday: 2,
        periodTypeId: 'am',
        lessonIndex: 1,
      ),
    );
    expect(result.changes, isEmpty);
    expect(
      result.errors,
      contains(
        '换入「subject（teacher）」时，教师「teacher」在'
        '9月8日（周二）上午第2节已为「other」上「other（teacher）」',
      ),
    );
  });

  test('跨学段共用场室缺少时间时不能提交调整', () {
    final shared = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: 'room',
      grades: const [
        GradeGroup(id: 'grade', stageId: 'stage', name: '一', sortOrder: 0),
        GradeGroup(id: 'grade2', stageId: 'stage2', name: '二', sortOrder: 1),
      ],
      classes: const [
        ClassGroup(id: 'class', gradeId: 'grade', name: '一班', sortOrder: 0),
        ClassGroup(id: 'class2', gradeId: 'grade2', name: '二班', sortOrder: 0),
      ],
      routines: [
        ...snapshot.routines,
        const StageRoutine(
          stageId: 'stage2',
          teachingWeekdays: {2},
          periodTypes: [
            LessonPeriodType(
              id: 'am2',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
          overrides: [],
        ),
      ],
      existingItems: snapshot.existingItems,
      roomAssignments: const [
        SubjectRoomAssignment(
          id: 'r1',
          subjectId: 'subject',
          termId: 'term',
          stageId: 'stage',
          scope: FreeSlotScope.stage,
          scopeId: 'stage',
          roomId: 'room',
        ),
        SubjectRoomAssignment(
          id: 'r2',
          subjectId: 'other',
          termId: 'term',
          stageId: 'stage2',
          scope: FreeSlotScope.stage,
          scopeId: 'stage2',
          roomId: 'room',
        ),
      ],
    );
    final lessons = const ActualTimetable().expand(shared, const []);
    final preview = const ActualTimetable().previewMove(
      snapshot: shared,
      lessons: lessons,
      exceptions: const [],
      sourceKey: lessons.first.key,
      targetDate: DateTime(2026, 9, 8),
      targetPosition: const SchedulePosition(
        stageId: 'stage',
        weekday: 2,
        periodTypeId: 'am',
        lessonIndex: 2,
      ),
    );
    expect(preview.errors.any((error) => error.contains('时间')), isTrue);
    expect(preview.changes, isEmpty);
  });

  test('合班课必须整组移动，涉及班级同步更新', () {
    final first = snapshot.existingItems.single;
    ScheduleItem grouped(String id, String classId) => ScheduleItem(
      id: id,
      termId: first.termId,
      assignmentId: id,
      classId: classId,
      teacherId: first.teacherId,
      subjectId: first.subjectId,
      weekMode: first.weekMode,
      meetingId: 'meeting',
      combinedGroupId: 'group',
      position: first.position,
    );
    final groupedSnapshot = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: 'group',
      grades: snapshot.grades,
      classes: [
        ...snapshot.classes,
        const ClassGroup(
          id: 'class2',
          gradeId: 'grade',
          name: '二班',
          sortOrder: 1,
        ),
      ],
      routines: snapshot.routines,
      existingItems: [grouped('one', 'class'), grouped('two', 'class2')],
    );
    final engine = const ActualTimetable();
    final lessons = engine.expand(groupedSnapshot, const []);
    final source = lessons.firstWhere((lesson) => lesson.item.id == 'one');
    final preview = engine.previewMove(
      snapshot: groupedSnapshot,
      lessons: lessons,
      exceptions: const [],
      sourceKey: source.key,
      targetDate: DateTime(2026, 9, 8),
      targetPosition: const SchedulePosition(
        stageId: 'stage',
        weekday: 2,
        periodTypeId: 'am',
        lessonIndex: 2,
      ),
    );
    expect(preview.errors, isEmpty);
    expect(preview.changes, hasLength(2));
    expect(preview.changes.map((change) => change.after.date).toSet(), {
      DateTime(2026, 9, 8),
    });
    expect(preview.changes.map((change) => change.after.item.classId).toSet(), {
      'class',
      'class2',
    });
    final occupied = ActualLesson(
      date: DateTime(2026, 9, 8),
      item: const ScheduleItem(
        id: 'occupied',
        termId: 'term',
        assignmentId: 'other',
        classId: 'class2',
        teacherId: 'other',
        subjectId: 'other',
        weekMode: WeekMode.weekly,
        position: SchedulePosition(
          stageId: 'stage',
          weekday: 2,
          periodTypeId: 'am',
          lessonIndex: 2,
        ),
      ),
    );
    final rejected = engine.previewMove(
      snapshot: groupedSnapshot,
      lessons: [...lessons, occupied],
      exceptions: const [],
      sourceKey: source.key,
      targetDate: DateTime(2026, 9, 8),
      targetPosition: occupied.item.position!,
    );
    expect(rejected.errors, isNotEmpty);
    expect(rejected.changes, isEmpty);
    final withTeacher = SchedulingSnapshot(
      term: groupedSnapshot.term,
      inputFingerprint: 'group',
      grades: groupedSnapshot.grades,
      classes: groupedSnapshot.classes,
      routines: groupedSnapshot.routines,
      existingItems: groupedSnapshot.existingItems,
      teachers: const [
        Teacher(id: 'teacher', name: '李', shortName: '李', sortOrder: 0),
        Teacher(id: 'substitute', name: '王', shortName: '王', sortOrder: 1),
      ],
    );
    final sub = engine.previewSubstitute(
      snapshot: withTeacher,
      lessons: lessons,
      exceptions: const [],
      sourceKey: source.key,
      teacherId: 'substitute',
    );
    expect(sub.errors, isEmpty);
    expect(sub.changes, hasLength(2));
    expect(sub.changes.map((change) => change.after.item.teacherId).toSet(), {
      'substitute',
    });
    ScheduleItem otherGroup(String id, String classId) => ScheduleItem(
      id: id,
      termId: 'term',
      assignmentId: id,
      classId: classId,
      teacherId: 'other',
      subjectId: 'subject2',
      weekMode: WeekMode.weekly,
      meetingId: 'other-meeting',
      combinedGroupId: 'other-group',
      position: const SchedulePosition(
        stageId: 'stage',
        weekday: 2,
        periodTypeId: 'am',
        lessonIndex: 2,
      ),
    );
    final otherLessons = [
      ActualLesson(
        date: DateTime(2026, 9, 8),
        item: otherGroup('other-one', 'class'),
      ),
      ActualLesson(
        date: DateTime(2026, 9, 8),
        item: otherGroup('other-two', 'class2'),
      ),
    ];
    final swap = engine.previewSwap(
      snapshot: withTeacher,
      lessons: [...lessons, ...otherLessons],
      exceptions: const [],
      firstKey: source.key,
      secondKey: otherLessons.first.key,
    );
    expect(swap.errors, isEmpty);
    expect(swap.changes, hasLength(4));
  });
}
