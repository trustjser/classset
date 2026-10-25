import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/subject.dart';

/// 一名教师对一个班级的一次课节需求及其排定位置。
///
/// 合班课以相同 [meetingId] 的多条班级记录表示。`position == null` 表示暂放。
class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.termId,
    required this.assignmentId,
    required this.classId,
    required this.teacherId,
    required this.subjectId,
    required this.weekMode,
    this.combinedGroupId,
    this.meetingId,
    this.position,
  });

  final String id;
  final String termId;
  final String assignmentId;
  final String classId;
  final String teacherId;
  final String subjectId;
  final WeekMode weekMode;
  final String? combinedGroupId;
  final String? meetingId;
  final SchedulePosition? position;

  bool get isPlaced => position != null;
  int get occurrenceCount => weekMode == WeekMode.weekly ? 2 : 1;

  ScheduleItem at(SchedulePosition? next) => ScheduleItem(
    id: id,
    termId: termId,
    assignmentId: assignmentId,
    classId: classId,
    teacherId: teacherId,
    subjectId: subjectId,
    weekMode: weekMode,
    combinedGroupId: combinedGroupId,
    meetingId: meetingId,
    position: next,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'termId': termId,
    'assignmentId': assignmentId,
    'classId': classId,
    'teacherId': teacherId,
    'subjectId': subjectId,
    'weekMode': weekMode.storageValue,
    'combinedGroupId': combinedGroupId,
    'meetingId': meetingId,
    'position': position?.toJson(),
  };

  factory ScheduleItem.fromJson(Map<String, Object?> json) => ScheduleItem(
    id: json['id'] as String,
    termId: json['termId'] as String,
    assignmentId: json['assignmentId'] as String,
    classId: json['classId'] as String,
    teacherId: json['teacherId'] as String,
    subjectId: json['subjectId'] as String,
    weekMode: WeekMode.fromStorage(json['weekMode'] as String?),
    combinedGroupId: json['combinedGroupId'] as String?,
    meetingId: json['meetingId'] as String?,
    position: switch (json['position']) {
      final Map value => SchedulePosition.fromJson(
        value.cast<String, Object?>(),
      ),
      _ => null,
    },
  );
}

/// Reports whether two week modes occur in at least one same template week.
bool weekModesOverlap(WeekMode left, WeekMode right) =>
    left == WeekMode.weekly || right == WeekMode.weekly || left == right;

/// Reports whether a lesson occurs in the requested template week.
bool occursInWeek(WeekMode mode, {required bool oddWeek}) =>
    mode == WeekMode.weekly ||
    (oddWeek ? mode == WeekMode.odd : mode == WeekMode.even);
