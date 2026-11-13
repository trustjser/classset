import 'package:class_set/domain/models/schedule_position.dart';

enum SupervisionKind {
  afterSchool('课后服务'),
  morningStudy('早自习'),
  eveningStudy('晚自习'),
  custom('自定义');

  const SupervisionKind(this.label);
  final String label;
}

enum SupervisionPreference {
  classTeacher('任教班级优先'),
  gradeTeacher('本年级优先'),
  subjectTeacher('指定学科优先');

  const SupervisionPreference(this.label);
  final String label;
}

enum SupervisionMatchMode { matchFirst, balanceFirst }

enum SupervisionMatchRequirement { none, any, all }

class SupervisionMatchingPreferences {
  const SupervisionMatchingPreferences({
    this.order = SupervisionPreference.values,
    this.enabled = const {
      SupervisionPreference.classTeacher,
      SupervisionPreference.gradeTeacher,
    },
    this.mode = SupervisionMatchMode.matchFirst,
    this.requirement = SupervisionMatchRequirement.none,
  });

  final List<SupervisionPreference> order;
  final Set<SupervisionPreference> enabled;
  final SupervisionMatchMode mode;
  final SupervisionMatchRequirement requirement;

  SupervisionMatchingPreferences copyWith({
    List<SupervisionPreference>? order,
    Set<SupervisionPreference>? enabled,
    SupervisionMatchMode? mode,
    SupervisionMatchRequirement? requirement,
  }) => SupervisionMatchingPreferences(
    order: order ?? this.order,
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    requirement: requirement ?? this.requirement,
  );

  Map<String, Object?> toJson() => {
    'order': order.map((item) => item.name).toList(),
    'enabled': enabled.map((item) => item.name).toList(),
    'mode': mode.name,
    'requirement': requirement.name,
  };

  factory SupervisionMatchingPreferences.fromJson(Map<String, Object?> json) =>
      SupervisionMatchingPreferences(
        order: {
          for (final name in (json['order'] as List? ?? const []))
            SupervisionPreference.values.byName(name as String),
          ...SupervisionPreference.values,
        }.toList(),
        enabled: json['enabled'] == null
            ? const {
                SupervisionPreference.classTeacher,
                SupervisionPreference.gradeTeacher,
              }
            : {
                for (final name in json['enabled'] as List)
                  SupervisionPreference.values.byName(name as String),
              },
        mode: SupervisionMatchMode.values.byName(
          json['mode'] as String? ?? 'matchFirst',
        ),
        requirement: SupervisionMatchRequirement.values.byName(
          json['requirement'] as String? ?? 'none',
        ),
      );
}

