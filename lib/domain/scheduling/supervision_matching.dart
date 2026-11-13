import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

/// Relationships come from actual, positive teaching shares in this term.
/// Pool membership and teacher limits are independent of these preferences.
class SupervisionMatching {
  SupervisionMatching(this.snapshot) {
    for (final assignment in snapshot.assignments) {
      if (assignment.termId != snapshot.term.id ||
          assignment.lessonCount <= 0) {
        continue;
      }
      (_classes[assignment.teacherId] ??= {}).add(assignment.classId);
      final grade = snapshot.gradeIdForClass(assignment.classId);
      if (grade != null) (_grades[assignment.teacherId] ??= {}).add(grade);
      (_subjects[assignment.teacherId] ??= {}).add(assignment.subjectId);
    }
  }

  final SchedulingSnapshot snapshot;
  final _classes = <String, Set<String>>{};
  final _grades = <String, Set<String>>{};
  final _subjects = <String, Set<String>>{};

  List<SupervisionPreference> activePreferences(
    SupervisionDraft draft,
    SupervisionPost post,
  ) => draft
      .preferencesFor(post)
      .order
      .where(
        (preference) =>
            draft.preferencesFor(post).enabled.contains(preference) &&
            (preference != SupervisionPreference.subjectTeacher ||
                post.targetSubjectIds.isNotEmpty),
      )
      .toList();

  int count(
    SupervisionPreference preference,
    SupervisionPost post,
    String teacher,
  ) => switch (preference) {
    SupervisionPreference.classTeacher =>
      post.classIds
          .where((id) => _classes[teacher]?.contains(id) ?? false)
          .length,
    SupervisionPreference.gradeTeacher =>
      post.classIds
          .where(
            (id) =>
                _grades[teacher]?.contains(snapshot.gradeIdForClass(id)) ??
                false,
          )
          .length,
    SupervisionPreference.subjectTeacher =>
      post.targetSubjectIds.any(
            (id) => _subjects[teacher]?.contains(id) ?? false,
          )
          ? 1
          : 0,
  };

  bool complete(
    SupervisionPreference preference,
    SupervisionPost post,
    String teacher,
  ) =>
      count(preference, post, teacher) ==
      (preference == SupervisionPreference.subjectTeacher
          ? 1
          : post.classIds.length);

  List<int> ranks(
    SupervisionDraft draft,
    SupervisionPost post,
    String teacher,
  ) => [
    for (final preference in activePreferences(draft, post))
      count(preference, post, teacher),
  ];

  bool meetsRequirement(
    SupervisionDraft draft,
    SupervisionPost post,
    String teacher,
  ) {
    final active = activePreferences(draft, post);
    if (active.isEmpty) return true;
    return switch (draft.preferencesFor(post).requirement) {
      SupervisionMatchRequirement.none => true,
      SupervisionMatchRequirement.any => active.any(
        (item) => complete(item, post, teacher),
      ),
      SupervisionMatchRequirement.all => active.every(
        (item) => complete(item, post, teacher),
      ),
    };
  }

  bool hasUnmetPreferences(
    SupervisionDraft draft,
    SupervisionPost post,
    String teacher,
  ) => activePreferences(
    draft,
    post,
  ).any((item) => !complete(item, post, teacher));

  List<String> reasons(SupervisionPost post, String teacher) => [
    if (count(SupervisionPreference.classTeacher, post, teacher) > 0)
      post.classIds.length == 1
          ? '任教本班'
          : '任教 ${count(SupervisionPreference.classTeacher, post, teacher)}/${post.classIds.length} 个班',
    if (count(SupervisionPreference.gradeTeacher, post, teacher) > 0)
      complete(SupervisionPreference.gradeTeacher, post, teacher)
          ? '任教本年级'
          : '任教部分年级',
    for (final subject in snapshot.subjects)
      if (post.targetSubjectIds.contains(subject.id) &&
          (_subjects[teacher]?.contains(subject.id) ?? false))
        '任教${subject.name}',
  ];

  int lessons(SupervisionDraft draft, String teacher, {String? excluding}) =>
      draft.posts
          .where(
            (post) =>
                post.id != excluding && draft.assignments[post.id] == teacher,
          )
          .fold(0, (sum, post) => sum + post.lessonIndices.length);

  /// The picker uses the same mode and ordered comparisons as smart allocation.
  int compare(
    SupervisionDraft draft,
    SupervisionPost post,
    String a,
    String b,
  ) {
    int preferenceOrder() {
      final first = ranks(draft, post, a);
      final second = ranks(draft, post, b);
      for (var i = 0; i < first.length; i++) {
        final order = second[i].compareTo(first[i]);
        if (order != 0) return order;
      }
      return 0;
    }

    final loadOrder = lessons(
      draft,
      a,
      excluding: post.id,
    ).compareTo(lessons(draft, b, excluding: post.id));
    if (draft.preferencesFor(post).mode == SupervisionMatchMode.balanceFirst &&
        loadOrder != 0) {
      return loadOrder;
    }
    final order = preferenceOrder();
    return order != 0
        ? order
        : loadOrder != 0
        ? loadOrder
        : a.compareTo(b);
  }
}
