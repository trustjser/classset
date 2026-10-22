/// 学期内的教师实体。
///
/// 教师 ID 是跨页面和导入导出的稳定标识；姓名允许重复，显示限定词用于
/// 在相同姓名时给用户提供额外辨识信息。 [subjectIds] 只是任课科目标签，
/// 供筛选和预排提示使用，不会限制实际分配。
class Teacher {
  const Teacher({
    required this.id,
    required this.name,
    required this.shortName,
    required this.sortOrder,
    this.displayQualifier,
    this.subjectIds = const <String>{},
  });

  final String id;
  final String name;
  final String shortName;
  final String? displayQualifier;
  final int sortOrder;
  final Set<String> subjectIds;

  String get displayName {
    final qualifier = displayQualifier?.trim() ?? '';
    return qualifier.isEmpty ? name : '$name（$qualifier）';
  }

  String get searchText => '$name $shortName ${displayQualifier ?? ''}';

  /// 任课科目标签不会产生硬性限制，因此未标记的科目也可以分配。
  bool canTeach(String _) => true;

  Teacher copyWith({
    String? name,
    String? shortName,
    String? displayQualifier,
    bool clearDisplayQualifier = false,
    int? sortOrder,
    Set<String>? subjectIds,
  }) => Teacher(
    id: id,
    name: name ?? this.name,
    shortName: shortName ?? this.shortName,
    displayQualifier: clearDisplayQualifier
        ? null
        : displayQualifier ?? this.displayQualifier,
    sortOrder: sortOrder ?? this.sortOrder,
    subjectIds: subjectIds ?? this.subjectIds,
  );
}

/// 教师与科目的标签关系，独立成行便于数据库增删和导入。
class TeacherSubjectTag {
  const TeacherSubjectTag({
    required this.id,
    required this.teacherId,
    required this.subjectId,
  });

  final String id;
  final String teacherId;
  final String subjectId;
}