class SupervisionTeacherPool {
  const SupervisionTeacherPool({
    required this.id,
    required this.name,
    this.teacherIds = const {},
  });
  final String id;
  final String name;
  final Set<String> teacherIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'teacherIds': teacherIds.toList(),
  };
  factory SupervisionTeacherPool.fromJson(Map<String, Object?> json) =>
      SupervisionTeacherPool(
        id: json['id'] as String,
        name: json['name'] as String,
        teacherIds: (json['teacherIds'] as List).cast<String>().toSet(),
      );
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
    this.teacherPoolId,
    this.matchingPreferences,
    this.targetSubjectIds = const {},
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

  /// Null follows the draft's default pool. An explicit missing pool stays empty.
  final String? teacherPoolId;
  final SupervisionMatchingPreferences? matchingPreferences;
  final Set<String> targetSubjectIds;

  SupervisionPost copyWith({
    String? teacherPoolId,
    bool inheritPool = false,
    SupervisionMatchingPreferences? matchingPreferences,
    bool inheritPreferences = false,
    Set<String>? targetSubjectIds,
  }) => SupervisionPost(
    id: id,
    kind: kind,
    name: name,
    stageId: stageId,
    weekday: weekday,
    periodTypeId: periodTypeId,
    lessonIndices: lessonIndices,
    classIds: classIds,
    groupName: groupName,
    location: location,
    teacherPoolId: inheritPool ? null : teacherPoolId ?? this.teacherPoolId,
    matchingPreferences: inheritPreferences
        ? null
        : matchingPreferences ?? this.matchingPreferences,
    targetSubjectIds: targetSubjectIds ?? this.targetSubjectIds,
  );

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
    'teacherPoolId': teacherPoolId,
    'matchingPreferences': matchingPreferences?.toJson(),
    'targetSubjectIds': targetSubjectIds.toList(),
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
        teacherPoolId: json['teacherPoolId'] as String?,
        matchingPreferences: json['matchingPreferences'] == null
            ? null
            : SupervisionMatchingPreferences.fromJson(
                _object(json['matchingPreferences']),
              ),
        targetSubjectIds: (json['targetSubjectIds'] as List? ?? const [])
            .cast<String>()
            .toSet(),
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
    this.teacherPools = const [],
    this.defaultTeacherPoolId,
    this.matchingPreferences = const SupervisionMatchingPreferences(),
    this.rules = const {},
    this.assignments = const {},
    this.manualPostIds = const {},
  });

  final String termId;
  final int revision;
  final List<SupervisionPost> posts;
  final Set<String> teacherIds;
  final List<SupervisionTeacherPool> teacherPools;
  final String? defaultTeacherPoolId;
  final SupervisionMatchingPreferences matchingPreferences;

  static const basePoolId = '__default__';
  Set<String> get allTeacherIds => {
    ...teacherIds,
    for (final pool in teacherPools) ...pool.teacherIds,
  };
  String poolIdFor(SupervisionPost post) =>
      post.teacherPoolId ?? defaultTeacherPoolId ?? basePoolId;
  Set<String> teachersFor(SupervisionPost post) {
    final id = poolIdFor(post);
    if (id == basePoolId) return teacherIds;
    return teacherPools
            .where((pool) => pool.id == id)
            .firstOrNull
            ?.teacherIds ??
        const {};
  }

  String get defaultTeacherPoolName =>
      _poolName(defaultTeacherPoolId ?? basePoolId);
  String poolNameFor(SupervisionPost post) => _poolName(poolIdFor(post));
  String _poolName(String id) {
    if (id == basePoolId) return '基础候选池';
    return teacherPools.where((pool) => pool.id == id).firstOrNull?.name ??
        '候选池已失效';
  }

  SupervisionMatchingPreferences preferencesFor(SupervisionPost post) =>
      post.matchingPreferences ?? matchingPreferences;

  final Map<String, SupervisionTeacherRule> rules;
  final Map<String, String> assignments;
  final Set<String> manualPostIds;

  SupervisionDraft copyWith({
    int? revision,
    List<SupervisionPost>? posts,
    Set<String>? teacherIds,
    List<SupervisionTeacherPool>? teacherPools,
    String? defaultTeacherPoolId,
    bool resetDefaultPool = false,
    SupervisionMatchingPreferences? matchingPreferences,
    Map<String, SupervisionTeacherRule>? rules,
    Map<String, String>? assignments,
    Set<String>? manualPostIds,
  }) => SupervisionDraft(
    termId: termId,
    revision: revision ?? this.revision,
    posts: posts ?? this.posts,
    teacherIds: teacherIds ?? this.teacherIds,
    teacherPools: teacherPools ?? this.teacherPools,
    defaultTeacherPoolId: resetDefaultPool
        ? null
        : defaultTeacherPoolId ?? this.defaultTeacherPoolId,
    matchingPreferences: matchingPreferences ?? this.matchingPreferences,
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
    'teacherPools': teacherPools.map((pool) => pool.toJson()).toList(),
    'defaultTeacherPoolId': defaultTeacherPoolId,
    'matchingPreferences': matchingPreferences.toJson(),
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
      teacherPools: _decodeList(
        json['teacherPools'] ?? const [],
        SupervisionTeacherPool.fromJson,
      ),
      defaultTeacherPoolId: json['defaultTeacherPoolId'] as String?,
      matchingPreferences: json['matchingPreferences'] == null
          ? const SupervisionMatchingPreferences()
          : SupervisionMatchingPreferences.fromJson(
              _object(json['matchingPreferences']),
            ),
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
