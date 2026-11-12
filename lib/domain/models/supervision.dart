import 'package:class_set/domain/models/schedule_position.dart';

enum SupervisionKind {
  afterSchool('课后服务'),
  morningStudy('早自习'),
  eveningStudy('晚自习'),
  custom('自定义');

  const SupervisionKind(this.label);
  final String label;
}

class SupervisionPost {
  const SupervisionPost({
    required this.id,
    required this.kind,
    required this.name,
    required this.stageId,
    required this.weekday,
    required this.periodTypeId,
    required this.lessonIndices,
    required this.classIds,
    this.groupName = '',
    this.location = '',
  });

  final String id;
  final SupervisionKind kind;
  final String name;
  final String groupName;
  final String location;
  final String stageId;
  final int weekday;
  final String periodTypeId;
  final List<int> lessonIndices;
  final List<String> classIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'groupName': groupName,
    'location': location,
    'stageId': stageId,
    'weekday': weekday,
    'periodTypeId': periodTypeId,
    'lessonIndices': lessonIndices,
    'classIds': classIds,
  };

  factory SupervisionPost.fromJson(Map<String, Object?> json) =>
      SupervisionPost(
        id: json['id'] as String,
        kind: SupervisionKind.values.byName(json['kind'] as String),
        name: json['name'] as String,
        groupName: json['groupName'] as String,
        location: json['location'] as String,
        stageId: json['stageId'] as String,
        weekday: json['weekday'] as int,
        periodTypeId: json['periodTypeId'] as String,
        lessonIndices: (json['lessonIndices'] as List).cast<int>(),
        classIds: (json['classIds'] as List).cast<String>(),
      );
}

class SupervisionTeacherRule {
  const SupervisionTeacherRule({
    this.maxLessons,
    this.maxDays,
    this.unavailable = const [],
  });

  final int? maxLessons;
  final int? maxDays;
  final List<SchedulePosition> unavailable;

  Map<String, Object?> toJson() => {
    'maxLessons': maxLessons,
    'maxDays': maxDays,
    'unavailable': unavailable.map((position) => position.toJson()).toList(),
  };

  factory SupervisionTeacherRule.fromJson(Map<String, Object?> json) =>
      SupervisionTeacherRule(
        maxLessons: json['maxLessons'] as int?,
        maxDays: json['maxDays'] as int?,
        unavailable: _decodeList(
          json['unavailable'],
          SchedulePosition.fromJson,
        ),
      );
}

class SupervisionDraft {
  const SupervisionDraft({
    required this.termId,
    this.revision = 0,
    this.posts = const [],
    this.teacherIds = const {},
    this.rules = const {},
    this.assignments = const {},
    this.manualPostIds = const {},
  });

  final String termId;
  final int revision;
  final List<SupervisionPost> posts;
  final Set<String> teacherIds;
  final Map<String, SupervisionTeacherRule> rules;
  final Map<String, String> assignments;
  final Set<String> manualPostIds;

  SupervisionDraft copyWith({
    int? revision,
    List<SupervisionPost>? posts,
    Set<String>? teacherIds,
    Map<String, SupervisionTeacherRule>? rules,
    Map<String, String>? assignments,
    Set<String>? manualPostIds,
  }) => SupervisionDraft(
    termId: termId,
    revision: revision ?? this.revision,
    posts: posts ?? this.posts,
    teacherIds: teacherIds ?? this.teacherIds,
    rules: rules ?? this.rules,
    assignments: assignments ?? this.assignments,
    manualPostIds: manualPostIds ?? this.manualPostIds,
  );

  Map<String, Object?> toJson() => {
    'format': 1,
    'termId': termId,
    'revision': revision,
    'posts': posts.map((post) => post.toJson()).toList(),
    'teacherIds': teacherIds.toList(),
    'rules': rules.map((id, rule) => MapEntry(id, rule.toJson())),
    'assignments': assignments,
    'manualPostIds': manualPostIds.toList(),
  };

