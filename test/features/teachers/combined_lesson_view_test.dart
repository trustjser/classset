import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/features/teachers/domain/combined_lesson_view.dart';
import 'package:flutter_test/flutter_test.dart';

TeacherAssignment _assignment({
  required String id,
  required String classId,
  String teacherId = 't1',
  String subjectId = 's1',
  WeekMode weekMode = WeekMode.weekly,
  int lessonCount = 2,
  String? groupId,
  String termId = 'term1',
}) => TeacherAssignment(
  id: id,
  termId: termId,
  teacherId: teacherId,
  classId: classId,
  subjectId: subjectId,
  weekMode: weekMode,
  lessonCount: lessonCount,
  combinedLessonGroupId: groupId,
);

Map<String, ClassBrief> _classById() => {
  for (final i in [1, 2, 3, 4, 5, 6])
    'c$i': ClassBrief(
      stageId: 'stage1',
      gradeId: 'g1',
      id: 'c$i',
      name: '一年级 $i 班',
    ),
};

void main() {
  group('buildCombinedLessonGroups', () {
    test('只聚合带合班标识的记录，并按组收集成员', () {
      final groups = buildCombinedLessonGroups([
        _assignment(id: 'a1', classId: 'c1', groupId: 'g1'),
        _assignment(id: 'a2', classId: 'c2', groupId: 'g1'),
        _assignment(id: 'a3', classId: 'c3'),
        _assignment(id: 'a4', classId: 'c4', groupId: 'g2', teacherId: 't2'),
      ]);
      expect(groups, hasLength(2));
      expect(groups.first.id, 'g1');
      expect(
        groups.first.members.map((row) => row.classId).toList(),
        ['c1', 'c2'],
      );
      expect(groups.last.teacherId, 't2');
    });

    test('可按学期与教师过滤', () {
      final groups = buildCombinedLessonGroups(
        [
          _assignment(id: 'a1', classId: 'c1', groupId: 'g1'),
          _assignment(id: 'a2', classId: 'c2', groupId: 'g1', termId: 'term2'),
          _assignment(
            id: 'a3',
            classId: 'c3',
            groupId: 'g2',
            teacherId: 't2',
          ),
        ],
        termId: 'term1',
        teacherId: 't1',
      );
      expect(groups, hasLength(1));
      expect(groups.single.members, hasLength(1));
    });

    test('组名由参与班级派生', () {
      final groups = buildCombinedLessonGroups([
        _assignment(id: 'a1', classId: 'c1', groupId: 'g1'),
        _assignment(id: 'a2', classId: 'c2', groupId: 'g1'),
      ]);
      expect(groups.single.displayName(_classById()), '一年级 1、2 班合班');
    });
  });

  group('combinedLessonStats', () {
    test('统计组数、班级数与教师数，同组同班只算一次', () {
      final stats = combinedLessonStats([
        _assignment(id: 'a1', classId: 'c1', groupId: 'g1'),
        _assignment(id: 'a2', classId: 'c2', groupId: 'g1'),
        _assignment(id: 'a3', classId: 'c1', groupId: 'g1'),
        _assignment(id: 'a4', classId: 'c3', groupId: 'g2', teacherId: 't2'),
        _assignment(id: 'a5', classId: 'c4', groupId: 'g2', teacherId: 't2'),
        _assignment(id: 'a6', classId: 'c5'),
      ]);
      expect(stats.groupCount, 2);
      expect(stats.classCount, 4);
      expect(stats.teacherCount, 2);
      expect(stats.isEmpty, isFalse);
    });

    test('没有合班时为空（主界面汇总条据此隐藏）', () {
      final stats = combinedLessonStats([
        _assignment(id: 'a1', classId: 'c1'),
        _assignment(id: 'a2', classId: 'c2'),
      ]);
      expect(stats.isEmpty, isTrue);
      expect(stats.groupCount, 0);
    });
  });

  group('combinedLessonCandidateGroups', () {
    test('按科目、周模式、节数分组，只返回可合并（≥2 班）的组', () {
      final groups = combinedLessonCandidateGroups(
        [
          _assignment(id: 'a1', classId: 'c1'),
          _assignment(id: 'a2', classId: 'c2'),
          _assignment(id: 'a3', classId: 'c3', lessonCount: 3),
          _assignment(id: 'a4', classId: 'c4', weekMode: WeekMode.odd),
        ],
        teacherId: 't1',
      );
      expect(groups, hasLength(1));
      expect(
        groups.single.available.map((row) => row.classId).toList(),
        ['c1', 'c2'],
      );
      expect(groups.single.lessonCount, 2);
    });

    test('排除已合班的记录与其他教师的记录', () {
      final groups = combinedLessonCandidateGroups(
        [
          _assignment(id: 'a1', classId: 'c1', groupId: 'g1'),
          _assignment(id: 'a2', classId: 'c2'),
          _assignment(id: 'a3', classId: 'c3'),
          _assignment(id: 'a4', classId: 'c4', teacherId: 't2'),
        ],
        teacherId: 't1',
      );
      expect(groups, hasLength(1));
      expect(
        groups.single.available.map((row) => row.id).toList(),
        ['a2', 'a3'],
      );
    });

    test('同一班多条任课只保留一条，与 repository 校验一致', () {
      final groups = combinedLessonCandidateGroups(
        [
          _assignment(id: 'a1', classId: 'c1'),
          _assignment(id: 'a2', classId: 'c1'),
          _assignment(id: 'a3', classId: 'c2'),
        ],
        teacherId: 't1',
      );
      expect(groups, hasLength(1));
      expect(
        groups.single.available.map((row) => row.id).toList(),
        ['a1', 'a3'],
      );
    });

    test('同一教师有多组条件时全部返回，供界面先选条件组', () {
      final groups = combinedLessonCandidateGroups(
        [
          _assignment(id: 'a1', classId: 'c1', subjectId: 's1'),
          _assignment(id: 'a2', classId: 'c2', subjectId: 's1'),
          _assignment(
            id: 'a3',
            classId: 'c3',
            subjectId: 's2',
            lessonCount: 1,
          ),
          _assignment(
            id: 'a4',
            classId: 'c4',
            subjectId: 's2',
            lessonCount: 1,
          ),
        ],
        teacherId: 't1',
      );
      expect(groups, hasLength(2));
      expect(groups.map((group) => group.lessonCount).toSet(), {1, 2});
    });
  });

  group('deriveCombinedLessonName', () {
    test('中文班级名合并为「年级 X、Y 班合班」', () {
      expect(
        deriveCombinedLessonName(['一年级 1 班', '一年级 2 班']),
        '一年级 1、2 班合班',
      );
      expect(
        deriveCombinedLessonName(['一年级 3 班', '一年级 4 班', '一年级 5 班']),
        '一年级 3、4、5 班合班',
      );
    });

    test('命名不规则时退化为完整名单', () {
      expect(
        deriveCombinedLessonName(['实验班', '一年级 2 班']),
        '实验班、一年级 2 班 合班',
      );
      expect(deriveCombinedLessonName([]), '合班组');
    });
  });
}
