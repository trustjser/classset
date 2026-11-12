import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/supervision_allocator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('优先安排受限岗位并保留合法手动指派', () {
    const first = SupervisionPost(
      id: 'flexible',
      kind: SupervisionKind.eveningStudy,
      name: '晚自习',
      stageId: 'stage',
      weekday: 7,
      periodTypeId: 'evening',
      lessonIndices: [1],
      classIds: ['first'],
    );
    const second = SupervisionPost(
      id: 'restricted',
      kind: SupervisionKind.eveningStudy,
      name: '晚自习',
      stageId: 'stage',
      weekday: 7,
      periodTypeId: 'evening',
      lessonIndices: [1, 2],
      classIds: ['second'],
    );
    final snapshot = SchedulingSnapshot(
      term: AcademicTerm(
        id: 'term',
        title: '学期',
        academicYear: '',
        semesterLabel: '',
        firstTeachingWeekStart: null,
        teachingWeekCount: 20,
        createdAt: DateTime(2026),
      ),
      inputFingerprint: '',
      teachers: const [
        Teacher(id: 'a', name: '张', shortName: '张', sortOrder: 0),
        Teacher(id: 'b', name: '李', shortName: '李', sortOrder: 1),
      ],
    );
    const draft = SupervisionDraft(
      termId: 'term',
      posts: [first, second],
      teacherIds: {'a', 'b'},
      rules: {
        'b': SupervisionTeacherRule(
          unavailable: [
            SchedulePosition(
              stageId: 'stage',
              weekday: 7,
              periodTypeId: 'evening',
              lessonIndex: 2,
            ),
          ],
        ),
      },
    );
    const allocator = SupervisionAllocator();
    expect(allocator.fill(snapshot, draft).assignments, {
      'flexible': 'b',
      'restricted': 'a',
    });
    final fixed = draft.copyWith(
      assignments: {'flexible': 'a'},
      manualPostIds: {'flexible'},
    );
    expect(allocator.fill(snapshot, fixed).assignments, {'flexible': 'a'});
    final restricted = draft.copyWith(
      rules: {...draft.rules, 'a': const SupervisionTeacherRule(maxLessons: 0)},
    );
    expect(allocator.fill(snapshot, restricted).assignments, {'flexible': 'b'});
  });
}
