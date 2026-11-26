import type {
  ClassGroup,
  GradeGroup,
  SchoolStage,
  ScopeType,
  Subject,
  SubjectRoomAssignment,
} from '@/domain/models';

export function resolveSubjectRoomAssignment(params: {
  assignments: SubjectRoomAssignment[];
  subjectId: string;
  termId: string;
  stageId: string;
  scope: ScopeType;
  scopeId: string;
  parentGradeId?: string | null;
}): SubjectRoomAssignment | null {
  const {
    assignments,
    subjectId,
    termId,
    stageId,
    scope,
    scopeId,
    parentGradeId,
  } = params;
  if (scope === 'school') {
    throw new Error('公共教室设置不支持全校范围');
  }
  const candidates: Array<{ scope: ScopeType; id: string }> = [
    { scope, id: scopeId },
  ];
  if (scope === 'class' && parentGradeId) {
    candidates.push({ scope: 'grade', id: parentGradeId });
  }
  if (scope !== 'stage') {
    candidates.push({ scope: 'stage', id: stageId });
  }
  for (const candidate of candidates) {
    for (const row of assignments) {
      if (
        row.subjectId === subjectId &&
        row.termId === termId &&
        row.stageId === stageId &&
        row.scopeType === candidate.scope &&
        row.scopeId === candidate.id
      ) {
        return row;
      }
    }
  }
  return null;
}

export class PublicRoomTermData {
  readonly termId: string;
  readonly stages: SchoolStage[];
  readonly grades: GradeGroup[];
  readonly classes: ClassGroup[];
  readonly assignments: SubjectRoomAssignment[];
  readonly subjects: Subject[];
  private _sharedRoomIds: Set<string> | null = null;

  constructor(params: {
    termId: string;
    stages: SchoolStage[];
    grades: GradeGroup[];
    classes: ClassGroup[];
    assignments: SubjectRoomAssignment[];
    subjects: Subject[];
  }) {
    this.termId = params.termId;
    this.stages = params.stages;
    this.grades = params.grades;
    this.classes = params.classes;
    this.assignments = params.assignments;
    this.subjects = params.subjects;
  }

  stageIdForClass(schoolClass: ClassGroup): string | undefined {
    return this.grades.find((g) => g.id === schoolClass.gradeId)?.stageId;
  }

  bindingLabel(row: SubjectRoomAssignment): string {
    const stage = this.stages.find((s) => s.id === row.stageId);
    const subject = this.subjects.find((s) => s.id === row.subjectId);
    const parts: string[] = [stage?.name ?? '已移除学段'];
    switch (row.scopeType) {
      case 'stage':
        parts.push('全学段');
        break;
      case 'grade':
        parts.push(
          this.grades.find((g) => g.id === row.scopeId)?.name ?? '已移除年级'
        );
        break;
      case 'class': {
        const schoolClass = this.classes.find((c) => c.id === row.scopeId);
        parts.push(
          this.grades.find((g) => g.id === schoolClass?.gradeId)?.name ??
            '已移除年级'
        );
        parts.push(schoolClass?.name ?? '已移除班级');
        break;
      }
      case 'school':
      default:
        parts.push('未知范围');
        break;
    }
    return `${subject?.name ?? '已移除科目'} · ${parts.join(' / ')}`;
  }

  isSharedAcrossStages(roomId: string): boolean {
    if (!this._sharedRoomIds) {
      this._sharedRoomIds = this.resolveSharedRooms();
    }
    return this._sharedRoomIds.has(roomId);
  }

  private resolveSharedRooms(): Set<string> {
    const byStageAndSubject = new Map<
      string,
      Map<string, SubjectRoomAssignment[]>
    >();
    for (const assignment of this.assignments) {
      let subjectMap = byStageAndSubject.get(assignment.stageId);
      if (!subjectMap) {
        subjectMap = new Map();
        byStageAndSubject.set(assignment.stageId, subjectMap);
      }
      const list = subjectMap.get(assignment.subjectId) ?? [];
      list.push(assignment);
      subjectMap.set(assignment.subjectId, list);
    }

    const usedStagesByRoom = new Map<string, Set<string>>();
    for (const schoolClass of this.classes) {
      const stageId = this.stageIdForClass(schoolClass);
      if (!stageId) continue;
      const subjectRules = byStageAndSubject.get(stageId);
      if (!subjectRules) continue;
      for (const [subjectId, rows] of subjectRules.entries()) {
        const effective = resolveSubjectRoomAssignment({
          assignments: rows,
          subjectId,
          termId: this.termId,
          stageId,
          scope: 'class',
          scopeId: schoolClass.id,
          parentGradeId: schoolClass.gradeId,
        });
        const roomId = effective?.roomId;
        if (roomId) {
          let stagesSet = usedStagesByRoom.get(roomId);
          if (!stagesSet) {
            stagesSet = new Set();
            usedStagesByRoom.set(roomId, stagesSet);
          }
          stagesSet.add(stageId);
        }
      }
    }

    const shared = new Set<string>();
    for (const [roomId, stagesSet] of usedStagesByRoom.entries()) {
      if (stagesSet.size >= 2) {
        shared.add(roomId);
      }
    }
    return shared;
  }
}

function roomScopeLabel(
  row: SubjectRoomAssignment,
  data: PublicRoomTermData
): string | null {
  switch (row.scopeType) {
    case 'stage':
    case 'school':
      return null;
    case 'grade':
      return data.grades.find((g) => g.id === row.scopeId)?.name ?? null;
    case 'class':
      return data.classes.find((c) => c.id === row.scopeId)?.name ?? null;
  }
}

export function getRoomAssociations(
  roomId: string,
  data: PublicRoomTermData | null
): Array<{ label: string; tooltip: string }> {
  if (!data) return [];
  const grouped = new Map<string, SubjectRoomAssignment[]>();
  for (const row of data.assignments) {
    if (row.roomId !== roomId) continue;
    const list = grouped.get(row.subjectId) ?? [];
    list.push(row);
    grouped.set(row.subjectId, list);
  }

  const labels: Array<{ label: string; tooltip: string }> = [];
  for (const [subjectId, rows] of grouped.entries()) {
    const subject = data.subjects.find((item) => item.id === subjectId);
    const stageNames = Array.from(
      new Set(
        rows.map(
          (row) =>
            data.stages.find((stage) => stage.id === row.stageId)?.name ??
            '已移除学段'
        )
      )
    );
    const scopeNames = Array.from(
      new Set(
        rows
          .map((row) => roomScopeLabel(row, data))
          .filter((name): name is string => Boolean(name))
      )
    );
    const suffix =
      stageNames.length > 1
        ? `（${stageNames.join('+')}）`
        : scopeNames.length === 0
        ? ''
        : `（${scopeNames.join('、')}）`;
    const tooltip = Array.from(
      new Set(rows.map((r) => data.bindingLabel(r)))
    ).join('\n');
    labels.push({
      label: `${subject?.name ?? '已移除科目'}${suffix}`,
      tooltip,
    });
  }
  return labels;
}
