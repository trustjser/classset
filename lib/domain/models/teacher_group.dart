/// 学期内的教师分组。教师可以同时属于多个分组。
class TeacherGroup {
  const TeacherGroup({
    required this.id,
    required this.termId,
    required this.name,
    required this.sortOrder,
    this.description,
  });

  final String id;
  final String termId;
  final String name;
  final int sortOrder;
  final String? description;

  TeacherGroup copyWith({
    String? name,
    String? description,
    bool clearDescription = false,
    int? sortOrder,
  }) => TeacherGroup(
    id: id,
    termId: termId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    description: clearDescription ? null : description ?? this.description,
  );
}

class TeacherGroupMember {
  const TeacherGroupMember({
    required this.id,
    required this.groupId,
    required this.teacherId,
  });

  final String id;
  final String groupId;
  final String teacherId;
}
