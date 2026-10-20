// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AcademicTermsTable extends AcademicTerms
    with TableInfo<$AcademicTermsTable, AcademicTerm> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AcademicTermsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _academicYearMeta = const VerificationMeta(
    'academicYear',
  );
  @override
  late final GeneratedColumn<String> academicYear = GeneratedColumn<String>(
    'academic_year',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _semesterLabelMeta = const VerificationMeta(
    'semesterLabel',
  );
  @override
  late final GeneratedColumn<String> semesterLabel = GeneratedColumn<String>(
    'semester_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstTeachingWeekStartMeta =
      const VerificationMeta('firstTeachingWeekStart');
  @override
  late final GeneratedColumn<String> firstTeachingWeekStart =
      GeneratedColumn<String>(
        'first_teaching_week_start',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _teachingWeekCountMeta = const VerificationMeta(
    'teachingWeekCount',
  );
  @override
  late final GeneratedColumn<int> teachingWeekCount = GeneratedColumn<int>(
    'teaching_week_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(20),
  );
  static const VerificationMeta _cycleModeMeta = const VerificationMeta(
    'cycleMode',
  );
  @override
  late final GeneratedColumn<String> cycleMode = GeneratedColumn<String>(
    'cycle_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('alternating'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    academicYear,
    semesterLabel,
    firstTeachingWeekStart,
    teachingWeekCount,
    cycleMode,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'academic_terms';
  @override
  VerificationContext validateIntegrity(
    Insertable<AcademicTerm> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('academic_year')) {
      context.handle(
        _academicYearMeta,
        academicYear.isAcceptableOrUnknown(
          data['academic_year']!,
          _academicYearMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_academicYearMeta);
    }
    if (data.containsKey('semester_label')) {
      context.handle(
        _semesterLabelMeta,
        semesterLabel.isAcceptableOrUnknown(
          data['semester_label']!,
          _semesterLabelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_semesterLabelMeta);
    }
    if (data.containsKey('first_teaching_week_start')) {
      context.handle(
        _firstTeachingWeekStartMeta,
        firstTeachingWeekStart.isAcceptableOrUnknown(
          data['first_teaching_week_start']!,
          _firstTeachingWeekStartMeta,
        ),
      );
    }
    if (data.containsKey('teaching_week_count')) {
      context.handle(
        _teachingWeekCountMeta,
        teachingWeekCount.isAcceptableOrUnknown(
          data['teaching_week_count']!,
          _teachingWeekCountMeta,
        ),
      );
    }
    if (data.containsKey('cycle_mode')) {
      context.handle(
        _cycleModeMeta,
        cycleMode.isAcceptableOrUnknown(data['cycle_mode']!, _cycleModeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AcademicTerm map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AcademicTerm(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      academicYear: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}academic_year'],
      )!,
      semesterLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}semester_label'],
      )!,
      firstTeachingWeekStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_teaching_week_start'],
      ),
      teachingWeekCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}teaching_week_count'],
      )!,
      cycleMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cycle_mode'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AcademicTermsTable createAlias(String alias) {
    return $AcademicTermsTable(attachedDatabase, alias);
  }
}

class AcademicTerm extends DataClass implements Insertable<AcademicTerm> {
  final String id;
  final String title;
  final String academicYear;
  final String semesterLabel;
  final String? firstTeachingWeekStart;
  final int teachingWeekCount;
  final String cycleMode;
  final int createdAt;
  const AcademicTerm({
    required this.id,
    required this.title,
    required this.academicYear,
    required this.semesterLabel,
    this.firstTeachingWeekStart,
    required this.teachingWeekCount,
    required this.cycleMode,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['academic_year'] = Variable<String>(academicYear);
    map['semester_label'] = Variable<String>(semesterLabel);
    if (!nullToAbsent || firstTeachingWeekStart != null) {
      map['first_teaching_week_start'] = Variable<String>(
        firstTeachingWeekStart,
      );
    }
    map['teaching_week_count'] = Variable<int>(teachingWeekCount);
    map['cycle_mode'] = Variable<String>(cycleMode);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AcademicTermsCompanion toCompanion(bool nullToAbsent) {
    return AcademicTermsCompanion(
      id: Value(id),
      title: Value(title),
      academicYear: Value(academicYear),
      semesterLabel: Value(semesterLabel),
      firstTeachingWeekStart: firstTeachingWeekStart == null && nullToAbsent
          ? const Value.absent()
          : Value(firstTeachingWeekStart),
      teachingWeekCount: Value(teachingWeekCount),
      cycleMode: Value(cycleMode),
      createdAt: Value(createdAt),
    );
  }

  factory AcademicTerm.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AcademicTerm(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      academicYear: serializer.fromJson<String>(json['academicYear']),
      semesterLabel: serializer.fromJson<String>(json['semesterLabel']),
      firstTeachingWeekStart: serializer.fromJson<String?>(
        json['firstTeachingWeekStart'],
      ),
      teachingWeekCount: serializer.fromJson<int>(json['teachingWeekCount']),
      cycleMode: serializer.fromJson<String>(json['cycleMode']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'academicYear': serializer.toJson<String>(academicYear),
      'semesterLabel': serializer.toJson<String>(semesterLabel),
      'firstTeachingWeekStart': serializer.toJson<String?>(
        firstTeachingWeekStart,
      ),
      'teachingWeekCount': serializer.toJson<int>(teachingWeekCount),
      'cycleMode': serializer.toJson<String>(cycleMode),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  AcademicTerm copyWith({
    String? id,
    String? title,
    String? academicYear,
    String? semesterLabel,
    Value<String?> firstTeachingWeekStart = const Value.absent(),
    int? teachingWeekCount,
    String? cycleMode,
    int? createdAt,
  }) => AcademicTerm(
    id: id ?? this.id,
    title: title ?? this.title,
    academicYear: academicYear ?? this.academicYear,
    semesterLabel: semesterLabel ?? this.semesterLabel,
    firstTeachingWeekStart: firstTeachingWeekStart.present
        ? firstTeachingWeekStart.value
        : this.firstTeachingWeekStart,
    teachingWeekCount: teachingWeekCount ?? this.teachingWeekCount,
    cycleMode: cycleMode ?? this.cycleMode,
    createdAt: createdAt ?? this.createdAt,
  );
  AcademicTerm copyWithCompanion(AcademicTermsCompanion data) {
    return AcademicTerm(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      academicYear: data.academicYear.present
          ? data.academicYear.value
          : this.academicYear,
      semesterLabel: data.semesterLabel.present
          ? data.semesterLabel.value
          : this.semesterLabel,
      firstTeachingWeekStart: data.firstTeachingWeekStart.present
          ? data.firstTeachingWeekStart.value
          : this.firstTeachingWeekStart,
      teachingWeekCount: data.teachingWeekCount.present
          ? data.teachingWeekCount.value
          : this.teachingWeekCount,
      cycleMode: data.cycleMode.present ? data.cycleMode.value : this.cycleMode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AcademicTerm(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('academicYear: $academicYear, ')
          ..write('semesterLabel: $semesterLabel, ')
          ..write('firstTeachingWeekStart: $firstTeachingWeekStart, ')
          ..write('teachingWeekCount: $teachingWeekCount, ')
          ..write('cycleMode: $cycleMode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    academicYear,
    semesterLabel,
    firstTeachingWeekStart,
    teachingWeekCount,
    cycleMode,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AcademicTerm &&
          other.id == this.id &&
          other.title == this.title &&
          other.academicYear == this.academicYear &&
          other.semesterLabel == this.semesterLabel &&
          other.firstTeachingWeekStart == this.firstTeachingWeekStart &&
          other.teachingWeekCount == this.teachingWeekCount &&
          other.cycleMode == this.cycleMode &&
          other.createdAt == this.createdAt);
}

class AcademicTermsCompanion extends UpdateCompanion<AcademicTerm> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> academicYear;
  final Value<String> semesterLabel;
  final Value<String?> firstTeachingWeekStart;
  final Value<int> teachingWeekCount;
  final Value<String> cycleMode;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AcademicTermsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.academicYear = const Value.absent(),
    this.semesterLabel = const Value.absent(),
    this.firstTeachingWeekStart = const Value.absent(),
    this.teachingWeekCount = const Value.absent(),
    this.cycleMode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AcademicTermsCompanion.insert({
    required String id,
    required String title,
    required String academicYear,
    required String semesterLabel,
    this.firstTeachingWeekStart = const Value.absent(),
    this.teachingWeekCount = const Value.absent(),
    this.cycleMode = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       academicYear = Value(academicYear),
       semesterLabel = Value(semesterLabel),
       createdAt = Value(createdAt);
  static Insertable<AcademicTerm> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? academicYear,
    Expression<String>? semesterLabel,
    Expression<String>? firstTeachingWeekStart,
    Expression<int>? teachingWeekCount,
    Expression<String>? cycleMode,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (academicYear != null) 'academic_year': academicYear,
      if (semesterLabel != null) 'semester_label': semesterLabel,
      if (firstTeachingWeekStart != null)
        'first_teaching_week_start': firstTeachingWeekStart,
      if (teachingWeekCount != null) 'teaching_week_count': teachingWeekCount,
      if (cycleMode != null) 'cycle_mode': cycleMode,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AcademicTermsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? academicYear,
    Value<String>? semesterLabel,
    Value<String?>? firstTeachingWeekStart,
    Value<int>? teachingWeekCount,
    Value<String>? cycleMode,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return AcademicTermsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      academicYear: academicYear ?? this.academicYear,
      semesterLabel: semesterLabel ?? this.semesterLabel,
      firstTeachingWeekStart:
          firstTeachingWeekStart ?? this.firstTeachingWeekStart,
      teachingWeekCount: teachingWeekCount ?? this.teachingWeekCount,
      cycleMode: cycleMode ?? this.cycleMode,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (academicYear.present) {
      map['academic_year'] = Variable<String>(academicYear.value);
    }
    if (semesterLabel.present) {
      map['semester_label'] = Variable<String>(semesterLabel.value);
    }
    if (firstTeachingWeekStart.present) {
      map['first_teaching_week_start'] = Variable<String>(
        firstTeachingWeekStart.value,
      );
    }
    if (teachingWeekCount.present) {
      map['teaching_week_count'] = Variable<int>(teachingWeekCount.value);
    }
    if (cycleMode.present) {
      map['cycle_mode'] = Variable<String>(cycleMode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AcademicTermsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('academicYear: $academicYear, ')
          ..write('semesterLabel: $semesterLabel, ')
          ..write('firstTeachingWeekStart: $firstTeachingWeekStart, ')
          ..write('teachingWeekCount: $teachingWeekCount, ')
          ..write('cycleMode: $cycleMode, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SchoolStagesTable extends SchoolStages
    with TableInfo<$SchoolStagesTable, SchoolStage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchoolStagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _termIdMeta = const VerificationMeta('termId');
  @override
  late final GeneratedColumn<String> termId = GeneratedColumn<String>(
    'term_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES academic_terms (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, termId, name, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'school_stages';
  @override
  VerificationContext validateIntegrity(
    Insertable<SchoolStage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('term_id')) {
      context.handle(
        _termIdMeta,
        termId.isAcceptableOrUnknown(data['term_id']!, _termIdMeta),
      );
    } else if (isInserting) {
      context.missing(_termIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SchoolStage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SchoolStage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      termId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}term_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $SchoolStagesTable createAlias(String alias) {
    return $SchoolStagesTable(attachedDatabase, alias);
  }
}

class SchoolStage extends DataClass implements Insertable<SchoolStage> {
  final String id;
  final String termId;
  final String name;
  final int sortOrder;
  const SchoolStage({
    required this.id,
    required this.termId,
    required this.name,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['term_id'] = Variable<String>(termId);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  SchoolStagesCompanion toCompanion(bool nullToAbsent) {
    return SchoolStagesCompanion(
      id: Value(id),
      termId: Value(termId),
      name: Value(name),
      sortOrder: Value(sortOrder),
    );
  }

  factory SchoolStage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SchoolStage(
      id: serializer.fromJson<String>(json['id']),
      termId: serializer.fromJson<String>(json['termId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'termId': serializer.toJson<String>(termId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  SchoolStage copyWith({
    String? id,
    String? termId,
    String? name,
    int? sortOrder,
  }) => SchoolStage(
    id: id ?? this.id,
    termId: termId ?? this.termId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  SchoolStage copyWithCompanion(SchoolStagesCompanion data) {
    return SchoolStage(
      id: data.id.present ? data.id.value : this.id,
      termId: data.termId.present ? data.termId.value : this.termId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SchoolStage(')
          ..write('id: $id, ')
          ..write('termId: $termId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, termId, name, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchoolStage &&
          other.id == this.id &&
          other.termId == this.termId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder);
}

class SchoolStagesCompanion extends UpdateCompanion<SchoolStage> {
  final Value<String> id;
  final Value<String> termId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const SchoolStagesCompanion({
    this.id = const Value.absent(),
    this.termId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SchoolStagesCompanion.insert({
    required String id,
    required String termId,
    required String name,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       termId = Value(termId),
       name = Value(name),
       sortOrder = Value(sortOrder);
  static Insertable<SchoolStage> custom({
    Expression<String>? id,
    Expression<String>? termId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (termId != null) 'term_id': termId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SchoolStagesCompanion copyWith({
    Value<String>? id,
    Value<String>? termId,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return SchoolStagesCompanion(
      id: id ?? this.id,
      termId: termId ?? this.termId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (termId.present) {
      map['term_id'] = Variable<String>(termId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchoolStagesCompanion(')
          ..write('id: $id, ')
          ..write('termId: $termId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GradeGroupsTable extends GradeGroups
    with TableInfo<$GradeGroupsTable, GradeGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GradeGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageIdMeta = const VerificationMeta(
    'stageId',
  );
  @override
  late final GeneratedColumn<String> stageId = GeneratedColumn<String>(
    'stage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES school_stages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, stageId, name, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'grade_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<GradeGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('stage_id')) {
      context.handle(
        _stageIdMeta,
        stageId.isAcceptableOrUnknown(data['stage_id']!, _stageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stageIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GradeGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GradeGroup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $GradeGroupsTable createAlias(String alias) {
    return $GradeGroupsTable(attachedDatabase, alias);
  }
}

class GradeGroup extends DataClass implements Insertable<GradeGroup> {
  final String id;
  final String stageId;
  final String name;
  final int sortOrder;
  const GradeGroup({
    required this.id,
    required this.stageId,
    required this.name,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['stage_id'] = Variable<String>(stageId);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  GradeGroupsCompanion toCompanion(bool nullToAbsent) {
    return GradeGroupsCompanion(
      id: Value(id),
      stageId: Value(stageId),
      name: Value(name),
      sortOrder: Value(sortOrder),
    );
  }

  factory GradeGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GradeGroup(
      id: serializer.fromJson<String>(json['id']),
      stageId: serializer.fromJson<String>(json['stageId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stageId': serializer.toJson<String>(stageId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  GradeGroup copyWith({
    String? id,
    String? stageId,
    String? name,
    int? sortOrder,
  }) => GradeGroup(
    id: id ?? this.id,
    stageId: stageId ?? this.stageId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  GradeGroup copyWithCompanion(GradeGroupsCompanion data) {
    return GradeGroup(
      id: data.id.present ? data.id.value : this.id,
      stageId: data.stageId.present ? data.stageId.value : this.stageId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GradeGroup(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, stageId, name, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GradeGroup &&
          other.id == this.id &&
          other.stageId == this.stageId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder);
}

class GradeGroupsCompanion extends UpdateCompanion<GradeGroup> {
  final Value<String> id;
  final Value<String> stageId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const GradeGroupsCompanion({
    this.id = const Value.absent(),
    this.stageId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GradeGroupsCompanion.insert({
    required String id,
    required String stageId,
    required String name,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stageId = Value(stageId),
       name = Value(name),
       sortOrder = Value(sortOrder);
  static Insertable<GradeGroup> custom({
    Expression<String>? id,
    Expression<String>? stageId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stageId != null) 'stage_id': stageId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GradeGroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? stageId,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return GradeGroupsCompanion(
      id: id ?? this.id,
      stageId: stageId ?? this.stageId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (stageId.present) {
      map['stage_id'] = Variable<String>(stageId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GradeGroupsCompanion(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClassGroupsTable extends ClassGroups
    with TableInfo<$ClassGroupsTable, ClassGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClassGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gradeIdMeta = const VerificationMeta(
    'gradeId',
  );
  @override
  late final GeneratedColumn<String> gradeId = GeneratedColumn<String>(
    'grade_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES grade_groups (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, gradeId, name, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'class_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClassGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('grade_id')) {
      context.handle(
        _gradeIdMeta,
        gradeId.isAcceptableOrUnknown(data['grade_id']!, _gradeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gradeIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClassGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClassGroup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      gradeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grade_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $ClassGroupsTable createAlias(String alias) {
    return $ClassGroupsTable(attachedDatabase, alias);
  }
}

class ClassGroup extends DataClass implements Insertable<ClassGroup> {
  final String id;
  final String gradeId;
  final String name;
  final int sortOrder;
  const ClassGroup({
    required this.id,
    required this.gradeId,
    required this.name,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['grade_id'] = Variable<String>(gradeId);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  ClassGroupsCompanion toCompanion(bool nullToAbsent) {
    return ClassGroupsCompanion(
      id: Value(id),
      gradeId: Value(gradeId),
      name: Value(name),
      sortOrder: Value(sortOrder),
    );
  }

  factory ClassGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClassGroup(
      id: serializer.fromJson<String>(json['id']),
      gradeId: serializer.fromJson<String>(json['gradeId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'gradeId': serializer.toJson<String>(gradeId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  ClassGroup copyWith({
    String? id,
    String? gradeId,
    String? name,
    int? sortOrder,
  }) => ClassGroup(
    id: id ?? this.id,
    gradeId: gradeId ?? this.gradeId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  ClassGroup copyWithCompanion(ClassGroupsCompanion data) {
    return ClassGroup(
      id: data.id.present ? data.id.value : this.id,
      gradeId: data.gradeId.present ? data.gradeId.value : this.gradeId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClassGroup(')
          ..write('id: $id, ')
          ..write('gradeId: $gradeId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, gradeId, name, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClassGroup &&
          other.id == this.id &&
          other.gradeId == this.gradeId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder);
}

class ClassGroupsCompanion extends UpdateCompanion<ClassGroup> {
  final Value<String> id;
  final Value<String> gradeId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const ClassGroupsCompanion({
    this.id = const Value.absent(),
    this.gradeId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClassGroupsCompanion.insert({
    required String id,
    required String gradeId,
    required String name,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       gradeId = Value(gradeId),
       name = Value(name),
       sortOrder = Value(sortOrder);
  static Insertable<ClassGroup> custom({
    Expression<String>? id,
    Expression<String>? gradeId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (gradeId != null) 'grade_id': gradeId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClassGroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? gradeId,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return ClassGroupsCompanion(
      id: id ?? this.id,
      gradeId: gradeId ?? this.gradeId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (gradeId.present) {
      map['grade_id'] = Variable<String>(gradeId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClassGroupsCompanion(')
          ..write('id: $id, ')
          ..write('gradeId: $gradeId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StageTeachingDaysTable extends StageTeachingDays
    with TableInfo<$StageTeachingDaysTable, StageTeachingDay> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StageTeachingDaysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageIdMeta = const VerificationMeta(
    'stageId',
  );
  @override
  late final GeneratedColumn<String> stageId = GeneratedColumn<String>(
    'stage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES school_stages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isTeachingDayMeta = const VerificationMeta(
    'isTeachingDay',
  );
  @override
  late final GeneratedColumn<bool> isTeachingDay = GeneratedColumn<bool>(
    'is_teaching_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_teaching_day" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, stageId, weekday, isTeachingDay];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stage_teaching_days';
  @override
  VerificationContext validateIntegrity(
    Insertable<StageTeachingDay> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('stage_id')) {
      context.handle(
        _stageIdMeta,
        stageId.isAcceptableOrUnknown(data['stage_id']!, _stageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stageIdMeta);
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    } else if (isInserting) {
      context.missing(_weekdayMeta);
    }
    if (data.containsKey('is_teaching_day')) {
      context.handle(
        _isTeachingDayMeta,
        isTeachingDay.isAcceptableOrUnknown(
          data['is_teaching_day']!,
          _isTeachingDayMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isTeachingDayMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StageTeachingDay map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StageTeachingDay(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_id'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      )!,
      isTeachingDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_teaching_day'],
      )!,
    );
  }

  @override
  $StageTeachingDaysTable createAlias(String alias) {
    return $StageTeachingDaysTable(attachedDatabase, alias);
  }
}

class StageTeachingDay extends DataClass
    implements Insertable<StageTeachingDay> {
  final String id;
  final String stageId;
  final int weekday;
  final bool isTeachingDay;
  const StageTeachingDay({
    required this.id,
    required this.stageId,
    required this.weekday,
    required this.isTeachingDay,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['stage_id'] = Variable<String>(stageId);
    map['weekday'] = Variable<int>(weekday);
    map['is_teaching_day'] = Variable<bool>(isTeachingDay);
    return map;
  }

  StageTeachingDaysCompanion toCompanion(bool nullToAbsent) {
    return StageTeachingDaysCompanion(
      id: Value(id),
      stageId: Value(stageId),
      weekday: Value(weekday),
      isTeachingDay: Value(isTeachingDay),
    );
  }

  factory StageTeachingDay.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StageTeachingDay(
      id: serializer.fromJson<String>(json['id']),
      stageId: serializer.fromJson<String>(json['stageId']),
      weekday: serializer.fromJson<int>(json['weekday']),
      isTeachingDay: serializer.fromJson<bool>(json['isTeachingDay']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stageId': serializer.toJson<String>(stageId),
      'weekday': serializer.toJson<int>(weekday),
      'isTeachingDay': serializer.toJson<bool>(isTeachingDay),
    };
  }

  StageTeachingDay copyWith({
    String? id,
    String? stageId,
    int? weekday,
    bool? isTeachingDay,
  }) => StageTeachingDay(
    id: id ?? this.id,
    stageId: stageId ?? this.stageId,
    weekday: weekday ?? this.weekday,
    isTeachingDay: isTeachingDay ?? this.isTeachingDay,
  );
  StageTeachingDay copyWithCompanion(StageTeachingDaysCompanion data) {
    return StageTeachingDay(
      id: data.id.present ? data.id.value : this.id,
      stageId: data.stageId.present ? data.stageId.value : this.stageId,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      isTeachingDay: data.isTeachingDay.present
          ? data.isTeachingDay.value
          : this.isTeachingDay,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StageTeachingDay(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('weekday: $weekday, ')
          ..write('isTeachingDay: $isTeachingDay')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, stageId, weekday, isTeachingDay);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StageTeachingDay &&
          other.id == this.id &&
          other.stageId == this.stageId &&
          other.weekday == this.weekday &&
          other.isTeachingDay == this.isTeachingDay);
}

class StageTeachingDaysCompanion extends UpdateCompanion<StageTeachingDay> {
  final Value<String> id;
  final Value<String> stageId;
  final Value<int> weekday;
  final Value<bool> isTeachingDay;
  final Value<int> rowid;
  const StageTeachingDaysCompanion({
    this.id = const Value.absent(),
    this.stageId = const Value.absent(),
    this.weekday = const Value.absent(),
    this.isTeachingDay = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StageTeachingDaysCompanion.insert({
    required String id,
    required String stageId,
    required int weekday,
    required bool isTeachingDay,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stageId = Value(stageId),
       weekday = Value(weekday),
       isTeachingDay = Value(isTeachingDay);
  static Insertable<StageTeachingDay> custom({
    Expression<String>? id,
    Expression<String>? stageId,
    Expression<int>? weekday,
    Expression<bool>? isTeachingDay,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stageId != null) 'stage_id': stageId,
      if (weekday != null) 'weekday': weekday,
      if (isTeachingDay != null) 'is_teaching_day': isTeachingDay,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StageTeachingDaysCompanion copyWith({
    Value<String>? id,
    Value<String>? stageId,
    Value<int>? weekday,
    Value<bool>? isTeachingDay,
    Value<int>? rowid,
  }) {
    return StageTeachingDaysCompanion(
      id: id ?? this.id,
      stageId: stageId ?? this.stageId,
      weekday: weekday ?? this.weekday,
      isTeachingDay: isTeachingDay ?? this.isTeachingDay,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (stageId.present) {
      map['stage_id'] = Variable<String>(stageId.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (isTeachingDay.present) {
      map['is_teaching_day'] = Variable<bool>(isTeachingDay.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StageTeachingDaysCompanion(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('weekday: $weekday, ')
          ..write('isTeachingDay: $isTeachingDay, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LessonPeriodTypesTable extends LessonPeriodTypes
    with TableInfo<$LessonPeriodTypesTable, LessonPeriodType> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LessonPeriodTypesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageIdMeta = const VerificationMeta(
    'stageId',
  );
  @override
  late final GeneratedColumn<String> stageId = GeneratedColumn<String>(
    'stage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES school_stages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _defaultLessonCountMeta =
      const VerificationMeta('defaultLessonCount');
  @override
  late final GeneratedColumn<int> defaultLessonCount = GeneratedColumn<int>(
    'default_lesson_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    stageId,
    name,
    defaultLessonCount,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lesson_period_types';
  @override
  VerificationContext validateIntegrity(
    Insertable<LessonPeriodType> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('stage_id')) {
      context.handle(
        _stageIdMeta,
        stageId.isAcceptableOrUnknown(data['stage_id']!, _stageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stageIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('default_lesson_count')) {
      context.handle(
        _defaultLessonCountMeta,
        defaultLessonCount.isAcceptableOrUnknown(
          data['default_lesson_count']!,
          _defaultLessonCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultLessonCountMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LessonPeriodType map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LessonPeriodType(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      defaultLessonCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_lesson_count'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $LessonPeriodTypesTable createAlias(String alias) {
    return $LessonPeriodTypesTable(attachedDatabase, alias);
  }
}

class LessonPeriodType extends DataClass
    implements Insertable<LessonPeriodType> {
  final String id;
  final String stageId;
  final String name;
  final int defaultLessonCount;
  final int sortOrder;
  const LessonPeriodType({
    required this.id,
    required this.stageId,
    required this.name,
    required this.defaultLessonCount,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['stage_id'] = Variable<String>(stageId);
    map['name'] = Variable<String>(name);
    map['default_lesson_count'] = Variable<int>(defaultLessonCount);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  LessonPeriodTypesCompanion toCompanion(bool nullToAbsent) {
    return LessonPeriodTypesCompanion(
      id: Value(id),
      stageId: Value(stageId),
      name: Value(name),
      defaultLessonCount: Value(defaultLessonCount),
      sortOrder: Value(sortOrder),
    );
  }

  factory LessonPeriodType.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LessonPeriodType(
      id: serializer.fromJson<String>(json['id']),
      stageId: serializer.fromJson<String>(json['stageId']),
      name: serializer.fromJson<String>(json['name']),
      defaultLessonCount: serializer.fromJson<int>(json['defaultLessonCount']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stageId': serializer.toJson<String>(stageId),
      'name': serializer.toJson<String>(name),
      'defaultLessonCount': serializer.toJson<int>(defaultLessonCount),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  LessonPeriodType copyWith({
    String? id,
    String? stageId,
    String? name,
    int? defaultLessonCount,
    int? sortOrder,
  }) => LessonPeriodType(
    id: id ?? this.id,
    stageId: stageId ?? this.stageId,
    name: name ?? this.name,
    defaultLessonCount: defaultLessonCount ?? this.defaultLessonCount,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  LessonPeriodType copyWithCompanion(LessonPeriodTypesCompanion data) {
    return LessonPeriodType(
      id: data.id.present ? data.id.value : this.id,
      stageId: data.stageId.present ? data.stageId.value : this.stageId,
      name: data.name.present ? data.name.value : this.name,
      defaultLessonCount: data.defaultLessonCount.present
          ? data.defaultLessonCount.value
          : this.defaultLessonCount,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LessonPeriodType(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('name: $name, ')
          ..write('defaultLessonCount: $defaultLessonCount, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, stageId, name, defaultLessonCount, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LessonPeriodType &&
          other.id == this.id &&
          other.stageId == this.stageId &&
          other.name == this.name &&
          other.defaultLessonCount == this.defaultLessonCount &&
          other.sortOrder == this.sortOrder);
}

class LessonPeriodTypesCompanion extends UpdateCompanion<LessonPeriodType> {
  final Value<String> id;
  final Value<String> stageId;
  final Value<String> name;
  final Value<int> defaultLessonCount;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const LessonPeriodTypesCompanion({
    this.id = const Value.absent(),
    this.stageId = const Value.absent(),
    this.name = const Value.absent(),
    this.defaultLessonCount = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LessonPeriodTypesCompanion.insert({
    required String id,
    required String stageId,
    required String name,
    required int defaultLessonCount,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stageId = Value(stageId),
       name = Value(name),
       defaultLessonCount = Value(defaultLessonCount),
       sortOrder = Value(sortOrder);
  static Insertable<LessonPeriodType> custom({
    Expression<String>? id,
    Expression<String>? stageId,
    Expression<String>? name,
    Expression<int>? defaultLessonCount,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stageId != null) 'stage_id': stageId,
      if (name != null) 'name': name,
      if (defaultLessonCount != null)
        'default_lesson_count': defaultLessonCount,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LessonPeriodTypesCompanion copyWith({
    Value<String>? id,
    Value<String>? stageId,
    Value<String>? name,
    Value<int>? defaultLessonCount,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return LessonPeriodTypesCompanion(
      id: id ?? this.id,
      stageId: stageId ?? this.stageId,
      name: name ?? this.name,
      defaultLessonCount: defaultLessonCount ?? this.defaultLessonCount,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (stageId.present) {
      map['stage_id'] = Variable<String>(stageId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (defaultLessonCount.present) {
      map['default_lesson_count'] = Variable<int>(defaultLessonCount.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LessonPeriodTypesCompanion(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('name: $name, ')
          ..write('defaultLessonCount: $defaultLessonCount, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyLessonOverridesTable extends DailyLessonOverrides
    with TableInfo<$DailyLessonOverridesTable, DailyLessonOverride> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyLessonOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageIdMeta = const VerificationMeta(
    'stageId',
  );
  @override
  late final GeneratedColumn<String> stageId = GeneratedColumn<String>(
    'stage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES school_stages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _periodTypeIdMeta = const VerificationMeta(
    'periodTypeId',
  );
  @override
  late final GeneratedColumn<String> periodTypeId = GeneratedColumn<String>(
    'period_type_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lesson_period_types (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lessonCountMeta = const VerificationMeta(
    'lessonCount',
  );
  @override
  late final GeneratedColumn<int> lessonCount = GeneratedColumn<int>(
    'lesson_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    stageId,
    periodTypeId,
    weekday,
    lessonCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_lesson_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyLessonOverride> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('stage_id')) {
      context.handle(
        _stageIdMeta,
        stageId.isAcceptableOrUnknown(data['stage_id']!, _stageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stageIdMeta);
    }
    if (data.containsKey('period_type_id')) {
      context.handle(
        _periodTypeIdMeta,
        periodTypeId.isAcceptableOrUnknown(
          data['period_type_id']!,
          _periodTypeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodTypeIdMeta);
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    } else if (isInserting) {
      context.missing(_weekdayMeta);
    }
    if (data.containsKey('lesson_count')) {
      context.handle(
        _lessonCountMeta,
        lessonCount.isAcceptableOrUnknown(
          data['lesson_count']!,
          _lessonCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lessonCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DailyLessonOverride map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyLessonOverride(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_id'],
      )!,
      periodTypeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_type_id'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      )!,
      lessonCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lesson_count'],
      )!,
    );
  }

  @override
  $DailyLessonOverridesTable createAlias(String alias) {
    return $DailyLessonOverridesTable(attachedDatabase, alias);
  }
}

class DailyLessonOverride extends DataClass
    implements Insertable<DailyLessonOverride> {
  final String id;
  final String stageId;
  final String periodTypeId;
  final int weekday;
  final int lessonCount;
  const DailyLessonOverride({
    required this.id,
    required this.stageId,
    required this.periodTypeId,
    required this.weekday,
    required this.lessonCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['stage_id'] = Variable<String>(stageId);
    map['period_type_id'] = Variable<String>(periodTypeId);
    map['weekday'] = Variable<int>(weekday);
    map['lesson_count'] = Variable<int>(lessonCount);
    return map;
  }

  DailyLessonOverridesCompanion toCompanion(bool nullToAbsent) {
    return DailyLessonOverridesCompanion(
      id: Value(id),
      stageId: Value(stageId),
      periodTypeId: Value(periodTypeId),
      weekday: Value(weekday),
      lessonCount: Value(lessonCount),
    );
  }

  factory DailyLessonOverride.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyLessonOverride(
      id: serializer.fromJson<String>(json['id']),
      stageId: serializer.fromJson<String>(json['stageId']),
      periodTypeId: serializer.fromJson<String>(json['periodTypeId']),
      weekday: serializer.fromJson<int>(json['weekday']),
      lessonCount: serializer.fromJson<int>(json['lessonCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stageId': serializer.toJson<String>(stageId),
      'periodTypeId': serializer.toJson<String>(periodTypeId),
      'weekday': serializer.toJson<int>(weekday),
      'lessonCount': serializer.toJson<int>(lessonCount),
    };
  }

  DailyLessonOverride copyWith({
    String? id,
    String? stageId,
    String? periodTypeId,
    int? weekday,
    int? lessonCount,
  }) => DailyLessonOverride(
    id: id ?? this.id,
    stageId: stageId ?? this.stageId,
    periodTypeId: periodTypeId ?? this.periodTypeId,
    weekday: weekday ?? this.weekday,
    lessonCount: lessonCount ?? this.lessonCount,
  );
  DailyLessonOverride copyWithCompanion(DailyLessonOverridesCompanion data) {
    return DailyLessonOverride(
      id: data.id.present ? data.id.value : this.id,
      stageId: data.stageId.present ? data.stageId.value : this.stageId,
      periodTypeId: data.periodTypeId.present
          ? data.periodTypeId.value
          : this.periodTypeId,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      lessonCount: data.lessonCount.present
          ? data.lessonCount.value
          : this.lessonCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyLessonOverride(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('periodTypeId: $periodTypeId, ')
          ..write('weekday: $weekday, ')
          ..write('lessonCount: $lessonCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, stageId, periodTypeId, weekday, lessonCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyLessonOverride &&
          other.id == this.id &&
          other.stageId == this.stageId &&
          other.periodTypeId == this.periodTypeId &&
          other.weekday == this.weekday &&
          other.lessonCount == this.lessonCount);
}

class DailyLessonOverridesCompanion
    extends UpdateCompanion<DailyLessonOverride> {
  final Value<String> id;
  final Value<String> stageId;
  final Value<String> periodTypeId;
  final Value<int> weekday;
  final Value<int> lessonCount;
  final Value<int> rowid;
  const DailyLessonOverridesCompanion({
    this.id = const Value.absent(),
    this.stageId = const Value.absent(),
    this.periodTypeId = const Value.absent(),
    this.weekday = const Value.absent(),
    this.lessonCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyLessonOverridesCompanion.insert({
    required String id,
    required String stageId,
    required String periodTypeId,
    required int weekday,
    required int lessonCount,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stageId = Value(stageId),
       periodTypeId = Value(periodTypeId),
       weekday = Value(weekday),
       lessonCount = Value(lessonCount);
  static Insertable<DailyLessonOverride> custom({
    Expression<String>? id,
    Expression<String>? stageId,
    Expression<String>? periodTypeId,
    Expression<int>? weekday,
    Expression<int>? lessonCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stageId != null) 'stage_id': stageId,
      if (periodTypeId != null) 'period_type_id': periodTypeId,
      if (weekday != null) 'weekday': weekday,
      if (lessonCount != null) 'lesson_count': lessonCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyLessonOverridesCompanion copyWith({
    Value<String>? id,
    Value<String>? stageId,
    Value<String>? periodTypeId,
    Value<int>? weekday,
    Value<int>? lessonCount,
    Value<int>? rowid,
  }) {
    return DailyLessonOverridesCompanion(
      id: id ?? this.id,
      stageId: stageId ?? this.stageId,
      periodTypeId: periodTypeId ?? this.periodTypeId,
      weekday: weekday ?? this.weekday,
      lessonCount: lessonCount ?? this.lessonCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (stageId.present) {
      map['stage_id'] = Variable<String>(stageId.value);
    }
    if (periodTypeId.present) {
      map['period_type_id'] = Variable<String>(periodTypeId.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (lessonCount.present) {
      map['lesson_count'] = Variable<int>(lessonCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyLessonOverridesCompanion(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('periodTypeId: $periodTypeId, ')
          ..write('weekday: $weekday, ')
          ..write('lessonCount: $lessonCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LessonTimesTable extends LessonTimes
    with TableInfo<$LessonTimesTable, LessonTime> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LessonTimesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodTypeIdMeta = const VerificationMeta(
    'periodTypeId',
  );
  @override
  late final GeneratedColumn<String> periodTypeId = GeneratedColumn<String>(
    'period_type_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lesson_period_types (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _lessonIndexMeta = const VerificationMeta(
    'lessonIndex',
  );
  @override
  late final GeneratedColumn<int> lessonIndex = GeneratedColumn<int>(
    'lesson_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startMinuteMeta = const VerificationMeta(
    'startMinute',
  );
  @override
  late final GeneratedColumn<int> startMinute = GeneratedColumn<int>(
    'start_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endMinuteMeta = const VerificationMeta(
    'endMinute',
  );
  @override
  late final GeneratedColumn<int> endMinute = GeneratedColumn<int>(
    'end_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    periodTypeId,
    lessonIndex,
    label,
    startMinute,
    endMinute,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lesson_times';
  @override
  VerificationContext validateIntegrity(
    Insertable<LessonTime> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('period_type_id')) {
      context.handle(
        _periodTypeIdMeta,
        periodTypeId.isAcceptableOrUnknown(
          data['period_type_id']!,
          _periodTypeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodTypeIdMeta);
    }
    if (data.containsKey('lesson_index')) {
      context.handle(
        _lessonIndexMeta,
        lessonIndex.isAcceptableOrUnknown(
          data['lesson_index']!,
          _lessonIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lessonIndexMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('start_minute')) {
      context.handle(
        _startMinuteMeta,
        startMinute.isAcceptableOrUnknown(
          data['start_minute']!,
          _startMinuteMeta,
        ),
      );
    }
    if (data.containsKey('end_minute')) {
      context.handle(
        _endMinuteMeta,
        endMinute.isAcceptableOrUnknown(data['end_minute']!, _endMinuteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LessonTime map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LessonTime(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      periodTypeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_type_id'],
      )!,
      lessonIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lesson_index'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      startMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_minute'],
      ),
      endMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_minute'],
      ),
    );
  }

  @override
  $LessonTimesTable createAlias(String alias) {
    return $LessonTimesTable(attachedDatabase, alias);
  }
}

class LessonTime extends DataClass implements Insertable<LessonTime> {
  final String id;
  final String periodTypeId;
  final int lessonIndex;
  final String label;
  final int? startMinute;
  final int? endMinute;
  const LessonTime({
    required this.id,
    required this.periodTypeId,
    required this.lessonIndex,
    required this.label,
    this.startMinute,
    this.endMinute,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['period_type_id'] = Variable<String>(periodTypeId);
    map['lesson_index'] = Variable<int>(lessonIndex);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || startMinute != null) {
      map['start_minute'] = Variable<int>(startMinute);
    }
    if (!nullToAbsent || endMinute != null) {
      map['end_minute'] = Variable<int>(endMinute);
    }
    return map;
  }

  LessonTimesCompanion toCompanion(bool nullToAbsent) {
    return LessonTimesCompanion(
      id: Value(id),
      periodTypeId: Value(periodTypeId),
      lessonIndex: Value(lessonIndex),
      label: Value(label),
      startMinute: startMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(startMinute),
      endMinute: endMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(endMinute),
    );
  }

  factory LessonTime.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LessonTime(
      id: serializer.fromJson<String>(json['id']),
      periodTypeId: serializer.fromJson<String>(json['periodTypeId']),
      lessonIndex: serializer.fromJson<int>(json['lessonIndex']),
      label: serializer.fromJson<String>(json['label']),
      startMinute: serializer.fromJson<int?>(json['startMinute']),
      endMinute: serializer.fromJson<int?>(json['endMinute']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'periodTypeId': serializer.toJson<String>(periodTypeId),
      'lessonIndex': serializer.toJson<int>(lessonIndex),
      'label': serializer.toJson<String>(label),
      'startMinute': serializer.toJson<int?>(startMinute),
      'endMinute': serializer.toJson<int?>(endMinute),
    };
  }

  LessonTime copyWith({
    String? id,
    String? periodTypeId,
    int? lessonIndex,
    String? label,
    Value<int?> startMinute = const Value.absent(),
    Value<int?> endMinute = const Value.absent(),
  }) => LessonTime(
    id: id ?? this.id,
    periodTypeId: periodTypeId ?? this.periodTypeId,
    lessonIndex: lessonIndex ?? this.lessonIndex,
    label: label ?? this.label,
    startMinute: startMinute.present ? startMinute.value : this.startMinute,
    endMinute: endMinute.present ? endMinute.value : this.endMinute,
  );
  LessonTime copyWithCompanion(LessonTimesCompanion data) {
    return LessonTime(
      id: data.id.present ? data.id.value : this.id,
      periodTypeId: data.periodTypeId.present
          ? data.periodTypeId.value
          : this.periodTypeId,
      lessonIndex: data.lessonIndex.present
          ? data.lessonIndex.value
          : this.lessonIndex,
      label: data.label.present ? data.label.value : this.label,
      startMinute: data.startMinute.present
          ? data.startMinute.value
          : this.startMinute,
      endMinute: data.endMinute.present ? data.endMinute.value : this.endMinute,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LessonTime(')
          ..write('id: $id, ')
          ..write('periodTypeId: $periodTypeId, ')
          ..write('lessonIndex: $lessonIndex, ')
          ..write('label: $label, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, periodTypeId, lessonIndex, label, startMinute, endMinute);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LessonTime &&
          other.id == this.id &&
          other.periodTypeId == this.periodTypeId &&
          other.lessonIndex == this.lessonIndex &&
          other.label == this.label &&
          other.startMinute == this.startMinute &&
          other.endMinute == this.endMinute);
}

class LessonTimesCompanion extends UpdateCompanion<LessonTime> {
  final Value<String> id;
  final Value<String> periodTypeId;
  final Value<int> lessonIndex;
  final Value<String> label;
  final Value<int?> startMinute;
  final Value<int?> endMinute;
  final Value<int> rowid;
  const LessonTimesCompanion({
    this.id = const Value.absent(),
    this.periodTypeId = const Value.absent(),
    this.lessonIndex = const Value.absent(),
    this.label = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LessonTimesCompanion.insert({
    required String id,
    required String periodTypeId,
    required int lessonIndex,
    required String label,
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       periodTypeId = Value(periodTypeId),
       lessonIndex = Value(lessonIndex),
       label = Value(label);
  static Insertable<LessonTime> custom({
    Expression<String>? id,
    Expression<String>? periodTypeId,
    Expression<int>? lessonIndex,
    Expression<String>? label,
    Expression<int>? startMinute,
    Expression<int>? endMinute,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (periodTypeId != null) 'period_type_id': periodTypeId,
      if (lessonIndex != null) 'lesson_index': lessonIndex,
      if (label != null) 'label': label,
      if (startMinute != null) 'start_minute': startMinute,
      if (endMinute != null) 'end_minute': endMinute,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LessonTimesCompanion copyWith({
    Value<String>? id,
    Value<String>? periodTypeId,
    Value<int>? lessonIndex,
    Value<String>? label,
    Value<int?>? startMinute,
    Value<int?>? endMinute,
    Value<int>? rowid,
  }) {
    return LessonTimesCompanion(
      id: id ?? this.id,
      periodTypeId: periodTypeId ?? this.periodTypeId,
      lessonIndex: lessonIndex ?? this.lessonIndex,
      label: label ?? this.label,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (periodTypeId.present) {
      map['period_type_id'] = Variable<String>(periodTypeId.value);
    }
    if (lessonIndex.present) {
      map['lesson_index'] = Variable<int>(lessonIndex.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (startMinute.present) {
      map['start_minute'] = Variable<int>(startMinute.value);
    }
    if (endMinute.present) {
      map['end_minute'] = Variable<int>(endMinute.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LessonTimesCompanion(')
          ..write('id: $id, ')
          ..write('periodTypeId: $periodTypeId, ')
          ..write('lessonIndex: $lessonIndex, ')
          ..write('label: $label, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CalendarExceptionsTable extends CalendarExceptions
    with TableInfo<$CalendarExceptionsTable, CalendarException> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalendarExceptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _termIdMeta = const VerificationMeta('termId');
  @override
  late final GeneratedColumn<String> termId = GeneratedColumn<String>(
    'term_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES academic_terms (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _makeupWeekdayMeta = const VerificationMeta(
    'makeupWeekday',
  );
  @override
  late final GeneratedColumn<int> makeupWeekday = GeneratedColumn<int>(
    'makeup_weekday',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _makeupForDateMeta = const VerificationMeta(
    'makeupForDate',
  );
  @override
  late final GeneratedColumn<String> makeupForDate = GeneratedColumn<String>(
    'makeup_for_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    termId,
    date,
    kind,
    makeupWeekday,
    makeupForDate,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_exceptions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CalendarException> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('term_id')) {
      context.handle(
        _termIdMeta,
        termId.isAcceptableOrUnknown(data['term_id']!, _termIdMeta),
      );
    } else if (isInserting) {
      context.missing(_termIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('makeup_weekday')) {
      context.handle(
        _makeupWeekdayMeta,
        makeupWeekday.isAcceptableOrUnknown(
          data['makeup_weekday']!,
          _makeupWeekdayMeta,
        ),
      );
    }
    if (data.containsKey('makeup_for_date')) {
      context.handle(
        _makeupForDateMeta,
        makeupForDate.isAcceptableOrUnknown(
          data['makeup_for_date']!,
          _makeupForDateMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CalendarException map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalendarException(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      termId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}term_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      makeupWeekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}makeup_weekday'],
      ),
      makeupForDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}makeup_for_date'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
    );
  }

  @override
  $CalendarExceptionsTable createAlias(String alias) {
    return $CalendarExceptionsTable(attachedDatabase, alias);
  }
}

class CalendarException extends DataClass
    implements Insertable<CalendarException> {
  final String id;
  final String termId;

  /// yyyy-MM-dd，仅日期。
  final String date;

  /// holiday=停课/节假日，makeup=补课。
  final String kind;

  /// 补课日采用的课表星期（1-7）；停课日为 null。
  final int? makeupWeekday;

  /// 补课对应的原课日期（yyyy-MM-dd）；停课日为 null。
  final String? makeupForDate;
  final String note;
  const CalendarException({
    required this.id,
    required this.termId,
    required this.date,
    required this.kind,
    this.makeupWeekday,
    this.makeupForDate,
    required this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['term_id'] = Variable<String>(termId);
    map['date'] = Variable<String>(date);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || makeupWeekday != null) {
      map['makeup_weekday'] = Variable<int>(makeupWeekday);
    }
    if (!nullToAbsent || makeupForDate != null) {
      map['makeup_for_date'] = Variable<String>(makeupForDate);
    }
    map['note'] = Variable<String>(note);
    return map;
  }

  CalendarExceptionsCompanion toCompanion(bool nullToAbsent) {
    return CalendarExceptionsCompanion(
      id: Value(id),
      termId: Value(termId),
      date: Value(date),
      kind: Value(kind),
      makeupWeekday: makeupWeekday == null && nullToAbsent
          ? const Value.absent()
          : Value(makeupWeekday),
      makeupForDate: makeupForDate == null && nullToAbsent
          ? const Value.absent()
          : Value(makeupForDate),
      note: Value(note),
    );
  }

  factory CalendarException.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalendarException(
      id: serializer.fromJson<String>(json['id']),
      termId: serializer.fromJson<String>(json['termId']),
      date: serializer.fromJson<String>(json['date']),
      kind: serializer.fromJson<String>(json['kind']),
      makeupWeekday: serializer.fromJson<int?>(json['makeupWeekday']),
      makeupForDate: serializer.fromJson<String?>(json['makeupForDate']),
      note: serializer.fromJson<String>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'termId': serializer.toJson<String>(termId),
      'date': serializer.toJson<String>(date),
      'kind': serializer.toJson<String>(kind),
      'makeupWeekday': serializer.toJson<int?>(makeupWeekday),
      'makeupForDate': serializer.toJson<String?>(makeupForDate),
      'note': serializer.toJson<String>(note),
    };
  }

  CalendarException copyWith({
    String? id,
    String? termId,
    String? date,
    String? kind,
    Value<int?> makeupWeekday = const Value.absent(),
    Value<String?> makeupForDate = const Value.absent(),
    String? note,
  }) => CalendarException(
    id: id ?? this.id,
    termId: termId ?? this.termId,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    makeupWeekday: makeupWeekday.present
        ? makeupWeekday.value
        : this.makeupWeekday,
    makeupForDate: makeupForDate.present
        ? makeupForDate.value
        : this.makeupForDate,
    note: note ?? this.note,
  );
  CalendarException copyWithCompanion(CalendarExceptionsCompanion data) {
    return CalendarException(
      id: data.id.present ? data.id.value : this.id,
      termId: data.termId.present ? data.termId.value : this.termId,
      date: data.date.present ? data.date.value : this.date,
      kind: data.kind.present ? data.kind.value : this.kind,
      makeupWeekday: data.makeupWeekday.present
          ? data.makeupWeekday.value
          : this.makeupWeekday,
      makeupForDate: data.makeupForDate.present
          ? data.makeupForDate.value
          : this.makeupForDate,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalendarException(')
          ..write('id: $id, ')
          ..write('termId: $termId, ')
          ..write('date: $date, ')
          ..write('kind: $kind, ')
          ..write('makeupWeekday: $makeupWeekday, ')
          ..write('makeupForDate: $makeupForDate, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, termId, date, kind, makeupWeekday, makeupForDate, note);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalendarException &&
          other.id == this.id &&
          other.termId == this.termId &&
          other.date == this.date &&
          other.kind == this.kind &&
          other.makeupWeekday == this.makeupWeekday &&
          other.makeupForDate == this.makeupForDate &&
          other.note == this.note);
}

class CalendarExceptionsCompanion extends UpdateCompanion<CalendarException> {
  final Value<String> id;
  final Value<String> termId;
  final Value<String> date;
  final Value<String> kind;
  final Value<int?> makeupWeekday;
  final Value<String?> makeupForDate;
  final Value<String> note;
  final Value<int> rowid;
  const CalendarExceptionsCompanion({
    this.id = const Value.absent(),
    this.termId = const Value.absent(),
    this.date = const Value.absent(),
    this.kind = const Value.absent(),
    this.makeupWeekday = const Value.absent(),
    this.makeupForDate = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CalendarExceptionsCompanion.insert({
    required String id,
    required String termId,
    required String date,
    required String kind,
    this.makeupWeekday = const Value.absent(),
    this.makeupForDate = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       termId = Value(termId),
       date = Value(date),
       kind = Value(kind);
  static Insertable<CalendarException> custom({
    Expression<String>? id,
    Expression<String>? termId,
    Expression<String>? date,
    Expression<String>? kind,
    Expression<int>? makeupWeekday,
    Expression<String>? makeupForDate,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (termId != null) 'term_id': termId,
      if (date != null) 'date': date,
      if (kind != null) 'kind': kind,
      if (makeupWeekday != null) 'makeup_weekday': makeupWeekday,
      if (makeupForDate != null) 'makeup_for_date': makeupForDate,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CalendarExceptionsCompanion copyWith({
    Value<String>? id,
    Value<String>? termId,
    Value<String>? date,
    Value<String>? kind,
    Value<int?>? makeupWeekday,
    Value<String?>? makeupForDate,
    Value<String>? note,
    Value<int>? rowid,
  }) {
    return CalendarExceptionsCompanion(
      id: id ?? this.id,
      termId: termId ?? this.termId,
      date: date ?? this.date,
      kind: kind ?? this.kind,
      makeupWeekday: makeupWeekday ?? this.makeupWeekday,
      makeupForDate: makeupForDate ?? this.makeupForDate,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (termId.present) {
      map['term_id'] = Variable<String>(termId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (makeupWeekday.present) {
      map['makeup_weekday'] = Variable<int>(makeupWeekday.value);
    }
    if (makeupForDate.present) {
      map['makeup_for_date'] = Variable<String>(makeupForDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CalendarExceptionsCompanion(')
          ..write('id: $id, ')
          ..write('termId: $termId, ')
          ..write('date: $date, ')
          ..write('kind: $kind, ')
          ..write('makeupWeekday: $makeupWeekday, ')
          ..write('makeupForDate: $makeupForDate, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FreeSlotsTable extends FreeSlots
    with TableInfo<$FreeSlotsTable, FreeSlot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FreeSlotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeTypeMeta = const VerificationMeta(
    'scopeType',
  );
  @override
  late final GeneratedColumn<String> scopeType = GeneratedColumn<String>(
    'scope_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeIdMeta = const VerificationMeta(
    'scopeId',
  );
  @override
  late final GeneratedColumn<String> scopeId = GeneratedColumn<String>(
    'scope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageIdMeta = const VerificationMeta(
    'stageId',
  );
  @override
  late final GeneratedColumn<String> stageId = GeneratedColumn<String>(
    'stage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES school_stages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _periodTypeIdMeta = const VerificationMeta(
    'periodTypeId',
  );
  @override
  late final GeneratedColumn<String> periodTypeId = GeneratedColumn<String>(
    'period_type_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lesson_period_types (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lessonIndexMeta = const VerificationMeta(
    'lessonIndex',
  );
  @override
  late final GeneratedColumn<int> lessonIndex = GeneratedColumn<int>(
    'lesson_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    scopeType,
    scopeId,
    stageId,
    periodTypeId,
    weekday,
    lessonIndex,
    label,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'free_slots';
  @override
  VerificationContext validateIntegrity(
    Insertable<FreeSlot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('scope_type')) {
      context.handle(
        _scopeTypeMeta,
        scopeType.isAcceptableOrUnknown(data['scope_type']!, _scopeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeTypeMeta);
    }
    if (data.containsKey('scope_id')) {
      context.handle(
        _scopeIdMeta,
        scopeId.isAcceptableOrUnknown(data['scope_id']!, _scopeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeIdMeta);
    }
    if (data.containsKey('stage_id')) {
      context.handle(
        _stageIdMeta,
        stageId.isAcceptableOrUnknown(data['stage_id']!, _stageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stageIdMeta);
    }
    if (data.containsKey('period_type_id')) {
      context.handle(
        _periodTypeIdMeta,
        periodTypeId.isAcceptableOrUnknown(
          data['period_type_id']!,
          _periodTypeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodTypeIdMeta);
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    } else if (isInserting) {
      context.missing(_weekdayMeta);
    }
    if (data.containsKey('lesson_index')) {
      context.handle(
        _lessonIndexMeta,
        lessonIndex.isAcceptableOrUnknown(
          data['lesson_index']!,
          _lessonIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lessonIndexMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FreeSlot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FreeSlot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      scopeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_type'],
      )!,
      scopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_id'],
      )!,
      stageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_id'],
      )!,
      periodTypeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_type_id'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      )!,
      lessonIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lesson_index'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
    );
  }

  @override
  $FreeSlotsTable createAlias(String alias) {
    return $FreeSlotsTable(attachedDatabase, alias);
  }
}

class FreeSlot extends DataClass implements Insertable<FreeSlot> {
  final String id;

  /// school/stage/grade/class。
  final String scopeType;

  /// 范围实体 ID：全校=学期 ID，学段=学段 ID，年级=年级 ID，班级=班级 ID。
  final String scopeId;
  final String stageId;
  final String periodTypeId;
  final int weekday;
  final int lessonIndex;
  final String label;
  const FreeSlot({
    required this.id,
    required this.scopeType,
    required this.scopeId,
    required this.stageId,
    required this.periodTypeId,
    required this.weekday,
    required this.lessonIndex,
    required this.label,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['scope_type'] = Variable<String>(scopeType);
    map['scope_id'] = Variable<String>(scopeId);
    map['stage_id'] = Variable<String>(stageId);
    map['period_type_id'] = Variable<String>(periodTypeId);
    map['weekday'] = Variable<int>(weekday);
    map['lesson_index'] = Variable<int>(lessonIndex);
    map['label'] = Variable<String>(label);
    return map;
  }

  FreeSlotsCompanion toCompanion(bool nullToAbsent) {
    return FreeSlotsCompanion(
      id: Value(id),
      scopeType: Value(scopeType),
      scopeId: Value(scopeId),
      stageId: Value(stageId),
      periodTypeId: Value(periodTypeId),
      weekday: Value(weekday),
      lessonIndex: Value(lessonIndex),
      label: Value(label),
    );
  }

  factory FreeSlot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FreeSlot(
      id: serializer.fromJson<String>(json['id']),
      scopeType: serializer.fromJson<String>(json['scopeType']),
      scopeId: serializer.fromJson<String>(json['scopeId']),
      stageId: serializer.fromJson<String>(json['stageId']),
      periodTypeId: serializer.fromJson<String>(json['periodTypeId']),
      weekday: serializer.fromJson<int>(json['weekday']),
      lessonIndex: serializer.fromJson<int>(json['lessonIndex']),
      label: serializer.fromJson<String>(json['label']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'scopeType': serializer.toJson<String>(scopeType),
      'scopeId': serializer.toJson<String>(scopeId),
      'stageId': serializer.toJson<String>(stageId),
      'periodTypeId': serializer.toJson<String>(periodTypeId),
      'weekday': serializer.toJson<int>(weekday),
      'lessonIndex': serializer.toJson<int>(lessonIndex),
      'label': serializer.toJson<String>(label),
    };
  }

  FreeSlot copyWith({
    String? id,
    String? scopeType,
    String? scopeId,
    String? stageId,
    String? periodTypeId,
    int? weekday,
    int? lessonIndex,
    String? label,
  }) => FreeSlot(
    id: id ?? this.id,
    scopeType: scopeType ?? this.scopeType,
    scopeId: scopeId ?? this.scopeId,
    stageId: stageId ?? this.stageId,
    periodTypeId: periodTypeId ?? this.periodTypeId,
    weekday: weekday ?? this.weekday,
    lessonIndex: lessonIndex ?? this.lessonIndex,
    label: label ?? this.label,
  );
  FreeSlot copyWithCompanion(FreeSlotsCompanion data) {
    return FreeSlot(
      id: data.id.present ? data.id.value : this.id,
      scopeType: data.scopeType.present ? data.scopeType.value : this.scopeType,
      scopeId: data.scopeId.present ? data.scopeId.value : this.scopeId,
      stageId: data.stageId.present ? data.stageId.value : this.stageId,
      periodTypeId: data.periodTypeId.present
          ? data.periodTypeId.value
          : this.periodTypeId,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      lessonIndex: data.lessonIndex.present
          ? data.lessonIndex.value
          : this.lessonIndex,
      label: data.label.present ? data.label.value : this.label,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FreeSlot(')
          ..write('id: $id, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeId: $scopeId, ')
          ..write('stageId: $stageId, ')
          ..write('periodTypeId: $periodTypeId, ')
          ..write('weekday: $weekday, ')
          ..write('lessonIndex: $lessonIndex, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    scopeType,
    scopeId,
    stageId,
    periodTypeId,
    weekday,
    lessonIndex,
    label,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FreeSlot &&
          other.id == this.id &&
          other.scopeType == this.scopeType &&
          other.scopeId == this.scopeId &&
          other.stageId == this.stageId &&
          other.periodTypeId == this.periodTypeId &&
          other.weekday == this.weekday &&
          other.lessonIndex == this.lessonIndex &&
          other.label == this.label);
}

class FreeSlotsCompanion extends UpdateCompanion<FreeSlot> {
  final Value<String> id;
  final Value<String> scopeType;
  final Value<String> scopeId;
  final Value<String> stageId;
  final Value<String> periodTypeId;
  final Value<int> weekday;
  final Value<int> lessonIndex;
  final Value<String> label;
  final Value<int> rowid;
  const FreeSlotsCompanion({
    this.id = const Value.absent(),
    this.scopeType = const Value.absent(),
    this.scopeId = const Value.absent(),
    this.stageId = const Value.absent(),
    this.periodTypeId = const Value.absent(),
    this.weekday = const Value.absent(),
    this.lessonIndex = const Value.absent(),
    this.label = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FreeSlotsCompanion.insert({
    required String id,
    required String scopeType,
    required String scopeId,
    required String stageId,
    required String periodTypeId,
    required int weekday,
    required int lessonIndex,
    required String label,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       scopeType = Value(scopeType),
       scopeId = Value(scopeId),
       stageId = Value(stageId),
       periodTypeId = Value(periodTypeId),
       weekday = Value(weekday),
       lessonIndex = Value(lessonIndex),
       label = Value(label);
  static Insertable<FreeSlot> custom({
    Expression<String>? id,
    Expression<String>? scopeType,
    Expression<String>? scopeId,
    Expression<String>? stageId,
    Expression<String>? periodTypeId,
    Expression<int>? weekday,
    Expression<int>? lessonIndex,
    Expression<String>? label,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scopeType != null) 'scope_type': scopeType,
      if (scopeId != null) 'scope_id': scopeId,
      if (stageId != null) 'stage_id': stageId,
      if (periodTypeId != null) 'period_type_id': periodTypeId,
      if (weekday != null) 'weekday': weekday,
      if (lessonIndex != null) 'lesson_index': lessonIndex,
      if (label != null) 'label': label,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FreeSlotsCompanion copyWith({
    Value<String>? id,
    Value<String>? scopeType,
    Value<String>? scopeId,
    Value<String>? stageId,
    Value<String>? periodTypeId,
    Value<int>? weekday,
    Value<int>? lessonIndex,
    Value<String>? label,
    Value<int>? rowid,
  }) {
    return FreeSlotsCompanion(
      id: id ?? this.id,
      scopeType: scopeType ?? this.scopeType,
      scopeId: scopeId ?? this.scopeId,
      stageId: stageId ?? this.stageId,
      periodTypeId: periodTypeId ?? this.periodTypeId,
      weekday: weekday ?? this.weekday,
      lessonIndex: lessonIndex ?? this.lessonIndex,
      label: label ?? this.label,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (scopeType.present) {
      map['scope_type'] = Variable<String>(scopeType.value);
    }
    if (scopeId.present) {
      map['scope_id'] = Variable<String>(scopeId.value);
    }
    if (stageId.present) {
      map['stage_id'] = Variable<String>(stageId.value);
    }
    if (periodTypeId.present) {
      map['period_type_id'] = Variable<String>(periodTypeId.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (lessonIndex.present) {
      map['lesson_index'] = Variable<int>(lessonIndex.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FreeSlotsCompanion(')
          ..write('id: $id, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeId: $scopeId, ')
          ..write('stageId: $stageId, ')
          ..write('periodTypeId: $periodTypeId, ')
          ..write('weekday: $weekday, ')
          ..write('lessonIndex: $lessonIndex, ')
          ..write('label: $label, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CommonPeriodsTable extends CommonPeriods
    with TableInfo<$CommonPeriodsTable, CommonPeriod> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CommonPeriodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageIdMeta = const VerificationMeta(
    'stageId',
  );
  @override
  late final GeneratedColumn<String> stageId = GeneratedColumn<String>(
    'stage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES school_stages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _insertAfterLessonIdMeta =
      const VerificationMeta('insertAfterLessonId');
  @override
  late final GeneratedColumn<String> insertAfterLessonId =
      GeneratedColumn<String>(
        'insert_after_lesson_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _durationMinutesMeta = const VerificationMeta(
    'durationMinutes',
  );
  @override
  late final GeneratedColumn<int> durationMinutes = GeneratedColumn<int>(
    'duration_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(10),
  );
  static const VerificationMeta _startMinuteMeta = const VerificationMeta(
    'startMinute',
  );
  @override
  late final GeneratedColumn<int> startMinute = GeneratedColumn<int>(
    'start_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endMinuteMeta = const VerificationMeta(
    'endMinute',
  );
  @override
  late final GeneratedColumn<int> endMinute = GeneratedColumn<int>(
    'end_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    stageId,
    name,
    insertAfterLessonId,
    durationMinutes,
    startMinute,
    endMinute,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'common_periods';
  @override
  VerificationContext validateIntegrity(
    Insertable<CommonPeriod> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('stage_id')) {
      context.handle(
        _stageIdMeta,
        stageId.isAcceptableOrUnknown(data['stage_id']!, _stageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stageIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('insert_after_lesson_id')) {
      context.handle(
        _insertAfterLessonIdMeta,
        insertAfterLessonId.isAcceptableOrUnknown(
          data['insert_after_lesson_id']!,
          _insertAfterLessonIdMeta,
        ),
      );
    }
    if (data.containsKey('duration_minutes')) {
      context.handle(
        _durationMinutesMeta,
        durationMinutes.isAcceptableOrUnknown(
          data['duration_minutes']!,
          _durationMinutesMeta,
        ),
      );
    }
    if (data.containsKey('start_minute')) {
      context.handle(
        _startMinuteMeta,
        startMinute.isAcceptableOrUnknown(
          data['start_minute']!,
          _startMinuteMeta,
        ),
      );
    }
    if (data.containsKey('end_minute')) {
      context.handle(
        _endMinuteMeta,
        endMinute.isAcceptableOrUnknown(data['end_minute']!, _endMinuteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CommonPeriod map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CommonPeriod(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      insertAfterLessonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}insert_after_lesson_id'],
      ),
      durationMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_minutes'],
      )!,
      startMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_minute'],
      ),
      endMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_minute'],
      ),
    );
  }

  @override
  $CommonPeriodsTable createAlias(String alias) {
    return $CommonPeriodsTable(attachedDatabase, alias);
  }
}

class CommonPeriod extends DataClass implements Insertable<CommonPeriod> {
  final String id;
  final String stageId;
  final String name;

  /// 挂在 lesson_times.id 之后；null = 第 1 节之前。
  final String? insertAfterLessonId;
  final int durationMinutes;
  final int? startMinute;
  final int? endMinute;
  const CommonPeriod({
    required this.id,
    required this.stageId,
    required this.name,
    this.insertAfterLessonId,
    required this.durationMinutes,
    this.startMinute,
    this.endMinute,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['stage_id'] = Variable<String>(stageId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || insertAfterLessonId != null) {
      map['insert_after_lesson_id'] = Variable<String>(insertAfterLessonId);
    }
    map['duration_minutes'] = Variable<int>(durationMinutes);
    if (!nullToAbsent || startMinute != null) {
      map['start_minute'] = Variable<int>(startMinute);
    }
    if (!nullToAbsent || endMinute != null) {
      map['end_minute'] = Variable<int>(endMinute);
    }
    return map;
  }

  CommonPeriodsCompanion toCompanion(bool nullToAbsent) {
    return CommonPeriodsCompanion(
      id: Value(id),
      stageId: Value(stageId),
      name: Value(name),
      insertAfterLessonId: insertAfterLessonId == null && nullToAbsent
          ? const Value.absent()
          : Value(insertAfterLessonId),
      durationMinutes: Value(durationMinutes),
      startMinute: startMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(startMinute),
      endMinute: endMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(endMinute),
    );
  }

  factory CommonPeriod.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CommonPeriod(
      id: serializer.fromJson<String>(json['id']),
      stageId: serializer.fromJson<String>(json['stageId']),
      name: serializer.fromJson<String>(json['name']),
      insertAfterLessonId: serializer.fromJson<String?>(
        json['insertAfterLessonId'],
      ),
      durationMinutes: serializer.fromJson<int>(json['durationMinutes']),
      startMinute: serializer.fromJson<int?>(json['startMinute']),
      endMinute: serializer.fromJson<int?>(json['endMinute']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stageId': serializer.toJson<String>(stageId),
      'name': serializer.toJson<String>(name),
      'insertAfterLessonId': serializer.toJson<String?>(insertAfterLessonId),
      'durationMinutes': serializer.toJson<int>(durationMinutes),
      'startMinute': serializer.toJson<int?>(startMinute),
      'endMinute': serializer.toJson<int?>(endMinute),
    };
  }

  CommonPeriod copyWith({
    String? id,
    String? stageId,
    String? name,
    Value<String?> insertAfterLessonId = const Value.absent(),
    int? durationMinutes,
    Value<int?> startMinute = const Value.absent(),
    Value<int?> endMinute = const Value.absent(),
  }) => CommonPeriod(
    id: id ?? this.id,
    stageId: stageId ?? this.stageId,
    name: name ?? this.name,
    insertAfterLessonId: insertAfterLessonId.present
        ? insertAfterLessonId.value
        : this.insertAfterLessonId,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    startMinute: startMinute.present ? startMinute.value : this.startMinute,
    endMinute: endMinute.present ? endMinute.value : this.endMinute,
  );
  CommonPeriod copyWithCompanion(CommonPeriodsCompanion data) {
    return CommonPeriod(
      id: data.id.present ? data.id.value : this.id,
      stageId: data.stageId.present ? data.stageId.value : this.stageId,
      name: data.name.present ? data.name.value : this.name,
      insertAfterLessonId: data.insertAfterLessonId.present
          ? data.insertAfterLessonId.value
          : this.insertAfterLessonId,
      durationMinutes: data.durationMinutes.present
          ? data.durationMinutes.value
          : this.durationMinutes,
      startMinute: data.startMinute.present
          ? data.startMinute.value
          : this.startMinute,
      endMinute: data.endMinute.present ? data.endMinute.value : this.endMinute,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CommonPeriod(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('name: $name, ')
          ..write('insertAfterLessonId: $insertAfterLessonId, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    stageId,
    name,
    insertAfterLessonId,
    durationMinutes,
    startMinute,
    endMinute,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CommonPeriod &&
          other.id == this.id &&
          other.stageId == this.stageId &&
          other.name == this.name &&
          other.insertAfterLessonId == this.insertAfterLessonId &&
          other.durationMinutes == this.durationMinutes &&
          other.startMinute == this.startMinute &&
          other.endMinute == this.endMinute);
}

class CommonPeriodsCompanion extends UpdateCompanion<CommonPeriod> {
  final Value<String> id;
  final Value<String> stageId;
  final Value<String> name;
  final Value<String?> insertAfterLessonId;
  final Value<int> durationMinutes;
  final Value<int?> startMinute;
  final Value<int?> endMinute;
  final Value<int> rowid;
  const CommonPeriodsCompanion({
    this.id = const Value.absent(),
    this.stageId = const Value.absent(),
    this.name = const Value.absent(),
    this.insertAfterLessonId = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CommonPeriodsCompanion.insert({
    required String id,
    required String stageId,
    required String name,
    this.insertAfterLessonId = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stageId = Value(stageId),
       name = Value(name);
  static Insertable<CommonPeriod> custom({
    Expression<String>? id,
    Expression<String>? stageId,
    Expression<String>? name,
    Expression<String>? insertAfterLessonId,
    Expression<int>? durationMinutes,
    Expression<int>? startMinute,
    Expression<int>? endMinute,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stageId != null) 'stage_id': stageId,
      if (name != null) 'name': name,
      if (insertAfterLessonId != null)
        'insert_after_lesson_id': insertAfterLessonId,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (startMinute != null) 'start_minute': startMinute,
      if (endMinute != null) 'end_minute': endMinute,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CommonPeriodsCompanion copyWith({
    Value<String>? id,
    Value<String>? stageId,
    Value<String>? name,
    Value<String?>? insertAfterLessonId,
    Value<int>? durationMinutes,
    Value<int?>? startMinute,
    Value<int?>? endMinute,
    Value<int>? rowid,
  }) {
    return CommonPeriodsCompanion(
      id: id ?? this.id,
      stageId: stageId ?? this.stageId,
      name: name ?? this.name,
      insertAfterLessonId: insertAfterLessonId ?? this.insertAfterLessonId,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (stageId.present) {
      map['stage_id'] = Variable<String>(stageId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (insertAfterLessonId.present) {
      map['insert_after_lesson_id'] = Variable<String>(
        insertAfterLessonId.value,
      );
    }
    if (durationMinutes.present) {
      map['duration_minutes'] = Variable<int>(durationMinutes.value);
    }
    if (startMinute.present) {
      map['start_minute'] = Variable<int>(startMinute.value);
    }
    if (endMinute.present) {
      map['end_minute'] = Variable<int>(endMinute.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CommonPeriodsCompanion(')
          ..write('id: $id, ')
          ..write('stageId: $stageId, ')
          ..write('name: $name, ')
          ..write('insertAfterLessonId: $insertAfterLessonId, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SubjectsTable extends Subjects with TableInfo<$SubjectsTable, Subject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shortNameMeta = const VerificationMeta(
    'shortName',
  );
  @override
  late final GeneratedColumn<String> shortName = GeneratedColumn<String>(
    'short_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, shortName, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subjects';
  @override
  VerificationContext validateIntegrity(
    Insertable<Subject> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('short_name')) {
      context.handle(
        _shortNameMeta,
        shortName.isAcceptableOrUnknown(data['short_name']!, _shortNameMeta),
      );
    } else if (isInserting) {
      context.missing(_shortNameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Subject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Subject(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      shortName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}short_name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $SubjectsTable createAlias(String alias) {
    return $SubjectsTable(attachedDatabase, alias);
  }
}

class Subject extends DataClass implements Insertable<Subject> {
  final String id;
  final String name;
  final String shortName;
  final int sortOrder;
  const Subject({
    required this.id,
    required this.name,
    required this.shortName,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['short_name'] = Variable<String>(shortName);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  SubjectsCompanion toCompanion(bool nullToAbsent) {
    return SubjectsCompanion(
      id: Value(id),
      name: Value(name),
      shortName: Value(shortName),
      sortOrder: Value(sortOrder),
    );
  }

  factory Subject.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Subject(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      shortName: serializer.fromJson<String>(json['shortName']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'shortName': serializer.toJson<String>(shortName),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Subject copyWith({
    String? id,
    String? name,
    String? shortName,
    int? sortOrder,
  }) => Subject(
    id: id ?? this.id,
    name: name ?? this.name,
    shortName: shortName ?? this.shortName,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  Subject copyWithCompanion(SubjectsCompanion data) {
    return Subject(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      shortName: data.shortName.present ? data.shortName.value : this.shortName,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Subject(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, shortName, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Subject &&
          other.id == this.id &&
          other.name == this.name &&
          other.shortName == this.shortName &&
          other.sortOrder == this.sortOrder);
}

class SubjectsCompanion extends UpdateCompanion<Subject> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> shortName;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const SubjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.shortName = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubjectsCompanion.insert({
    required String id,
    required String name,
    required String shortName,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       shortName = Value(shortName),
       sortOrder = Value(sortOrder);
  static Insertable<Subject> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? shortName,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (shortName != null) 'short_name': shortName,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubjectsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? shortName,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return SubjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (shortName.present) {
      map['short_name'] = Variable<String>(shortName.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SubjectRequirementsTable extends SubjectRequirements
    with TableInfo<$SubjectRequirementsTable, SubjectRequirement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubjectRequirementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES subjects (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _gradeIdMeta = const VerificationMeta(
    'gradeId',
  );
  @override
  late final GeneratedColumn<String> gradeId = GeneratedColumn<String>(
    'grade_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES grade_groups (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _classIdMeta = const VerificationMeta(
    'classId',
  );
  @override
  late final GeneratedColumn<String> classId = GeneratedColumn<String>(
    'class_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES class_groups (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _weekModeMeta = const VerificationMeta(
    'weekMode',
  );
  @override
  late final GeneratedColumn<String> weekMode = GeneratedColumn<String>(
    'week_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('weekly'),
  );
  static const VerificationMeta _lessonCountMeta = const VerificationMeta(
    'lessonCount',
  );
  @override
  late final GeneratedColumn<int> lessonCount = GeneratedColumn<int>(
    'lesson_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subjectId,
    gradeId,
    classId,
    weekMode,
    lessonCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subject_requirements';
  @override
  VerificationContext validateIntegrity(
    Insertable<SubjectRequirement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('grade_id')) {
      context.handle(
        _gradeIdMeta,
        gradeId.isAcceptableOrUnknown(data['grade_id']!, _gradeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gradeIdMeta);
    }
    if (data.containsKey('class_id')) {
      context.handle(
        _classIdMeta,
        classId.isAcceptableOrUnknown(data['class_id']!, _classIdMeta),
      );
    }
    if (data.containsKey('week_mode')) {
      context.handle(
        _weekModeMeta,
        weekMode.isAcceptableOrUnknown(data['week_mode']!, _weekModeMeta),
      );
    }
    if (data.containsKey('lesson_count')) {
      context.handle(
        _lessonCountMeta,
        lessonCount.isAcceptableOrUnknown(
          data['lesson_count']!,
          _lessonCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SubjectRequirement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubjectRequirement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      gradeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grade_id'],
      )!,
      classId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}class_id'],
      ),
      weekMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}week_mode'],
      )!,
      lessonCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lesson_count'],
      )!,
    );
  }

  @override
  $SubjectRequirementsTable createAlias(String alias) {
    return $SubjectRequirementsTable(attachedDatabase, alias);
  }
}

class SubjectRequirement extends DataClass
    implements Insertable<SubjectRequirement> {
  final String id;
  final String subjectId;
  final String gradeId;

  /// 非 null = 按班覆盖；null = 年级默认。
  final String? classId;

  /// weekly / odd / even。
  final String weekMode;
  final int lessonCount;
  const SubjectRequirement({
    required this.id,
    required this.subjectId,
    required this.gradeId,
    this.classId,
    required this.weekMode,
    required this.lessonCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['subject_id'] = Variable<String>(subjectId);
    map['grade_id'] = Variable<String>(gradeId);
    if (!nullToAbsent || classId != null) {
      map['class_id'] = Variable<String>(classId);
    }
    map['week_mode'] = Variable<String>(weekMode);
    map['lesson_count'] = Variable<int>(lessonCount);
    return map;
  }

  SubjectRequirementsCompanion toCompanion(bool nullToAbsent) {
    return SubjectRequirementsCompanion(
      id: Value(id),
      subjectId: Value(subjectId),
      gradeId: Value(gradeId),
      classId: classId == null && nullToAbsent
          ? const Value.absent()
          : Value(classId),
      weekMode: Value(weekMode),
      lessonCount: Value(lessonCount),
    );
  }

  factory SubjectRequirement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubjectRequirement(
      id: serializer.fromJson<String>(json['id']),
      subjectId: serializer.fromJson<String>(json['subjectId']),
      gradeId: serializer.fromJson<String>(json['gradeId']),
      classId: serializer.fromJson<String?>(json['classId']),
      weekMode: serializer.fromJson<String>(json['weekMode']),
      lessonCount: serializer.fromJson<int>(json['lessonCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'subjectId': serializer.toJson<String>(subjectId),
      'gradeId': serializer.toJson<String>(gradeId),
      'classId': serializer.toJson<String?>(classId),
      'weekMode': serializer.toJson<String>(weekMode),
      'lessonCount': serializer.toJson<int>(lessonCount),
    };
  }

  SubjectRequirement copyWith({
    String? id,
    String? subjectId,
    String? gradeId,
    Value<String?> classId = const Value.absent(),
    String? weekMode,
    int? lessonCount,
  }) => SubjectRequirement(
    id: id ?? this.id,
    subjectId: subjectId ?? this.subjectId,
    gradeId: gradeId ?? this.gradeId,
    classId: classId.present ? classId.value : this.classId,
    weekMode: weekMode ?? this.weekMode,
    lessonCount: lessonCount ?? this.lessonCount,
  );
  SubjectRequirement copyWithCompanion(SubjectRequirementsCompanion data) {
    return SubjectRequirement(
      id: data.id.present ? data.id.value : this.id,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      gradeId: data.gradeId.present ? data.gradeId.value : this.gradeId,
      classId: data.classId.present ? data.classId.value : this.classId,
      weekMode: data.weekMode.present ? data.weekMode.value : this.weekMode,
      lessonCount: data.lessonCount.present
          ? data.lessonCount.value
          : this.lessonCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubjectRequirement(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('gradeId: $gradeId, ')
          ..write('classId: $classId, ')
          ..write('weekMode: $weekMode, ')
          ..write('lessonCount: $lessonCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, subjectId, gradeId, classId, weekMode, lessonCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubjectRequirement &&
          other.id == this.id &&
          other.subjectId == this.subjectId &&
          other.gradeId == this.gradeId &&
          other.classId == this.classId &&
          other.weekMode == this.weekMode &&
          other.lessonCount == this.lessonCount);
}

class SubjectRequirementsCompanion extends UpdateCompanion<SubjectRequirement> {
  final Value<String> id;
  final Value<String> subjectId;
  final Value<String> gradeId;
  final Value<String?> classId;
  final Value<String> weekMode;
  final Value<int> lessonCount;
  final Value<int> rowid;
  const SubjectRequirementsCompanion({
    this.id = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.gradeId = const Value.absent(),
    this.classId = const Value.absent(),
    this.weekMode = const Value.absent(),
    this.lessonCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubjectRequirementsCompanion.insert({
    required String id,
    required String subjectId,
    required String gradeId,
    this.classId = const Value.absent(),
    this.weekMode = const Value.absent(),
    this.lessonCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       subjectId = Value(subjectId),
       gradeId = Value(gradeId);
  static Insertable<SubjectRequirement> custom({
    Expression<String>? id,
    Expression<String>? subjectId,
    Expression<String>? gradeId,
    Expression<String>? classId,
    Expression<String>? weekMode,
    Expression<int>? lessonCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subjectId != null) 'subject_id': subjectId,
      if (gradeId != null) 'grade_id': gradeId,
      if (classId != null) 'class_id': classId,
      if (weekMode != null) 'week_mode': weekMode,
      if (lessonCount != null) 'lesson_count': lessonCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubjectRequirementsCompanion copyWith({
    Value<String>? id,
    Value<String>? subjectId,
    Value<String>? gradeId,
    Value<String?>? classId,
    Value<String>? weekMode,
    Value<int>? lessonCount,
    Value<int>? rowid,
  }) {
    return SubjectRequirementsCompanion(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      gradeId: gradeId ?? this.gradeId,
      classId: classId ?? this.classId,
      weekMode: weekMode ?? this.weekMode,
      lessonCount: lessonCount ?? this.lessonCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (gradeId.present) {
      map['grade_id'] = Variable<String>(gradeId.value);
    }
    if (classId.present) {
      map['class_id'] = Variable<String>(classId.value);
    }
    if (weekMode.present) {
      map['week_mode'] = Variable<String>(weekMode.value);
    }
    if (lessonCount.present) {
      map['lesson_count'] = Variable<int>(lessonCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubjectRequirementsCompanion(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('gradeId: $gradeId, ')
          ..write('classId: $classId, ')
          ..write('weekMode: $weekMode, ')
          ..write('lessonCount: $lessonCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SubjectPresetsTable extends SubjectPresets
    with TableInfo<$SubjectPresetsTable, SubjectPreset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubjectPresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES subjects (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _scopeTypeMeta = const VerificationMeta(
    'scopeType',
  );
  @override
  late final GeneratedColumn<String> scopeType = GeneratedColumn<String>(
    'scope_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeIdMeta = const VerificationMeta(
    'scopeId',
  );
  @override
  late final GeneratedColumn<String> scopeId = GeneratedColumn<String>(
    'scope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageIdMeta = const VerificationMeta(
    'stageId',
  );
  @override
  late final GeneratedColumn<String> stageId = GeneratedColumn<String>(
    'stage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES school_stages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodTypeIdMeta = const VerificationMeta(
    'periodTypeId',
  );
  @override
  late final GeneratedColumn<String> periodTypeId = GeneratedColumn<String>(
    'period_type_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lesson_period_types (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _lessonIndexMeta = const VerificationMeta(
    'lessonIndex',
  );
  @override
  late final GeneratedColumn<int> lessonIndex = GeneratedColumn<int>(
    'lesson_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('auto'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subjectId,
    scopeType,
    scopeId,
    stageId,
    weekday,
    periodTypeId,
    lessonIndex,
    value,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subject_presets';
  @override
  VerificationContext validateIntegrity(
    Insertable<SubjectPreset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('scope_type')) {
      context.handle(
        _scopeTypeMeta,
        scopeType.isAcceptableOrUnknown(data['scope_type']!, _scopeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeTypeMeta);
    }
    if (data.containsKey('scope_id')) {
      context.handle(
        _scopeIdMeta,
        scopeId.isAcceptableOrUnknown(data['scope_id']!, _scopeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeIdMeta);
    }
    if (data.containsKey('stage_id')) {
      context.handle(
        _stageIdMeta,
        stageId.isAcceptableOrUnknown(data['stage_id']!, _stageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stageIdMeta);
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    } else if (isInserting) {
      context.missing(_weekdayMeta);
    }
    if (data.containsKey('period_type_id')) {
      context.handle(
        _periodTypeIdMeta,
        periodTypeId.isAcceptableOrUnknown(
          data['period_type_id']!,
          _periodTypeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodTypeIdMeta);
    }
    if (data.containsKey('lesson_index')) {
      context.handle(
        _lessonIndexMeta,
        lessonIndex.isAcceptableOrUnknown(
          data['lesson_index']!,
          _lessonIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lessonIndexMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SubjectPreset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubjectPreset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      scopeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_type'],
      )!,
      scopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_id'],
      )!,
      stageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_id'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      )!,
      periodTypeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_type_id'],
      )!,
      lessonIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lesson_index'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SubjectPresetsTable createAlias(String alias) {
    return $SubjectPresetsTable(attachedDatabase, alias);
  }
}

class SubjectPreset extends DataClass implements Insertable<SubjectPreset> {
  final String id;
  final String subjectId;

  /// school/stage/grade/class；全校 scopeId = 学期 ID。
  final String scopeType;
  final String scopeId;

  /// 所属学段（全校范围行按学段展开存储）。
  final String stageId;
  final int weekday;
  final String periodTypeId;
  final int lessonIndex;

  /// auto/prefer/must/forbid。
  final String value;
  const SubjectPreset({
    required this.id,
    required this.subjectId,
    required this.scopeType,
    required this.scopeId,
    required this.stageId,
    required this.weekday,
    required this.periodTypeId,
    required this.lessonIndex,
    required this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['subject_id'] = Variable<String>(subjectId);
    map['scope_type'] = Variable<String>(scopeType);
    map['scope_id'] = Variable<String>(scopeId);
    map['stage_id'] = Variable<String>(stageId);
    map['weekday'] = Variable<int>(weekday);
    map['period_type_id'] = Variable<String>(periodTypeId);
    map['lesson_index'] = Variable<int>(lessonIndex);
    map['value'] = Variable<String>(value);
    return map;
  }

  SubjectPresetsCompanion toCompanion(bool nullToAbsent) {
    return SubjectPresetsCompanion(
      id: Value(id),
      subjectId: Value(subjectId),
      scopeType: Value(scopeType),
      scopeId: Value(scopeId),
      stageId: Value(stageId),
      weekday: Value(weekday),
      periodTypeId: Value(periodTypeId),
      lessonIndex: Value(lessonIndex),
      value: Value(value),
    );
  }

  factory SubjectPreset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubjectPreset(
      id: serializer.fromJson<String>(json['id']),
      subjectId: serializer.fromJson<String>(json['subjectId']),
      scopeType: serializer.fromJson<String>(json['scopeType']),
      scopeId: serializer.fromJson<String>(json['scopeId']),
      stageId: serializer.fromJson<String>(json['stageId']),
      weekday: serializer.fromJson<int>(json['weekday']),
      periodTypeId: serializer.fromJson<String>(json['periodTypeId']),
      lessonIndex: serializer.fromJson<int>(json['lessonIndex']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'subjectId': serializer.toJson<String>(subjectId),
      'scopeType': serializer.toJson<String>(scopeType),
      'scopeId': serializer.toJson<String>(scopeId),
      'stageId': serializer.toJson<String>(stageId),
      'weekday': serializer.toJson<int>(weekday),
      'periodTypeId': serializer.toJson<String>(periodTypeId),
      'lessonIndex': serializer.toJson<int>(lessonIndex),
      'value': serializer.toJson<String>(value),
    };
  }

  SubjectPreset copyWith({
    String? id,
    String? subjectId,
    String? scopeType,
    String? scopeId,
    String? stageId,
    int? weekday,
    String? periodTypeId,
    int? lessonIndex,
    String? value,
  }) => SubjectPreset(
    id: id ?? this.id,
    subjectId: subjectId ?? this.subjectId,
    scopeType: scopeType ?? this.scopeType,
    scopeId: scopeId ?? this.scopeId,
    stageId: stageId ?? this.stageId,
    weekday: weekday ?? this.weekday,
    periodTypeId: periodTypeId ?? this.periodTypeId,
    lessonIndex: lessonIndex ?? this.lessonIndex,
    value: value ?? this.value,
  );
  SubjectPreset copyWithCompanion(SubjectPresetsCompanion data) {
    return SubjectPreset(
      id: data.id.present ? data.id.value : this.id,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      scopeType: data.scopeType.present ? data.scopeType.value : this.scopeType,
      scopeId: data.scopeId.present ? data.scopeId.value : this.scopeId,
      stageId: data.stageId.present ? data.stageId.value : this.stageId,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      periodTypeId: data.periodTypeId.present
          ? data.periodTypeId.value
          : this.periodTypeId,
      lessonIndex: data.lessonIndex.present
          ? data.lessonIndex.value
          : this.lessonIndex,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubjectPreset(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeId: $scopeId, ')
          ..write('stageId: $stageId, ')
          ..write('weekday: $weekday, ')
          ..write('periodTypeId: $periodTypeId, ')
          ..write('lessonIndex: $lessonIndex, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    subjectId,
    scopeType,
    scopeId,
    stageId,
    weekday,
    periodTypeId,
    lessonIndex,
    value,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubjectPreset &&
          other.id == this.id &&
          other.subjectId == this.subjectId &&
          other.scopeType == this.scopeType &&
          other.scopeId == this.scopeId &&
          other.stageId == this.stageId &&
          other.weekday == this.weekday &&
          other.periodTypeId == this.periodTypeId &&
          other.lessonIndex == this.lessonIndex &&
          other.value == this.value);
}

class SubjectPresetsCompanion extends UpdateCompanion<SubjectPreset> {
  final Value<String> id;
  final Value<String> subjectId;
  final Value<String> scopeType;
  final Value<String> scopeId;
  final Value<String> stageId;
  final Value<int> weekday;
  final Value<String> periodTypeId;
  final Value<int> lessonIndex;
  final Value<String> value;
  final Value<int> rowid;
  const SubjectPresetsCompanion({
    this.id = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.scopeType = const Value.absent(),
    this.scopeId = const Value.absent(),
    this.stageId = const Value.absent(),
    this.weekday = const Value.absent(),
    this.periodTypeId = const Value.absent(),
    this.lessonIndex = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubjectPresetsCompanion.insert({
    required String id,
    required String subjectId,
    required String scopeType,
    required String scopeId,
    required String stageId,
    required int weekday,
    required String periodTypeId,
    required int lessonIndex,
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       subjectId = Value(subjectId),
       scopeType = Value(scopeType),
       scopeId = Value(scopeId),
       stageId = Value(stageId),
       weekday = Value(weekday),
       periodTypeId = Value(periodTypeId),
       lessonIndex = Value(lessonIndex);
  static Insertable<SubjectPreset> custom({
    Expression<String>? id,
    Expression<String>? subjectId,
    Expression<String>? scopeType,
    Expression<String>? scopeId,
    Expression<String>? stageId,
    Expression<int>? weekday,
    Expression<String>? periodTypeId,
    Expression<int>? lessonIndex,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subjectId != null) 'subject_id': subjectId,
      if (scopeType != null) 'scope_type': scopeType,
      if (scopeId != null) 'scope_id': scopeId,
      if (stageId != null) 'stage_id': stageId,
      if (weekday != null) 'weekday': weekday,
      if (periodTypeId != null) 'period_type_id': periodTypeId,
      if (lessonIndex != null) 'lesson_index': lessonIndex,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubjectPresetsCompanion copyWith({
    Value<String>? id,
    Value<String>? subjectId,
    Value<String>? scopeType,
    Value<String>? scopeId,
    Value<String>? stageId,
    Value<int>? weekday,
    Value<String>? periodTypeId,
    Value<int>? lessonIndex,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SubjectPresetsCompanion(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      scopeType: scopeType ?? this.scopeType,
      scopeId: scopeId ?? this.scopeId,
      stageId: stageId ?? this.stageId,
      weekday: weekday ?? this.weekday,
      periodTypeId: periodTypeId ?? this.periodTypeId,
      lessonIndex: lessonIndex ?? this.lessonIndex,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (scopeType.present) {
      map['scope_type'] = Variable<String>(scopeType.value);
    }
    if (scopeId.present) {
      map['scope_id'] = Variable<String>(scopeId.value);
    }
    if (stageId.present) {
      map['stage_id'] = Variable<String>(stageId.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (periodTypeId.present) {
      map['period_type_id'] = Variable<String>(periodTypeId.value);
    }
    if (lessonIndex.present) {
      map['lesson_index'] = Variable<int>(lessonIndex.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubjectPresetsCompanion(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeId: $scopeId, ')
          ..write('stageId: $stageId, ')
          ..write('weekday: $weekday, ')
          ..write('periodTypeId: $periodTypeId, ')
          ..write('lessonIndex: $lessonIndex, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SubjectPairingsTable extends SubjectPairings
    with TableInfo<$SubjectPairingsTable, SubjectPairing> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubjectPairingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _classIdMeta = const VerificationMeta(
    'classId',
  );
  @override
  late final GeneratedColumn<String> classId = GeneratedColumn<String>(
    'class_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES class_groups (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _oddSubjectIdMeta = const VerificationMeta(
    'oddSubjectId',
  );
  @override
  late final GeneratedColumn<String> oddSubjectId = GeneratedColumn<String>(
    'odd_subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES subjects (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _evenSubjectIdMeta = const VerificationMeta(
    'evenSubjectId',
  );
  @override
  late final GeneratedColumn<String> evenSubjectId = GeneratedColumn<String>(
    'even_subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES subjects (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    classId,
    oddSubjectId,
    evenSubjectId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subject_pairings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SubjectPairing> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('class_id')) {
      context.handle(
        _classIdMeta,
        classId.isAcceptableOrUnknown(data['class_id']!, _classIdMeta),
      );
    } else if (isInserting) {
      context.missing(_classIdMeta);
    }
    if (data.containsKey('odd_subject_id')) {
      context.handle(
        _oddSubjectIdMeta,
        oddSubjectId.isAcceptableOrUnknown(
          data['odd_subject_id']!,
          _oddSubjectIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_oddSubjectIdMeta);
    }
    if (data.containsKey('even_subject_id')) {
      context.handle(
        _evenSubjectIdMeta,
        evenSubjectId.isAcceptableOrUnknown(
          data['even_subject_id']!,
          _evenSubjectIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_evenSubjectIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SubjectPairing map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubjectPairing(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      classId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}class_id'],
      )!,
      oddSubjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}odd_subject_id'],
      )!,
      evenSubjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}even_subject_id'],
      )!,
    );
  }

  @override
  $SubjectPairingsTable createAlias(String alias) {
    return $SubjectPairingsTable(attachedDatabase, alias);
  }
}

class SubjectPairing extends DataClass implements Insertable<SubjectPairing> {
  final String id;
  final String classId;
  final String oddSubjectId;
  final String evenSubjectId;
  const SubjectPairing({
    required this.id,
    required this.classId,
    required this.oddSubjectId,
    required this.evenSubjectId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['class_id'] = Variable<String>(classId);
    map['odd_subject_id'] = Variable<String>(oddSubjectId);
    map['even_subject_id'] = Variable<String>(evenSubjectId);
    return map;
  }

  SubjectPairingsCompanion toCompanion(bool nullToAbsent) {
    return SubjectPairingsCompanion(
      id: Value(id),
      classId: Value(classId),
      oddSubjectId: Value(oddSubjectId),
      evenSubjectId: Value(evenSubjectId),
    );
  }

  factory SubjectPairing.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubjectPairing(
      id: serializer.fromJson<String>(json['id']),
      classId: serializer.fromJson<String>(json['classId']),
      oddSubjectId: serializer.fromJson<String>(json['oddSubjectId']),
      evenSubjectId: serializer.fromJson<String>(json['evenSubjectId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'classId': serializer.toJson<String>(classId),
      'oddSubjectId': serializer.toJson<String>(oddSubjectId),
      'evenSubjectId': serializer.toJson<String>(evenSubjectId),
    };
  }

  SubjectPairing copyWith({
    String? id,
    String? classId,
    String? oddSubjectId,
    String? evenSubjectId,
  }) => SubjectPairing(
    id: id ?? this.id,
    classId: classId ?? this.classId,
    oddSubjectId: oddSubjectId ?? this.oddSubjectId,
    evenSubjectId: evenSubjectId ?? this.evenSubjectId,
  );
  SubjectPairing copyWithCompanion(SubjectPairingsCompanion data) {
    return SubjectPairing(
      id: data.id.present ? data.id.value : this.id,
      classId: data.classId.present ? data.classId.value : this.classId,
      oddSubjectId: data.oddSubjectId.present
          ? data.oddSubjectId.value
          : this.oddSubjectId,
      evenSubjectId: data.evenSubjectId.present
          ? data.evenSubjectId.value
          : this.evenSubjectId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubjectPairing(')
          ..write('id: $id, ')
          ..write('classId: $classId, ')
          ..write('oddSubjectId: $oddSubjectId, ')
          ..write('evenSubjectId: $evenSubjectId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, classId, oddSubjectId, evenSubjectId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubjectPairing &&
          other.id == this.id &&
          other.classId == this.classId &&
          other.oddSubjectId == this.oddSubjectId &&
          other.evenSubjectId == this.evenSubjectId);
}

class SubjectPairingsCompanion extends UpdateCompanion<SubjectPairing> {
  final Value<String> id;
  final Value<String> classId;
  final Value<String> oddSubjectId;
  final Value<String> evenSubjectId;
  final Value<int> rowid;
  const SubjectPairingsCompanion({
    this.id = const Value.absent(),
    this.classId = const Value.absent(),
    this.oddSubjectId = const Value.absent(),
    this.evenSubjectId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubjectPairingsCompanion.insert({
    required String id,
    required String classId,
    required String oddSubjectId,
    required String evenSubjectId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       classId = Value(classId),
       oddSubjectId = Value(oddSubjectId),
       evenSubjectId = Value(evenSubjectId);
  static Insertable<SubjectPairing> custom({
    Expression<String>? id,
    Expression<String>? classId,
    Expression<String>? oddSubjectId,
    Expression<String>? evenSubjectId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (classId != null) 'class_id': classId,
      if (oddSubjectId != null) 'odd_subject_id': oddSubjectId,
      if (evenSubjectId != null) 'even_subject_id': evenSubjectId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubjectPairingsCompanion copyWith({
    Value<String>? id,
    Value<String>? classId,
    Value<String>? oddSubjectId,
    Value<String>? evenSubjectId,
    Value<int>? rowid,
  }) {
    return SubjectPairingsCompanion(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      oddSubjectId: oddSubjectId ?? this.oddSubjectId,
      evenSubjectId: evenSubjectId ?? this.evenSubjectId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (classId.present) {
      map['class_id'] = Variable<String>(classId.value);
    }
    if (oddSubjectId.present) {
      map['odd_subject_id'] = Variable<String>(oddSubjectId.value);
    }
    if (evenSubjectId.present) {
      map['even_subject_id'] = Variable<String>(evenSubjectId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubjectPairingsCompanion(')
          ..write('id: $id, ')
          ..write('classId: $classId, ')
          ..write('oddSubjectId: $oddSubjectId, ')
          ..write('evenSubjectId: $evenSubjectId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SubjectLessonConstraintsTable extends SubjectLessonConstraints
    with TableInfo<$SubjectLessonConstraintsTable, SubjectLessonConstraint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubjectLessonConstraintsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES subjects (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _scopeTypeMeta = const VerificationMeta(
    'scopeType',
  );
  @override
  late final GeneratedColumn<String> scopeType = GeneratedColumn<String>(
    'scope_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeIdMeta = const VerificationMeta(
    'scopeId',
  );
  @override
  late final GeneratedColumn<String> scopeId = GeneratedColumn<String>(
    'scope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageIdMeta = const VerificationMeta(
    'stageId',
  );
  @override
  late final GeneratedColumn<String> stageId = GeneratedColumn<String>(
    'stage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES school_stages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minimumDailyLessonsMeta =
      const VerificationMeta('minimumDailyLessons');
  @override
  late final GeneratedColumn<int> minimumDailyLessons = GeneratedColumn<int>(
    'minimum_daily_lessons',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maximumDailyLessonsMeta =
      const VerificationMeta('maximumDailyLessons');
  @override
  late final GeneratedColumn<int> maximumDailyLessons = GeneratedColumn<int>(
    'maximum_daily_lessons',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minimumDailyConsecutivePairsMeta =
      const VerificationMeta('minimumDailyConsecutivePairs');
  @override
  late final GeneratedColumn<int> minimumDailyConsecutivePairs =
      GeneratedColumn<int>(
        'minimum_daily_consecutive_pairs',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _maximumDailyConsecutivePairsMeta =
      const VerificationMeta('maximumDailyConsecutivePairs');
  @override
  late final GeneratedColumn<int> maximumDailyConsecutivePairs =
      GeneratedColumn<int>(
        'maximum_daily_consecutive_pairs',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _minimumWeeklyConsecutivePairsMeta =
      const VerificationMeta('minimumWeeklyConsecutivePairs');
  @override
  late final GeneratedColumn<int> minimumWeeklyConsecutivePairs =
      GeneratedColumn<int>(
        'minimum_weekly_consecutive_pairs',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _maximumWeeklyConsecutivePairsMeta =
      const VerificationMeta('maximumWeeklyConsecutivePairs');
  @override
  late final GeneratedColumn<int> maximumWeeklyConsecutivePairs =
      GeneratedColumn<int>(
        'maximum_weekly_consecutive_pairs',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subjectId,
    scopeType,
    scopeId,
    stageId,
    weekday,
    minimumDailyLessons,
    maximumDailyLessons,
    minimumDailyConsecutivePairs,
    maximumDailyConsecutivePairs,
    minimumWeeklyConsecutivePairs,
    maximumWeeklyConsecutivePairs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subject_lesson_constraints';
  @override
  VerificationContext validateIntegrity(
    Insertable<SubjectLessonConstraint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('scope_type')) {
      context.handle(
        _scopeTypeMeta,
        scopeType.isAcceptableOrUnknown(data['scope_type']!, _scopeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeTypeMeta);
    }
    if (data.containsKey('scope_id')) {
      context.handle(
        _scopeIdMeta,
        scopeId.isAcceptableOrUnknown(data['scope_id']!, _scopeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeIdMeta);
    }
    if (data.containsKey('stage_id')) {
      context.handle(
        _stageIdMeta,
        stageId.isAcceptableOrUnknown(data['stage_id']!, _stageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stageIdMeta);
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    }
    if (data.containsKey('minimum_daily_lessons')) {
      context.handle(
        _minimumDailyLessonsMeta,
        minimumDailyLessons.isAcceptableOrUnknown(
          data['minimum_daily_lessons']!,
          _minimumDailyLessonsMeta,
        ),
      );
    }
    if (data.containsKey('maximum_daily_lessons')) {
      context.handle(
        _maximumDailyLessonsMeta,
        maximumDailyLessons.isAcceptableOrUnknown(
          data['maximum_daily_lessons']!,
          _maximumDailyLessonsMeta,
        ),
      );
    }
    if (data.containsKey('minimum_daily_consecutive_pairs')) {
      context.handle(
        _minimumDailyConsecutivePairsMeta,
        minimumDailyConsecutivePairs.isAcceptableOrUnknown(
          data['minimum_daily_consecutive_pairs']!,
          _minimumDailyConsecutivePairsMeta,
        ),
      );
    }
    if (data.containsKey('maximum_daily_consecutive_pairs')) {
      context.handle(
        _maximumDailyConsecutivePairsMeta,
        maximumDailyConsecutivePairs.isAcceptableOrUnknown(
          data['maximum_daily_consecutive_pairs']!,
          _maximumDailyConsecutivePairsMeta,
        ),
      );
    }
    if (data.containsKey('minimum_weekly_consecutive_pairs')) {
      context.handle(
        _minimumWeeklyConsecutivePairsMeta,
        minimumWeeklyConsecutivePairs.isAcceptableOrUnknown(
          data['minimum_weekly_consecutive_pairs']!,
          _minimumWeeklyConsecutivePairsMeta,
        ),
      );
    }
    if (data.containsKey('maximum_weekly_consecutive_pairs')) {
      context.handle(
        _maximumWeeklyConsecutivePairsMeta,
        maximumWeeklyConsecutivePairs.isAcceptableOrUnknown(
          data['maximum_weekly_consecutive_pairs']!,
          _maximumWeeklyConsecutivePairsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {subjectId, scopeType, scopeId, stageId, weekday},
  ];
  @override
  SubjectLessonConstraint map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubjectLessonConstraint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      scopeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_type'],
      )!,
      scopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_id'],
      )!,
      stageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_id'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      ),
      minimumDailyLessons: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minimum_daily_lessons'],
      ),
      maximumDailyLessons: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}maximum_daily_lessons'],
      ),
      minimumDailyConsecutivePairs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minimum_daily_consecutive_pairs'],
      ),
      maximumDailyConsecutivePairs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}maximum_daily_consecutive_pairs'],
      ),
      minimumWeeklyConsecutivePairs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minimum_weekly_consecutive_pairs'],
      ),
      maximumWeeklyConsecutivePairs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}maximum_weekly_consecutive_pairs'],
      ),
    );
  }

  @override
  $SubjectLessonConstraintsTable createAlias(String alias) {
    return $SubjectLessonConstraintsTable(attachedDatabase, alias);
  }
}

class SubjectLessonConstraint extends DataClass
    implements Insertable<SubjectLessonConstraint> {
  final String id;
  final String subjectId;
  final String scopeType;
  final String scopeId;
  final String stageId;

  /// null 表示“每天”；1 到 7 覆盖某个星期。
  final int? weekday;
  final int? minimumDailyLessons;
  final int? maximumDailyLessons;
  final int? minimumDailyConsecutivePairs;
  final int? maximumDailyConsecutivePairs;
  final int? minimumWeeklyConsecutivePairs;
  final int? maximumWeeklyConsecutivePairs;
  const SubjectLessonConstraint({
    required this.id,
    required this.subjectId,
    required this.scopeType,
    required this.scopeId,
    required this.stageId,
    this.weekday,
    this.minimumDailyLessons,
    this.maximumDailyLessons,
    this.minimumDailyConsecutivePairs,
    this.maximumDailyConsecutivePairs,
    this.minimumWeeklyConsecutivePairs,
    this.maximumWeeklyConsecutivePairs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['subject_id'] = Variable<String>(subjectId);
    map['scope_type'] = Variable<String>(scopeType);
    map['scope_id'] = Variable<String>(scopeId);
    map['stage_id'] = Variable<String>(stageId);
    if (!nullToAbsent || weekday != null) {
      map['weekday'] = Variable<int>(weekday);
    }
    if (!nullToAbsent || minimumDailyLessons != null) {
      map['minimum_daily_lessons'] = Variable<int>(minimumDailyLessons);
    }
    if (!nullToAbsent || maximumDailyLessons != null) {
      map['maximum_daily_lessons'] = Variable<int>(maximumDailyLessons);
    }
    if (!nullToAbsent || minimumDailyConsecutivePairs != null) {
      map['minimum_daily_consecutive_pairs'] = Variable<int>(
        minimumDailyConsecutivePairs,
      );
    }
    if (!nullToAbsent || maximumDailyConsecutivePairs != null) {
      map['maximum_daily_consecutive_pairs'] = Variable<int>(
        maximumDailyConsecutivePairs,
      );
    }
    if (!nullToAbsent || minimumWeeklyConsecutivePairs != null) {
      map['minimum_weekly_consecutive_pairs'] = Variable<int>(
        minimumWeeklyConsecutivePairs,
      );
    }
    if (!nullToAbsent || maximumWeeklyConsecutivePairs != null) {
      map['maximum_weekly_consecutive_pairs'] = Variable<int>(
        maximumWeeklyConsecutivePairs,
      );
    }
    return map;
  }

  SubjectLessonConstraintsCompanion toCompanion(bool nullToAbsent) {
    return SubjectLessonConstraintsCompanion(
      id: Value(id),
      subjectId: Value(subjectId),
      scopeType: Value(scopeType),
      scopeId: Value(scopeId),
      stageId: Value(stageId),
      weekday: weekday == null && nullToAbsent
          ? const Value.absent()
          : Value(weekday),
      minimumDailyLessons: minimumDailyLessons == null && nullToAbsent
          ? const Value.absent()
          : Value(minimumDailyLessons),
      maximumDailyLessons: maximumDailyLessons == null && nullToAbsent
          ? const Value.absent()
          : Value(maximumDailyLessons),
      minimumDailyConsecutivePairs:
          minimumDailyConsecutivePairs == null && nullToAbsent
          ? const Value.absent()
          : Value(minimumDailyConsecutivePairs),
      maximumDailyConsecutivePairs:
          maximumDailyConsecutivePairs == null && nullToAbsent
          ? const Value.absent()
          : Value(maximumDailyConsecutivePairs),
      minimumWeeklyConsecutivePairs:
          minimumWeeklyConsecutivePairs == null && nullToAbsent
          ? const Value.absent()
          : Value(minimumWeeklyConsecutivePairs),
      maximumWeeklyConsecutivePairs:
          maximumWeeklyConsecutivePairs == null && nullToAbsent
          ? const Value.absent()
          : Value(maximumWeeklyConsecutivePairs),
    );
  }

  factory SubjectLessonConstraint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubjectLessonConstraint(
      id: serializer.fromJson<String>(json['id']),
      subjectId: serializer.fromJson<String>(json['subjectId']),
      scopeType: serializer.fromJson<String>(json['scopeType']),
      scopeId: serializer.fromJson<String>(json['scopeId']),
      stageId: serializer.fromJson<String>(json['stageId']),
      weekday: serializer.fromJson<int?>(json['weekday']),
      minimumDailyLessons: serializer.fromJson<int?>(
        json['minimumDailyLessons'],
      ),
      maximumDailyLessons: serializer.fromJson<int?>(
        json['maximumDailyLessons'],
      ),
      minimumDailyConsecutivePairs: serializer.fromJson<int?>(
        json['minimumDailyConsecutivePairs'],
      ),
      maximumDailyConsecutivePairs: serializer.fromJson<int?>(
        json['maximumDailyConsecutivePairs'],
      ),
      minimumWeeklyConsecutivePairs: serializer.fromJson<int?>(
        json['minimumWeeklyConsecutivePairs'],
      ),
      maximumWeeklyConsecutivePairs: serializer.fromJson<int?>(
        json['maximumWeeklyConsecutivePairs'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'subjectId': serializer.toJson<String>(subjectId),
      'scopeType': serializer.toJson<String>(scopeType),
      'scopeId': serializer.toJson<String>(scopeId),
      'stageId': serializer.toJson<String>(stageId),
      'weekday': serializer.toJson<int?>(weekday),
      'minimumDailyLessons': serializer.toJson<int?>(minimumDailyLessons),
      'maximumDailyLessons': serializer.toJson<int?>(maximumDailyLessons),
      'minimumDailyConsecutivePairs': serializer.toJson<int?>(
        minimumDailyConsecutivePairs,
      ),
      'maximumDailyConsecutivePairs': serializer.toJson<int?>(
        maximumDailyConsecutivePairs,
      ),
      'minimumWeeklyConsecutivePairs': serializer.toJson<int?>(
        minimumWeeklyConsecutivePairs,
      ),
      'maximumWeeklyConsecutivePairs': serializer.toJson<int?>(
        maximumWeeklyConsecutivePairs,
      ),
    };
  }

  SubjectLessonConstraint copyWith({
    String? id,
    String? subjectId,
    String? scopeType,
    String? scopeId,
    String? stageId,
    Value<int?> weekday = const Value.absent(),
    Value<int?> minimumDailyLessons = const Value.absent(),
    Value<int?> maximumDailyLessons = const Value.absent(),
    Value<int?> minimumDailyConsecutivePairs = const Value.absent(),
    Value<int?> maximumDailyConsecutivePairs = const Value.absent(),
    Value<int?> minimumWeeklyConsecutivePairs = const Value.absent(),
    Value<int?> maximumWeeklyConsecutivePairs = const Value.absent(),
  }) => SubjectLessonConstraint(
    id: id ?? this.id,
    subjectId: subjectId ?? this.subjectId,
    scopeType: scopeType ?? this.scopeType,
    scopeId: scopeId ?? this.scopeId,
    stageId: stageId ?? this.stageId,
    weekday: weekday.present ? weekday.value : this.weekday,
    minimumDailyLessons: minimumDailyLessons.present
        ? minimumDailyLessons.value
        : this.minimumDailyLessons,
    maximumDailyLessons: maximumDailyLessons.present
        ? maximumDailyLessons.value
        : this.maximumDailyLessons,
    minimumDailyConsecutivePairs: minimumDailyConsecutivePairs.present
        ? minimumDailyConsecutivePairs.value
        : this.minimumDailyConsecutivePairs,
    maximumDailyConsecutivePairs: maximumDailyConsecutivePairs.present
        ? maximumDailyConsecutivePairs.value
        : this.maximumDailyConsecutivePairs,
    minimumWeeklyConsecutivePairs: minimumWeeklyConsecutivePairs.present
        ? minimumWeeklyConsecutivePairs.value
        : this.minimumWeeklyConsecutivePairs,
    maximumWeeklyConsecutivePairs: maximumWeeklyConsecutivePairs.present
        ? maximumWeeklyConsecutivePairs.value
        : this.maximumWeeklyConsecutivePairs,
  );
  SubjectLessonConstraint copyWithCompanion(
    SubjectLessonConstraintsCompanion data,
  ) {
    return SubjectLessonConstraint(
      id: data.id.present ? data.id.value : this.id,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      scopeType: data.scopeType.present ? data.scopeType.value : this.scopeType,
      scopeId: data.scopeId.present ? data.scopeId.value : this.scopeId,
      stageId: data.stageId.present ? data.stageId.value : this.stageId,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      minimumDailyLessons: data.minimumDailyLessons.present
          ? data.minimumDailyLessons.value
          : this.minimumDailyLessons,
      maximumDailyLessons: data.maximumDailyLessons.present
          ? data.maximumDailyLessons.value
          : this.maximumDailyLessons,
      minimumDailyConsecutivePairs: data.minimumDailyConsecutivePairs.present
          ? data.minimumDailyConsecutivePairs.value
          : this.minimumDailyConsecutivePairs,
      maximumDailyConsecutivePairs: data.maximumDailyConsecutivePairs.present
          ? data.maximumDailyConsecutivePairs.value
          : this.maximumDailyConsecutivePairs,
      minimumWeeklyConsecutivePairs: data.minimumWeeklyConsecutivePairs.present
          ? data.minimumWeeklyConsecutivePairs.value
          : this.minimumWeeklyConsecutivePairs,
      maximumWeeklyConsecutivePairs: data.maximumWeeklyConsecutivePairs.present
          ? data.maximumWeeklyConsecutivePairs.value
          : this.maximumWeeklyConsecutivePairs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubjectLessonConstraint(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeId: $scopeId, ')
          ..write('stageId: $stageId, ')
          ..write('weekday: $weekday, ')
          ..write('minimumDailyLessons: $minimumDailyLessons, ')
          ..write('maximumDailyLessons: $maximumDailyLessons, ')
          ..write(
            'minimumDailyConsecutivePairs: $minimumDailyConsecutivePairs, ',
          )
          ..write(
            'maximumDailyConsecutivePairs: $maximumDailyConsecutivePairs, ',
          )
          ..write(
            'minimumWeeklyConsecutivePairs: $minimumWeeklyConsecutivePairs, ',
          )
          ..write(
            'maximumWeeklyConsecutivePairs: $maximumWeeklyConsecutivePairs',
          )
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    subjectId,
    scopeType,
    scopeId,
    stageId,
    weekday,
    minimumDailyLessons,
    maximumDailyLessons,
    minimumDailyConsecutivePairs,
    maximumDailyConsecutivePairs,
    minimumWeeklyConsecutivePairs,
    maximumWeeklyConsecutivePairs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubjectLessonConstraint &&
          other.id == this.id &&
          other.subjectId == this.subjectId &&
          other.scopeType == this.scopeType &&
          other.scopeId == this.scopeId &&
          other.stageId == this.stageId &&
          other.weekday == this.weekday &&
          other.minimumDailyLessons == this.minimumDailyLessons &&
          other.maximumDailyLessons == this.maximumDailyLessons &&
          other.minimumDailyConsecutivePairs ==
              this.minimumDailyConsecutivePairs &&
          other.maximumDailyConsecutivePairs ==
              this.maximumDailyConsecutivePairs &&
          other.minimumWeeklyConsecutivePairs ==
              this.minimumWeeklyConsecutivePairs &&
          other.maximumWeeklyConsecutivePairs ==
              this.maximumWeeklyConsecutivePairs);
}

class SubjectLessonConstraintsCompanion
    extends UpdateCompanion<SubjectLessonConstraint> {
  final Value<String> id;
  final Value<String> subjectId;
  final Value<String> scopeType;
  final Value<String> scopeId;
  final Value<String> stageId;
  final Value<int?> weekday;
  final Value<int?> minimumDailyLessons;
  final Value<int?> maximumDailyLessons;
  final Value<int?> minimumDailyConsecutivePairs;
  final Value<int?> maximumDailyConsecutivePairs;
  final Value<int?> minimumWeeklyConsecutivePairs;
  final Value<int?> maximumWeeklyConsecutivePairs;
  final Value<int> rowid;
  const SubjectLessonConstraintsCompanion({
    this.id = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.scopeType = const Value.absent(),
    this.scopeId = const Value.absent(),
    this.stageId = const Value.absent(),
    this.weekday = const Value.absent(),
    this.minimumDailyLessons = const Value.absent(),
    this.maximumDailyLessons = const Value.absent(),
    this.minimumDailyConsecutivePairs = const Value.absent(),
    this.maximumDailyConsecutivePairs = const Value.absent(),
    this.minimumWeeklyConsecutivePairs = const Value.absent(),
    this.maximumWeeklyConsecutivePairs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubjectLessonConstraintsCompanion.insert({
    required String id,
    required String subjectId,
    required String scopeType,
    required String scopeId,
    required String stageId,
    this.weekday = const Value.absent(),
    this.minimumDailyLessons = const Value.absent(),
    this.maximumDailyLessons = const Value.absent(),
    this.minimumDailyConsecutivePairs = const Value.absent(),
    this.maximumDailyConsecutivePairs = const Value.absent(),
    this.minimumWeeklyConsecutivePairs = const Value.absent(),
    this.maximumWeeklyConsecutivePairs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       subjectId = Value(subjectId),
       scopeType = Value(scopeType),
       scopeId = Value(scopeId),
       stageId = Value(stageId);
  static Insertable<SubjectLessonConstraint> custom({
    Expression<String>? id,
    Expression<String>? subjectId,
    Expression<String>? scopeType,
    Expression<String>? scopeId,
    Expression<String>? stageId,
    Expression<int>? weekday,
    Expression<int>? minimumDailyLessons,
    Expression<int>? maximumDailyLessons,
    Expression<int>? minimumDailyConsecutivePairs,
    Expression<int>? maximumDailyConsecutivePairs,
    Expression<int>? minimumWeeklyConsecutivePairs,
    Expression<int>? maximumWeeklyConsecutivePairs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subjectId != null) 'subject_id': subjectId,
      if (scopeType != null) 'scope_type': scopeType,
      if (scopeId != null) 'scope_id': scopeId,
      if (stageId != null) 'stage_id': stageId,
      if (weekday != null) 'weekday': weekday,
      if (minimumDailyLessons != null)
        'minimum_daily_lessons': minimumDailyLessons,
      if (maximumDailyLessons != null)
        'maximum_daily_lessons': maximumDailyLessons,
      if (minimumDailyConsecutivePairs != null)
        'minimum_daily_consecutive_pairs': minimumDailyConsecutivePairs,
      if (maximumDailyConsecutivePairs != null)
        'maximum_daily_consecutive_pairs': maximumDailyConsecutivePairs,
      if (minimumWeeklyConsecutivePairs != null)
        'minimum_weekly_consecutive_pairs': minimumWeeklyConsecutivePairs,
      if (maximumWeeklyConsecutivePairs != null)
        'maximum_weekly_consecutive_pairs': maximumWeeklyConsecutivePairs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubjectLessonConstraintsCompanion copyWith({
    Value<String>? id,
    Value<String>? subjectId,
    Value<String>? scopeType,
    Value<String>? scopeId,
    Value<String>? stageId,
    Value<int?>? weekday,
    Value<int?>? minimumDailyLessons,
    Value<int?>? maximumDailyLessons,
    Value<int?>? minimumDailyConsecutivePairs,
    Value<int?>? maximumDailyConsecutivePairs,
    Value<int?>? minimumWeeklyConsecutivePairs,
    Value<int?>? maximumWeeklyConsecutivePairs,
    Value<int>? rowid,
  }) {
    return SubjectLessonConstraintsCompanion(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      scopeType: scopeType ?? this.scopeType,
      scopeId: scopeId ?? this.scopeId,
      stageId: stageId ?? this.stageId,
      weekday: weekday ?? this.weekday,
      minimumDailyLessons: minimumDailyLessons ?? this.minimumDailyLessons,
      maximumDailyLessons: maximumDailyLessons ?? this.maximumDailyLessons,
      minimumDailyConsecutivePairs:
          minimumDailyConsecutivePairs ?? this.minimumDailyConsecutivePairs,
      maximumDailyConsecutivePairs:
          maximumDailyConsecutivePairs ?? this.maximumDailyConsecutivePairs,
      minimumWeeklyConsecutivePairs:
          minimumWeeklyConsecutivePairs ?? this.minimumWeeklyConsecutivePairs,
      maximumWeeklyConsecutivePairs:
          maximumWeeklyConsecutivePairs ?? this.maximumWeeklyConsecutivePairs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (scopeType.present) {
      map['scope_type'] = Variable<String>(scopeType.value);
    }
    if (scopeId.present) {
      map['scope_id'] = Variable<String>(scopeId.value);
    }
    if (stageId.present) {
      map['stage_id'] = Variable<String>(stageId.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (minimumDailyLessons.present) {
      map['minimum_daily_lessons'] = Variable<int>(minimumDailyLessons.value);
    }
    if (maximumDailyLessons.present) {
      map['maximum_daily_lessons'] = Variable<int>(maximumDailyLessons.value);
    }
    if (minimumDailyConsecutivePairs.present) {
      map['minimum_daily_consecutive_pairs'] = Variable<int>(
        minimumDailyConsecutivePairs.value,
      );
    }
    if (maximumDailyConsecutivePairs.present) {
      map['maximum_daily_consecutive_pairs'] = Variable<int>(
        maximumDailyConsecutivePairs.value,
      );
    }
    if (minimumWeeklyConsecutivePairs.present) {
      map['minimum_weekly_consecutive_pairs'] = Variable<int>(
        minimumWeeklyConsecutivePairs.value,
      );
    }
    if (maximumWeeklyConsecutivePairs.present) {
      map['maximum_weekly_consecutive_pairs'] = Variable<int>(
        maximumWeeklyConsecutivePairs.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubjectLessonConstraintsCompanion(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeId: $scopeId, ')
          ..write('stageId: $stageId, ')
          ..write('weekday: $weekday, ')
          ..write('minimumDailyLessons: $minimumDailyLessons, ')
          ..write('maximumDailyLessons: $maximumDailyLessons, ')
          ..write(
            'minimumDailyConsecutivePairs: $minimumDailyConsecutivePairs, ',
          )
          ..write(
            'maximumDailyConsecutivePairs: $maximumDailyConsecutivePairs, ',
          )
          ..write(
            'minimumWeeklyConsecutivePairs: $minimumWeeklyConsecutivePairs, ',
          )
          ..write(
            'maximumWeeklyConsecutivePairs: $maximumWeeklyConsecutivePairs, ',
          )
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AcademicTermsTable academicTerms = $AcademicTermsTable(this);
  late final $SchoolStagesTable schoolStages = $SchoolStagesTable(this);
  late final $GradeGroupsTable gradeGroups = $GradeGroupsTable(this);
  late final $ClassGroupsTable classGroups = $ClassGroupsTable(this);
  late final $StageTeachingDaysTable stageTeachingDays =
      $StageTeachingDaysTable(this);
  late final $LessonPeriodTypesTable lessonPeriodTypes =
      $LessonPeriodTypesTable(this);
  late final $DailyLessonOverridesTable dailyLessonOverrides =
      $DailyLessonOverridesTable(this);
  late final $LessonTimesTable lessonTimes = $LessonTimesTable(this);
  late final $CalendarExceptionsTable calendarExceptions =
      $CalendarExceptionsTable(this);
  late final $FreeSlotsTable freeSlots = $FreeSlotsTable(this);
  late final $CommonPeriodsTable commonPeriods = $CommonPeriodsTable(this);
  late final $SubjectsTable subjects = $SubjectsTable(this);
  late final $SubjectRequirementsTable subjectRequirements =
      $SubjectRequirementsTable(this);
  late final $SubjectPresetsTable subjectPresets = $SubjectPresetsTable(this);
  late final $SubjectPairingsTable subjectPairings = $SubjectPairingsTable(
    this,
  );
  late final $SubjectLessonConstraintsTable subjectLessonConstraints =
      $SubjectLessonConstraintsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    academicTerms,
    schoolStages,
    gradeGroups,
    classGroups,
    stageTeachingDays,
    lessonPeriodTypes,
    dailyLessonOverrides,
    lessonTimes,
    calendarExceptions,
    freeSlots,
    commonPeriods,
    subjects,
    subjectRequirements,
    subjectPresets,
    subjectPairings,
    subjectLessonConstraints,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'academic_terms',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('school_stages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'school_stages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('grade_groups', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'grade_groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('class_groups', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'school_stages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('stage_teaching_days', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'school_stages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('lesson_period_types', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'school_stages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('daily_lesson_overrides', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'lesson_period_types',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('daily_lesson_overrides', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'lesson_period_types',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('lesson_times', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'academic_terms',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('calendar_exceptions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'school_stages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('free_slots', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'lesson_period_types',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('free_slots', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'school_stages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('common_periods', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'subjects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subject_requirements', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'grade_groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subject_requirements', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'class_groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subject_requirements', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'subjects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subject_presets', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'school_stages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subject_presets', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'lesson_period_types',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subject_presets', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'class_groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subject_pairings', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'subjects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subject_pairings', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'subjects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subject_pairings', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'subjects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('subject_lesson_constraints', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'school_stages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('subject_lesson_constraints', kind: UpdateKind.delete),
      ],
    ),
  ]);
}

typedef $$AcademicTermsTableCreateCompanionBuilder =
    AcademicTermsCompanion Function({
      required String id,
      required String title,
      required String academicYear,
      required String semesterLabel,
      Value<String?> firstTeachingWeekStart,
      Value<int> teachingWeekCount,
      Value<String> cycleMode,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$AcademicTermsTableUpdateCompanionBuilder =
    AcademicTermsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> academicYear,
      Value<String> semesterLabel,
      Value<String?> firstTeachingWeekStart,
      Value<int> teachingWeekCount,
      Value<String> cycleMode,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$AcademicTermsTableReferences
    extends BaseReferences<_$AppDatabase, $AcademicTermsTable, AcademicTerm> {
  $$AcademicTermsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$SchoolStagesTable, List<SchoolStage>>
  _schoolStagesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.schoolStages,
    aliasName: 'academic_terms__id__school_stages__term_id',
  );

  $$SchoolStagesTableProcessedTableManager get schoolStagesRefs {
    final manager = $$SchoolStagesTableTableManager(
      $_db,
      $_db.schoolStages,
    ).filter((f) => f.termId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_schoolStagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CalendarExceptionsTable, List<CalendarException>>
  _calendarExceptionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.calendarExceptions,
        aliasName: 'academic_terms__id__calendar_exceptions__term_id',
      );

  $$CalendarExceptionsTableProcessedTableManager get calendarExceptionsRefs {
    final manager = $$CalendarExceptionsTableTableManager(
      $_db,
      $_db.calendarExceptions,
    ).filter((f) => f.termId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _calendarExceptionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AcademicTermsTableFilterComposer
    extends Composer<_$AppDatabase, $AcademicTermsTable> {
  $$AcademicTermsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get academicYear => $composableBuilder(
    column: $table.academicYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get semesterLabel => $composableBuilder(
    column: $table.semesterLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstTeachingWeekStart => $composableBuilder(
    column: $table.firstTeachingWeekStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get teachingWeekCount => $composableBuilder(
    column: $table.teachingWeekCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cycleMode => $composableBuilder(
    column: $table.cycleMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> schoolStagesRefs(
    Expression<bool> Function($$SchoolStagesTableFilterComposer f) f,
  ) {
    final $$SchoolStagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.termId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableFilterComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> calendarExceptionsRefs(
    Expression<bool> Function($$CalendarExceptionsTableFilterComposer f) f,
  ) {
    final $$CalendarExceptionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.calendarExceptions,
      getReferencedColumn: (t) => t.termId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CalendarExceptionsTableFilterComposer(
            $db: $db,
            $table: $db.calendarExceptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AcademicTermsTableOrderingComposer
    extends Composer<_$AppDatabase, $AcademicTermsTable> {
  $$AcademicTermsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get academicYear => $composableBuilder(
    column: $table.academicYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get semesterLabel => $composableBuilder(
    column: $table.semesterLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstTeachingWeekStart => $composableBuilder(
    column: $table.firstTeachingWeekStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get teachingWeekCount => $composableBuilder(
    column: $table.teachingWeekCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cycleMode => $composableBuilder(
    column: $table.cycleMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AcademicTermsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AcademicTermsTable> {
  $$AcademicTermsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get academicYear => $composableBuilder(
    column: $table.academicYear,
    builder: (column) => column,
  );

  GeneratedColumn<String> get semesterLabel => $composableBuilder(
    column: $table.semesterLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstTeachingWeekStart => $composableBuilder(
    column: $table.firstTeachingWeekStart,
    builder: (column) => column,
  );

  GeneratedColumn<int> get teachingWeekCount => $composableBuilder(
    column: $table.teachingWeekCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cycleMode =>
      $composableBuilder(column: $table.cycleMode, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> schoolStagesRefs<T extends Object>(
    Expression<T> Function($$SchoolStagesTableAnnotationComposer a) f,
  ) {
    final $$SchoolStagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.termId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableAnnotationComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> calendarExceptionsRefs<T extends Object>(
    Expression<T> Function($$CalendarExceptionsTableAnnotationComposer a) f,
  ) {
    final $$CalendarExceptionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.calendarExceptions,
          getReferencedColumn: (t) => t.termId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CalendarExceptionsTableAnnotationComposer(
                $db: $db,
                $table: $db.calendarExceptions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$AcademicTermsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AcademicTermsTable,
          AcademicTerm,
          $$AcademicTermsTableFilterComposer,
          $$AcademicTermsTableOrderingComposer,
          $$AcademicTermsTableAnnotationComposer,
          $$AcademicTermsTableCreateCompanionBuilder,
          $$AcademicTermsTableUpdateCompanionBuilder,
          (AcademicTerm, $$AcademicTermsTableReferences),
          AcademicTerm,
          PrefetchHooks Function({
            bool schoolStagesRefs,
            bool calendarExceptionsRefs,
          })
        > {
  $$AcademicTermsTableTableManager(_$AppDatabase db, $AcademicTermsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AcademicTermsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AcademicTermsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AcademicTermsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> academicYear = const Value.absent(),
                Value<String> semesterLabel = const Value.absent(),
                Value<String?> firstTeachingWeekStart = const Value.absent(),
                Value<int> teachingWeekCount = const Value.absent(),
                Value<String> cycleMode = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AcademicTermsCompanion(
                id: id,
                title: title,
                academicYear: academicYear,
                semesterLabel: semesterLabel,
                firstTeachingWeekStart: firstTeachingWeekStart,
                teachingWeekCount: teachingWeekCount,
                cycleMode: cycleMode,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String academicYear,
                required String semesterLabel,
                Value<String?> firstTeachingWeekStart = const Value.absent(),
                Value<int> teachingWeekCount = const Value.absent(),
                Value<String> cycleMode = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => AcademicTermsCompanion.insert(
                id: id,
                title: title,
                academicYear: academicYear,
                semesterLabel: semesterLabel,
                firstTeachingWeekStart: firstTeachingWeekStart,
                teachingWeekCount: teachingWeekCount,
                cycleMode: cycleMode,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AcademicTermsTable, AcademicTerm>(table),
                  $$AcademicTermsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({schoolStagesRefs = false, calendarExceptionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (schoolStagesRefs) db.schoolStages,
                    if (calendarExceptionsRefs) db.calendarExceptions,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (schoolStagesRefs)
                        await $_getPrefetchedData<
                          AcademicTerm,
                          $AcademicTermsTable,
                          SchoolStage
                        >(
                          currentTable: table,
                          referencedTable: $$AcademicTermsTableReferences
                              ._schoolStagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AcademicTermsTableReferences(
                                db,
                                table,
                                p0,
                              ).schoolStagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.termId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (calendarExceptionsRefs)
                        await $_getPrefetchedData<
                          AcademicTerm,
                          $AcademicTermsTable,
                          CalendarException
                        >(
                          currentTable: table,
                          referencedTable: $$AcademicTermsTableReferences
                              ._calendarExceptionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AcademicTermsTableReferences(
                                db,
                                table,
                                p0,
                              ).calendarExceptionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.termId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AcademicTermsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AcademicTermsTable,
      AcademicTerm,
      $$AcademicTermsTableFilterComposer,
      $$AcademicTermsTableOrderingComposer,
      $$AcademicTermsTableAnnotationComposer,
      $$AcademicTermsTableCreateCompanionBuilder,
      $$AcademicTermsTableUpdateCompanionBuilder,
      (AcademicTerm, $$AcademicTermsTableReferences),
      AcademicTerm,
      PrefetchHooks Function({
        bool schoolStagesRefs,
        bool calendarExceptionsRefs,
      })
    >;
typedef $$SchoolStagesTableCreateCompanionBuilder =
    SchoolStagesCompanion Function({
      required String id,
      required String termId,
      required String name,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$SchoolStagesTableUpdateCompanionBuilder =
    SchoolStagesCompanion Function({
      Value<String> id,
      Value<String> termId,
      Value<String> name,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$SchoolStagesTableReferences
    extends BaseReferences<_$AppDatabase, $SchoolStagesTable, SchoolStage> {
  $$SchoolStagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AcademicTermsTable _termIdTable(_$AppDatabase db) => db.academicTerms
      .createAlias('school_stages__term_id__academic_terms__id');

  $$AcademicTermsTableProcessedTableManager get termId {
    final $_column = $_itemColumn<String>('term_id')!;

    final manager = $$AcademicTermsTableTableManager(
      $_db,
      $_db.academicTerms,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_termIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$GradeGroupsTable, List<GradeGroup>>
  _gradeGroupsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.gradeGroups,
    aliasName: 'school_stages__id__grade_groups__stage_id',
  );

  $$GradeGroupsTableProcessedTableManager get gradeGroupsRefs {
    final manager = $$GradeGroupsTableTableManager(
      $_db,
      $_db.gradeGroups,
    ).filter((f) => f.stageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_gradeGroupsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$StageTeachingDaysTable, List<StageTeachingDay>>
  _stageTeachingDaysRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.stageTeachingDays,
        aliasName: 'school_stages__id__stage_teaching_days__stage_id',
      );

  $$StageTeachingDaysTableProcessedTableManager get stageTeachingDaysRefs {
    final manager = $$StageTeachingDaysTableTableManager(
      $_db,
      $_db.stageTeachingDays,
    ).filter((f) => f.stageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _stageTeachingDaysRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$LessonPeriodTypesTable, List<LessonPeriodType>>
  _lessonPeriodTypesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.lessonPeriodTypes,
        aliasName: 'school_stages__id__lesson_period_types__stage_id',
      );

  $$LessonPeriodTypesTableProcessedTableManager get lessonPeriodTypesRefs {
    final manager = $$LessonPeriodTypesTableTableManager(
      $_db,
      $_db.lessonPeriodTypes,
    ).filter((f) => f.stageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _lessonPeriodTypesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $DailyLessonOverridesTable,
    List<DailyLessonOverride>
  >
  _dailyLessonOverridesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.dailyLessonOverrides,
        aliasName: 'school_stages__id__daily_lesson_overrides__stage_id',
      );

  $$DailyLessonOverridesTableProcessedTableManager
  get dailyLessonOverridesRefs {
    final manager = $$DailyLessonOverridesTableTableManager(
      $_db,
      $_db.dailyLessonOverrides,
    ).filter((f) => f.stageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _dailyLessonOverridesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FreeSlotsTable, List<FreeSlot>>
  _freeSlotsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.freeSlots,
    aliasName: 'school_stages__id__free_slots__stage_id',
  );

  $$FreeSlotsTableProcessedTableManager get freeSlotsRefs {
    final manager = $$FreeSlotsTableTableManager(
      $_db,
      $_db.freeSlots,
    ).filter((f) => f.stageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_freeSlotsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CommonPeriodsTable, List<CommonPeriod>>
  _commonPeriodsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.commonPeriods,
    aliasName: 'school_stages__id__common_periods__stage_id',
  );

  $$CommonPeriodsTableProcessedTableManager get commonPeriodsRefs {
    final manager = $$CommonPeriodsTableTableManager(
      $_db,
      $_db.commonPeriods,
    ).filter((f) => f.stageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_commonPeriodsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SubjectPresetsTable, List<SubjectPreset>>
  _subjectPresetsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.subjectPresets,
    aliasName: 'school_stages__id__subject_presets__stage_id',
  );

  $$SubjectPresetsTableProcessedTableManager get subjectPresetsRefs {
    final manager = $$SubjectPresetsTableTableManager(
      $_db,
      $_db.subjectPresets,
    ).filter((f) => f.stageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_subjectPresetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $SubjectLessonConstraintsTable,
    List<SubjectLessonConstraint>
  >
  _subjectLessonConstraintsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.subjectLessonConstraints,
        aliasName: 'school_stages__id__subject_lesson_constraints__stage_id',
      );

  $$SubjectLessonConstraintsTableProcessedTableManager
  get subjectLessonConstraintsRefs {
    final manager = $$SubjectLessonConstraintsTableTableManager(
      $_db,
      $_db.subjectLessonConstraints,
    ).filter((f) => f.stageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _subjectLessonConstraintsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SchoolStagesTableFilterComposer
    extends Composer<_$AppDatabase, $SchoolStagesTable> {
  $$SchoolStagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$AcademicTermsTableFilterComposer get termId {
    final $$AcademicTermsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.termId,
      referencedTable: $db.academicTerms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcademicTermsTableFilterComposer(
            $db: $db,
            $table: $db.academicTerms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> gradeGroupsRefs(
    Expression<bool> Function($$GradeGroupsTableFilterComposer f) f,
  ) {
    final $$GradeGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gradeGroups,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeGroupsTableFilterComposer(
            $db: $db,
            $table: $db.gradeGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> stageTeachingDaysRefs(
    Expression<bool> Function($$StageTeachingDaysTableFilterComposer f) f,
  ) {
    final $$StageTeachingDaysTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stageTeachingDays,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StageTeachingDaysTableFilterComposer(
            $db: $db,
            $table: $db.stageTeachingDays,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> lessonPeriodTypesRefs(
    Expression<bool> Function($$LessonPeriodTypesTableFilterComposer f) f,
  ) {
    final $$LessonPeriodTypesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.lessonPeriodTypes,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonPeriodTypesTableFilterComposer(
            $db: $db,
            $table: $db.lessonPeriodTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> dailyLessonOverridesRefs(
    Expression<bool> Function($$DailyLessonOverridesTableFilterComposer f) f,
  ) {
    final $$DailyLessonOverridesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyLessonOverrides,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyLessonOverridesTableFilterComposer(
            $db: $db,
            $table: $db.dailyLessonOverrides,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> freeSlotsRefs(
    Expression<bool> Function($$FreeSlotsTableFilterComposer f) f,
  ) {
    final $$FreeSlotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.freeSlots,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FreeSlotsTableFilterComposer(
            $db: $db,
            $table: $db.freeSlots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> commonPeriodsRefs(
    Expression<bool> Function($$CommonPeriodsTableFilterComposer f) f,
  ) {
    final $$CommonPeriodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.commonPeriods,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommonPeriodsTableFilterComposer(
            $db: $db,
            $table: $db.commonPeriods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> subjectPresetsRefs(
    Expression<bool> Function($$SubjectPresetsTableFilterComposer f) f,
  ) {
    final $$SubjectPresetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectPresets,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectPresetsTableFilterComposer(
            $db: $db,
            $table: $db.subjectPresets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> subjectLessonConstraintsRefs(
    Expression<bool> Function($$SubjectLessonConstraintsTableFilterComposer f)
    f,
  ) {
    final $$SubjectLessonConstraintsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.subjectLessonConstraints,
          getReferencedColumn: (t) => t.stageId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SubjectLessonConstraintsTableFilterComposer(
                $db: $db,
                $table: $db.subjectLessonConstraints,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SchoolStagesTableOrderingComposer
    extends Composer<_$AppDatabase, $SchoolStagesTable> {
  $$SchoolStagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$AcademicTermsTableOrderingComposer get termId {
    final $$AcademicTermsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.termId,
      referencedTable: $db.academicTerms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcademicTermsTableOrderingComposer(
            $db: $db,
            $table: $db.academicTerms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SchoolStagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchoolStagesTable> {
  $$SchoolStagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$AcademicTermsTableAnnotationComposer get termId {
    final $$AcademicTermsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.termId,
      referencedTable: $db.academicTerms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcademicTermsTableAnnotationComposer(
            $db: $db,
            $table: $db.academicTerms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> gradeGroupsRefs<T extends Object>(
    Expression<T> Function($$GradeGroupsTableAnnotationComposer a) f,
  ) {
    final $$GradeGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gradeGroups,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.gradeGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> stageTeachingDaysRefs<T extends Object>(
    Expression<T> Function($$StageTeachingDaysTableAnnotationComposer a) f,
  ) {
    final $$StageTeachingDaysTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.stageTeachingDays,
          getReferencedColumn: (t) => t.stageId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$StageTeachingDaysTableAnnotationComposer(
                $db: $db,
                $table: $db.stageTeachingDays,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> lessonPeriodTypesRefs<T extends Object>(
    Expression<T> Function($$LessonPeriodTypesTableAnnotationComposer a) f,
  ) {
    final $$LessonPeriodTypesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.lessonPeriodTypes,
          getReferencedColumn: (t) => t.stageId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LessonPeriodTypesTableAnnotationComposer(
                $db: $db,
                $table: $db.lessonPeriodTypes,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> dailyLessonOverridesRefs<T extends Object>(
    Expression<T> Function($$DailyLessonOverridesTableAnnotationComposer a) f,
  ) {
    final $$DailyLessonOverridesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.dailyLessonOverrides,
          getReferencedColumn: (t) => t.stageId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DailyLessonOverridesTableAnnotationComposer(
                $db: $db,
                $table: $db.dailyLessonOverrides,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> freeSlotsRefs<T extends Object>(
    Expression<T> Function($$FreeSlotsTableAnnotationComposer a) f,
  ) {
    final $$FreeSlotsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.freeSlots,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FreeSlotsTableAnnotationComposer(
            $db: $db,
            $table: $db.freeSlots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> commonPeriodsRefs<T extends Object>(
    Expression<T> Function($$CommonPeriodsTableAnnotationComposer a) f,
  ) {
    final $$CommonPeriodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.commonPeriods,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommonPeriodsTableAnnotationComposer(
            $db: $db,
            $table: $db.commonPeriods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> subjectPresetsRefs<T extends Object>(
    Expression<T> Function($$SubjectPresetsTableAnnotationComposer a) f,
  ) {
    final $$SubjectPresetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectPresets,
      getReferencedColumn: (t) => t.stageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectPresetsTableAnnotationComposer(
            $db: $db,
            $table: $db.subjectPresets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> subjectLessonConstraintsRefs<T extends Object>(
    Expression<T> Function($$SubjectLessonConstraintsTableAnnotationComposer a)
    f,
  ) {
    final $$SubjectLessonConstraintsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.subjectLessonConstraints,
          getReferencedColumn: (t) => t.stageId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SubjectLessonConstraintsTableAnnotationComposer(
                $db: $db,
                $table: $db.subjectLessonConstraints,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SchoolStagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SchoolStagesTable,
          SchoolStage,
          $$SchoolStagesTableFilterComposer,
          $$SchoolStagesTableOrderingComposer,
          $$SchoolStagesTableAnnotationComposer,
          $$SchoolStagesTableCreateCompanionBuilder,
          $$SchoolStagesTableUpdateCompanionBuilder,
          (SchoolStage, $$SchoolStagesTableReferences),
          SchoolStage,
          PrefetchHooks Function({
            bool termId,
            bool gradeGroupsRefs,
            bool stageTeachingDaysRefs,
            bool lessonPeriodTypesRefs,
            bool dailyLessonOverridesRefs,
            bool freeSlotsRefs,
            bool commonPeriodsRefs,
            bool subjectPresetsRefs,
            bool subjectLessonConstraintsRefs,
          })
        > {
  $$SchoolStagesTableTableManager(_$AppDatabase db, $SchoolStagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchoolStagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchoolStagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchoolStagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> termId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SchoolStagesCompanion(
                id: id,
                termId: termId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String termId,
                required String name,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => SchoolStagesCompanion.insert(
                id: id,
                termId: termId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SchoolStagesTable, SchoolStage>(table),
                  $$SchoolStagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                termId = false,
                gradeGroupsRefs = false,
                stageTeachingDaysRefs = false,
                lessonPeriodTypesRefs = false,
                dailyLessonOverridesRefs = false,
                freeSlotsRefs = false,
                commonPeriodsRefs = false,
                subjectPresetsRefs = false,
                subjectLessonConstraintsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (gradeGroupsRefs) db.gradeGroups,
                    if (stageTeachingDaysRefs) db.stageTeachingDays,
                    if (lessonPeriodTypesRefs) db.lessonPeriodTypes,
                    if (dailyLessonOverridesRefs) db.dailyLessonOverrides,
                    if (freeSlotsRefs) db.freeSlots,
                    if (commonPeriodsRefs) db.commonPeriods,
                    if (subjectPresetsRefs) db.subjectPresets,
                    if (subjectLessonConstraintsRefs)
                      db.subjectLessonConstraints,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (termId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.termId,
                            referencedTable: $$SchoolStagesTableReferences
                                ._termIdTable(db),
                            referencedColumn: $$SchoolStagesTableReferences
                                ._termIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (gradeGroupsRefs)
                        await $_getPrefetchedData<
                          SchoolStage,
                          $SchoolStagesTable,
                          GradeGroup
                        >(
                          currentTable: table,
                          referencedTable: $$SchoolStagesTableReferences
                              ._gradeGroupsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SchoolStagesTableReferences(
                                db,
                                table,
                                p0,
                              ).gradeGroupsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.stageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (stageTeachingDaysRefs)
                        await $_getPrefetchedData<
                          SchoolStage,
                          $SchoolStagesTable,
                          StageTeachingDay
                        >(
                          currentTable: table,
                          referencedTable: $$SchoolStagesTableReferences
                              ._stageTeachingDaysRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SchoolStagesTableReferences(
                                db,
                                table,
                                p0,
                              ).stageTeachingDaysRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.stageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (lessonPeriodTypesRefs)
                        await $_getPrefetchedData<
                          SchoolStage,
                          $SchoolStagesTable,
                          LessonPeriodType
                        >(
                          currentTable: table,
                          referencedTable: $$SchoolStagesTableReferences
                              ._lessonPeriodTypesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SchoolStagesTableReferences(
                                db,
                                table,
                                p0,
                              ).lessonPeriodTypesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.stageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (dailyLessonOverridesRefs)
                        await $_getPrefetchedData<
                          SchoolStage,
                          $SchoolStagesTable,
                          DailyLessonOverride
                        >(
                          currentTable: table,
                          referencedTable: $$SchoolStagesTableReferences
                              ._dailyLessonOverridesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SchoolStagesTableReferences(
                                db,
                                table,
                                p0,
                              ).dailyLessonOverridesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.stageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (freeSlotsRefs)
                        await $_getPrefetchedData<
                          SchoolStage,
                          $SchoolStagesTable,
                          FreeSlot
                        >(
                          currentTable: table,
                          referencedTable: $$SchoolStagesTableReferences
                              ._freeSlotsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SchoolStagesTableReferences(
                                db,
                                table,
                                p0,
                              ).freeSlotsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.stageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (commonPeriodsRefs)
                        await $_getPrefetchedData<
                          SchoolStage,
                          $SchoolStagesTable,
                          CommonPeriod
                        >(
                          currentTable: table,
                          referencedTable: $$SchoolStagesTableReferences
                              ._commonPeriodsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SchoolStagesTableReferences(
                                db,
                                table,
                                p0,
                              ).commonPeriodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.stageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (subjectPresetsRefs)
                        await $_getPrefetchedData<
                          SchoolStage,
                          $SchoolStagesTable,
                          SubjectPreset
                        >(
                          currentTable: table,
                          referencedTable: $$SchoolStagesTableReferences
                              ._subjectPresetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SchoolStagesTableReferences(
                                db,
                                table,
                                p0,
                              ).subjectPresetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.stageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (subjectLessonConstraintsRefs)
                        await $_getPrefetchedData<
                          SchoolStage,
                          $SchoolStagesTable,
                          SubjectLessonConstraint
                        >(
                          currentTable: table,
                          referencedTable: $$SchoolStagesTableReferences
                              ._subjectLessonConstraintsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SchoolStagesTableReferences(
                                db,
                                table,
                                p0,
                              ).subjectLessonConstraintsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.stageId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SchoolStagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SchoolStagesTable,
      SchoolStage,
      $$SchoolStagesTableFilterComposer,
      $$SchoolStagesTableOrderingComposer,
      $$SchoolStagesTableAnnotationComposer,
      $$SchoolStagesTableCreateCompanionBuilder,
      $$SchoolStagesTableUpdateCompanionBuilder,
      (SchoolStage, $$SchoolStagesTableReferences),
      SchoolStage,
      PrefetchHooks Function({
        bool termId,
        bool gradeGroupsRefs,
        bool stageTeachingDaysRefs,
        bool lessonPeriodTypesRefs,
        bool dailyLessonOverridesRefs,
        bool freeSlotsRefs,
        bool commonPeriodsRefs,
        bool subjectPresetsRefs,
        bool subjectLessonConstraintsRefs,
      })
    >;
typedef $$GradeGroupsTableCreateCompanionBuilder =
    GradeGroupsCompanion Function({
      required String id,
      required String stageId,
      required String name,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$GradeGroupsTableUpdateCompanionBuilder =
    GradeGroupsCompanion Function({
      Value<String> id,
      Value<String> stageId,
      Value<String> name,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$GradeGroupsTableReferences
    extends BaseReferences<_$AppDatabase, $GradeGroupsTable, GradeGroup> {
  $$GradeGroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SchoolStagesTable _stageIdTable(_$AppDatabase db) =>
      db.schoolStages.createAlias('grade_groups__stage_id__school_stages__id');

  $$SchoolStagesTableProcessedTableManager get stageId {
    final $_column = $_itemColumn<String>('stage_id')!;

    final manager = $$SchoolStagesTableTableManager(
      $_db,
      $_db.schoolStages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_stageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ClassGroupsTable, List<ClassGroup>>
  _classGroupsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.classGroups,
    aliasName: 'grade_groups__id__class_groups__grade_id',
  );

  $$ClassGroupsTableProcessedTableManager get classGroupsRefs {
    final manager = $$ClassGroupsTableTableManager(
      $_db,
      $_db.classGroups,
    ).filter((f) => f.gradeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_classGroupsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $SubjectRequirementsTable,
    List<SubjectRequirement>
  >
  _subjectRequirementsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.subjectRequirements,
        aliasName: 'grade_groups__id__subject_requirements__grade_id',
      );

  $$SubjectRequirementsTableProcessedTableManager get subjectRequirementsRefs {
    final manager = $$SubjectRequirementsTableTableManager(
      $_db,
      $_db.subjectRequirements,
    ).filter((f) => f.gradeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _subjectRequirementsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GradeGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $GradeGroupsTable> {
  $$GradeGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$SchoolStagesTableFilterComposer get stageId {
    final $$SchoolStagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableFilterComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> classGroupsRefs(
    Expression<bool> Function($$ClassGroupsTableFilterComposer f) f,
  ) {
    final $$ClassGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.classGroups,
      getReferencedColumn: (t) => t.gradeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassGroupsTableFilterComposer(
            $db: $db,
            $table: $db.classGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> subjectRequirementsRefs(
    Expression<bool> Function($$SubjectRequirementsTableFilterComposer f) f,
  ) {
    final $$SubjectRequirementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectRequirements,
      getReferencedColumn: (t) => t.gradeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectRequirementsTableFilterComposer(
            $db: $db,
            $table: $db.subjectRequirements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GradeGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $GradeGroupsTable> {
  $$GradeGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$SchoolStagesTableOrderingComposer get stageId {
    final $$SchoolStagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableOrderingComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GradeGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GradeGroupsTable> {
  $$GradeGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$SchoolStagesTableAnnotationComposer get stageId {
    final $$SchoolStagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableAnnotationComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> classGroupsRefs<T extends Object>(
    Expression<T> Function($$ClassGroupsTableAnnotationComposer a) f,
  ) {
    final $$ClassGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.classGroups,
      getReferencedColumn: (t) => t.gradeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.classGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> subjectRequirementsRefs<T extends Object>(
    Expression<T> Function($$SubjectRequirementsTableAnnotationComposer a) f,
  ) {
    final $$SubjectRequirementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.subjectRequirements,
          getReferencedColumn: (t) => t.gradeId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SubjectRequirementsTableAnnotationComposer(
                $db: $db,
                $table: $db.subjectRequirements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$GradeGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GradeGroupsTable,
          GradeGroup,
          $$GradeGroupsTableFilterComposer,
          $$GradeGroupsTableOrderingComposer,
          $$GradeGroupsTableAnnotationComposer,
          $$GradeGroupsTableCreateCompanionBuilder,
          $$GradeGroupsTableUpdateCompanionBuilder,
          (GradeGroup, $$GradeGroupsTableReferences),
          GradeGroup,
          PrefetchHooks Function({
            bool stageId,
            bool classGroupsRefs,
            bool subjectRequirementsRefs,
          })
        > {
  $$GradeGroupsTableTableManager(_$AppDatabase db, $GradeGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GradeGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GradeGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GradeGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stageId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GradeGroupsCompanion(
                id: id,
                stageId: stageId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stageId,
                required String name,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => GradeGroupsCompanion.insert(
                id: id,
                stageId: stageId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GradeGroupsTable, GradeGroup>(table),
                  $$GradeGroupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                stageId = false,
                classGroupsRefs = false,
                subjectRequirementsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (classGroupsRefs) db.classGroups,
                    if (subjectRequirementsRefs) db.subjectRequirements,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (stageId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.stageId,
                            referencedTable: $$GradeGroupsTableReferences
                                ._stageIdTable(db),
                            referencedColumn: $$GradeGroupsTableReferences
                                ._stageIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (classGroupsRefs)
                        await $_getPrefetchedData<
                          GradeGroup,
                          $GradeGroupsTable,
                          ClassGroup
                        >(
                          currentTable: table,
                          referencedTable: $$GradeGroupsTableReferences
                              ._classGroupsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$GradeGroupsTableReferences(
                                db,
                                table,
                                p0,
                              ).classGroupsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.gradeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (subjectRequirementsRefs)
                        await $_getPrefetchedData<
                          GradeGroup,
                          $GradeGroupsTable,
                          SubjectRequirement
                        >(
                          currentTable: table,
                          referencedTable: $$GradeGroupsTableReferences
                              ._subjectRequirementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$GradeGroupsTableReferences(
                                db,
                                table,
                                p0,
                              ).subjectRequirementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.gradeId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$GradeGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GradeGroupsTable,
      GradeGroup,
      $$GradeGroupsTableFilterComposer,
      $$GradeGroupsTableOrderingComposer,
      $$GradeGroupsTableAnnotationComposer,
      $$GradeGroupsTableCreateCompanionBuilder,
      $$GradeGroupsTableUpdateCompanionBuilder,
      (GradeGroup, $$GradeGroupsTableReferences),
      GradeGroup,
      PrefetchHooks Function({
        bool stageId,
        bool classGroupsRefs,
        bool subjectRequirementsRefs,
      })
    >;
typedef $$ClassGroupsTableCreateCompanionBuilder =
    ClassGroupsCompanion Function({
      required String id,
      required String gradeId,
      required String name,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$ClassGroupsTableUpdateCompanionBuilder =
    ClassGroupsCompanion Function({
      Value<String> id,
      Value<String> gradeId,
      Value<String> name,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$ClassGroupsTableReferences
    extends BaseReferences<_$AppDatabase, $ClassGroupsTable, ClassGroup> {
  $$ClassGroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GradeGroupsTable _gradeIdTable(_$AppDatabase db) =>
      db.gradeGroups.createAlias('class_groups__grade_id__grade_groups__id');

  $$GradeGroupsTableProcessedTableManager get gradeId {
    final $_column = $_itemColumn<String>('grade_id')!;

    final manager = $$GradeGroupsTableTableManager(
      $_db,
      $_db.gradeGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_gradeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $SubjectRequirementsTable,
    List<SubjectRequirement>
  >
  _subjectRequirementsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.subjectRequirements,
        aliasName: 'class_groups__id__subject_requirements__class_id',
      );

  $$SubjectRequirementsTableProcessedTableManager get subjectRequirementsRefs {
    final manager = $$SubjectRequirementsTableTableManager(
      $_db,
      $_db.subjectRequirements,
    ).filter((f) => f.classId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _subjectRequirementsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SubjectPairingsTable, List<SubjectPairing>>
  _subjectPairingsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.subjectPairings,
    aliasName: 'class_groups__id__subject_pairings__class_id',
  );

  $$SubjectPairingsTableProcessedTableManager get subjectPairingsRefs {
    final manager = $$SubjectPairingsTableTableManager(
      $_db,
      $_db.subjectPairings,
    ).filter((f) => f.classId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _subjectPairingsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ClassGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $ClassGroupsTable> {
  $$ClassGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$GradeGroupsTableFilterComposer get gradeId {
    final $$GradeGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gradeId,
      referencedTable: $db.gradeGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeGroupsTableFilterComposer(
            $db: $db,
            $table: $db.gradeGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> subjectRequirementsRefs(
    Expression<bool> Function($$SubjectRequirementsTableFilterComposer f) f,
  ) {
    final $$SubjectRequirementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectRequirements,
      getReferencedColumn: (t) => t.classId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectRequirementsTableFilterComposer(
            $db: $db,
            $table: $db.subjectRequirements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> subjectPairingsRefs(
    Expression<bool> Function($$SubjectPairingsTableFilterComposer f) f,
  ) {
    final $$SubjectPairingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectPairings,
      getReferencedColumn: (t) => t.classId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectPairingsTableFilterComposer(
            $db: $db,
            $table: $db.subjectPairings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClassGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClassGroupsTable> {
  $$ClassGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$GradeGroupsTableOrderingComposer get gradeId {
    final $$GradeGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gradeId,
      referencedTable: $db.gradeGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.gradeGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ClassGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClassGroupsTable> {
  $$ClassGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$GradeGroupsTableAnnotationComposer get gradeId {
    final $$GradeGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gradeId,
      referencedTable: $db.gradeGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.gradeGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> subjectRequirementsRefs<T extends Object>(
    Expression<T> Function($$SubjectRequirementsTableAnnotationComposer a) f,
  ) {
    final $$SubjectRequirementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.subjectRequirements,
          getReferencedColumn: (t) => t.classId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SubjectRequirementsTableAnnotationComposer(
                $db: $db,
                $table: $db.subjectRequirements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> subjectPairingsRefs<T extends Object>(
    Expression<T> Function($$SubjectPairingsTableAnnotationComposer a) f,
  ) {
    final $$SubjectPairingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectPairings,
      getReferencedColumn: (t) => t.classId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectPairingsTableAnnotationComposer(
            $db: $db,
            $table: $db.subjectPairings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClassGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClassGroupsTable,
          ClassGroup,
          $$ClassGroupsTableFilterComposer,
          $$ClassGroupsTableOrderingComposer,
          $$ClassGroupsTableAnnotationComposer,
          $$ClassGroupsTableCreateCompanionBuilder,
          $$ClassGroupsTableUpdateCompanionBuilder,
          (ClassGroup, $$ClassGroupsTableReferences),
          ClassGroup,
          PrefetchHooks Function({
            bool gradeId,
            bool subjectRequirementsRefs,
            bool subjectPairingsRefs,
          })
        > {
  $$ClassGroupsTableTableManager(_$AppDatabase db, $ClassGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClassGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClassGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClassGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> gradeId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClassGroupsCompanion(
                id: id,
                gradeId: gradeId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String gradeId,
                required String name,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => ClassGroupsCompanion.insert(
                id: id,
                gradeId: gradeId,
                name: name,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ClassGroupsTable, ClassGroup>(table),
                  $$ClassGroupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                gradeId = false,
                subjectRequirementsRefs = false,
                subjectPairingsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (subjectRequirementsRefs) db.subjectRequirements,
                    if (subjectPairingsRefs) db.subjectPairings,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (gradeId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.gradeId,
                            referencedTable: $$ClassGroupsTableReferences
                                ._gradeIdTable(db),
                            referencedColumn: $$ClassGroupsTableReferences
                                ._gradeIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (subjectRequirementsRefs)
                        await $_getPrefetchedData<
                          ClassGroup,
                          $ClassGroupsTable,
                          SubjectRequirement
                        >(
                          currentTable: table,
                          referencedTable: $$ClassGroupsTableReferences
                              ._subjectRequirementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ClassGroupsTableReferences(
                                db,
                                table,
                                p0,
                              ).subjectRequirementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.classId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (subjectPairingsRefs)
                        await $_getPrefetchedData<
                          ClassGroup,
                          $ClassGroupsTable,
                          SubjectPairing
                        >(
                          currentTable: table,
                          referencedTable: $$ClassGroupsTableReferences
                              ._subjectPairingsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ClassGroupsTableReferences(
                                db,
                                table,
                                p0,
                              ).subjectPairingsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.classId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ClassGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClassGroupsTable,
      ClassGroup,
      $$ClassGroupsTableFilterComposer,
      $$ClassGroupsTableOrderingComposer,
      $$ClassGroupsTableAnnotationComposer,
      $$ClassGroupsTableCreateCompanionBuilder,
      $$ClassGroupsTableUpdateCompanionBuilder,
      (ClassGroup, $$ClassGroupsTableReferences),
      ClassGroup,
      PrefetchHooks Function({
        bool gradeId,
        bool subjectRequirementsRefs,
        bool subjectPairingsRefs,
      })
    >;
typedef $$StageTeachingDaysTableCreateCompanionBuilder =
    StageTeachingDaysCompanion Function({
      required String id,
      required String stageId,
      required int weekday,
      required bool isTeachingDay,
      Value<int> rowid,
    });
typedef $$StageTeachingDaysTableUpdateCompanionBuilder =
    StageTeachingDaysCompanion Function({
      Value<String> id,
      Value<String> stageId,
      Value<int> weekday,
      Value<bool> isTeachingDay,
      Value<int> rowid,
    });

final class $$StageTeachingDaysTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $StageTeachingDaysTable,
          StageTeachingDay
        > {
  $$StageTeachingDaysTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SchoolStagesTable _stageIdTable(_$AppDatabase db) => db.schoolStages
      .createAlias('stage_teaching_days__stage_id__school_stages__id');

  $$SchoolStagesTableProcessedTableManager get stageId {
    final $_column = $_itemColumn<String>('stage_id')!;

    final manager = $$SchoolStagesTableTableManager(
      $_db,
      $_db.schoolStages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_stageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StageTeachingDaysTableFilterComposer
    extends Composer<_$AppDatabase, $StageTeachingDaysTable> {
  $$StageTeachingDaysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isTeachingDay => $composableBuilder(
    column: $table.isTeachingDay,
    builder: (column) => ColumnFilters(column),
  );

  $$SchoolStagesTableFilterComposer get stageId {
    final $$SchoolStagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableFilterComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StageTeachingDaysTableOrderingComposer
    extends Composer<_$AppDatabase, $StageTeachingDaysTable> {
  $$StageTeachingDaysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isTeachingDay => $composableBuilder(
    column: $table.isTeachingDay,
    builder: (column) => ColumnOrderings(column),
  );

  $$SchoolStagesTableOrderingComposer get stageId {
    final $$SchoolStagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableOrderingComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StageTeachingDaysTableAnnotationComposer
    extends Composer<_$AppDatabase, $StageTeachingDaysTable> {
  $$StageTeachingDaysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<bool> get isTeachingDay => $composableBuilder(
    column: $table.isTeachingDay,
    builder: (column) => column,
  );

  $$SchoolStagesTableAnnotationComposer get stageId {
    final $$SchoolStagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableAnnotationComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StageTeachingDaysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StageTeachingDaysTable,
          StageTeachingDay,
          $$StageTeachingDaysTableFilterComposer,
          $$StageTeachingDaysTableOrderingComposer,
          $$StageTeachingDaysTableAnnotationComposer,
          $$StageTeachingDaysTableCreateCompanionBuilder,
          $$StageTeachingDaysTableUpdateCompanionBuilder,
          (StageTeachingDay, $$StageTeachingDaysTableReferences),
          StageTeachingDay,
          PrefetchHooks Function({bool stageId})
        > {
  $$StageTeachingDaysTableTableManager(
    _$AppDatabase db,
    $StageTeachingDaysTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StageTeachingDaysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StageTeachingDaysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StageTeachingDaysTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stageId = const Value.absent(),
                Value<int> weekday = const Value.absent(),
                Value<bool> isTeachingDay = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StageTeachingDaysCompanion(
                id: id,
                stageId: stageId,
                weekday: weekday,
                isTeachingDay: isTeachingDay,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stageId,
                required int weekday,
                required bool isTeachingDay,
                Value<int> rowid = const Value.absent(),
              }) => StageTeachingDaysCompanion.insert(
                id: id,
                stageId: stageId,
                weekday: weekday,
                isTeachingDay: isTeachingDay,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StageTeachingDaysTable, StageTeachingDay>(table),
                  $$StageTeachingDaysTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({stageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (stageId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.stageId,
                        referencedTable: $$StageTeachingDaysTableReferences
                            ._stageIdTable(db),
                        referencedColumn: $$StageTeachingDaysTableReferences
                            ._stageIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$StageTeachingDaysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StageTeachingDaysTable,
      StageTeachingDay,
      $$StageTeachingDaysTableFilterComposer,
      $$StageTeachingDaysTableOrderingComposer,
      $$StageTeachingDaysTableAnnotationComposer,
      $$StageTeachingDaysTableCreateCompanionBuilder,
      $$StageTeachingDaysTableUpdateCompanionBuilder,
      (StageTeachingDay, $$StageTeachingDaysTableReferences),
      StageTeachingDay,
      PrefetchHooks Function({bool stageId})
    >;
typedef $$LessonPeriodTypesTableCreateCompanionBuilder =
    LessonPeriodTypesCompanion Function({
      required String id,
      required String stageId,
      required String name,
      required int defaultLessonCount,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$LessonPeriodTypesTableUpdateCompanionBuilder =
    LessonPeriodTypesCompanion Function({
      Value<String> id,
      Value<String> stageId,
      Value<String> name,
      Value<int> defaultLessonCount,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$LessonPeriodTypesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $LessonPeriodTypesTable,
          LessonPeriodType
        > {
  $$LessonPeriodTypesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SchoolStagesTable _stageIdTable(_$AppDatabase db) => db.schoolStages
      .createAlias('lesson_period_types__stage_id__school_stages__id');

  $$SchoolStagesTableProcessedTableManager get stageId {
    final $_column = $_itemColumn<String>('stage_id')!;

    final manager = $$SchoolStagesTableTableManager(
      $_db,
      $_db.schoolStages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_stageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $DailyLessonOverridesTable,
    List<DailyLessonOverride>
  >
  _dailyLessonOverridesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.dailyLessonOverrides,
        aliasName:
            'lesson_period_types__id__daily_lesson_overrides__period_type_id',
      );

  $$DailyLessonOverridesTableProcessedTableManager
  get dailyLessonOverridesRefs {
    final manager = $$DailyLessonOverridesTableTableManager(
      $_db,
      $_db.dailyLessonOverrides,
    ).filter((f) => f.periodTypeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _dailyLessonOverridesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$LessonTimesTable, List<LessonTime>>
  _lessonTimesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.lessonTimes,
    aliasName: 'lesson_period_types__id__lesson_times__period_type_id',
  );

  $$LessonTimesTableProcessedTableManager get lessonTimesRefs {
    final manager = $$LessonTimesTableTableManager(
      $_db,
      $_db.lessonTimes,
    ).filter((f) => f.periodTypeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_lessonTimesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FreeSlotsTable, List<FreeSlot>>
  _freeSlotsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.freeSlots,
    aliasName: 'lesson_period_types__id__free_slots__period_type_id',
  );

  $$FreeSlotsTableProcessedTableManager get freeSlotsRefs {
    final manager = $$FreeSlotsTableTableManager(
      $_db,
      $_db.freeSlots,
    ).filter((f) => f.periodTypeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_freeSlotsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SubjectPresetsTable, List<SubjectPreset>>
  _subjectPresetsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.subjectPresets,
    aliasName: 'lesson_period_types__id__subject_presets__period_type_id',
  );

  $$SubjectPresetsTableProcessedTableManager get subjectPresetsRefs {
    final manager = $$SubjectPresetsTableTableManager(
      $_db,
      $_db.subjectPresets,
    ).filter((f) => f.periodTypeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_subjectPresetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LessonPeriodTypesTableFilterComposer
    extends Composer<_$AppDatabase, $LessonPeriodTypesTable> {
  $$LessonPeriodTypesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultLessonCount => $composableBuilder(
    column: $table.defaultLessonCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$SchoolStagesTableFilterComposer get stageId {
    final $$SchoolStagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableFilterComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> dailyLessonOverridesRefs(
    Expression<bool> Function($$DailyLessonOverridesTableFilterComposer f) f,
  ) {
    final $$DailyLessonOverridesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyLessonOverrides,
      getReferencedColumn: (t) => t.periodTypeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyLessonOverridesTableFilterComposer(
            $db: $db,
            $table: $db.dailyLessonOverrides,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> lessonTimesRefs(
    Expression<bool> Function($$LessonTimesTableFilterComposer f) f,
  ) {
    final $$LessonTimesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.lessonTimes,
      getReferencedColumn: (t) => t.periodTypeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonTimesTableFilterComposer(
            $db: $db,
            $table: $db.lessonTimes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> freeSlotsRefs(
    Expression<bool> Function($$FreeSlotsTableFilterComposer f) f,
  ) {
    final $$FreeSlotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.freeSlots,
      getReferencedColumn: (t) => t.periodTypeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FreeSlotsTableFilterComposer(
            $db: $db,
            $table: $db.freeSlots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> subjectPresetsRefs(
    Expression<bool> Function($$SubjectPresetsTableFilterComposer f) f,
  ) {
    final $$SubjectPresetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectPresets,
      getReferencedColumn: (t) => t.periodTypeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectPresetsTableFilterComposer(
            $db: $db,
            $table: $db.subjectPresets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LessonPeriodTypesTableOrderingComposer
    extends Composer<_$AppDatabase, $LessonPeriodTypesTable> {
  $$LessonPeriodTypesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultLessonCount => $composableBuilder(
    column: $table.defaultLessonCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$SchoolStagesTableOrderingComposer get stageId {
    final $$SchoolStagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableOrderingComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LessonPeriodTypesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LessonPeriodTypesTable> {
  $$LessonPeriodTypesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get defaultLessonCount => $composableBuilder(
    column: $table.defaultLessonCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$SchoolStagesTableAnnotationComposer get stageId {
    final $$SchoolStagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableAnnotationComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> dailyLessonOverridesRefs<T extends Object>(
    Expression<T> Function($$DailyLessonOverridesTableAnnotationComposer a) f,
  ) {
    final $$DailyLessonOverridesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.dailyLessonOverrides,
          getReferencedColumn: (t) => t.periodTypeId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DailyLessonOverridesTableAnnotationComposer(
                $db: $db,
                $table: $db.dailyLessonOverrides,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> lessonTimesRefs<T extends Object>(
    Expression<T> Function($$LessonTimesTableAnnotationComposer a) f,
  ) {
    final $$LessonTimesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.lessonTimes,
      getReferencedColumn: (t) => t.periodTypeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonTimesTableAnnotationComposer(
            $db: $db,
            $table: $db.lessonTimes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> freeSlotsRefs<T extends Object>(
    Expression<T> Function($$FreeSlotsTableAnnotationComposer a) f,
  ) {
    final $$FreeSlotsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.freeSlots,
      getReferencedColumn: (t) => t.periodTypeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FreeSlotsTableAnnotationComposer(
            $db: $db,
            $table: $db.freeSlots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> subjectPresetsRefs<T extends Object>(
    Expression<T> Function($$SubjectPresetsTableAnnotationComposer a) f,
  ) {
    final $$SubjectPresetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectPresets,
      getReferencedColumn: (t) => t.periodTypeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectPresetsTableAnnotationComposer(
            $db: $db,
            $table: $db.subjectPresets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LessonPeriodTypesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LessonPeriodTypesTable,
          LessonPeriodType,
          $$LessonPeriodTypesTableFilterComposer,
          $$LessonPeriodTypesTableOrderingComposer,
          $$LessonPeriodTypesTableAnnotationComposer,
          $$LessonPeriodTypesTableCreateCompanionBuilder,
          $$LessonPeriodTypesTableUpdateCompanionBuilder,
          (LessonPeriodType, $$LessonPeriodTypesTableReferences),
          LessonPeriodType,
          PrefetchHooks Function({
            bool stageId,
            bool dailyLessonOverridesRefs,
            bool lessonTimesRefs,
            bool freeSlotsRefs,
            bool subjectPresetsRefs,
          })
        > {
  $$LessonPeriodTypesTableTableManager(
    _$AppDatabase db,
    $LessonPeriodTypesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LessonPeriodTypesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LessonPeriodTypesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LessonPeriodTypesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stageId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> defaultLessonCount = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LessonPeriodTypesCompanion(
                id: id,
                stageId: stageId,
                name: name,
                defaultLessonCount: defaultLessonCount,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stageId,
                required String name,
                required int defaultLessonCount,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => LessonPeriodTypesCompanion.insert(
                id: id,
                stageId: stageId,
                name: name,
                defaultLessonCount: defaultLessonCount,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LessonPeriodTypesTable, LessonPeriodType>(table),
                  $$LessonPeriodTypesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                stageId = false,
                dailyLessonOverridesRefs = false,
                lessonTimesRefs = false,
                freeSlotsRefs = false,
                subjectPresetsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dailyLessonOverridesRefs) db.dailyLessonOverrides,
                    if (lessonTimesRefs) db.lessonTimes,
                    if (freeSlotsRefs) db.freeSlots,
                    if (subjectPresetsRefs) db.subjectPresets,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (stageId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.stageId,
                            referencedTable: $$LessonPeriodTypesTableReferences
                                ._stageIdTable(db),
                            referencedColumn: $$LessonPeriodTypesTableReferences
                                ._stageIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dailyLessonOverridesRefs)
                        await $_getPrefetchedData<
                          LessonPeriodType,
                          $LessonPeriodTypesTable,
                          DailyLessonOverride
                        >(
                          currentTable: table,
                          referencedTable: $$LessonPeriodTypesTableReferences
                              ._dailyLessonOverridesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LessonPeriodTypesTableReferences(
                                db,
                                table,
                                p0,
                              ).dailyLessonOverridesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.periodTypeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (lessonTimesRefs)
                        await $_getPrefetchedData<
                          LessonPeriodType,
                          $LessonPeriodTypesTable,
                          LessonTime
                        >(
                          currentTable: table,
                          referencedTable: $$LessonPeriodTypesTableReferences
                              ._lessonTimesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LessonPeriodTypesTableReferences(
                                db,
                                table,
                                p0,
                              ).lessonTimesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.periodTypeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (freeSlotsRefs)
                        await $_getPrefetchedData<
                          LessonPeriodType,
                          $LessonPeriodTypesTable,
                          FreeSlot
                        >(
                          currentTable: table,
                          referencedTable: $$LessonPeriodTypesTableReferences
                              ._freeSlotsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LessonPeriodTypesTableReferences(
                                db,
                                table,
                                p0,
                              ).freeSlotsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.periodTypeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (subjectPresetsRefs)
                        await $_getPrefetchedData<
                          LessonPeriodType,
                          $LessonPeriodTypesTable,
                          SubjectPreset
                        >(
                          currentTable: table,
                          referencedTable: $$LessonPeriodTypesTableReferences
                              ._subjectPresetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LessonPeriodTypesTableReferences(
                                db,
                                table,
                                p0,
                              ).subjectPresetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.periodTypeId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LessonPeriodTypesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LessonPeriodTypesTable,
      LessonPeriodType,
      $$LessonPeriodTypesTableFilterComposer,
      $$LessonPeriodTypesTableOrderingComposer,
      $$LessonPeriodTypesTableAnnotationComposer,
      $$LessonPeriodTypesTableCreateCompanionBuilder,
      $$LessonPeriodTypesTableUpdateCompanionBuilder,
      (LessonPeriodType, $$LessonPeriodTypesTableReferences),
      LessonPeriodType,
      PrefetchHooks Function({
        bool stageId,
        bool dailyLessonOverridesRefs,
        bool lessonTimesRefs,
        bool freeSlotsRefs,
        bool subjectPresetsRefs,
      })
    >;
typedef $$DailyLessonOverridesTableCreateCompanionBuilder =
    DailyLessonOverridesCompanion Function({
      required String id,
      required String stageId,
      required String periodTypeId,
      required int weekday,
      required int lessonCount,
      Value<int> rowid,
    });
typedef $$DailyLessonOverridesTableUpdateCompanionBuilder =
    DailyLessonOverridesCompanion Function({
      Value<String> id,
      Value<String> stageId,
      Value<String> periodTypeId,
      Value<int> weekday,
      Value<int> lessonCount,
      Value<int> rowid,
    });

final class $$DailyLessonOverridesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $DailyLessonOverridesTable,
          DailyLessonOverride
        > {
  $$DailyLessonOverridesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SchoolStagesTable _stageIdTable(_$AppDatabase db) => db.schoolStages
      .createAlias('daily_lesson_overrides__stage_id__school_stages__id');

  $$SchoolStagesTableProcessedTableManager get stageId {
    final $_column = $_itemColumn<String>('stage_id')!;

    final manager = $$SchoolStagesTableTableManager(
      $_db,
      $_db.schoolStages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_stageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $LessonPeriodTypesTable _periodTypeIdTable(_$AppDatabase db) =>
      db.lessonPeriodTypes.createAlias(
        'daily_lesson_overrides__period_type_id__lesson_period_types__id',
      );

  $$LessonPeriodTypesTableProcessedTableManager get periodTypeId {
    final $_column = $_itemColumn<String>('period_type_id')!;

    final manager = $$LessonPeriodTypesTableTableManager(
      $_db,
      $_db.lessonPeriodTypes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_periodTypeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DailyLessonOverridesTableFilterComposer
    extends Composer<_$AppDatabase, $DailyLessonOverridesTable> {
  $$DailyLessonOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lessonCount => $composableBuilder(
    column: $table.lessonCount,
    builder: (column) => ColumnFilters(column),
  );

  $$SchoolStagesTableFilterComposer get stageId {
    final $$SchoolStagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableFilterComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LessonPeriodTypesTableFilterComposer get periodTypeId {
    final $$LessonPeriodTypesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodTypeId,
      referencedTable: $db.lessonPeriodTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonPeriodTypesTableFilterComposer(
            $db: $db,
            $table: $db.lessonPeriodTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyLessonOverridesTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyLessonOverridesTable> {
  $$DailyLessonOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lessonCount => $composableBuilder(
    column: $table.lessonCount,
    builder: (column) => ColumnOrderings(column),
  );

  $$SchoolStagesTableOrderingComposer get stageId {
    final $$SchoolStagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableOrderingComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LessonPeriodTypesTableOrderingComposer get periodTypeId {
    final $$LessonPeriodTypesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodTypeId,
      referencedTable: $db.lessonPeriodTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonPeriodTypesTableOrderingComposer(
            $db: $db,
            $table: $db.lessonPeriodTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyLessonOverridesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyLessonOverridesTable> {
  $$DailyLessonOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<int> get lessonCount => $composableBuilder(
    column: $table.lessonCount,
    builder: (column) => column,
  );

  $$SchoolStagesTableAnnotationComposer get stageId {
    final $$SchoolStagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableAnnotationComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LessonPeriodTypesTableAnnotationComposer get periodTypeId {
    final $$LessonPeriodTypesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.periodTypeId,
          referencedTable: $db.lessonPeriodTypes,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LessonPeriodTypesTableAnnotationComposer(
                $db: $db,
                $table: $db.lessonPeriodTypes,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DailyLessonOverridesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyLessonOverridesTable,
          DailyLessonOverride,
          $$DailyLessonOverridesTableFilterComposer,
          $$DailyLessonOverridesTableOrderingComposer,
          $$DailyLessonOverridesTableAnnotationComposer,
          $$DailyLessonOverridesTableCreateCompanionBuilder,
          $$DailyLessonOverridesTableUpdateCompanionBuilder,
          (DailyLessonOverride, $$DailyLessonOverridesTableReferences),
          DailyLessonOverride,
          PrefetchHooks Function({bool stageId, bool periodTypeId})
        > {
  $$DailyLessonOverridesTableTableManager(
    _$AppDatabase db,
    $DailyLessonOverridesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyLessonOverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyLessonOverridesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DailyLessonOverridesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stageId = const Value.absent(),
                Value<String> periodTypeId = const Value.absent(),
                Value<int> weekday = const Value.absent(),
                Value<int> lessonCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyLessonOverridesCompanion(
                id: id,
                stageId: stageId,
                periodTypeId: periodTypeId,
                weekday: weekday,
                lessonCount: lessonCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stageId,
                required String periodTypeId,
                required int weekday,
                required int lessonCount,
                Value<int> rowid = const Value.absent(),
              }) => DailyLessonOverridesCompanion.insert(
                id: id,
                stageId: stageId,
                periodTypeId: periodTypeId,
                weekday: weekday,
                lessonCount: lessonCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DailyLessonOverridesTable, DailyLessonOverride>(
                    table,
                  ),
                  $$DailyLessonOverridesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({stageId = false, periodTypeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (stageId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.stageId,
                        referencedTable: $$DailyLessonOverridesTableReferences
                            ._stageIdTable(db),
                        referencedColumn: $$DailyLessonOverridesTableReferences
                            ._stageIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (periodTypeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.periodTypeId,
                        referencedTable: $$DailyLessonOverridesTableReferences
                            ._periodTypeIdTable(db),
                        referencedColumn: $$DailyLessonOverridesTableReferences
                            ._periodTypeIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DailyLessonOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyLessonOverridesTable,
      DailyLessonOverride,
      $$DailyLessonOverridesTableFilterComposer,
      $$DailyLessonOverridesTableOrderingComposer,
      $$DailyLessonOverridesTableAnnotationComposer,
      $$DailyLessonOverridesTableCreateCompanionBuilder,
      $$DailyLessonOverridesTableUpdateCompanionBuilder,
      (DailyLessonOverride, $$DailyLessonOverridesTableReferences),
      DailyLessonOverride,
      PrefetchHooks Function({bool stageId, bool periodTypeId})
    >;
typedef $$LessonTimesTableCreateCompanionBuilder =
    LessonTimesCompanion Function({
      required String id,
      required String periodTypeId,
      required int lessonIndex,
      required String label,
      Value<int?> startMinute,
      Value<int?> endMinute,
      Value<int> rowid,
    });
typedef $$LessonTimesTableUpdateCompanionBuilder =
    LessonTimesCompanion Function({
      Value<String> id,
      Value<String> periodTypeId,
      Value<int> lessonIndex,
      Value<String> label,
      Value<int?> startMinute,
      Value<int?> endMinute,
      Value<int> rowid,
    });

final class $$LessonTimesTableReferences
    extends BaseReferences<_$AppDatabase, $LessonTimesTable, LessonTime> {
  $$LessonTimesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LessonPeriodTypesTable _periodTypeIdTable(_$AppDatabase db) => db
      .lessonPeriodTypes
      .createAlias('lesson_times__period_type_id__lesson_period_types__id');

  $$LessonPeriodTypesTableProcessedTableManager get periodTypeId {
    final $_column = $_itemColumn<String>('period_type_id')!;

    final manager = $$LessonPeriodTypesTableTableManager(
      $_db,
      $_db.lessonPeriodTypes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_periodTypeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LessonTimesTableFilterComposer
    extends Composer<_$AppDatabase, $LessonTimesTable> {
  $$LessonTimesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lessonIndex => $composableBuilder(
    column: $table.lessonIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnFilters(column),
  );

  $$LessonPeriodTypesTableFilterComposer get periodTypeId {
    final $$LessonPeriodTypesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodTypeId,
      referencedTable: $db.lessonPeriodTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonPeriodTypesTableFilterComposer(
            $db: $db,
            $table: $db.lessonPeriodTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LessonTimesTableOrderingComposer
    extends Composer<_$AppDatabase, $LessonTimesTable> {
  $$LessonTimesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lessonIndex => $composableBuilder(
    column: $table.lessonIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnOrderings(column),
  );

  $$LessonPeriodTypesTableOrderingComposer get periodTypeId {
    final $$LessonPeriodTypesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodTypeId,
      referencedTable: $db.lessonPeriodTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonPeriodTypesTableOrderingComposer(
            $db: $db,
            $table: $db.lessonPeriodTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LessonTimesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LessonTimesTable> {
  $$LessonTimesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get lessonIndex => $composableBuilder(
    column: $table.lessonIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endMinute =>
      $composableBuilder(column: $table.endMinute, builder: (column) => column);

  $$LessonPeriodTypesTableAnnotationComposer get periodTypeId {
    final $$LessonPeriodTypesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.periodTypeId,
          referencedTable: $db.lessonPeriodTypes,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LessonPeriodTypesTableAnnotationComposer(
                $db: $db,
                $table: $db.lessonPeriodTypes,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$LessonTimesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LessonTimesTable,
          LessonTime,
          $$LessonTimesTableFilterComposer,
          $$LessonTimesTableOrderingComposer,
          $$LessonTimesTableAnnotationComposer,
          $$LessonTimesTableCreateCompanionBuilder,
          $$LessonTimesTableUpdateCompanionBuilder,
          (LessonTime, $$LessonTimesTableReferences),
          LessonTime,
          PrefetchHooks Function({bool periodTypeId})
        > {
  $$LessonTimesTableTableManager(_$AppDatabase db, $LessonTimesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LessonTimesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LessonTimesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LessonTimesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> periodTypeId = const Value.absent(),
                Value<int> lessonIndex = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int?> startMinute = const Value.absent(),
                Value<int?> endMinute = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LessonTimesCompanion(
                id: id,
                periodTypeId: periodTypeId,
                lessonIndex: lessonIndex,
                label: label,
                startMinute: startMinute,
                endMinute: endMinute,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String periodTypeId,
                required int lessonIndex,
                required String label,
                Value<int?> startMinute = const Value.absent(),
                Value<int?> endMinute = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LessonTimesCompanion.insert(
                id: id,
                periodTypeId: periodTypeId,
                lessonIndex: lessonIndex,
                label: label,
                startMinute: startMinute,
                endMinute: endMinute,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LessonTimesTable, LessonTime>(table),
                  $$LessonTimesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({periodTypeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (periodTypeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.periodTypeId,
                        referencedTable: $$LessonTimesTableReferences
                            ._periodTypeIdTable(db),
                        referencedColumn: $$LessonTimesTableReferences
                            ._periodTypeIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LessonTimesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LessonTimesTable,
      LessonTime,
      $$LessonTimesTableFilterComposer,
      $$LessonTimesTableOrderingComposer,
      $$LessonTimesTableAnnotationComposer,
      $$LessonTimesTableCreateCompanionBuilder,
      $$LessonTimesTableUpdateCompanionBuilder,
      (LessonTime, $$LessonTimesTableReferences),
      LessonTime,
      PrefetchHooks Function({bool periodTypeId})
    >;
typedef $$CalendarExceptionsTableCreateCompanionBuilder =
    CalendarExceptionsCompanion Function({
      required String id,
      required String termId,
      required String date,
      required String kind,
      Value<int?> makeupWeekday,
      Value<String?> makeupForDate,
      Value<String> note,
      Value<int> rowid,
    });
typedef $$CalendarExceptionsTableUpdateCompanionBuilder =
    CalendarExceptionsCompanion Function({
      Value<String> id,
      Value<String> termId,
      Value<String> date,
      Value<String> kind,
      Value<int?> makeupWeekday,
      Value<String?> makeupForDate,
      Value<String> note,
      Value<int> rowid,
    });

final class $$CalendarExceptionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $CalendarExceptionsTable,
          CalendarException
        > {
  $$CalendarExceptionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AcademicTermsTable _termIdTable(_$AppDatabase db) => db.academicTerms
      .createAlias('calendar_exceptions__term_id__academic_terms__id');

  $$AcademicTermsTableProcessedTableManager get termId {
    final $_column = $_itemColumn<String>('term_id')!;

    final manager = $$AcademicTermsTableTableManager(
      $_db,
      $_db.academicTerms,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_termIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CalendarExceptionsTableFilterComposer
    extends Composer<_$AppDatabase, $CalendarExceptionsTable> {
  $$CalendarExceptionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get makeupWeekday => $composableBuilder(
    column: $table.makeupWeekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get makeupForDate => $composableBuilder(
    column: $table.makeupForDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  $$AcademicTermsTableFilterComposer get termId {
    final $$AcademicTermsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.termId,
      referencedTable: $db.academicTerms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcademicTermsTableFilterComposer(
            $db: $db,
            $table: $db.academicTerms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CalendarExceptionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CalendarExceptionsTable> {
  $$CalendarExceptionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get makeupWeekday => $composableBuilder(
    column: $table.makeupWeekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get makeupForDate => $composableBuilder(
    column: $table.makeupForDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  $$AcademicTermsTableOrderingComposer get termId {
    final $$AcademicTermsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.termId,
      referencedTable: $db.academicTerms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcademicTermsTableOrderingComposer(
            $db: $db,
            $table: $db.academicTerms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CalendarExceptionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalendarExceptionsTable> {
  $$CalendarExceptionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get makeupWeekday => $composableBuilder(
    column: $table.makeupWeekday,
    builder: (column) => column,
  );

  GeneratedColumn<String> get makeupForDate => $composableBuilder(
    column: $table.makeupForDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  $$AcademicTermsTableAnnotationComposer get termId {
    final $$AcademicTermsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.termId,
      referencedTable: $db.academicTerms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcademicTermsTableAnnotationComposer(
            $db: $db,
            $table: $db.academicTerms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CalendarExceptionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CalendarExceptionsTable,
          CalendarException,
          $$CalendarExceptionsTableFilterComposer,
          $$CalendarExceptionsTableOrderingComposer,
          $$CalendarExceptionsTableAnnotationComposer,
          $$CalendarExceptionsTableCreateCompanionBuilder,
          $$CalendarExceptionsTableUpdateCompanionBuilder,
          (CalendarException, $$CalendarExceptionsTableReferences),
          CalendarException,
          PrefetchHooks Function({bool termId})
        > {
  $$CalendarExceptionsTableTableManager(
    _$AppDatabase db,
    $CalendarExceptionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalendarExceptionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalendarExceptionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CalendarExceptionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> termId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int?> makeupWeekday = const Value.absent(),
                Value<String?> makeupForDate = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalendarExceptionsCompanion(
                id: id,
                termId: termId,
                date: date,
                kind: kind,
                makeupWeekday: makeupWeekday,
                makeupForDate: makeupForDate,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String termId,
                required String date,
                required String kind,
                Value<int?> makeupWeekday = const Value.absent(),
                Value<String?> makeupForDate = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalendarExceptionsCompanion.insert(
                id: id,
                termId: termId,
                date: date,
                kind: kind,
                makeupWeekday: makeupWeekday,
                makeupForDate: makeupForDate,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CalendarExceptionsTable, CalendarException>(
                    table,
                  ),
                  $$CalendarExceptionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({termId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (termId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.termId,
                        referencedTable: $$CalendarExceptionsTableReferences
                            ._termIdTable(db),
                        referencedColumn: $$CalendarExceptionsTableReferences
                            ._termIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CalendarExceptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CalendarExceptionsTable,
      CalendarException,
      $$CalendarExceptionsTableFilterComposer,
      $$CalendarExceptionsTableOrderingComposer,
      $$CalendarExceptionsTableAnnotationComposer,
      $$CalendarExceptionsTableCreateCompanionBuilder,
      $$CalendarExceptionsTableUpdateCompanionBuilder,
      (CalendarException, $$CalendarExceptionsTableReferences),
      CalendarException,
      PrefetchHooks Function({bool termId})
    >;
typedef $$FreeSlotsTableCreateCompanionBuilder = FreeSlotsCompanion Function({
  required String id,
  required String scopeType,
  required String scopeId,
  required String stageId,
  required String periodTypeId,
  required int weekday,
  required int lessonIndex,
  required String label,
  Value<int> rowid,
});
typedef $$FreeSlotsTableUpdateCompanionBuilder = FreeSlotsCompanion Function({
  Value<String> id,
  Value<String> scopeType,
  Value<String> scopeId,
  Value<String> stageId,
  Value<String> periodTypeId,
  Value<int> weekday,
  Value<int> lessonIndex,
  Value<String> label,
  Value<int> rowid,
});

final class $$FreeSlotsTableReferences
    extends BaseReferences<_$AppDatabase, $FreeSlotsTable, FreeSlot> {
  $$FreeSlotsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SchoolStagesTable _stageIdTable(_$AppDatabase db) =>
      db.schoolStages.createAlias('free_slots__stage_id__school_stages__id');

  $$SchoolStagesTableProcessedTableManager get stageId {
    final $_column = $_itemColumn<String>('stage_id')!;

    final manager = $$SchoolStagesTableTableManager(
      $_db,
      $_db.schoolStages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_stageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $LessonPeriodTypesTable _periodTypeIdTable(_$AppDatabase db) => db
      .lessonPeriodTypes
      .createAlias('free_slots__period_type_id__lesson_period_types__id');

  $$LessonPeriodTypesTableProcessedTableManager get periodTypeId {
    final $_column = $_itemColumn<String>('period_type_id')!;

    final manager = $$LessonPeriodTypesTableTableManager(
      $_db,
      $_db.lessonPeriodTypes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_periodTypeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FreeSlotsTableFilterComposer
    extends Composer<_$AppDatabase, $FreeSlotsTable> {
  $$FreeSlotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeId => $composableBuilder(
    column: $table.scopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lessonIndex => $composableBuilder(
    column: $table.lessonIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  $$SchoolStagesTableFilterComposer get stageId {
    final $$SchoolStagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableFilterComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LessonPeriodTypesTableFilterComposer get periodTypeId {
    final $$LessonPeriodTypesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodTypeId,
      referencedTable: $db.lessonPeriodTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonPeriodTypesTableFilterComposer(
            $db: $db,
            $table: $db.lessonPeriodTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FreeSlotsTableOrderingComposer
    extends Composer<_$AppDatabase, $FreeSlotsTable> {
  $$FreeSlotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeId => $composableBuilder(
    column: $table.scopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lessonIndex => $composableBuilder(
    column: $table.lessonIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  $$SchoolStagesTableOrderingComposer get stageId {
    final $$SchoolStagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableOrderingComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LessonPeriodTypesTableOrderingComposer get periodTypeId {
    final $$LessonPeriodTypesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodTypeId,
      referencedTable: $db.lessonPeriodTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonPeriodTypesTableOrderingComposer(
            $db: $db,
            $table: $db.lessonPeriodTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FreeSlotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FreeSlotsTable> {
  $$FreeSlotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scopeType =>
      $composableBuilder(column: $table.scopeType, builder: (column) => column);

  GeneratedColumn<String> get scopeId =>
      $composableBuilder(column: $table.scopeId, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<int> get lessonIndex => $composableBuilder(
    column: $table.lessonIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  $$SchoolStagesTableAnnotationComposer get stageId {
    final $$SchoolStagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableAnnotationComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LessonPeriodTypesTableAnnotationComposer get periodTypeId {
    final $$LessonPeriodTypesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.periodTypeId,
          referencedTable: $db.lessonPeriodTypes,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LessonPeriodTypesTableAnnotationComposer(
                $db: $db,
                $table: $db.lessonPeriodTypes,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$FreeSlotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FreeSlotsTable,
          FreeSlot,
          $$FreeSlotsTableFilterComposer,
          $$FreeSlotsTableOrderingComposer,
          $$FreeSlotsTableAnnotationComposer,
          $$FreeSlotsTableCreateCompanionBuilder,
          $$FreeSlotsTableUpdateCompanionBuilder,
          (FreeSlot, $$FreeSlotsTableReferences),
          FreeSlot,
          PrefetchHooks Function({bool stageId, bool periodTypeId})
        > {
  $$FreeSlotsTableTableManager(_$AppDatabase db, $FreeSlotsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FreeSlotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FreeSlotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FreeSlotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> scopeType = const Value.absent(),
                Value<String> scopeId = const Value.absent(),
                Value<String> stageId = const Value.absent(),
                Value<String> periodTypeId = const Value.absent(),
                Value<int> weekday = const Value.absent(),
                Value<int> lessonIndex = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FreeSlotsCompanion(
                id: id,
                scopeType: scopeType,
                scopeId: scopeId,
                stageId: stageId,
                periodTypeId: periodTypeId,
                weekday: weekday,
                lessonIndex: lessonIndex,
                label: label,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String scopeType,
                required String scopeId,
                required String stageId,
                required String periodTypeId,
                required int weekday,
                required int lessonIndex,
                required String label,
                Value<int> rowid = const Value.absent(),
              }) => FreeSlotsCompanion.insert(
                id: id,
                scopeType: scopeType,
                scopeId: scopeId,
                stageId: stageId,
                periodTypeId: periodTypeId,
                weekday: weekday,
                lessonIndex: lessonIndex,
                label: label,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FreeSlotsTable, FreeSlot>(table),
                  $$FreeSlotsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({stageId = false, periodTypeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (stageId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.stageId,
                        referencedTable: $$FreeSlotsTableReferences
                            ._stageIdTable(db),
                        referencedColumn: $$FreeSlotsTableReferences
                            ._stageIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (periodTypeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.periodTypeId,
                        referencedTable: $$FreeSlotsTableReferences
                            ._periodTypeIdTable(db),
                        referencedColumn: $$FreeSlotsTableReferences
                            ._periodTypeIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FreeSlotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FreeSlotsTable,
      FreeSlot,
      $$FreeSlotsTableFilterComposer,
      $$FreeSlotsTableOrderingComposer,
      $$FreeSlotsTableAnnotationComposer,
      $$FreeSlotsTableCreateCompanionBuilder,
      $$FreeSlotsTableUpdateCompanionBuilder,
      (FreeSlot, $$FreeSlotsTableReferences),
      FreeSlot,
      PrefetchHooks Function({bool stageId, bool periodTypeId})
    >;
typedef $$CommonPeriodsTableCreateCompanionBuilder =
    CommonPeriodsCompanion Function({
      required String id,
      required String stageId,
      required String name,
      Value<String?> insertAfterLessonId,
      Value<int> durationMinutes,
      Value<int?> startMinute,
      Value<int?> endMinute,
      Value<int> rowid,
    });
typedef $$CommonPeriodsTableUpdateCompanionBuilder =
    CommonPeriodsCompanion Function({
      Value<String> id,
      Value<String> stageId,
      Value<String> name,
      Value<String?> insertAfterLessonId,
      Value<int> durationMinutes,
      Value<int?> startMinute,
      Value<int?> endMinute,
      Value<int> rowid,
    });

final class $$CommonPeriodsTableReferences
    extends BaseReferences<_$AppDatabase, $CommonPeriodsTable, CommonPeriod> {
  $$CommonPeriodsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SchoolStagesTable _stageIdTable(_$AppDatabase db) => db.schoolStages
      .createAlias('common_periods__stage_id__school_stages__id');

  $$SchoolStagesTableProcessedTableManager get stageId {
    final $_column = $_itemColumn<String>('stage_id')!;

    final manager = $$SchoolStagesTableTableManager(
      $_db,
      $_db.schoolStages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_stageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CommonPeriodsTableFilterComposer
    extends Composer<_$AppDatabase, $CommonPeriodsTable> {
  $$CommonPeriodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get insertAfterLessonId => $composableBuilder(
    column: $table.insertAfterLessonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnFilters(column),
  );

  $$SchoolStagesTableFilterComposer get stageId {
    final $$SchoolStagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableFilterComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CommonPeriodsTableOrderingComposer
    extends Composer<_$AppDatabase, $CommonPeriodsTable> {
  $$CommonPeriodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get insertAfterLessonId => $composableBuilder(
    column: $table.insertAfterLessonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnOrderings(column),
  );

  $$SchoolStagesTableOrderingComposer get stageId {
    final $$SchoolStagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableOrderingComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CommonPeriodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CommonPeriodsTable> {
  $$CommonPeriodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get insertAfterLessonId => $composableBuilder(
    column: $table.insertAfterLessonId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endMinute =>
      $composableBuilder(column: $table.endMinute, builder: (column) => column);

  $$SchoolStagesTableAnnotationComposer get stageId {
    final $$SchoolStagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableAnnotationComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CommonPeriodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CommonPeriodsTable,
          CommonPeriod,
          $$CommonPeriodsTableFilterComposer,
          $$CommonPeriodsTableOrderingComposer,
          $$CommonPeriodsTableAnnotationComposer,
          $$CommonPeriodsTableCreateCompanionBuilder,
          $$CommonPeriodsTableUpdateCompanionBuilder,
          (CommonPeriod, $$CommonPeriodsTableReferences),
          CommonPeriod,
          PrefetchHooks Function({bool stageId})
        > {
  $$CommonPeriodsTableTableManager(_$AppDatabase db, $CommonPeriodsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CommonPeriodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CommonPeriodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CommonPeriodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stageId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> insertAfterLessonId = const Value.absent(),
                Value<int> durationMinutes = const Value.absent(),
                Value<int?> startMinute = const Value.absent(),
                Value<int?> endMinute = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CommonPeriodsCompanion(
                id: id,
                stageId: stageId,
                name: name,
                insertAfterLessonId: insertAfterLessonId,
                durationMinutes: durationMinutes,
                startMinute: startMinute,
                endMinute: endMinute,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stageId,
                required String name,
                Value<String?> insertAfterLessonId = const Value.absent(),
                Value<int> durationMinutes = const Value.absent(),
                Value<int?> startMinute = const Value.absent(),
                Value<int?> endMinute = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CommonPeriodsCompanion.insert(
                id: id,
                stageId: stageId,
                name: name,
                insertAfterLessonId: insertAfterLessonId,
                durationMinutes: durationMinutes,
                startMinute: startMinute,
                endMinute: endMinute,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CommonPeriodsTable, CommonPeriod>(table),
                  $$CommonPeriodsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({stageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (stageId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.stageId,
                        referencedTable: $$CommonPeriodsTableReferences
                            ._stageIdTable(db),
                        referencedColumn: $$CommonPeriodsTableReferences
                            ._stageIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CommonPeriodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CommonPeriodsTable,
      CommonPeriod,
      $$CommonPeriodsTableFilterComposer,
      $$CommonPeriodsTableOrderingComposer,
      $$CommonPeriodsTableAnnotationComposer,
      $$CommonPeriodsTableCreateCompanionBuilder,
      $$CommonPeriodsTableUpdateCompanionBuilder,
      (CommonPeriod, $$CommonPeriodsTableReferences),
      CommonPeriod,
      PrefetchHooks Function({bool stageId})
    >;
typedef $$SubjectsTableCreateCompanionBuilder = SubjectsCompanion Function({
  required String id,
  required String name,
  required String shortName,
  required int sortOrder,
  Value<int> rowid,
});
typedef $$SubjectsTableUpdateCompanionBuilder = SubjectsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> shortName,
  Value<int> sortOrder,
  Value<int> rowid,
});

final class $$SubjectsTableReferences
    extends BaseReferences<_$AppDatabase, $SubjectsTable, Subject> {
  $$SubjectsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $SubjectRequirementsTable,
    List<SubjectRequirement>
  >
  _subjectRequirementsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.subjectRequirements,
        aliasName: 'subjects__id__subject_requirements__subject_id',
      );

  $$SubjectRequirementsTableProcessedTableManager get subjectRequirementsRefs {
    final manager = $$SubjectRequirementsTableTableManager(
      $_db,
      $_db.subjectRequirements,
    ).filter((f) => f.subjectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _subjectRequirementsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SubjectPresetsTable, List<SubjectPreset>>
  _subjectPresetsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.subjectPresets,
    aliasName: 'subjects__id__subject_presets__subject_id',
  );

  $$SubjectPresetsTableProcessedTableManager get subjectPresetsRefs {
    final manager = $$SubjectPresetsTableTableManager(
      $_db,
      $_db.subjectPresets,
    ).filter((f) => f.subjectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_subjectPresetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $SubjectLessonConstraintsTable,
    List<SubjectLessonConstraint>
  >
  _subjectLessonConstraintsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.subjectLessonConstraints,
        aliasName: 'subjects__id__subject_lesson_constraints__subject_id',
      );

  $$SubjectLessonConstraintsTableProcessedTableManager
  get subjectLessonConstraintsRefs {
    final manager = $$SubjectLessonConstraintsTableTableManager(
      $_db,
      $_db.subjectLessonConstraints,
    ).filter((f) => f.subjectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _subjectLessonConstraintsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SubjectsTableFilterComposer
    extends Composer<_$AppDatabase, $SubjectsTable> {
  $$SubjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> subjectRequirementsRefs(
    Expression<bool> Function($$SubjectRequirementsTableFilterComposer f) f,
  ) {
    final $$SubjectRequirementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectRequirements,
      getReferencedColumn: (t) => t.subjectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectRequirementsTableFilterComposer(
            $db: $db,
            $table: $db.subjectRequirements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> subjectPresetsRefs(
    Expression<bool> Function($$SubjectPresetsTableFilterComposer f) f,
  ) {
    final $$SubjectPresetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectPresets,
      getReferencedColumn: (t) => t.subjectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectPresetsTableFilterComposer(
            $db: $db,
            $table: $db.subjectPresets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> subjectLessonConstraintsRefs(
    Expression<bool> Function($$SubjectLessonConstraintsTableFilterComposer f)
    f,
  ) {
    final $$SubjectLessonConstraintsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.subjectLessonConstraints,
          getReferencedColumn: (t) => t.subjectId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SubjectLessonConstraintsTableFilterComposer(
                $db: $db,
                $table: $db.subjectLessonConstraints,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SubjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubjectsTable> {
  $$SubjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SubjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubjectsTable> {
  $$SubjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get shortName =>
      $composableBuilder(column: $table.shortName, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  Expression<T> subjectRequirementsRefs<T extends Object>(
    Expression<T> Function($$SubjectRequirementsTableAnnotationComposer a) f,
  ) {
    final $$SubjectRequirementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.subjectRequirements,
          getReferencedColumn: (t) => t.subjectId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SubjectRequirementsTableAnnotationComposer(
                $db: $db,
                $table: $db.subjectRequirements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> subjectPresetsRefs<T extends Object>(
    Expression<T> Function($$SubjectPresetsTableAnnotationComposer a) f,
  ) {
    final $$SubjectPresetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subjectPresets,
      getReferencedColumn: (t) => t.subjectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectPresetsTableAnnotationComposer(
            $db: $db,
            $table: $db.subjectPresets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> subjectLessonConstraintsRefs<T extends Object>(
    Expression<T> Function($$SubjectLessonConstraintsTableAnnotationComposer a)
    f,
  ) {
    final $$SubjectLessonConstraintsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.subjectLessonConstraints,
          getReferencedColumn: (t) => t.subjectId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SubjectLessonConstraintsTableAnnotationComposer(
                $db: $db,
                $table: $db.subjectLessonConstraints,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SubjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubjectsTable,
          Subject,
          $$SubjectsTableFilterComposer,
          $$SubjectsTableOrderingComposer,
          $$SubjectsTableAnnotationComposer,
          $$SubjectsTableCreateCompanionBuilder,
          $$SubjectsTableUpdateCompanionBuilder,
          (Subject, $$SubjectsTableReferences),
          Subject,
          PrefetchHooks Function({
            bool subjectRequirementsRefs,
            bool subjectPresetsRefs,
            bool subjectLessonConstraintsRefs,
          })
        > {
  $$SubjectsTableTableManager(_$AppDatabase db, $SubjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> shortName = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubjectsCompanion(
                id: id,
                name: name,
                shortName: shortName,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String shortName,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => SubjectsCompanion.insert(
                id: id,
                name: name,
                shortName: shortName,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SubjectsTable, Subject>(table),
                  $$SubjectsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                subjectRequirementsRefs = false,
                subjectPresetsRefs = false,
                subjectLessonConstraintsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (subjectRequirementsRefs) db.subjectRequirements,
                    if (subjectPresetsRefs) db.subjectPresets,
                    if (subjectLessonConstraintsRefs)
                      db.subjectLessonConstraints,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (subjectRequirementsRefs)
                        await $_getPrefetchedData<
                          Subject,
                          $SubjectsTable,
                          SubjectRequirement
                        >(
                          currentTable: table,
                          referencedTable: $$SubjectsTableReferences
                              ._subjectRequirementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SubjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).subjectRequirementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.subjectId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (subjectPresetsRefs)
                        await $_getPrefetchedData<
                          Subject,
                          $SubjectsTable,
                          SubjectPreset
                        >(
                          currentTable: table,
                          referencedTable: $$SubjectsTableReferences
                              ._subjectPresetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SubjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).subjectPresetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.subjectId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (subjectLessonConstraintsRefs)
                        await $_getPrefetchedData<
                          Subject,
                          $SubjectsTable,
                          SubjectLessonConstraint
                        >(
                          currentTable: table,
                          referencedTable: $$SubjectsTableReferences
                              ._subjectLessonConstraintsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SubjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).subjectLessonConstraintsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.subjectId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SubjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubjectsTable,
      Subject,
      $$SubjectsTableFilterComposer,
      $$SubjectsTableOrderingComposer,
      $$SubjectsTableAnnotationComposer,
      $$SubjectsTableCreateCompanionBuilder,
      $$SubjectsTableUpdateCompanionBuilder,
      (Subject, $$SubjectsTableReferences),
      Subject,
      PrefetchHooks Function({
        bool subjectRequirementsRefs,
        bool subjectPresetsRefs,
        bool subjectLessonConstraintsRefs,
      })
    >;
typedef $$SubjectRequirementsTableCreateCompanionBuilder =
    SubjectRequirementsCompanion Function({
      required String id,
      required String subjectId,
      required String gradeId,
      Value<String?> classId,
      Value<String> weekMode,
      Value<int> lessonCount,
      Value<int> rowid,
    });
typedef $$SubjectRequirementsTableUpdateCompanionBuilder =
    SubjectRequirementsCompanion Function({
      Value<String> id,
      Value<String> subjectId,
      Value<String> gradeId,
      Value<String?> classId,
      Value<String> weekMode,
      Value<int> lessonCount,
      Value<int> rowid,
    });

final class $$SubjectRequirementsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $SubjectRequirementsTable,
          SubjectRequirement
        > {
  $$SubjectRequirementsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SubjectsTable _subjectIdTable(_$AppDatabase db) =>
      db.subjects.createAlias('subject_requirements__subject_id__subjects__id');

  $$SubjectsTableProcessedTableManager get subjectId {
    final $_column = $_itemColumn<String>('subject_id')!;

    final manager = $$SubjectsTableTableManager(
      $_db,
      $_db.subjects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_subjectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $GradeGroupsTable _gradeIdTable(_$AppDatabase db) => db.gradeGroups
      .createAlias('subject_requirements__grade_id__grade_groups__id');

  $$GradeGroupsTableProcessedTableManager get gradeId {
    final $_column = $_itemColumn<String>('grade_id')!;

    final manager = $$GradeGroupsTableTableManager(
      $_db,
      $_db.gradeGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_gradeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ClassGroupsTable _classIdTable(_$AppDatabase db) => db.classGroups
      .createAlias('subject_requirements__class_id__class_groups__id');

  $$ClassGroupsTableProcessedTableManager? get classId {
    final $_column = $_itemColumn<String>('class_id');
    if ($_column == null) return null;
    final manager = $$ClassGroupsTableTableManager(
      $_db,
      $_db.classGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_classIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SubjectRequirementsTableFilterComposer
    extends Composer<_$AppDatabase, $SubjectRequirementsTable> {
  $$SubjectRequirementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weekMode => $composableBuilder(
    column: $table.weekMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lessonCount => $composableBuilder(
    column: $table.lessonCount,
    builder: (column) => ColumnFilters(column),
  );

  $$SubjectsTableFilterComposer get subjectId {
    final $$SubjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableFilterComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GradeGroupsTableFilterComposer get gradeId {
    final $$GradeGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gradeId,
      referencedTable: $db.gradeGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeGroupsTableFilterComposer(
            $db: $db,
            $table: $db.gradeGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ClassGroupsTableFilterComposer get classId {
    final $$ClassGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.classId,
      referencedTable: $db.classGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassGroupsTableFilterComposer(
            $db: $db,
            $table: $db.classGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectRequirementsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubjectRequirementsTable> {
  $$SubjectRequirementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weekMode => $composableBuilder(
    column: $table.weekMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lessonCount => $composableBuilder(
    column: $table.lessonCount,
    builder: (column) => ColumnOrderings(column),
  );

  $$SubjectsTableOrderingComposer get subjectId {
    final $$SubjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableOrderingComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GradeGroupsTableOrderingComposer get gradeId {
    final $$GradeGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gradeId,
      referencedTable: $db.gradeGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.gradeGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ClassGroupsTableOrderingComposer get classId {
    final $$ClassGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.classId,
      referencedTable: $db.classGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.classGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectRequirementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubjectRequirementsTable> {
  $$SubjectRequirementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get weekMode =>
      $composableBuilder(column: $table.weekMode, builder: (column) => column);

  GeneratedColumn<int> get lessonCount => $composableBuilder(
    column: $table.lessonCount,
    builder: (column) => column,
  );

  $$SubjectsTableAnnotationComposer get subjectId {
    final $$SubjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GradeGroupsTableAnnotationComposer get gradeId {
    final $$GradeGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gradeId,
      referencedTable: $db.gradeGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.gradeGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ClassGroupsTableAnnotationComposer get classId {
    final $$ClassGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.classId,
      referencedTable: $db.classGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.classGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectRequirementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubjectRequirementsTable,
          SubjectRequirement,
          $$SubjectRequirementsTableFilterComposer,
          $$SubjectRequirementsTableOrderingComposer,
          $$SubjectRequirementsTableAnnotationComposer,
          $$SubjectRequirementsTableCreateCompanionBuilder,
          $$SubjectRequirementsTableUpdateCompanionBuilder,
          (SubjectRequirement, $$SubjectRequirementsTableReferences),
          SubjectRequirement,
          PrefetchHooks Function({bool subjectId, bool gradeId, bool classId})
        > {
  $$SubjectRequirementsTableTableManager(
    _$AppDatabase db,
    $SubjectRequirementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubjectRequirementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubjectRequirementsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SubjectRequirementsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> subjectId = const Value.absent(),
                Value<String> gradeId = const Value.absent(),
                Value<String?> classId = const Value.absent(),
                Value<String> weekMode = const Value.absent(),
                Value<int> lessonCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubjectRequirementsCompanion(
                id: id,
                subjectId: subjectId,
                gradeId: gradeId,
                classId: classId,
                weekMode: weekMode,
                lessonCount: lessonCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String subjectId,
                required String gradeId,
                Value<String?> classId = const Value.absent(),
                Value<String> weekMode = const Value.absent(),
                Value<int> lessonCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubjectRequirementsCompanion.insert(
                id: id,
                subjectId: subjectId,
                gradeId: gradeId,
                classId: classId,
                weekMode: weekMode,
                lessonCount: lessonCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SubjectRequirementsTable, SubjectRequirement>(
                    table,
                  ),
                  $$SubjectRequirementsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({subjectId = false, gradeId = false, classId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (subjectId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.subjectId,
                            referencedTable:
                                $$SubjectRequirementsTableReferences
                                    ._subjectIdTable(db),
                            referencedColumn:
                                $$SubjectRequirementsTableReferences
                                    ._subjectIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (gradeId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.gradeId,
                            referencedTable:
                                $$SubjectRequirementsTableReferences
                                    ._gradeIdTable(db),
                            referencedColumn:
                                $$SubjectRequirementsTableReferences
                                    ._gradeIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (classId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.classId,
                            referencedTable:
                                $$SubjectRequirementsTableReferences
                                    ._classIdTable(db),
                            referencedColumn:
                                $$SubjectRequirementsTableReferences
                                    ._classIdTable(db)
                                    .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$SubjectRequirementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubjectRequirementsTable,
      SubjectRequirement,
      $$SubjectRequirementsTableFilterComposer,
      $$SubjectRequirementsTableOrderingComposer,
      $$SubjectRequirementsTableAnnotationComposer,
      $$SubjectRequirementsTableCreateCompanionBuilder,
      $$SubjectRequirementsTableUpdateCompanionBuilder,
      (SubjectRequirement, $$SubjectRequirementsTableReferences),
      SubjectRequirement,
      PrefetchHooks Function({bool subjectId, bool gradeId, bool classId})
    >;
typedef $$SubjectPresetsTableCreateCompanionBuilder =
    SubjectPresetsCompanion Function({
      required String id,
      required String subjectId,
      required String scopeType,
      required String scopeId,
      required String stageId,
      required int weekday,
      required String periodTypeId,
      required int lessonIndex,
      Value<String> value,
      Value<int> rowid,
    });
typedef $$SubjectPresetsTableUpdateCompanionBuilder =
    SubjectPresetsCompanion Function({
      Value<String> id,
      Value<String> subjectId,
      Value<String> scopeType,
      Value<String> scopeId,
      Value<String> stageId,
      Value<int> weekday,
      Value<String> periodTypeId,
      Value<int> lessonIndex,
      Value<String> value,
      Value<int> rowid,
    });

final class $$SubjectPresetsTableReferences
    extends BaseReferences<_$AppDatabase, $SubjectPresetsTable, SubjectPreset> {
  $$SubjectPresetsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SubjectsTable _subjectIdTable(_$AppDatabase db) =>
      db.subjects.createAlias('subject_presets__subject_id__subjects__id');

  $$SubjectsTableProcessedTableManager get subjectId {
    final $_column = $_itemColumn<String>('subject_id')!;

    final manager = $$SubjectsTableTableManager(
      $_db,
      $_db.subjects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_subjectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SchoolStagesTable _stageIdTable(_$AppDatabase db) => db.schoolStages
      .createAlias('subject_presets__stage_id__school_stages__id');

  $$SchoolStagesTableProcessedTableManager get stageId {
    final $_column = $_itemColumn<String>('stage_id')!;

    final manager = $$SchoolStagesTableTableManager(
      $_db,
      $_db.schoolStages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_stageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $LessonPeriodTypesTable _periodTypeIdTable(_$AppDatabase db) => db
      .lessonPeriodTypes
      .createAlias('subject_presets__period_type_id__lesson_period_types__id');

  $$LessonPeriodTypesTableProcessedTableManager get periodTypeId {
    final $_column = $_itemColumn<String>('period_type_id')!;

    final manager = $$LessonPeriodTypesTableTableManager(
      $_db,
      $_db.lessonPeriodTypes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_periodTypeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SubjectPresetsTableFilterComposer
    extends Composer<_$AppDatabase, $SubjectPresetsTable> {
  $$SubjectPresetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeId => $composableBuilder(
    column: $table.scopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lessonIndex => $composableBuilder(
    column: $table.lessonIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  $$SubjectsTableFilterComposer get subjectId {
    final $$SubjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableFilterComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SchoolStagesTableFilterComposer get stageId {
    final $$SchoolStagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableFilterComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LessonPeriodTypesTableFilterComposer get periodTypeId {
    final $$LessonPeriodTypesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodTypeId,
      referencedTable: $db.lessonPeriodTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonPeriodTypesTableFilterComposer(
            $db: $db,
            $table: $db.lessonPeriodTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectPresetsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubjectPresetsTable> {
  $$SubjectPresetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeId => $composableBuilder(
    column: $table.scopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lessonIndex => $composableBuilder(
    column: $table.lessonIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  $$SubjectsTableOrderingComposer get subjectId {
    final $$SubjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableOrderingComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SchoolStagesTableOrderingComposer get stageId {
    final $$SchoolStagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableOrderingComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LessonPeriodTypesTableOrderingComposer get periodTypeId {
    final $$LessonPeriodTypesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodTypeId,
      referencedTable: $db.lessonPeriodTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LessonPeriodTypesTableOrderingComposer(
            $db: $db,
            $table: $db.lessonPeriodTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectPresetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubjectPresetsTable> {
  $$SubjectPresetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scopeType =>
      $composableBuilder(column: $table.scopeType, builder: (column) => column);

  GeneratedColumn<String> get scopeId =>
      $composableBuilder(column: $table.scopeId, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<int> get lessonIndex => $composableBuilder(
    column: $table.lessonIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  $$SubjectsTableAnnotationComposer get subjectId {
    final $$SubjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SchoolStagesTableAnnotationComposer get stageId {
    final $$SchoolStagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableAnnotationComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LessonPeriodTypesTableAnnotationComposer get periodTypeId {
    final $$LessonPeriodTypesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.periodTypeId,
          referencedTable: $db.lessonPeriodTypes,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LessonPeriodTypesTableAnnotationComposer(
                $db: $db,
                $table: $db.lessonPeriodTypes,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$SubjectPresetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubjectPresetsTable,
          SubjectPreset,
          $$SubjectPresetsTableFilterComposer,
          $$SubjectPresetsTableOrderingComposer,
          $$SubjectPresetsTableAnnotationComposer,
          $$SubjectPresetsTableCreateCompanionBuilder,
          $$SubjectPresetsTableUpdateCompanionBuilder,
          (SubjectPreset, $$SubjectPresetsTableReferences),
          SubjectPreset,
          PrefetchHooks Function({
            bool subjectId,
            bool stageId,
            bool periodTypeId,
          })
        > {
  $$SubjectPresetsTableTableManager(
    _$AppDatabase db,
    $SubjectPresetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubjectPresetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubjectPresetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubjectPresetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> subjectId = const Value.absent(),
                Value<String> scopeType = const Value.absent(),
                Value<String> scopeId = const Value.absent(),
                Value<String> stageId = const Value.absent(),
                Value<int> weekday = const Value.absent(),
                Value<String> periodTypeId = const Value.absent(),
                Value<int> lessonIndex = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubjectPresetsCompanion(
                id: id,
                subjectId: subjectId,
                scopeType: scopeType,
                scopeId: scopeId,
                stageId: stageId,
                weekday: weekday,
                periodTypeId: periodTypeId,
                lessonIndex: lessonIndex,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String subjectId,
                required String scopeType,
                required String scopeId,
                required String stageId,
                required int weekday,
                required String periodTypeId,
                required int lessonIndex,
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubjectPresetsCompanion.insert(
                id: id,
                subjectId: subjectId,
                scopeType: scopeType,
                scopeId: scopeId,
                stageId: stageId,
                weekday: weekday,
                periodTypeId: periodTypeId,
                lessonIndex: lessonIndex,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SubjectPresetsTable, SubjectPreset>(table),
                  $$SubjectPresetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({subjectId = false, stageId = false, periodTypeId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (subjectId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.subjectId,
                            referencedTable: $$SubjectPresetsTableReferences
                                ._subjectIdTable(db),
                            referencedColumn: $$SubjectPresetsTableReferences
                                ._subjectIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (stageId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.stageId,
                            referencedTable: $$SubjectPresetsTableReferences
                                ._stageIdTable(db),
                            referencedColumn: $$SubjectPresetsTableReferences
                                ._stageIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (periodTypeId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.periodTypeId,
                            referencedTable: $$SubjectPresetsTableReferences
                                ._periodTypeIdTable(db),
                            referencedColumn: $$SubjectPresetsTableReferences
                                ._periodTypeIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$SubjectPresetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubjectPresetsTable,
      SubjectPreset,
      $$SubjectPresetsTableFilterComposer,
      $$SubjectPresetsTableOrderingComposer,
      $$SubjectPresetsTableAnnotationComposer,
      $$SubjectPresetsTableCreateCompanionBuilder,
      $$SubjectPresetsTableUpdateCompanionBuilder,
      (SubjectPreset, $$SubjectPresetsTableReferences),
      SubjectPreset,
      PrefetchHooks Function({bool subjectId, bool stageId, bool periodTypeId})
    >;
typedef $$SubjectPairingsTableCreateCompanionBuilder =
    SubjectPairingsCompanion Function({
      required String id,
      required String classId,
      required String oddSubjectId,
      required String evenSubjectId,
      Value<int> rowid,
    });
typedef $$SubjectPairingsTableUpdateCompanionBuilder =
    SubjectPairingsCompanion Function({
      Value<String> id,
      Value<String> classId,
      Value<String> oddSubjectId,
      Value<String> evenSubjectId,
      Value<int> rowid,
    });

final class $$SubjectPairingsTableReferences
    extends
        BaseReferences<_$AppDatabase, $SubjectPairingsTable, SubjectPairing> {
  $$SubjectPairingsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ClassGroupsTable _classIdTable(_$AppDatabase db) => db.classGroups
      .createAlias('subject_pairings__class_id__class_groups__id');

  $$ClassGroupsTableProcessedTableManager get classId {
    final $_column = $_itemColumn<String>('class_id')!;

    final manager = $$ClassGroupsTableTableManager(
      $_db,
      $_db.classGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_classIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SubjectsTable _oddSubjectIdTable(_$AppDatabase db) =>
      db.subjects.createAlias('subject_pairings__odd_subject_id__subjects__id');

  $$SubjectsTableProcessedTableManager get oddSubjectId {
    final $_column = $_itemColumn<String>('odd_subject_id')!;

    final manager = $$SubjectsTableTableManager(
      $_db,
      $_db.subjects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_oddSubjectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SubjectsTable _evenSubjectIdTable(_$AppDatabase db) => db.subjects
      .createAlias('subject_pairings__even_subject_id__subjects__id');

  $$SubjectsTableProcessedTableManager get evenSubjectId {
    final $_column = $_itemColumn<String>('even_subject_id')!;

    final manager = $$SubjectsTableTableManager(
      $_db,
      $_db.subjects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_evenSubjectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SubjectPairingsTableFilterComposer
    extends Composer<_$AppDatabase, $SubjectPairingsTable> {
  $$SubjectPairingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  $$ClassGroupsTableFilterComposer get classId {
    final $$ClassGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.classId,
      referencedTable: $db.classGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassGroupsTableFilterComposer(
            $db: $db,
            $table: $db.classGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SubjectsTableFilterComposer get oddSubjectId {
    final $$SubjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.oddSubjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableFilterComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SubjectsTableFilterComposer get evenSubjectId {
    final $$SubjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.evenSubjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableFilterComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectPairingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubjectPairingsTable> {
  $$SubjectPairingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  $$ClassGroupsTableOrderingComposer get classId {
    final $$ClassGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.classId,
      referencedTable: $db.classGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.classGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SubjectsTableOrderingComposer get oddSubjectId {
    final $$SubjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.oddSubjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableOrderingComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SubjectsTableOrderingComposer get evenSubjectId {
    final $$SubjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.evenSubjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableOrderingComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectPairingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubjectPairingsTable> {
  $$SubjectPairingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  $$ClassGroupsTableAnnotationComposer get classId {
    final $$ClassGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.classId,
      referencedTable: $db.classGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.classGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SubjectsTableAnnotationComposer get oddSubjectId {
    final $$SubjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.oddSubjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SubjectsTableAnnotationComposer get evenSubjectId {
    final $$SubjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.evenSubjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectPairingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubjectPairingsTable,
          SubjectPairing,
          $$SubjectPairingsTableFilterComposer,
          $$SubjectPairingsTableOrderingComposer,
          $$SubjectPairingsTableAnnotationComposer,
          $$SubjectPairingsTableCreateCompanionBuilder,
          $$SubjectPairingsTableUpdateCompanionBuilder,
          (SubjectPairing, $$SubjectPairingsTableReferences),
          SubjectPairing,
          PrefetchHooks Function({
            bool classId,
            bool oddSubjectId,
            bool evenSubjectId,
          })
        > {
  $$SubjectPairingsTableTableManager(
    _$AppDatabase db,
    $SubjectPairingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubjectPairingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubjectPairingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubjectPairingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> classId = const Value.absent(),
                Value<String> oddSubjectId = const Value.absent(),
                Value<String> evenSubjectId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubjectPairingsCompanion(
                id: id,
                classId: classId,
                oddSubjectId: oddSubjectId,
                evenSubjectId: evenSubjectId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String classId,
                required String oddSubjectId,
                required String evenSubjectId,
                Value<int> rowid = const Value.absent(),
              }) => SubjectPairingsCompanion.insert(
                id: id,
                classId: classId,
                oddSubjectId: oddSubjectId,
                evenSubjectId: evenSubjectId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SubjectPairingsTable, SubjectPairing>(table),
                  $$SubjectPairingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({classId = false, oddSubjectId = false, evenSubjectId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (classId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.classId,
                            referencedTable: $$SubjectPairingsTableReferences
                                ._classIdTable(db),
                            referencedColumn: $$SubjectPairingsTableReferences
                                ._classIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (oddSubjectId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.oddSubjectId,
                            referencedTable: $$SubjectPairingsTableReferences
                                ._oddSubjectIdTable(db),
                            referencedColumn: $$SubjectPairingsTableReferences
                                ._oddSubjectIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (evenSubjectId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.evenSubjectId,
                            referencedTable: $$SubjectPairingsTableReferences
                                ._evenSubjectIdTable(db),
                            referencedColumn: $$SubjectPairingsTableReferences
                                ._evenSubjectIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$SubjectPairingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubjectPairingsTable,
      SubjectPairing,
      $$SubjectPairingsTableFilterComposer,
      $$SubjectPairingsTableOrderingComposer,
      $$SubjectPairingsTableAnnotationComposer,
      $$SubjectPairingsTableCreateCompanionBuilder,
      $$SubjectPairingsTableUpdateCompanionBuilder,
      (SubjectPairing, $$SubjectPairingsTableReferences),
      SubjectPairing,
      PrefetchHooks Function({
        bool classId,
        bool oddSubjectId,
        bool evenSubjectId,
      })
    >;
typedef $$SubjectLessonConstraintsTableCreateCompanionBuilder =
    SubjectLessonConstraintsCompanion Function({
      required String id,
      required String subjectId,
      required String scopeType,
      required String scopeId,
      required String stageId,
      Value<int?> weekday,
      Value<int?> minimumDailyLessons,
      Value<int?> maximumDailyLessons,
      Value<int?> minimumDailyConsecutivePairs,
      Value<int?> maximumDailyConsecutivePairs,
      Value<int?> minimumWeeklyConsecutivePairs,
      Value<int?> maximumWeeklyConsecutivePairs,
      Value<int> rowid,
    });
typedef $$SubjectLessonConstraintsTableUpdateCompanionBuilder =
    SubjectLessonConstraintsCompanion Function({
      Value<String> id,
      Value<String> subjectId,
      Value<String> scopeType,
      Value<String> scopeId,
      Value<String> stageId,
      Value<int?> weekday,
      Value<int?> minimumDailyLessons,
      Value<int?> maximumDailyLessons,
      Value<int?> minimumDailyConsecutivePairs,
      Value<int?> maximumDailyConsecutivePairs,
      Value<int?> minimumWeeklyConsecutivePairs,
      Value<int?> maximumWeeklyConsecutivePairs,
      Value<int> rowid,
    });

final class $$SubjectLessonConstraintsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $SubjectLessonConstraintsTable,
          SubjectLessonConstraint
        > {
  $$SubjectLessonConstraintsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SubjectsTable _subjectIdTable(_$AppDatabase db) => db.subjects
      .createAlias('subject_lesson_constraints__subject_id__subjects__id');

  $$SubjectsTableProcessedTableManager get subjectId {
    final $_column = $_itemColumn<String>('subject_id')!;

    final manager = $$SubjectsTableTableManager(
      $_db,
      $_db.subjects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_subjectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SchoolStagesTable _stageIdTable(_$AppDatabase db) => db.schoolStages
      .createAlias('subject_lesson_constraints__stage_id__school_stages__id');

  $$SchoolStagesTableProcessedTableManager get stageId {
    final $_column = $_itemColumn<String>('stage_id')!;

    final manager = $$SchoolStagesTableTableManager(
      $_db,
      $_db.schoolStages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_stageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SubjectLessonConstraintsTableFilterComposer
    extends Composer<_$AppDatabase, $SubjectLessonConstraintsTable> {
  $$SubjectLessonConstraintsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeId => $composableBuilder(
    column: $table.scopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minimumDailyLessons => $composableBuilder(
    column: $table.minimumDailyLessons,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maximumDailyLessons => $composableBuilder(
    column: $table.maximumDailyLessons,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minimumDailyConsecutivePairs => $composableBuilder(
    column: $table.minimumDailyConsecutivePairs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maximumDailyConsecutivePairs => $composableBuilder(
    column: $table.maximumDailyConsecutivePairs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minimumWeeklyConsecutivePairs => $composableBuilder(
    column: $table.minimumWeeklyConsecutivePairs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maximumWeeklyConsecutivePairs => $composableBuilder(
    column: $table.maximumWeeklyConsecutivePairs,
    builder: (column) => ColumnFilters(column),
  );

  $$SubjectsTableFilterComposer get subjectId {
    final $$SubjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableFilterComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SchoolStagesTableFilterComposer get stageId {
    final $$SchoolStagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableFilterComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectLessonConstraintsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubjectLessonConstraintsTable> {
  $$SubjectLessonConstraintsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeId => $composableBuilder(
    column: $table.scopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minimumDailyLessons => $composableBuilder(
    column: $table.minimumDailyLessons,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maximumDailyLessons => $composableBuilder(
    column: $table.maximumDailyLessons,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minimumDailyConsecutivePairs => $composableBuilder(
    column: $table.minimumDailyConsecutivePairs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maximumDailyConsecutivePairs => $composableBuilder(
    column: $table.maximumDailyConsecutivePairs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minimumWeeklyConsecutivePairs => $composableBuilder(
    column: $table.minimumWeeklyConsecutivePairs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maximumWeeklyConsecutivePairs => $composableBuilder(
    column: $table.maximumWeeklyConsecutivePairs,
    builder: (column) => ColumnOrderings(column),
  );

  $$SubjectsTableOrderingComposer get subjectId {
    final $$SubjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableOrderingComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SchoolStagesTableOrderingComposer get stageId {
    final $$SchoolStagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableOrderingComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectLessonConstraintsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubjectLessonConstraintsTable> {
  $$SubjectLessonConstraintsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scopeType =>
      $composableBuilder(column: $table.scopeType, builder: (column) => column);

  GeneratedColumn<String> get scopeId =>
      $composableBuilder(column: $table.scopeId, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<int> get minimumDailyLessons => $composableBuilder(
    column: $table.minimumDailyLessons,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maximumDailyLessons => $composableBuilder(
    column: $table.maximumDailyLessons,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minimumDailyConsecutivePairs => $composableBuilder(
    column: $table.minimumDailyConsecutivePairs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maximumDailyConsecutivePairs => $composableBuilder(
    column: $table.maximumDailyConsecutivePairs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minimumWeeklyConsecutivePairs => $composableBuilder(
    column: $table.minimumWeeklyConsecutivePairs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maximumWeeklyConsecutivePairs => $composableBuilder(
    column: $table.maximumWeeklyConsecutivePairs,
    builder: (column) => column,
  );

  $$SubjectsTableAnnotationComposer get subjectId {
    final $$SubjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.subjectId,
      referencedTable: $db.subjects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.subjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SchoolStagesTableAnnotationComposer get stageId {
    final $$SchoolStagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.stageId,
      referencedTable: $db.schoolStages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchoolStagesTableAnnotationComposer(
            $db: $db,
            $table: $db.schoolStages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubjectLessonConstraintsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubjectLessonConstraintsTable,
          SubjectLessonConstraint,
          $$SubjectLessonConstraintsTableFilterComposer,
          $$SubjectLessonConstraintsTableOrderingComposer,
          $$SubjectLessonConstraintsTableAnnotationComposer,
          $$SubjectLessonConstraintsTableCreateCompanionBuilder,
          $$SubjectLessonConstraintsTableUpdateCompanionBuilder,
          (SubjectLessonConstraint, $$SubjectLessonConstraintsTableReferences),
          SubjectLessonConstraint,
          PrefetchHooks Function({bool subjectId, bool stageId})
        > {
  $$SubjectLessonConstraintsTableTableManager(
    _$AppDatabase db,
    $SubjectLessonConstraintsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubjectLessonConstraintsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SubjectLessonConstraintsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SubjectLessonConstraintsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> subjectId = const Value.absent(),
                Value<String> scopeType = const Value.absent(),
                Value<String> scopeId = const Value.absent(),
                Value<String> stageId = const Value.absent(),
                Value<int?> weekday = const Value.absent(),
                Value<int?> minimumDailyLessons = const Value.absent(),
                Value<int?> maximumDailyLessons = const Value.absent(),
                Value<int?> minimumDailyConsecutivePairs = const Value.absent(),
                Value<int?> maximumDailyConsecutivePairs = const Value.absent(),
                Value<int?> minimumWeeklyConsecutivePairs =
                    const Value.absent(),
                Value<int?> maximumWeeklyConsecutivePairs =
                    const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubjectLessonConstraintsCompanion(
                id: id,
                subjectId: subjectId,
                scopeType: scopeType,
                scopeId: scopeId,
                stageId: stageId,
                weekday: weekday,
                minimumDailyLessons: minimumDailyLessons,
                maximumDailyLessons: maximumDailyLessons,
                minimumDailyConsecutivePairs: minimumDailyConsecutivePairs,
                maximumDailyConsecutivePairs: maximumDailyConsecutivePairs,
                minimumWeeklyConsecutivePairs: minimumWeeklyConsecutivePairs,
                maximumWeeklyConsecutivePairs: maximumWeeklyConsecutivePairs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String subjectId,
                required String scopeType,
                required String scopeId,
                required String stageId,
                Value<int?> weekday = const Value.absent(),
                Value<int?> minimumDailyLessons = const Value.absent(),
                Value<int?> maximumDailyLessons = const Value.absent(),
                Value<int?> minimumDailyConsecutivePairs = const Value.absent(),
                Value<int?> maximumDailyConsecutivePairs = const Value.absent(),
                Value<int?> minimumWeeklyConsecutivePairs =
                    const Value.absent(),
                Value<int?> maximumWeeklyConsecutivePairs =
                    const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubjectLessonConstraintsCompanion.insert(
                id: id,
                subjectId: subjectId,
                scopeType: scopeType,
                scopeId: scopeId,
                stageId: stageId,
                weekday: weekday,
                minimumDailyLessons: minimumDailyLessons,
                maximumDailyLessons: maximumDailyLessons,
                minimumDailyConsecutivePairs: minimumDailyConsecutivePairs,
                maximumDailyConsecutivePairs: maximumDailyConsecutivePairs,
                minimumWeeklyConsecutivePairs: minimumWeeklyConsecutivePairs,
                maximumWeeklyConsecutivePairs: maximumWeeklyConsecutivePairs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $SubjectLessonConstraintsTable,
                    SubjectLessonConstraint
                  >(table),
                  $$SubjectLessonConstraintsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({subjectId = false, stageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (subjectId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.subjectId,
                        referencedTable:
                            $$SubjectLessonConstraintsTableReferences
                                ._subjectIdTable(db),
                        referencedColumn:
                            $$SubjectLessonConstraintsTableReferences
                                ._subjectIdTable(db)
                                .id,
                      ) as T;
                    }
                    if (stageId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.stageId,
                        referencedTable:
                            $$SubjectLessonConstraintsTableReferences
                                ._stageIdTable(db),
                        referencedColumn:
                            $$SubjectLessonConstraintsTableReferences
                                ._stageIdTable(db)
                                .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SubjectLessonConstraintsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubjectLessonConstraintsTable,
      SubjectLessonConstraint,
      $$SubjectLessonConstraintsTableFilterComposer,
      $$SubjectLessonConstraintsTableOrderingComposer,
      $$SubjectLessonConstraintsTableAnnotationComposer,
      $$SubjectLessonConstraintsTableCreateCompanionBuilder,
      $$SubjectLessonConstraintsTableUpdateCompanionBuilder,
      (SubjectLessonConstraint, $$SubjectLessonConstraintsTableReferences),
      SubjectLessonConstraint,
      PrefetchHooks Function({bool subjectId, bool stageId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AcademicTermsTableTableManager get academicTerms =>
      $$AcademicTermsTableTableManager(_db, _db.academicTerms);
  $$SchoolStagesTableTableManager get schoolStages =>
      $$SchoolStagesTableTableManager(_db, _db.schoolStages);
  $$GradeGroupsTableTableManager get gradeGroups =>
      $$GradeGroupsTableTableManager(_db, _db.gradeGroups);
  $$ClassGroupsTableTableManager get classGroups =>
      $$ClassGroupsTableTableManager(_db, _db.classGroups);
  $$StageTeachingDaysTableTableManager get stageTeachingDays =>
      $$StageTeachingDaysTableTableManager(_db, _db.stageTeachingDays);
  $$LessonPeriodTypesTableTableManager get lessonPeriodTypes =>
      $$LessonPeriodTypesTableTableManager(_db, _db.lessonPeriodTypes);
  $$DailyLessonOverridesTableTableManager get dailyLessonOverrides =>
      $$DailyLessonOverridesTableTableManager(_db, _db.dailyLessonOverrides);
  $$LessonTimesTableTableManager get lessonTimes =>
      $$LessonTimesTableTableManager(_db, _db.lessonTimes);
  $$CalendarExceptionsTableTableManager get calendarExceptions =>
      $$CalendarExceptionsTableTableManager(_db, _db.calendarExceptions);
  $$FreeSlotsTableTableManager get freeSlots =>
      $$FreeSlotsTableTableManager(_db, _db.freeSlots);
  $$CommonPeriodsTableTableManager get commonPeriods =>
      $$CommonPeriodsTableTableManager(_db, _db.commonPeriods);
  $$SubjectsTableTableManager get subjects =>
      $$SubjectsTableTableManager(_db, _db.subjects);
  $$SubjectRequirementsTableTableManager get subjectRequirements =>
      $$SubjectRequirementsTableTableManager(_db, _db.subjectRequirements);
  $$SubjectPresetsTableTableManager get subjectPresets =>
      $$SubjectPresetsTableTableManager(_db, _db.subjectPresets);
  $$SubjectPairingsTableTableManager get subjectPairings =>
      $$SubjectPairingsTableTableManager(_db, _db.subjectPairings);
  $$SubjectLessonConstraintsTableTableManager get subjectLessonConstraints =>
      $$SubjectLessonConstraintsTableTableManager(
        _db,
        _db.subjectLessonConstraints,
      );
}
