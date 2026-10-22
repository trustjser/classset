import 'package:flutter_test/flutter_test.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/models/combined_lesson_group.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/domain/models/teacher_preset.dart';

void main() {
  group('Teacher', () {
    test('formats stable identity and display qualifier', () {
      const teacher = Teacher(
        id: 't-1',
        name: '王老师',
        shortName: '王',
        displayQualifier: '跨学段',
        sortOrder: 2,
      );

      expect(teacher.displayName, '王老师（跨学段）');
      expect(teacher.searchText, contains('王老师'));
      expect(teacher.searchText, contains('王'));
    });

    test(
      'stores subject tags without turning them into assignment restrictions',
      () {
        const teacher = Teacher(
          id: 't-1',
          name: '王老师',
          shortName: '王',
          sortOrder: 0,
          subjectIds: {'math', 'science'},
        );

        expect(teacher.subjectIds, containsAll(<String>['math', 'science']));
        expect(teacher.canTeach('art'), isTrue);
        expect(teacher.canTeach('math'), isTrue);
      },
    );
  });

  group('teacher assignment statistics', () {
    test('calculates biweekly average and odd/even totals', () {
      const assignments = [
        TeacherAssignment(
          id: 'a-1',
          termId: 'term-1',
          teacherId: 't-1',
          classId: 'c-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
        TeacherAssignment(
          id: 'a-2',
          termId: 'term-1',
          teacherId: 't-1',
          classId: 'c-2',
          subjectId: 'science',
          weekMode: WeekMode.odd,
          lessonCount: 2,
        ),
        TeacherAssignment(
          id: 'a-3',
          termId: 'term-1',
          teacherId: 't-1',
          classId: 'c-3',
          subjectId: 'art',
          weekMode: WeekMode.even,
          lessonCount: 4,
        ),
      ];

      final summary = TeacherAssignmentSummary.from(assignments);
      expect(summary.weekly, 4);
      expect(summary.odd, 6);
      expect(summary.even, 8);
      expect(summary.biweeklyAverage, 7);
    });

    test('counts a combined lesson group once in teacher workload', () {
      const assignments = [
        TeacherAssignment(
          id: 'a-1',
          termId: 'term-1',
          teacherId: 't-1',
          classId: 'c-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 3,
          combinedLessonGroupId: 'combined-1',
        ),
        TeacherAssignment(
          id: 'a-2',
          termId: 'term-1',
          teacherId: 't-1',
          classId: 'c-2',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 3,
          combinedLessonGroupId: 'combined-1',
        ),
        TeacherAssignment(
          id: 'a-3',
          termId: 'term-1',
          teacherId: 't-1',
          classId: 'c-3',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
      ];

      final summary = TeacherAssignmentSummary.from(assignments);
      expect(summary.weekly, 5);
      expect(summary.odd, 5);
      expect(summary.even, 5);
    });
  });

  group('teacher groups and presets', () {
    test('supports multiple memberships', () {
      const group = TeacherGroup(
        id: 'g-1',
        termId: 'term-1',
        name: '班主任组',
        sortOrder: 0,
      );
      const member = TeacherGroupMember(
        id: 'm-1',
        groupId: 'g-1',
        teacherId: 't-1',
      );

      expect(group.id, member.groupId);
      expect(member.teacherId, 't-1');
    });

    test('personal preset overrides group, including explicit auto', () {
      const groups = [
        TeacherGroupPreset(
          id: 'gp-1',
          groupId: 'g-1',
          scope: TeacherPresetScope.school,
          scopeId: 'term-1',
          stageId: 'stage-1',
          weekday: 1,
          periodTypeId: 'am',
          lessonIndex: 1,
          value: PresetValue.forbid,
        ),
      ];
      final groupValue = resolveTeacherPreset(personal: null, groups: groups);
      expect(groupValue, PresetValue.forbid);

      final personalAuto = TeacherPreset(
        id: 'tp-1',
        teacherId: 't-1',
        scope: TeacherPresetScope.school,
        scopeId: 'term-1',
        stageId: 'stage-1',
        weekday: 1,
        periodTypeId: 'am',
        lessonIndex: 1,
        value: PresetValue.auto,
      );
      expect(
        resolveTeacherPreset(personal: personalAuto, groups: groups),
        PresetValue.auto,
      );
    });

    test('rejects conflicting group rules', () {
      TeacherGroupPreset preset(PresetValue value, String id) =>
          TeacherGroupPreset(
            id: id,
            groupId: id,
            scope: TeacherPresetScope.school,
            scopeId: 'term-1',
            stageId: 'stage-1',
            weekday: 1,
            periodTypeId: 'am',
            lessonIndex: 1,
            value: value,
          );

      expect(
        () => resolveTeacherPreset(
          personal: null,
          groups: [
            preset(PresetValue.must, 'g-1'),
            preset(PresetValue.forbid, 'g-2'),
          ],
        ),
        throwsA(isA<TeacherPresetConflictException>()),
      );
    });
  });

  test(
    'only combines lessons with the same teacher subject week and range',
    () {
      final base = <String, Object>{
        'teacherId': 't-1',
        'subjectId': 'math',
        'weekMode': WeekMode.weekly,
        'startLesson': 1,
        'endLesson': 2,
      };
      expect(
        canCombineLessons(
          teacherId: base['teacherId']! as String,
          subjectId: base['subjectId']! as String,
          weekMode: base['weekMode']! as WeekMode,
          otherTeacherId: 't-1',
          otherSubjectId: 'math',
          otherWeekMode: WeekMode.weekly,
          startLesson: 1,
          endLesson: 2,
          otherStartLesson: 1,
          otherEndLesson: 2,
        ),
        isTrue,
      );
      expect(
        canCombineLessons(
          teacherId: 't-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          otherTeacherId: 't-1',
          otherSubjectId: 'math',
          otherWeekMode: WeekMode.weekly,
          startLesson: 1,
          endLesson: 2,
          otherStartLesson: 2,
          otherEndLesson: 3,
        ),
        isFalse,
      );
    },
  );
}
