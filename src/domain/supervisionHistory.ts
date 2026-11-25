import type { SupervisionDraft } from './supervision.ts';

interface DutyEdit {
  label: string;
  before: SupervisionDraft;
  after: SupervisionDraft;
}

function deepCloneDraft(draft: SupervisionDraft): SupervisionDraft {
  return JSON.parse(JSON.stringify(draft)) as SupervisionDraft;
}

function canonicalContent(draft: SupervisionDraft): string {
  const copy = { ...draft, revision: 0 };
  return JSON.stringify(copy);
}

export class SupervisionDraftHistory {
  private currentDraft: SupervisionDraft;
  private currentContent: string;
  private savedContent: string;
  private undoStack: DutyEdit[] = [];
  private redoStack: DutyEdit[] = [];
  private readonly limit = 100;

  constructor(initial: SupervisionDraft) {
    this.currentDraft = deepCloneDraft(initial);
    this.currentContent = canonicalContent(initial);
    this.savedContent = this.currentContent;
  }

  get current(): SupervisionDraft {
    return this.currentDraft;
  }

  get hasChanges(): boolean {
    return this.currentContent !== this.savedContent;
  }

  get canUndo(): boolean {
    return this.undoStack.length > 0;
  }

  get canRedo(): boolean {
    return this.redoStack.length > 0;
  }

  get undoLabel(): string | undefined {
    return this.undoStack[this.undoStack.length - 1]?.label;
  }

  get redoLabel(): string | undefined {
    return this.redoStack[this.redoStack.length - 1]?.label;
  }

  clone(): SupervisionDraftHistory {
    const copy = new SupervisionDraftHistory(this.currentDraft);
    copy.currentContent = this.currentContent;
    copy.savedContent = this.savedContent;
    copy.undoStack = this.undoStack.map((edit) => ({
      label: edit.label,
      before: deepCloneDraft(edit.before),
      after: deepCloneDraft(edit.after),
    }));
    copy.redoStack = this.redoStack.map((edit) => ({
      label: edit.label,
      before: deepCloneDraft(edit.before),
      after: deepCloneDraft(edit.after),
    }));
    return copy;
  }

  isCurrent(draft: SupervisionDraft): boolean {
    return (
      draft.revision === this.currentDraft.revision &&
      canonicalContent(draft) === this.currentContent
    );
  }

  replace(next: SupervisionDraft, label: string): boolean {
    const nextContent = canonicalContent(next);
    if (nextContent === this.currentContent) {
      return false;
    }
    this.undoStack.push({
      label,
      before: deepCloneDraft(this.currentDraft),
      after: deepCloneDraft(next),
    });
    if (this.undoStack.length > this.limit) {
      this.undoStack.shift();
    }
    this.redoStack = [];
    this.currentDraft = { ...next, revision: this.currentDraft.revision };
    this.currentContent = nextContent;
    return true;
  }

  undo(): SupervisionDraft | null {
    if (this.undoStack.length === 0) return null;
    const edit = this.undoStack.pop()!;
    this.redoStack.push(edit);
    this.currentDraft = {
      ...deepCloneDraft(edit.before),
      revision: this.currentDraft.revision,
    };
    this.currentContent = canonicalContent(this.currentDraft);
    return this.currentDraft;
  }

  redo(): SupervisionDraft | null {
    if (this.redoStack.length === 0) return null;
    const edit = this.redoStack.pop()!;
    this.undoStack.push(edit);
    this.currentDraft = {
      ...deepCloneDraft(edit.after),
      revision: this.currentDraft.revision,
    };
    this.currentContent = canonicalContent(this.currentDraft);
    return this.currentDraft;
  }

  markSaved(saved: SupervisionDraft): void {
    const savedContent = canonicalContent(saved);
    this.savedContent = savedContent;
    if (this.currentContent === savedContent) {
      this.currentDraft = deepCloneDraft(saved);
      this.currentContent = savedContent;
    } else {
      this.currentDraft = { ...this.currentDraft, revision: saved.revision };
    }
  }

  reset(draft: SupervisionDraft): void {
    this.currentDraft = deepCloneDraft(draft);
    this.currentContent = canonicalContent(draft);
    this.savedContent = this.currentContent;
    this.undoStack = [];
    this.redoStack = [];
  }
}
