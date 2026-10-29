import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/schedule_reconciler.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('年级需求展开为班级需求时只报告真实节数变化', () {
    final term = AcademicTerm(
      id: 't',
      title: '学期',
      academicYear: '2027',
      semesterLabel: '第一学期',
      firstTeachingWeekStart: null,
      teachingWeekCount: 20,
      createdAt: DateTime(2027),
    );
    SchedulingSnapshot snapshot(List<SubjectRequirement> requirements) =>
        SchedulingSnapshot(
          term: term,
          inputFingerprint: 'test',
          grades: const [
            GradeGroup(id: 'g', stageId: 'stage', name: '一年级', sortOrder: 0),
          ],
          classes: const [
            ClassGroup(id: 'c1', gradeId: 'g', name: '一班', sortOrder: 0),
            ClassGroup(id: 'c2', gradeId: 'g', name: '二班', sortOrder: 1),
          ],
          subjects: const [
            Subject(id: 'math', name: '数学', shortName: '数', sortOrder: 0),
            Subject(id: 'pe', name: '体育与健康', shortName: '体育', sortOrder: 1),
          ],
          requirements: requirements,
        );
    const before = [
      SubjectRequirement(
        id: 'm',
        subjectId: 'math',
        gradeId: 'g',
        weekMode: WeekMode.weekly,
        lessonCount: 5,
      ),
      SubjectRequirement(
        id: 'p',
        subjectId: 'pe',
        gradeId: 'g',
        weekMode: WeekMode.weekly,
        lessonCount: 4,
      ),
    ];
    const after = [
      SubjectRequirement(
        id: 'm1',
        subjectId: 'math',
        gradeId: 'g',
        classId: 'c1',
        weekMode: WeekMode.weekly,
        lessonCount: 5,
      ),
      SubjectRequirement(
        id: 'm2',
        subjectId: 'math',
        gradeId: 'g',
        classId: 'c2',
        weekMode: WeekMode.weekly,
        lessonCount: 5,
      ),
      SubjectRequirement(
        id: 'p1',
        subjectId: 'pe',
        gradeId: 'g',
        classId: 'c1',
        weekMode: WeekMode.weekly,
        lessonCount: 2,
      ),
      SubjectRequirement(
        id: 'p2',
        subjectId: 'pe',
        gradeId: 'g',
        classId: 'c2',
        weekMode: WeekMode.weekly,
        lessonCount: 2,
      ),
    ];
    final changes = const ScheduleReconciler()
        .describeChanges(snapshot(before), snapshot(after))
        .where((change) => change.group == '科目节数')
        .toList();
    expect(changes, hasLength(1));
    expect(changes.single.label, contains('体育与健康'));
    expect(changes.single.before, '4 节');
    expect(changes.single.after, '2 节');
  });
}
