import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/combined_lesson_group.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_lesson_constraint.dart';
import 'package:class_set/domain/models/subject_parallel_limit.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/domain/models/teacher_preset.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

Map<String, Object?> schedulingSnapshotToJson(SchedulingSnapshot s) => {
  'term': {
    'id': s.term.id,
    'title': s.term.title,
    'academicYear': s.term.academicYear,
    'semesterLabel': s.term.semesterLabel,
    'firstTeachingWeekStart': s.term.firstTeachingWeekStart?.toIso8601String(),
    'teachingWeekCount': s.term.teachingWeekCount,
    'createdAt': s.term.createdAt.toIso8601String(),
    'cycleMode': s.term.cycleMode.storageValue,
  },
  'inputFingerprint': s.inputFingerprint,
  'stages': _sorted(
    s.stages,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'termId': e.termId,
      'name': e.name,
      'sortOrder': e.sortOrder,
    },
  ),
  'grades': _sorted(
    s.grades,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'stageId': e.stageId,
      'name': e.name,
      'sortOrder': e.sortOrder,
    },
  ),
  'classes': _sorted(
    s.classes,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'gradeId': e.gradeId,
      'name': e.name,
      'sortOrder': e.sortOrder,
    },
  ),
  'routines': _sorted(
    s.routines,
    (e) => e.stageId,
    (e) => {
      'stageId': e.stageId,
      'teachingWeekdays': e.teachingWeekdays.toList()..sort(),
      'periodTypes': _sorted(
        e.periodTypes,
        (p) => p.id,
        (p) => {
          'id': p.id,
          'name': p.name,
          'defaultLessonCount': p.defaultLessonCount,
          'sortOrder': p.sortOrder,
          'lessonTimes': [
            for (final time in [
              ...p.lessonTimes,
            ]..sort((a, b) => a.lessonIndex.compareTo(b.lessonIndex)))
              {
                'lessonIndex': time.lessonIndex,
                'label': time.label,
                'startMinute': time.startMinute,
                'endMinute': time.endMinute,
              },
          ],
        },
      ),
      'overrides': [
        for (final row
            in [...e.overrides]..sort(
              (a, b) => '${a.periodTypeId}:${a.weekday}'.compareTo(
                '${b.periodTypeId}:${b.weekday}',
              ),
            ))
          {
            'periodTypeId': row.periodTypeId,
            'weekday': row.weekday,
            'lessonCount': row.lessonCount,
          },
      ],
    },
  ),
  'subjects': _sorted(
    s.subjects,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'termId': e.termId,
      'name': e.name,
      'shortName': e.shortName,
      'sortOrder': e.sortOrder,
    },
  ),
  'requirements': _sorted(
    s.requirements,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'subjectId': e.subjectId,
      'gradeId': e.gradeId,
      'classId': e.classId,
      'weekMode': e.weekMode.storageValue,
      'lessonCount': e.lessonCount,
    },
  ),
  'teachers': _sorted(
    s.teachers,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'name': e.name,
      'shortName': e.shortName,
      'sortOrder': e.sortOrder,
      'displayQualifier': e.displayQualifier,
      'subjectIds': e.subjectIds.toList()..sort(),
    },
  ),
  'assignments': _sorted(
    s.assignments,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'termId': e.termId,
      'teacherId': e.teacherId,
      'classId': e.classId,
      'subjectId': e.subjectId,
      'weekMode': e.weekMode.storageValue,
      'lessonCount': e.lessonCount,
      'sortOrder': e.sortOrder,
      'combinedLessonGroupId': e.combinedLessonGroupId,
    },
  ),
  'freeSlots': _sorted(
    s.freeSlots,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'scope': e.scope.storageValue,
      'scopeId': e.scopeId,
      'stageId': e.stageId,
      'periodTypeId': e.periodTypeId,
      'weekday': e.weekday,
      'lessonIndex': e.lessonIndex,
      'label': e.label,
    },
  ),
  'subjectPresets': _sorted(
    s.subjectPresets,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'subjectId': e.subjectId,
      'scope': e.scope.storageValue,
      'scopeId': e.scopeId,
      'stageId': e.stageId,
      'weekday': e.weekday,
      'periodTypeId': e.periodTypeId,
      'lessonIndex': e.lessonIndex,
      'value': e.value.storageValue,
    },
  ),
  'teacherPresets': _sorted(
    s.teacherPresets,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'teacherId': e.teacherId,
      'scope': e.scope.storageValue,
      'scopeId': e.scopeId,
      'stageId': e.stageId,
      'weekday': e.weekday,
      'periodTypeId': e.periodTypeId,
      'lessonIndex': e.lessonIndex,
      'value': e.value.storageValue,
    },
  ),
  'teacherGroupPresets': _sorted(
    s.teacherGroupPresets,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'groupId': e.groupId,
      'scope': e.scope.storageValue,
      'scopeId': e.scopeId,
      'stageId': e.stageId,
      'weekday': e.weekday,
      'periodTypeId': e.periodTypeId,
      'lessonIndex': e.lessonIndex,
      'value': e.value.storageValue,
    },
  ),
  'teacherGroupMembers': _sorted(
    s.teacherGroupMembers,
    (e) => e.id,
    (e) => {'id': e.id, 'groupId': e.groupId, 'teacherId': e.teacherId},
  ),
  'conditions': _sorted(
    s.conditions,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'termId': e.termId,
      'type': e.type.name,
      'targetType': e.targetType?.name,
      'targetId': e.targetId,
      'otherTargetId': e.otherTargetId,
      'periodTypeId': e.periodTypeId,
      'weekday': e.weekday,
      'minimum': e.minimum,
      'maximum': e.maximum,
      'exact': e.exact,
      'name': e.name,
    },
  ),
  'preferences': s.preferences.toJson(),
  'locks': [
    for (final row
        in [...s.locks]..sort(
          (a, b) => '${a.scope.name}:${a.targetId}'.compareTo(
            '${b.scope.name}:${b.targetId}',
          ),
        ))
      {'termId': row.termId, 'scope': row.scope.name, 'targetId': row.targetId},
  ],
  'existingItems': _sorted(s.existingItems, (e) => e.id, (e) => e.toJson()),
  'supervision': [for (final item in s.supervision) item.toJson()],
  'supervisionWeekModes': {
    for (final key in s.supervisionWeekModes.keys.toList()..sort())
      key:
          s.supervisionWeekModes[key]!.map((mode) => mode.storageValue).toList()
            ..sort(),
  },
  if (s.supervisionCalendar case final exceptions?)
    'supervisionCalendar': _sorted(
      exceptions,
      (row) => row.id,
      (row) => {
        'id': row.id,
        'termId': row.termId,
        'date': row.date.toIso8601String(),
        'kind': row.kind.storageValue,
        'makeupWeekday': row.makeupWeekday,
        'makeupForDate': row.makeupForDate?.toIso8601String(),
        'note': row.note,
      },
    ),
  'visibleSupervision': [
    for (final item in s.visibleSupervision) item.toJson(),
  ],
  'rooms': _sorted(
    s.rooms,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'name': e.name,
      'roomCount': e.roomCount,
      'capacityPerRoom': e.capacityPerRoom,
      'sortOrder': e.sortOrder,
    },
  ),
  'roomAssignments': _sorted(
    s.roomAssignments,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'subjectId': e.subjectId,
      'termId': e.termId,
      'stageId': e.stageId,
      'scope': e.scope.storageValue,
      'scopeId': e.scopeId,
      'roomId': e.roomId,
    },
  ),
  'parallelLimits': _sorted(
    s.parallelLimits,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'subjectId': e.subjectId,
      'termId': e.termId,
      'stageId': e.stageId,
      'scope': e.scope.storageValue,
      'scopeId': e.scopeId,
      'maxParallelLessons': e.maxParallelLessons,
    },
  ),
  'combinedGroups': _sorted(
    s.combinedGroups,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'termId': e.termId,
      'teacherId': e.teacherId,
      'subjectId': e.subjectId,
      'weekMode': e.weekMode.storageValue,
      'classIds': [...e.classIds]..sort(),
    },
  ),
  'pairings': _sorted(
    s.pairings,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'classId': e.classId,
      'oddSubjectId': e.oddSubjectId,
      'evenSubjectId': e.evenSubjectId,
    },
  ),
  'lessonConstraints': _sorted(
    s.lessonConstraints,
    (e) => e.id,
    (e) => {
      'id': e.id,
      'subjectId': e.subjectId,
      'scope': e.scope.storageValue,
      'scopeId': e.scopeId,
      'stageId': e.stageId,
      'weekday': e.weekday,
      'minimumDailyLessons': e.minimumDailyLessons,
      'maximumDailyLessons': e.maximumDailyLessons,
      'minimumDailyConsecutivePairs': e.minimumDailyConsecutivePairs,
      'maximumDailyConsecutivePairs': e.maximumDailyConsecutivePairs,
      'minimumWeeklyConsecutivePairs': e.minimumWeeklyConsecutivePairs,
      'maximumWeeklyConsecutivePairs': e.maximumWeeklyConsecutivePairs,
    },
  ),
  'allowedPeriodTypeIdsBySubject': {
    for (final key in s.allowedPeriodTypeIdsBySubject.keys.toList()..sort())
      key: s.allowedPeriodTypeIdsBySubject[key]!.toList()..sort(),
  },
  'requiredConsecutivePairsByRequirement': {
    for (final key
        in s.requiredConsecutivePairsByRequirement.keys.toList()..sort())
      key: s.requiredConsecutivePairsByRequirement[key],
  },
};

