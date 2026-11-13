import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/supervision_allocator.dart';
import 'package:class_set/domain/scheduling/supervision_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const allocator = SupervisionAllocator();
  test('指定池与默认池互不借人，空池缺岗而不扩池', () {
    final draft = configured(
      posts: [
        post('one', 1, pool: 'math'),
        post('two', 2),
      ],
      pools: [
        pool('math', ['b']),
      ],
    );
    expect(allocator.fill(snapshot(), draft).assignments, {
      'one': 'b',
      'two': 'a',
    });
    final empty = configured(
      posts: [post('one', 1, pool: 'empty')],
      pools: [pool('empty', [])],
    );
    expect(allocator.fill(snapshot(), empty).assignments, isEmpty);
    expect(
      allocator.teacherBlockers(snapshot(), draft, draft.posts.first, 'a'),
      isNotEmpty,
    );
    final missing = configured(posts: [post('one', 1, pool: 'gone')]);
    expect(allocator.fill(snapshot(), missing).assignments, isEmpty);
  });
  test('匹配优先按实际任课班级，均衡优先可由池内其他教师补位', () {
    final posts = [post('one', 1), post('two', 2)];
    final match = configured(
      posts: posts,
      teachers: ['a', 'b'],
      prefs: prefs(),
    );
    expect(allocator.fill(snapshot(), match).assignments, {
      'one': 'b',
      'two': 'b',
    });
    final balanced = configured(
      posts: posts,
      teachers: ['a', 'b'],
      prefs: prefs(mode: 'balanceFirst'),
    );
    expect(allocator.fill(snapshot(), balanced).assignments.values.toSet(), {
      'a',
      'b',
    });
  });
  test('调整偏好顺序改变结果，指定学科使用本学期实际任课', () {
    final posts = [
      post('one', 1, subjects: ['math']),
    ];
    final classFirst = configured(
      posts: posts,
      teachers: ['a', 'b'],
      prefs: prefs(enabled: ['classTeacher', 'subjectTeacher']),
    );
    expect(allocator.fill(snapshot(), classFirst).assignments, {'one': 'b'});
    final subjectFirst = configured(
      posts: posts,
      teachers: ['a', 'b'],
      prefs: prefs(
        order: ['subjectTeacher', 'classTeacher', 'gradeTeacher'],
        enabled: ['classTeacher', 'subjectTeacher'],
      ),
    );
    expect(allocator.fill(snapshot(), subjectFirst).assignments, {'one': 'a'});
  });
  test('必须符合任一或全部，岗位覆盖可恢复软匹配', () {
    final one = post('one', 1, subjects: ['math']);
    final any = configured(
      posts: [one],
      teachers: ['a', 'b'],
      prefs: prefs(
        enabled: ['classTeacher', 'subjectTeacher'],
        requirement: 'any',
      ),
    );
    expect(
      allocator.teacherBlockers(snapshot(), any, any.posts.single, 'a'),
      isEmpty,
    );
    expect(
      allocator.teacherBlockers(snapshot(), any, any.posts.single, 'b'),
      isEmpty,
    );
    final all = configured(
      posts: [one],
      teachers: ['a', 'b'],
      prefs: prefs(
        enabled: ['classTeacher', 'subjectTeacher'],
        requirement: 'all',
      ),
    );
    expect(allocator.fill(snapshot(), all).assignments, isEmpty);
    final override = configured(
      posts: [
        {...one, 'matchingPreferences': prefs(enabled: [])},
      ],
      teachers: ['a', 'b'],
      prefs: prefs(requirement: 'all'),
    );
    expect(allocator.fill(snapshot(), override).assignments, isNotEmpty);
  });
  test('本年级关系按实际任课推导，合班硬条件要求覆盖全部来源班', () {
    final grade = configured(
      posts: [post('one', 1)],
      teachers: ['a'],
      prefs: prefs(enabled: ['gradeTeacher'], requirement: 'all'),
    );
    expect(allocator.fill(snapshot(), grade).assignments, {'one': 'a'});
    final merged = configured(
      posts: [
        {
          ...post('merged', 1),
          'classIds': ['c1', 'c2'],
        },
      ],
      teachers: ['a', 'b'],
      prefs: prefs(enabled: ['classTeacher'], requirement: 'all'),
    );
    expect(allocator.fill(snapshot(), merged).assignments, isEmpty);
    final soft = configured(
      posts: [
        {
          ...post('merged', 1),
          'classIds': ['c1', 'c2'],
        },
      ],
      teachers: ['a', 'b'],
      prefs: prefs(enabled: ['classTeacher']),
    );
    expect(
      allocator
          .fill(
            snapshot().copyWith(
              assignments: [
                ...snapshot().assignments,
                const TeacherAssignment(
                  id: 'b2',
                  termId: 't',
                  teacherId: 'b',
                  classId: 'c2',
                  subjectId: 'chinese',
                  weekMode: WeekMode.weekly,
                  lessonCount: 2,
                ),
              ],
            ),
            soft,
          )
          .assignments,
      {'merged': 'b'},
    );
  });
  test('不同候选池共用教师负载上限，且覆盖数优先于偏好', () {
    final draft = configured(
      posts: [
        post('one', 1, pool: 'p1'),
        post('two', 2, pool: 'p2'),
      ],
      teachers: ['a'],
      pools: [
        pool('p1', ['b']),
        pool('p2', ['b']),
      ],
      rules: {'b': const SupervisionTeacherRule(maxLessons: 1).toJson()},
    );
    expect(allocator.fill(snapshot(), draft).assignments.length, 1);
    final coverage = configured(
      posts: [
        post('one', 1),
        post('two', 1, pool: 'p'),
      ],
      teachers: ['a', 'b'],
      pools: [
        pool('p', ['b']),
      ],
      prefs: prefs(),
    );
    expect(allocator.fill(snapshot(), coverage).assignments, {
      'one': 'a',
      'two': 'b',
    });
  });
  test('设置改变保留手动指派，并在统一校验中报告池外教师', () {
    final draft = configured(
      posts: [post('one', 1, pool: 'p')],
      pools: [
        pool('p', ['b']),
      ],
    ).copyWith(assignments: {'one': 'a'}, manualPostIds: {'one'});
    final next = allocator.fill(snapshot(), draft);
    expect(next.assignments, {'one': 'a'});
    expect(
      allocator.teacherBlockers(snapshot(), next, next.posts.single, 'a'),
      isNotEmpty,
    );
  });
  test('失效候选池或目标学科需要明确修正，不能静默继承或忽略', () {
    const validation = SupervisionValidation();
    final draft = configured(
      posts: [
        post('one', 1, pool: 'gone', subjects: ['gone-subject']),
      ],
    );
    expect(
      validation.postErrors(snapshot(), draft),
      contains('辅导：候选池已不存在，请重新设置'),
    );
    expect(
      validation.postErrors(snapshot(), draft),
      contains('辅导：目标学科已不存在，请重新设置'),
    );
  });
  test('旧草稿仍可补齐，新配置经过 JSON 重开保留默认池和覆盖', () {
    final old = SupervisionDraft.fromJson(
      const SupervisionDraft(termId: 't', teacherIds: {'a'}).toJson()
        ..remove('teacherPools')
        ..remove('defaultTeacherPoolId')
        ..remove('matchingPreferences'),
    );
    expect(old.teacherIds, {'a'});
    final configuredDraft = configured(
      posts: [post('one', 1)],
      pools: [
        pool('p', ['b']),
      ],
      defaultPool: 'p',
      prefs: prefs(requirement: 'all'),
    );
    final reopened = SupervisionDraft.fromJson(configuredDraft.toJson());
    expect(allocator.fill(snapshot(), reopened).assignments, {'one': 'b'});
    expect(reopened.toJson()['teacherPools'], [
      pool('p', ['b']),
    ]);
    expect(reopened.toJson()['matchingPreferences'], prefs(requirement: 'all'));
  });
}

