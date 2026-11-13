import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/supervision_validation.dart';
import 'package:class_set/domain/scheduling/supervision_matching.dart';

class SupervisionAllocator {
  const SupervisionAllocator();

  static const _validation = SupervisionValidation();

  List<String> teacherBlockers(
    SchedulingSnapshot snapshot,
    SupervisionDraft draft,
    SupervisionPost post,
    String teacherId, {
    SupervisionMatching? matching,
  }) {
    final positions = _validation.positions(snapshot, post);
    final rule = draft.rules[teacherId] ?? const SupervisionTeacherRule();
    final others = draft.posts.where(
      (other) =>
          other.id != post.id && draft.assignments[other.id] == teacherId,
    );
    final errors = <String>[];
    if (!draft.teachersFor(post).contains(teacherId) ||
        !snapshot.teachers.any((teacher) => teacher.id == teacherId)) {
      errors.add('教师不在岗位候选池中');
    }
    if (!(matching ?? SupervisionMatching(snapshot)).meetsRequirement(
      draft,
      post,
      teacherId,
    )) {
      errors.add('未满足岗位必须符合的匹配条件');
    }
    if (positions.any((position) => rule.unavailable.any(position.sameCell))) {
      errors.add('教师在该节次禁排');
    }
    final courses = snapshot.existingItems
        .where((item) => item.teacherId == teacherId)
        .map((item) => item.position)
        .whereType<SchedulePosition>()
        .map((position) => _validation.withRoutineClock(snapshot, position))
        .toList();
    if (positions.any((position) => courses.any(position.overlaps))) {
      errors.add('教师已有正课');
    }
    final otherPositions = others.expand(
      (other) => _validation.positions(snapshot, other),
    );
    if (positions.any((position) => otherPositions.any(position.overlaps))) {
      errors.add('教师已有带班');
    }
    if (positions.any(
      (position) => [...courses, ...otherPositions].any(
        (other) =>
            other.weekday == position.weekday &&
            other.stageId != position.stageId &&
            (!other.hasClockTime || !position.hasClockTime),
      ),
    )) {
      errors.add('跨学段排班需要补全节次时间');
    }
    final total = others.fold<int>(
      post.lessonIndices.length,
      (count, other) => count + other.lessonIndices.length,
    );
    if (rule.maxLessons != null && total > rule.maxLessons!) {
      errors.add('超过每周带班节次上限');
    }
    final days = {post.weekday, ...others.map((other) => other.weekday)};
    if (rule.maxDays != null && days.length > rule.maxDays!) {
      errors.add('超过每周带班天数上限');
    }
    return errors;
  }

  SupervisionDraft fill(SchedulingSnapshot snapshot, SupervisionDraft draft) {
    final ids = draft.allTeacherIds.toList()..sort();
    final matching = SupervisionMatching(snapshot);
    final assignments = <String, String>{
      for (final post in draft.posts)
        if (draft.manualPostIds.contains(post.id) &&
            draft.assignments.containsKey(post.id))
          post.id: draft.assignments[post.id]!,
    };
    final state = draft.copyWith(assignments: assignments);
    final posts = draft.posts
        .where((post) => !assignments.containsKey(post.id))
        .toList();
    final candidates = {
      for (final post in posts)
        post.id: [
          for (final id in ids)
            if (teacherBlockers(
              snapshot,
              state,
              post,
              id,
              matching: matching,
            ).isEmpty)
              id,
        ],
    };
    posts.sort((a, b) {
      final order = candidates[a.id]!.length.compareTo(
        candidates[b.id]!.length,
      );
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    final remaining = List<int>.filled(posts.length + 1, 0);
    for (var index = posts.length - 1; index >= 0; index--) {
      remaining[index] =
          remaining[index + 1] + posts[index].lessonIndices.length;
    }
    final loads = {for (final id in ids) id: 0};
    for (final post in draft.posts) {
      final teacher = assignments[post.id];
      if (loads.containsKey(teacher)) {
        loads[teacher!] = loads[teacher]! + post.lessonIndices.length;
      }
    }
    var best = Map<String, String>.of(assignments);
    var bestCoverage = -1;
    List<int>? bestMetric;
    final ranks = {
      for (final post in draft.posts)
        post.id: {
          for (final teacher in ids)
            teacher: matching.ranks(draft, post, teacher),
        },
    };
    List<int> metric(int balance) {
      final first = List<int>.filled(3, 0);
      final balanced = List<int>.filled(3, 0);
      for (final post in draft.posts) {
        final teacher = assignments[post.id];
        if (teacher == null) continue;
        final target =
            draft.preferencesFor(post).mode == SupervisionMatchMode.matchFirst
            ? first
            : balanced;
        final values = ranks[post.id]?[teacher] ?? const <int>[];
        for (var i = 0; i < values.length; i++) {
          target[i] -= values[i];
        }
      }
      return [...first, balance, ...balanced];
    }

    bool better(List<int> a, List<int> b) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return a[i] < b[i];
      }
      return false;
    }

    var budget = 12000;
    void visit(int index, int coverage) {
      if (budget-- <= 0 || coverage + remaining[index] < bestCoverage) return;
      final balance = loads.values.fold<int>(
        0,
        (sum, load) => sum + load * load,
      );
      final currentMetric = metric(balance);
      if (coverage > bestCoverage ||
          (coverage == bestCoverage &&
              (bestMetric == null || better(currentMetric, bestMetric!)))) {
        best = Map.of(assignments);
        bestCoverage = coverage;
        bestMetric = currentMetric;
      }
      if (index == posts.length) return;
      final post = posts[index];
      final ranked = [...candidates[post.id]!]
        ..sort((a, b) {
          final loadOrder = loads[a]!.compareTo(loads[b]!);
          if (draft.preferencesFor(post).mode ==
                  SupervisionMatchMode.balanceFirst &&
              loadOrder != 0) {
            return loadOrder;
          }
          final first = ranks[post.id]![a]!;
          final second = ranks[post.id]![b]!;
          for (var i = 0; i < first.length; i++) {
            final order = second[i].compareTo(first[i]);
            if (order != 0) return order;
          }
          return loadOrder == 0 ? a.compareTo(b) : loadOrder;
        });
      final size = post.lessonIndices.length;
      for (final teacher in ranked) {
        if (budget <= 0) break;
        if (teacherBlockers(
          snapshot,
          state,
          post,
          teacher,
          matching: matching,
        ).isNotEmpty) {
          continue;
        }
        assignments[post.id] = teacher;
        loads[teacher] = loads[teacher]! + size;
        visit(index + 1, coverage + size);
        assignments.remove(post.id);
        loads[teacher] = loads[teacher]! - size;
      }
      visit(index + 1, coverage);
    }

    visit(0, 0);
    return draft.copyWith(assignments: best);
  }
}