  factory SupervisionDraft.fromJson(Map<String, Object?> json) {
    if (json['format'] != 1) throw const FormatException('不支持的带班草稿格式');
    return SupervisionDraft(
      termId: json['termId'] as String,
      revision: json['revision'] as int,
      posts: _decodeList(json['posts'], SupervisionPost.fromJson),
      teacherIds: (json['teacherIds'] as List).cast<String>().toSet(),
      rules: _object(json['rules']).map(
        (id, value) =>
            MapEntry(id, SupervisionTeacherRule.fromJson(_object(value))),
      ),
      assignments: _object(json['assignments']).cast<String, String>(),
      manualPostIds: (json['manualPostIds'] as List).cast<String>().toSet(),
    );
  }
}

class SupervisionOccurrence {
  const SupervisionOccurrence({
    required this.post,
    required this.teacherId,
    required this.position,
    this.classNames = const [],
    this.teacherName = '',
  });

  final SupervisionPost post;
  final String teacherId;
  final SchedulePosition position;
  final List<String> classNames;
  final String teacherName;

  int? get startMinute => position.startMinute;
  int? get endMinute => position.endMinute;
  List<String> get classIds => post.classIds;

  Map<String, Object?> toJson() => {
    'post': post.toJson(),
    'teacherId': teacherId,
    'position': position.toJson(),
    'startMinute': startMinute,
    'endMinute': endMinute,
    'classNames': classNames,
    'teacherName': teacherName,
  };

  factory SupervisionOccurrence.fromJson(Map<String, Object?> json) =>
      SupervisionOccurrence(
        post: SupervisionPost.fromJson(_object(json['post'])),
        teacherId: json['teacherId'] as String,
        position: SchedulePosition.fromJson(_object(json['position'])),
        classNames: (json['classNames'] as List).cast<String>(),
        teacherName: json['teacherName'] as String,
      );
}

class SupervisionVersion {
  const SupervisionVersion({
    required this.termId,
    required this.effectiveDate,
    required this.draft,
    this.occurrences = const [],
  });

  final String termId;
  final DateTime effectiveDate;
  final SupervisionDraft draft;
  final List<SupervisionOccurrence> occurrences;

  Map<String, Object?> toJson() => {
    'termId': termId,
    'effectiveDate': effectiveDate.toIso8601String(),
    'draft': draft.toJson(),
    'occurrences': occurrences
        .map((occurrence) => occurrence.toJson())
        .toList(),
  };

  factory SupervisionVersion.fromJson(Map<String, Object?> json) =>
      SupervisionVersion(
        termId: json['termId'] as String,
        effectiveDate: DateTime.parse(json['effectiveDate'] as String),
        draft: SupervisionDraft.fromJson(_object(json['draft'])),
        occurrences: _decodeList(
          json['occurrences'],
          SupervisionOccurrence.fromJson,
        ),
      );

  static SupervisionVersion? forDate(
    Iterable<SupervisionVersion> versions,
    DateTime date,
  ) {
    SupervisionVersion? selected;
    for (final version in versions) {
      if (!version.effectiveDate.isAfter(date) &&
          (selected == null ||
              version.effectiveDate.isAfter(selected.effectiveDate))) {
        selected = version;
      }
    }
    return selected;
  }
}

class SupervisionPreview {
  const SupervisionPreview({
    required this.effectiveDate,
    required this.draft,
    required this.fingerprint,
    this.before,
    this.errors = const [],
    this.missingPostIds = const [],
    this.scheduleChanges = const [],
    this.replacedFutureDate,
  });

  final DateTime effectiveDate;
  final SupervisionVersion? before;
  final SupervisionDraft draft;
  final List<String> errors;
  final List<String> missingPostIds;
  final List<String> scheduleChanges;
  final DateTime? replacedFutureDate;
  final String fingerprint;

  bool get canPublish => errors.isEmpty && missingPostIds.isEmpty;
}

Map<String, Object?> _object(Object? json) =>
    (json as Map).cast<String, Object?>();

List<T> _decodeList<T>(Object? list, T Function(Map<String, Object?>) decode) =>
    [for (final item in list as List) decode(_object(item))];