SchedulingSnapshot schedulingSnapshotFromJson(Map<String, Object?> json) {
  final term = _map(json['term']);
  return SchedulingSnapshot(
    term: AcademicTerm(
      id: term['id'] as String,
      title: term['title'] as String,
      academicYear: term['academicYear'] as String,
      semesterLabel: term['semesterLabel'] as String,
      firstTeachingWeekStart: _date(term['firstTeachingWeekStart']),
      teachingWeekCount: _int(term['teachingWeekCount']),
      createdAt: _date(term['createdAt'])!,
      cycleMode: AcademicTermCycle.fromStorage(term['cycleMode'] as String?),
    ),
    inputFingerprint: json['inputFingerprint'] as String,
    stages: _rows(
      json,
      'stages',
      (m) => SchoolStage(
        id: m['id'] as String,
        termId: m['termId'] as String,
        name: m['name'] as String,
        sortOrder: _int(m['sortOrder']),
      ),
    ),
    grades: _rows(
      json,
      'grades',
      (m) => GradeGroup(
        id: m['id'] as String,
        stageId: m['stageId'] as String,
        name: m['name'] as String,
        sortOrder: _int(m['sortOrder']),
      ),
    ),
    classes: _rows(
      json,
      'classes',
      (m) => ClassGroup(
        id: m['id'] as String,
        gradeId: m['gradeId'] as String,
        name: m['name'] as String,
        sortOrder: _int(m['sortOrder']),
      ),
    ),
    routines: _rows(
      json,
      'routines',
      (m) => StageRoutine(
        stageId: m['stageId'] as String,
        teachingWeekdays: (m['teachingWeekdays'] as List).map(_int).toSet(),
        periodTypes: _rows(
          m,
          'periodTypes',
          (p) => LessonPeriodType(
            id: p['id'] as String,
            name: p['name'] as String,
            defaultLessonCount: _int(p['defaultLessonCount']),
            sortOrder: _int(p['sortOrder']),
            lessonTimes: _rows(
              p,
              'lessonTimes',
              (t) => LessonTime(
                lessonIndex: _int(t['lessonIndex']),
                label: t['label'] as String,
                startMinute: _nullableInt(t['startMinute']),
                endMinute: _nullableInt(t['endMinute']),
              ),
            ),
          ),
        ),
        overrides: _rows(
          m,
          'overrides',
          (o) => RoutineOverride(
            periodTypeId: o['periodTypeId'] as String,
            weekday: _int(o['weekday']),
            lessonCount: _int(o['lessonCount']),
          ),
        ),
      ),
    ),
    subjects: _rows(
      json,
      'subjects',
      (m) => Subject(
        id: m['id'] as String,
        termId: m['termId'] as String?,
        name: m['name'] as String,
        shortName: m['shortName'] as String,
        sortOrder: _int(m['sortOrder']),
      ),
    ),
    requirements: _rows(
      json,
      'requirements',
      (m) => SubjectRequirement(
        id: m['id'] as String,
        subjectId: m['subjectId'] as String,
        gradeId: m['gradeId'] as String,
        classId: m['classId'] as String?,
        weekMode: WeekMode.fromStorage(m['weekMode'] as String?),
        lessonCount: _int(m['lessonCount']),
      ),
    ),
    teachers: _rows(
      json,
      'teachers',
      (m) => Teacher(
        id: m['id'] as String,
        name: m['name'] as String,
        shortName: m['shortName'] as String,
        sortOrder: _int(m['sortOrder']),
        displayQualifier: m['displayQualifier'] as String?,
        subjectIds: (m['subjectIds'] as List).cast<String>().toSet(),
      ),
    ),
    assignments: _rows(
      json,
      'assignments',
      (m) => TeacherAssignment(
        id: m['id'] as String,
        termId: m['termId'] as String,
        teacherId: m['teacherId'] as String,
        classId: m['classId'] as String,
        subjectId: m['subjectId'] as String,
        weekMode: WeekMode.fromStorage(m['weekMode'] as String?),
        lessonCount: _int(m['lessonCount']),
        sortOrder: _int(m['sortOrder']),
        combinedLessonGroupId: m['combinedLessonGroupId'] as String?,
      ),
    ),
    freeSlots: _rows(
      json,
      'freeSlots',
      (m) => FreeSlot(
        id: m['id'] as String,
        scope: FreeSlotScope.fromStorage(m['scope'] as String),
        scopeId: m['scopeId'] as String,
        stageId: m['stageId'] as String,
        periodTypeId: m['periodTypeId'] as String,
        weekday: _int(m['weekday']),
        lessonIndex: _int(m['lessonIndex']),
        label: m['label'] as String,
      ),
    ),
    subjectPresets: _rows(
      json,
      'subjectPresets',
      (m) => SubjectPreset(
        id: m['id'] as String,
        subjectId: m['subjectId'] as String,
        scope: FreeSlotScope.fromStorage(m['scope'] as String),
        scopeId: m['scopeId'] as String,
        stageId: m['stageId'] as String,
        weekday: _int(m['weekday']),
        periodTypeId: m['periodTypeId'] as String,
        lessonIndex: _int(m['lessonIndex']),
        value: PresetValue.fromStorage(m['value'] as String?),
      ),
    ),
    teacherPresets: _rows(
      json,
      'teacherPresets',
      (m) => TeacherPreset(
        id: m['id'] as String,
        teacherId: m['teacherId'] as String,
        scope: TeacherPresetScope.fromStorage(m['scope'] as String?),
        scopeId: m['scopeId'] as String,
        stageId: m['stageId'] as String,
        weekday: _int(m['weekday']),
        periodTypeId: m['periodTypeId'] as String,
        lessonIndex: _int(m['lessonIndex']),
        value: PresetValue.fromStorage(m['value'] as String?),
      ),
    ),
    teacherGroupPresets: _rows(
      json,
      'teacherGroupPresets',
      (m) => TeacherGroupPreset(
        id: m['id'] as String,
        groupId: m['groupId'] as String,
        scope: TeacherPresetScope.fromStorage(m['scope'] as String?),
        scopeId: m['scopeId'] as String,
        stageId: m['stageId'] as String,
        weekday: _int(m['weekday']),
        periodTypeId: m['periodTypeId'] as String,
        lessonIndex: _int(m['lessonIndex']),
        value: PresetValue.fromStorage(m['value'] as String?),
      ),
    ),
    teacherGroupMembers: _rows(
      json,
      'teacherGroupMembers',
      (m) => TeacherGroupMember(
        id: m['id'] as String,
        groupId: m['groupId'] as String,
        teacherId: m['teacherId'] as String,
      ),
    ),
    conditions: _rows(
      json,
      'conditions',
      (m) => ScheduleCondition(
        id: m['id'] as String,
        termId: m['termId'] as String,
        type: ScheduleConditionType.values.byName(m['type'] as String),
        targetType: m['targetType'] == null
            ? null
            : ScheduleConditionTarget.values.byName(m['targetType'] as String),
        targetId: m['targetId'] as String?,
        otherTargetId: m['otherTargetId'] as String?,
        periodTypeId: m['periodTypeId'] as String?,
        weekday: _nullableInt(m['weekday']),
        minimum: _nullableInt(m['minimum']),
        maximum: _nullableInt(m['maximum']),
        exact: _nullableInt(m['exact']),
        name: m['name'] as String?,
      ),
    ),
    preferences: SchedulePreferences.fromJson(_map(json['preferences'])),
    locks: _rows(
      json,
      'locks',
      (m) => ScheduleLock(
        termId: m['termId'] as String,
        scope: ScheduleLockScope.values.byName(m['scope'] as String),
        targetId: m['targetId'] as String,
      ),
    ),
    existingItems: _rows(json, 'existingItems', ScheduleItem.fromJson),
    supervision: _rows(json, 'supervision', SupervisionOccurrence.fromJson),
    supervisionWeekModes: {
      for (final entry
          in (json['supervisionWeekModes'] as Map<String, Object?>? ??
                  const <String, Object?>{})
              .entries)
        entry.key: (entry.value as List)
            .map((mode) => WeekMode.fromStorage(mode as String))
            .toSet(),
    },
    supervisionCalendar: json.containsKey('supervisionCalendar')
        ? _rows(
            json,
            'supervisionCalendar',
            (row) => CalendarException(
              id: row['id'] as String,
              termId: row['termId'] as String,
              date: DateTime.parse(row['date'] as String),
              kind: CalendarExceptionKind.fromStorage(row['kind'] as String),
              makeupWeekday: row['makeupWeekday'] as int?,
              makeupForDate: _date(row['makeupForDate']),
              note: row['note'] as String,
            ),
          )
        : null,
    visibleSupervision: _rows(
      json,
      'visibleSupervision',
      SupervisionOccurrence.fromJson,
    ),
    rooms: _rows(
      json,
      'rooms',
      (m) => PublicRoom(
        id: m['id'] as String,
        name: m['name'] as String,
        roomCount: _int(m['roomCount']),
        capacityPerRoom: _int(m['capacityPerRoom']),
        sortOrder: _int(m['sortOrder']),
      ),
    ),
    roomAssignments: _rows(
      json,
      'roomAssignments',
      (m) => SubjectRoomAssignment(
        id: m['id'] as String,
        subjectId: m['subjectId'] as String,
        termId: m['termId'] as String,
        stageId: m['stageId'] as String,
        scope: FreeSlotScope.fromStorage(m['scope'] as String),
        scopeId: m['scopeId'] as String,
        roomId: m['roomId'] as String?,
      ),
    ),
    parallelLimits: _rows(
      json,
      'parallelLimits',
      (m) => SubjectParallelLimit(
        id: m['id'] as String,
        subjectId: m['subjectId'] as String,
        termId: m['termId'] as String,
        stageId: m['stageId'] as String,
        scope: FreeSlotScope.fromStorage(m['scope'] as String),
        scopeId: m['scopeId'] as String,
        maxParallelLessons: _int(m['maxParallelLessons']),
      ),
    ),
    combinedGroups: _rows(
      json,
      'combinedGroups',
      (m) => CombinedLessonGroup(
        id: m['id'] as String,
        termId: m['termId'] as String,
        teacherId: m['teacherId'] as String,
        subjectId: m['subjectId'] as String,
        weekMode: WeekMode.fromStorage(m['weekMode'] as String?),
        classIds: (m['classIds'] as List).cast<String>(),
      ),
    ),
    pairings: _rows(
      json,
      'pairings',
      (m) => SubjectPairing(
        id: m['id'] as String,
        classId: m['classId'] as String,
        oddSubjectId: m['oddSubjectId'] as String,
        evenSubjectId: m['evenSubjectId'] as String,
      ),
    ),
    lessonConstraints: _rows(
      json,
      'lessonConstraints',
      (m) => SubjectLessonConstraint(
        id: m['id'] as String,
        subjectId: m['subjectId'] as String,
        scope: FreeSlotScope.fromStorage(m['scope'] as String),
        scopeId: m['scopeId'] as String,
        stageId: m['stageId'] as String,
        weekday: _nullableInt(m['weekday']),
        minimumDailyLessons: _nullableInt(m['minimumDailyLessons']),
        maximumDailyLessons: _nullableInt(m['maximumDailyLessons']),
        minimumDailyConsecutivePairs: _nullableInt(
          m['minimumDailyConsecutivePairs'],
        ),
        maximumDailyConsecutivePairs: _nullableInt(
          m['maximumDailyConsecutivePairs'],
        ),
        minimumWeeklyConsecutivePairs: _nullableInt(
          m['minimumWeeklyConsecutivePairs'],
        ),
        maximumWeeklyConsecutivePairs: _nullableInt(
          m['maximumWeeklyConsecutivePairs'],
        ),
      ),
    ),
    allowedPeriodTypeIdsBySubject: {
      for (final entry in _map(json['allowedPeriodTypeIdsBySubject']).entries)
        entry.key: (entry.value as List).cast<String>().toSet(),
    },
    requiredConsecutivePairsByRequirement: {
      for (final entry in _map(
        json['requiredConsecutivePairsByRequirement'],
      ).entries)
        entry.key: _int(entry.value),
    },
  );
}

List<Map<String, Object?>> _sorted<T>(
  List<T> rows,
  String Function(T) id,
  Map<String, Object?> Function(T) encode,
) {
  final ordered = [...rows]..sort((a, b) => id(a).compareTo(id(b)));
  return [for (final row in ordered) encode(row)];
}

Map<String, Object?> _map(Object? value) =>
    (value as Map).cast<String, Object?>();

List<T> _rows<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?>) decode,
) => [
  for (final value in (json[key] as List?) ?? const []) decode(_map(value)),
];

int _int(Object? value) => (value as num).toInt();
int? _nullableInt(Object? value) => (value as num?)?.toInt();
DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
