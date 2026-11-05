import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';

/// 由 [TeacherAssignment.combinedLessonGroupId] 聚合出的一个已设置合班组。
///
/// 合班组目前没有独立的数据表，组名由参与班级名派生，不持久化。
class CombinedLessonGroupView {
  const CombinedLessonGroupView({
    required this.id,
    required this.teacherId,
    required this.subjectId,
    required this.weekMode,
    required this.lessonCount,
    required this.members,
  });

  final String id;
  final String teacherId;
  final String subjectId;
  final WeekMode weekMode;
  final int lessonCount;
  final List<TeacherAssignment> members;

  List<String> get classIds =>
      members.map((assignment) => assignment.classId).toList();

  /// 例：「一年级 1 班」+「一年级 2 班」→「一年级 1、2 班合班」。
  String displayName(Map<String, ClassBrief> classById) =>
      deriveCombinedLessonName(
        members
            .map(
              (assignment) =>
                  classById[assignment.classId]?.name ?? assignment.classId,
            )
            .toList(growable: false),
      );
}

/// 主界面汇总条与「全部合班课」使用的统计口径。
class CombinedLessonStats {
  const CombinedLessonStats({
    required this.groupCount,
    required this.classCount,
    required this.teacherCount,
  });

  final int groupCount;
  final int classCount;
  final int teacherCount;

  bool get isEmpty => groupCount == 0;
}

/// 同一教师下，教师 / 科目 / 周模式 / 每周节数完全一致的一组可合并任课。
///
/// [available] 已按班级去重，且不含已在合班组中的记录。
class CombinedLessonCandidateGroup {
  const CombinedLessonCandidateGroup({
    required this.key,
    required this.teacherId,
    required this.subjectId,
    required this.weekMode,
    required this.lessonCount,
    required this.available,
  });

  final String key;
  final String teacherId;
  final String subjectId;
  final WeekMode weekMode;
  final int lessonCount;
  final List<TeacherAssignment> available;
}

/// 从任课记录聚合出全部已设置的合班组。
List<CombinedLessonGroupView> buildCombinedLessonGroups(
  Iterable<TeacherAssignment> assignments, {
  String? termId,
  String? teacherId,
}) {
  final grouped = <String, List<TeacherAssignment>>{};
  for (final assignment in assignments) {
    if (termId != null && assignment.termId != termId) continue;
    if (teacherId != null && assignment.teacherId != teacherId) continue;
    final groupId = assignment.combinedLessonGroupId;
    if (groupId == null || groupId.isEmpty) continue;
    grouped.putIfAbsent(groupId, () => <TeacherAssignment>[]).add(assignment);
  }
  final result = <CombinedLessonGroupView>[];
  for (final entry in grouped.entries) {
    final members = entry.value;
    if (members.isEmpty) continue;
    final first = members.first;
    result.add(
      CombinedLessonGroupView(
        id: entry.key,
        teacherId: first.teacherId,
        subjectId: first.subjectId,
        weekMode: first.weekMode,
        lessonCount: first.lessonCount,
        members: List<TeacherAssignment>.unmodifiable(members),
      ),
    );
  }
  result.sort((left, right) => left.id.compareTo(right.id));
  return List<CombinedLessonGroupView>.unmodifiable(result);
}

/// 汇总已设置的合班组数量、涉及班级数与教师数。
CombinedLessonStats combinedLessonStats(
  Iterable<TeacherAssignment> assignments, {
  String? termId,
}) {
  final groups = buildCombinedLessonGroups(assignments, termId: termId);
  final classKeys = <String>{};
  final teacherIds = <String>{};
  for (final group in groups) {
    teacherIds.add(group.teacherId);
    for (final member in group.members) {
      classKeys.add('${group.id}:${member.classId}');
    }
  }
  return CombinedLessonStats(
    groupCount: groups.length,
    classCount: classKeys.length,
    teacherCount: teacherIds.length,
  );
}

/// 按合并条件划分候选组，仅返回可以组成合班（至少 2 个班）的组。
List<CombinedLessonCandidateGroup> combinedLessonCandidateGroups(
  Iterable<TeacherAssignment> assignments, {
  required String teacherId,
  String? termId,
}) {
  final grouped = <String, List<TeacherAssignment>>{};
  for (final assignment in assignments) {
    if (termId != null && assignment.termId != termId) continue;
    if (assignment.teacherId != teacherId) continue;
    if (assignment.combinedLessonGroupId != null) continue;
    final key =
        '$teacherId|${assignment.subjectId}|'
        '${assignment.weekMode.storageValue}|${assignment.lessonCount}';
    grouped.putIfAbsent(key, () => <TeacherAssignment>[]).add(assignment);
  }
  final result = <CombinedLessonCandidateGroup>[];
  for (final entry in grouped.entries) {
    // 一个班只保留一条任课，与 repository 的「每班仅选一条」校验一致。
    final seenClasses = <String>{};
    final available = <TeacherAssignment>[];
    for (final assignment in entry.value) {
      if (seenClasses.add(assignment.classId)) available.add(assignment);
    }
    if (available.length < 2) continue;
    final first = available.first;
    result.add(
      CombinedLessonCandidateGroup(
        key: entry.key,
        teacherId: teacherId,
        subjectId: first.subjectId,
        weekMode: first.weekMode,
        lessonCount: first.lessonCount,
        available: List<TeacherAssignment>.unmodifiable(available),
      ),
    );
  }
  result.sort((left, right) => left.key.compareTo(right.key));
  return List<CombinedLessonCandidateGroup>.unmodifiable(result);
}

/// 由参与班级名派生合班组名，例如「一年级 1 班」「一年级 2 班」→
/// 「一年级 1、2 班合班」。班级命名不规则时退化为完整名单拼接。
String deriveCombinedLessonName(List<String> classNames) {
  if (classNames.isEmpty) return '合班组';
  final first = classNames.first;
  final shape = RegExp(r'^(.*?)(\d+)(\s*班.*)$').firstMatch(first);
  if (shape == null) return '${classNames.join('、')} 合班';
  final numbers = <String>[];
  for (final name in classNames) {
    final match = RegExp(r'(\d+)\s*班').firstMatch(name);
    numbers.add(match?.group(1) ?? name);
  }
  return '${shape.group(1)}${numbers.join('、')}${shape.group(3)}合班';
}