Map<String, Object?> prefs({
  List<String> order = const ['classTeacher', 'gradeTeacher', 'subjectTeacher'],
  List<String> enabled = const ['classTeacher', 'gradeTeacher'],
  String mode = 'matchFirst',
  String requirement = 'none',
}) => {
  'order': order,
  'enabled': enabled,
  'mode': mode,
  'requirement': requirement,
};
Map<String, Object?> pool(String id, List<String> teachers) => {
  'id': id,
  'name': id,
  'teacherIds': teachers,
};
Map<String, Object?> post(
  String id,
  int day, {
  String? pool,
  List<String> subjects = const [],
}) => {
  ...const SupervisionPost(
    id: '',
    kind: SupervisionKind.afterSchool,
    name: '辅导',
    stageId: 's',
    weekday: 1,
    periodTypeId: 'p',
    lessonIndices: [1],
    classIds: ['c1'],
  ).toJson(),
  'id': id,
  'weekday': day,
  'teacherPoolId': pool,
  'targetSubjectIds': subjects,
};
SupervisionDraft configured({
  required List<Map<String, Object?>> posts,
  List<String> teachers = const ['a'],
  List<Map<String, Object?>> pools = const [],
  Map<String, Object?>? prefs,
  String? defaultPool,
  Map<String, Object?> rules = const {},
}) => SupervisionDraft.fromJson({
  ...const SupervisionDraft(termId: 't').toJson(),
  'posts': posts,
  'teacherIds': teachers,
  'teacherPools': pools,
  'defaultTeacherPoolId': defaultPool,
  'matchingPreferences': ?prefs,
  'rules': rules,
});
SchedulingSnapshot snapshot() => SchedulingSnapshot(
  term: AcademicTerm(
    id: 't',
    title: '学期',
    academicYear: '',
    semesterLabel: '',
    firstTeachingWeekStart: null,
    teachingWeekCount: 20,
    createdAt: DateTime(2026),
  ),
  inputFingerprint: '',
  stages: const [SchoolStage(id: 's', termId: 't', name: '初中', sortOrder: 0)],
  grades: const [GradeGroup(id: 'g', stageId: 's', name: '七年级', sortOrder: 0)],
  classes: const [
    ClassGroup(id: 'c1', gradeId: 'g', name: '一班', sortOrder: 0),
    ClassGroup(id: 'c2', gradeId: 'g', name: '二班', sortOrder: 1),
  ],
  teachers: const [
    Teacher(id: 'a', name: '甲', shortName: '甲', sortOrder: 0),
    Teacher(id: 'b', name: '乙', shortName: '乙', sortOrder: 1),
  ],
  assignments: const [
    TeacherAssignment(
      id: 'a1',
      termId: 't',
      teacherId: 'a',
      classId: 'c2',
      subjectId: 'math',
      weekMode: WeekMode.weekly,
      lessonCount: 3,
    ),
    TeacherAssignment(
      id: 'b1',
      termId: 't',
      teacherId: 'b',
      classId: 'c1',
      subjectId: 'chinese',
      weekMode: WeekMode.weekly,
      lessonCount: 3,
    ),
    TeacherAssignment(
      id: 'zero',
      termId: 't',
      teacherId: 'a',
      classId: 'c1',
      subjectId: 'chinese',
      weekMode: WeekMode.weekly,
      lessonCount: 0,
    ),
    TeacherAssignment(
      id: 'old',
      termId: 'old',
      teacherId: 'b',
      classId: 'c2',
      subjectId: 'math',
      weekMode: WeekMode.weekly,
      lessonCount: 3,
    ),
  ],
);
