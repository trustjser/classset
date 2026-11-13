import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/features/supervision/supervision_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('超过100步后只保留最近操作，保存后的恢复不回退存储版本号', () {
    final history = SupervisionDraftHistory(
      const SupervisionDraft(termId: 't', revision: 1),
    );
    for (var i = 1; i <= 101; i++) {
      history.replace(
        history.current.copyWith(teacherIds: {'teacher$i'}),
        '调整教师',
      );
    }
    history.markSaved(history.current.copyWith(revision: 500));
    for (var i = 0; i < 100; i++) {
      expect(history.undo(), isNotNull);
    }
    expect(history.current.teacherIds, {'teacher1'});
    expect(history.current.revision, 500);
    expect(history.undo(), isNull);
    for (var i = 0; i < 100; i++) {
      history.redo();
    }
    expect(history.current.teacherIds, {'teacher101'});
    expect(history.hasChanges, isFalse);
  });
  test('成员顺序不产生历史，偏好顺序有意义，快照不受传入集合后续变动影响', () {
    final original = <String, String>{'p': 'a'};
    final next = <String, String>{'p': 'b'};
    final history = SupervisionDraftHistory(
      SupervisionDraft(
        termId: 't',
        teacherIds: const {'a', 'b'},
        assignments: original,
      ),
    );
    history.replace(history.current.copyWith(assignments: next), '调整教师');
    original['p'] = 'changed';
    next['p'] = 'changed';
    history.undo();
    expect(history.current.assignments, {'p': 'a'});
    expect(
      history.replace(history.current.copyWith(teacherIds: {'b', 'a'}), '不变'),
      isFalse,
    );
    expect(history.canRedo, isTrue);
    history.redo();
    expect(history.current.assignments, {'p': 'b'});
    history.replace(
      history.current.copyWith(
        matchingPreferences: const SupervisionMatchingPreferences(
          order: [
            SupervisionPreference.gradeTeacher,
            SupervisionPreference.classTeacher,
            SupervisionPreference.subjectTeacher,
          ],
        ),
      ),
      '调整优先级',
    );
    history.undo();
    expect(
      history.current.matchingPreferences.order.first,
      SupervisionPreference.classTeacher,
    );
    history.reset(history.current.copyWith(revision: 501));
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
    expect(history.hasChanges, isFalse);
  });
}
