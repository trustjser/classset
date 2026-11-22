import React, { useEffect, useMemo, useReducer, useState } from 'react';
import {
  AlertTriangle,
  ArrowDown,
  ArrowUp,
  Check,
  Plus,
  RotateCcw,
  Wand2,
  X,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import {
  normalizeNumericValue,
  numericInputDraftReducer,
  parseNumericDraft,
} from '@/lib/numberInput';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import {
  ClassGroup,
  GradeGroup,
  SchoolStage,
} from '@/domain/models';
import { formatRoutineSummary } from '@/domain/routineUtils';
import { useAppStore } from '@/store/useAppStore';
import {
  CLASS_BATCH_TEMPLATES,
  generateClassNamesForGrade,
  generateGradeNames,
  GRADE_NAMING_TEMPLATES,
  GradeNamingMode,
  STAGE_PRESETS,
} from './gradeNameTemplates';

/**
 * 学段强调色：严格对齐 AppTheme.stageAccent（按学段序号 晴空蓝 / 鸢尾紫 / 琥珀色 轮换）
 */
function getStageAccentVars(index: number) {
  const mod = index % 3;
  if (mod === 0) {
    return {
      dotColor: 'var(--color-accent)',
      textColor: 'var(--color-accent)',
      tintBg: 'var(--color-selection)',
      borderColor: 'color-mix(in srgb, var(--color-accent) 34%, var(--color-surface))',
    };
  }
  if (mod === 1) {
    return {
      dotColor: 'var(--color-purple)',
      textColor: 'var(--color-purple)',
      tintBg: 'color-mix(in srgb, var(--color-purple) 12%, var(--color-surface))',
      borderColor: 'color-mix(in srgb, var(--color-purple) 34%, var(--color-surface))',
    };
  }
  return {
    dotColor: 'var(--color-warning)',
    textColor: 'var(--color-warning)',
    tintBg: 'var(--color-warning-surface)',
    borderColor: 'color-mix(in srgb, var(--color-warning) 34%, var(--color-surface))',
  };
}

export const ClassesPage: React.FC = () => {
  const {
    activeTermId,
    stages,
    grades,
    classes,
    routinesByStage,
    lastClassFillUndo,
    addOrUpdateStage,
    removeStage,
    addOrUpdateGrades,
    removeGrade,
    addOrUpdateClasses,
    removeClass,
    applyBatchClassFill,
    undoBatchClassFill,
  } = useAppStore();

  // 行内编辑班级状态
  const [editingClassId, setEditingClassId] = useState<string | null>(null);
  const [editingClassName, setEditingClassName] = useState('');
  const [inlineError, setInlineError] = useState<string | null>(null);

  // 顶部反馈通知条
  const [bannerNotice, setBannerNotice] = useState<string | null>(null);
  const [reorderError, setReorderError] = useState<string | null>(null);

  // 弹窗状态
  const [stageModalOpen, setStageModalOpen] = useState(false);
  const [editingStage, setEditingStage] = useState<SchoolStage | null>(null);

  const [addGradesOpen, setAddGradesOpen] = useState(false);
  const [editGradeTarget, setEditGradeTarget] = useState<GradeGroup | null>(null);
  const [deleteGradeTarget, setDeleteGradeTarget] = useState<GradeGroup | null>(null);

  const [addClassGradeTarget, setAddClassGradeTarget] = useState<GradeGroup | null>(null);
  const [batchFillOpen, setBatchFillOpen] = useState(false);

  const [deleteClassTarget, setDeleteClassTarget] = useState<ClassGroup | null>(null);
  const [deleteStageTarget, setDeleteStageTarget] = useState<SchoolStage | null>(null);

  const gradesByStage = useMemo(() => {
    const map = new Map<string, GradeGroup[]>();
    for (const st of stages) map.set(st.id, []);
    for (const gr of grades) {
      const list = map.get(gr.stageId) ?? [];
      list.push(gr);
      map.set(gr.stageId, list);
    }
    return map;
  }, [stages, grades]);

  const classesByGrade = useMemo(() => {
    const map = new Map<string, ClassGroup[]>();
    for (const gr of grades) map.set(gr.id, []);
    for (const cls of classes) {
      const list = map.get(cls.gradeId) ?? [];
      list.push(cls);
      map.set(cls.gradeId, list);
    }
    return map;
  }, [grades, classes]);

  const tableRows = useMemo(() => {
    const rows: Array<{
      stage: SchoolStage;
      stageIndex: number;
      grade: GradeGroup;
      gradeIndexInStage: number;
      stageGradeCount: number;
    }> = [];
    stages.forEach((st, stIdx) => {
      const gList = gradesByStage.get(st.id) ?? [];
      gList.forEach((gr, gIdx) => {
        rows.push({
          stage: st,
          stageIndex: stIdx,
          grade: gr,
          gradeIndexInStage: gIdx,
          stageGradeCount: gList.length,
        });
      });
    });
    return rows;
  }, [stages, gradesByStage]);

  // 年级在所属学段内上下移动排序
  const handleMoveGrade = async (stageId: string, gradeId: string, delta: -1 | 1) => {
    const list = [...(gradesByStage.get(stageId) ?? [])];
    const idx = list.findIndex((g) => g.id === gradeId);
    const targetIdx = idx + delta;
    if (idx < 0 || targetIdx < 0 || targetIdx >= list.length) return;
    const tempOrder = list[idx].sortOrder;
    const swappedA: GradeGroup = { ...list[idx], sortOrder: list[targetIdx].sortOrder };
    const swappedB: GradeGroup = { ...list[targetIdx], sortOrder: tempOrder };
    try {
      await addOrUpdateGrades([swappedA, swappedB]);
      setReorderError(null);
    } catch (error) {
      setReorderError(error instanceof Error ? error.message : '年级顺序调整失败，请重试');
    }
  };

  // 班级在所属年级内左右移动排序
  const handleMoveClass = async (gradeId: string, classId: string, delta: -1 | 1) => {
    const list = [...(classesByGrade.get(gradeId) ?? [])];
    const idx = list.findIndex((c) => c.id === classId);
    const targetIdx = idx + delta;
    if (idx < 0 || targetIdx < 0 || targetIdx >= list.length) return;
    const swappedA: ClassGroup = { ...list[idx], sortOrder: list[targetIdx].sortOrder };
    const swappedB: ClassGroup = { ...list[targetIdx], sortOrder: list[idx].sortOrder };
    try {
      await addOrUpdateClasses([swappedA, swappedB]);
      setReorderError(null);
    } catch (error) {
      setReorderError(error instanceof Error ? error.message : '班级顺序调整失败，请重试');
    }
  };

  // 行内保存班级名称
  const handleInlineSaveClass = async (cls: ClassGroup) => {
    const trimmed = editingClassName.trim();
    const siblings = classesByGrade.get(cls.gradeId) ?? [];
    if (!trimmed) {
      setInlineError('名称不能为空');
      return;
    }
    if (siblings.some((other) => other.id !== cls.id && other.name === trimmed)) {
      setInlineError('同年级下班级名称重复');
      return;
    }
    if (trimmed !== cls.name) {
      await addOrUpdateClasses([{ ...cls, name: trimmed }]);
    }
    setEditingClassId(null);
    setInlineError(null);
  };

  return (
    <div className="space-y-6">
      {reorderError && (
        <p className="rounded-control border border-destructive/25 bg-destructive-surface px-4 py-2.5 text-[13px] text-destructive" role="alert">
          {reorderError}
        </p>
      )}
      {bannerNotice && (
        <div className="px-4 py-2.5 rounded-control bg-selection border border-primary/30 flex items-center justify-between text-[13px] text-primary font-medium">
          <span>{bannerNotice}</span>
          <button
            type="button"
            onClick={() => setBannerNotice(null)}
            className="p-1 hover:opacity-75"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      )}

      {/* 学段卡片与新增入口按数量等分整行，始终保持单行。 */}
      <div
        className="grid gap-3"
        style={{
          gridTemplateColumns: `repeat(${stages.length + 1}, minmax(0, 1fr))`,
        }}
      >
        {stages.map((stage, idx) => {
          const accent = getStageAccentVars(idx);
          const stageGrades = gradesByStage.get(stage.id) ?? [];
          const stageClassCount = stageGrades.reduce(
            (sum, g) => sum + (classesByGrade.get(g.id)?.length ?? 0),
            0
          );
          const routine = routinesByStage[stage.id];
          const canDeleteStage = stages.length > 1 && stageGrades.length === 0;

          return (
            <Card
              key={stage.id}
              className="h-[104px] p-4 flex flex-col justify-between"
            >
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2 min-w-0">
                  <span
                    className="w-2.5 h-2.5 rounded-full shrink-0"
                    style={{ backgroundColor: accent.dotColor }}
                  />
                  <span className="text-[14px] font-bold text-ink truncate">
                    {stage.name}
                  </span>
                </div>

                <div className="flex items-center gap-2.5 shrink-0 text-[11.5px]">
                  <button
                    type="button"
                    onClick={() => {
                      setEditingStage(stage);
                      setStageModalOpen(true);
                    }}
                    className="text-primary hover:underline font-medium"
                  >
                    改名
                  </button>
                  {stages.length > 1 && (
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <span>
                          <button
                            type="button"
                            disabled={!canDeleteStage}
                            onClick={() =>
                              canDeleteStage && setDeleteStageTarget(stage)
                            }
                            className={`${
                              canDeleteStage
                                ? 'text-ink-secondary hover:text-destructive'
                                : 'text-ink-secondary/40 cursor-not-allowed'
                            }`}
                          >
                            删除
                          </button>
                        </span>
                      </TooltipTrigger>
                      <TooltipContent>
                        {canDeleteStage
                          ? '删除空学段'
                          : '请先迁移或删除该学段下的年级'}
                      </TooltipContent>
                    </Tooltip>
                  )}
                </div>
              </div>

              <div className="min-w-0">
                <div className="truncate text-[12px] text-ink-secondary font-mono">
                  {stageGrades.length} 个年级 · {stageClassCount} 个班级
                </div>
                <div className="text-[11.5px] text-ink-secondary truncate mt-0.5">
                  {formatRoutineSummary(routine)}
                </div>
              </div>
            </Card>
          );
        })}

        {/* 新增学段卡片 */}
        <button
          type="button"
          onClick={() => {
            setEditingStage(null);
            setStageModalOpen(true);
          }}
          className="h-[104px] rounded-card bg-surface border border-dashed border-control-border hover:border-primary hover:bg-selection/40 flex flex-col items-center justify-center gap-1.5 text-primary transition-colors duration-feedback"
        >
          <Plus className="h-5 w-5" />
          <span className="text-[13px] font-semibold">新增学段</span>
        </button>
      </div>

      {/* 第二部分：年级与班级主表（对齐 _GradeClassTable） */}
      <Card className="overflow-hidden">
        {/* 表头 */}
        <div className="grid grid-cols-[150px_120px_1fr_110px] items-center h-11 px-4 bg-table-header border-b border-table-divider text-[12px] font-semibold text-ink-secondary">
          <div className="flex items-center gap-1.5">
            <span>年级</span>
            <Tooltip>
              <TooltipTrigger asChild>
                <button
                  type="button"
                  onClick={() => setAddGradesOpen(true)}
                  className="w-5 h-5 rounded hover:bg-selection text-primary flex items-center justify-center"
                >
                  <Plus className="h-3.5 w-3.5" />
                </button>
              </TooltipTrigger>
              <TooltipContent>批量新增年级</TooltipContent>
            </Tooltip>
          </div>
          <div>所属学段</div>
          <div className="flex items-center gap-1.5">
            <span>班级</span>
            <Tooltip>
              <TooltipTrigger asChild>
                <button
                  type="button"
                  onClick={() => setBatchFillOpen(true)}
                  className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded hover:bg-selection text-primary text-[11px] font-medium"
                >
                  <Wand2 className="h-3 w-3" />
                  模板填充
                </button>
              </TooltipTrigger>
              <TooltipContent>按模板批量填充班级名称</TooltipContent>
            </Tooltip>
          </div>
          <div className="flex items-center justify-end gap-1 pr-2">
            <span>操作</span>
            {lastClassFillUndo && lastClassFillUndo.length > 0 && (
              <button
                type="button"
                aria-label={`撤销上次填充，恢复 ${lastClassFillUndo.length} 个班级`}
                title={`撤销上次填充 (${lastClassFillUndo.length})`}
                onClick={async () => {
                  const count = await undoBatchClassFill();
                  setBannerNotice(`已撤销上次批量填充（恢复 ${count} 个班级原名称）`);
                }}
                className="inline-flex items-center gap-1 rounded px-1.5 py-1 text-[11px] font-medium text-primary transition-colors hover:bg-selection"
              >
                <RotateCcw className="h-3 w-3" />
                撤销
              </button>
            )}
          </div>
        </div>

        {/* 表格行 */}
        {tableRows.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <p className="text-[13.5px] text-ink-secondary">
              当前还没有年级，点击下方按钮按模板批量新增年级。
            </p>
            <Button variant="outline" onClick={() => setAddGradesOpen(true)}>
              <Plus className="h-4 w-4" />
              新增年级
            </Button>
          </div>
        ) : (
          <div className="divide-y divide-table-divider">
            {tableRows.map(
              ({
                stage,
                stageIndex,
                grade,
                gradeIndexInStage,
                stageGradeCount,
              }) => {
                const accent = getStageAccentVars(stageIndex);
                const gradeClasses = classesByGrade.get(grade.id) ?? [];

                return (
                  <div
                    key={grade.id}
                    className="grid grid-cols-[150px_120px_1fr_110px] items-center min-h-[64px] px-4 py-3 bg-surface hover:bg-canvas/40 transition-colors"
                  >
                    {/* 年级名称与学段内上下排序 */}
                    <div className="flex items-center gap-1.5 pr-2">
                      <span className="text-[13px] font-semibold text-ink truncate">
                        {grade.name}
                      </span>
                      <div className="flex items-center opacity-60 hover:opacity-100">
                        <button
                          type="button"
                          disabled={gradeIndexInStage === 0}
                          onClick={() =>
                            void handleMoveGrade(stage.id, grade.id, -1)
                          }
                          className="p-0.5 text-ink-secondary hover:text-primary disabled:opacity-25"
                          title="在学段内上移"
                        >
                          <ArrowUp className="h-3.5 w-3.5" />
                        </button>
                        <button
                          type="button"
                          disabled={gradeIndexInStage >= stageGradeCount - 1}
                          onClick={() =>
                            void handleMoveGrade(stage.id, grade.id, 1)
                          }
                          className="p-0.5 text-ink-secondary hover:text-primary disabled:opacity-25"
                          title="在学段内下移"
                        >
                          <ArrowDown className="h-3.5 w-3.5" />
                        </button>
                      </div>
                    </div>

                    {/* 所属学段徽章 */}
                    <div>
                      <span
                        className="inline-flex items-center px-2 py-0.5 rounded-[6px] text-[11.5px] font-semibold"
                        style={{
                          backgroundColor: accent.tintBg,
                          color: accent.textColor,
                        }}
                      >
                        {stage.name}
                      </span>
                    </div>

                    {/* 班级 Chips + 内联编辑器 + 添加班级按钮 */}
                    <div className="flex flex-wrap items-center gap-1.5 pr-3">
                      {gradeClasses.map((cls, clsIdx) => {
                        const isInlineEditing = editingClassId === cls.id;
                        if (isInlineEditing) {
                          return (
                            <div
                              key={cls.id}
                              className="inline-flex items-center gap-1.5"
                            >
                              <Input
                                autoFocus
                                value={editingClassName}
                                onChange={(e) =>
                                  setEditingClassName(e.target.value)
                                }
                                onKeyDown={(e) => {
                                  if (e.key === 'Enter') {
                                    void handleInlineSaveClass(cls);
                                  } else if (e.key === 'Escape') {
                                    setEditingClassId(null);
                                    setInlineError(null);
                                  }
                                }}
                                onBlur={() => void handleInlineSaveClass(cls)}
                                className="h-7 w-32 px-2 text-[12.5px] bg-surface"
                              />
                              <span className="text-[11px] text-ink-secondary">
                                回车保存 · Esc 取消
                              </span>
                              {inlineError && (
                                <span className="text-[11px] text-destructive font-medium">
                                  {inlineError}
                                </span>
                              )}
                            </div>
                          );
                        }

                        return (
                          <div
                            key={cls.id}
                            className="group inline-flex items-center gap-1 h-7 px-2.5 rounded-[7px] border text-[12.5px] font-medium text-ink transition-colors"
                            style={{
                              backgroundColor: accent.tintBg,
                              borderColor: accent.borderColor,
                            }}
                          >
                            <button
                              type="button"
                              onClick={() => {
                                setEditingClassId(cls.id);
                                setEditingClassName(cls.name);
                                setInlineError(null);
                              }}
                              title="点击直接修改班级名称"
                              className="hover:underline"
                            >
                              {cls.name}
                            </button>

                            {/* 悬浮操作：前移 / 后移 / 删除 */}
                            <div className="hidden group-hover:inline-flex items-center gap-0.5 ml-1 pl-1 border-l border-border/60">
                              {clsIdx > 0 && (
                                <button
                                  type="button"
                                  onClick={() =>
                                    void handleMoveClass(grade.id, cls.id, -1)
                                  }
                                  className="p-0.5 text-ink-secondary hover:text-primary"
                                  title="向前移动"
                                >
                                  ←
                                </button>
                              )}
                              {clsIdx < gradeClasses.length - 1 && (
                                <button
                                  type="button"
                                  onClick={() =>
                                    void handleMoveClass(grade.id, cls.id, 1)
                                  }
                                  className="p-0.5 text-ink-secondary hover:text-primary"
                                  title="向后移动"
                                >
                                  →
                                </button>
                              )}
                              <button
                                type="button"
                                onClick={() => setDeleteClassTarget(cls)}
                                className="p-0.5 text-ink-secondary hover:text-destructive"
                                title="删除班级"
                              >
                                <X className="h-3 w-3" />
                              </button>
                            </div>
                          </div>
                        );
                      })}

                      <Button
                        variant="ghost"
                        size="sm"
                        className="h-7 px-2 text-[12px] text-primary"
                        onClick={() => setAddClassGradeTarget(grade)}
                      >
                        <Plus className="h-3.5 w-3.5" />
                        添加班级
                      </Button>
                    </div>

                    {/* 年级操作列 */}
                    <div className="flex items-center justify-end gap-2 pr-1 text-[12px]">
                      <button
                        type="button"
                        onClick={() => setEditGradeTarget(grade)}
                        className="text-primary hover:underline font-medium"
                      >
                        编辑
                      </button>
                      <button
                        type="button"
                        onClick={() => setDeleteGradeTarget(grade)}
                        className="text-ink-secondary hover:text-destructive"
                      >
                        删除
                      </button>
                    </div>
                  </div>
                );
              }
            )}
          </div>
        )}
      </Card>

      {/* 弹窗 1：新增 / 改名学段弹窗 */}
      <StageNameModal
        open={stageModalOpen}
        stage={editingStage}
        existingNames={stages.map((s) => s.name)}
        onClose={() => setStageModalOpen(false)}
        onSave={async (name) => {
          if (!activeTermId) return;
          if (editingStage) {
            await addOrUpdateStage({ ...editingStage, name });
          } else {
            await addOrUpdateStage({
              id: `stage_${Date.now()}`,
              termId: activeTermId,
              name,
              sortOrder: stages.length,
            });
          }
          setStageModalOpen(false);
        }}
      />

      {/* 弹窗 2：按模板批量新增年级弹窗 */}
      <BatchAddGradesModal
        open={addGradesOpen}
        stages={stages}
        gradesByStage={gradesByStage}
        onClose={() => setAddGradesOpen(false)}
        onAdd={async (stageId, names) => {
          const existing = gradesByStage.get(stageId) ?? [];
          const nextOrder =
            existing.reduce((max, g) => Math.max(max, g.sortOrder), -1) + 1;
          const created: GradeGroup[] = names.map((name, idx) => ({
            id: `grade_${Date.now()}_${idx}`,
            stageId,
            name,
            sortOrder: nextOrder + idx,
          }));
          await addOrUpdateGrades(created);
          setAddGradesOpen(false);
        }}
      />

      {/* 弹窗 3：编辑年级（名称与所属学段迁移） */}
      <EditGradeModal
        open={editGradeTarget !== null}
        grade={editGradeTarget}
        stages={stages}
        gradesByStage={gradesByStage}
        onClose={() => setEditGradeTarget(null)}
        onSave={async (updated) => {
          await addOrUpdateGrades([updated]);
          setEditGradeTarget(null);
        }}
      />

      {/* 弹窗 4：为指定年级批量新增班级 */}
      <AddClassesModal
        open={addClassGradeTarget !== null}
        grade={addClassGradeTarget}
        existingClasses={
          addClassGradeTarget
            ? classesByGrade.get(addClassGradeTarget.id) ?? []
            : []
        }
        onClose={() => setAddClassGradeTarget(null)}
        onAdd={async (grade, names) => {
          const current = classesByGrade.get(grade.id) ?? [];
          const nextOrder =
            current.reduce((max, c) => Math.max(max, c.sortOrder), -1) + 1;
          const created: ClassGroup[] = names.map((name, idx) => ({
            id: `cls_${Date.now()}_${idx}`,
            gradeId: grade.id,
            name,
            sortOrder: nextOrder + idx,
          }));
          await addOrUpdateClasses(created);
          setAddClassGradeTarget(null);
        }}
      />

      {/* 弹窗 5：批量填充班级名称（模板 + 多学段范围 + 预览 + 撤销上次填充） */}
      <BatchFillClassNamesModal
        open={batchFillOpen}
        stages={stages}
        gradesByStage={gradesByStage}
        classesByGrade={classesByGrade}
        canUndo={Boolean(lastClassFillUndo && lastClassFillUndo.length > 0)}
        onClose={() => setBatchFillOpen(false)}
        onUndo={async () => {
          const count = await undoBatchClassFill();
          setBatchFillOpen(false);
          setBannerNotice(`已撤销上次批量填充（恢复 ${count} 个班级）`);
        }}
        onApply={async (renames) => {
          const { updatedCount, skippedCount } = await applyBatchClassFill(
            renames
          );
          setBatchFillOpen(false);
          setBannerNotice(
            skippedCount === 0
              ? `已按模板批量重命名 ${updatedCount} 个班级`
              : `已重命名 ${updatedCount} 个班级，${skippedCount} 个因重名或无变化被跳过`
          );
        }}
      />

      {/* 弹窗 6：删除年级二次确认（列出连带删除的资料） */}
      <DeleteGradeConfirmModal
        grade={deleteGradeTarget}
        classCount={
          deleteGradeTarget
            ? classesByGrade.get(deleteGradeTarget.id)?.length ?? 0
            : 0
        }
        onClose={() => setDeleteGradeTarget(null)}
        onConfirm={async (gradeId) => {
          await removeGrade(gradeId);
          setDeleteGradeTarget(null);
        }}
      />

      {/* 弹窗 7：删除班级二次确认 */}
      <Dialog
        open={deleteClassTarget !== null}
        onOpenChange={(v) => !v && setDeleteClassTarget(null)}
      >
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>
              删除班级「{deleteClassTarget?.name}」？
            </DialogTitle>
            <DialogDescription>
              该班级的科目节数、任课、课表数据将一并删除；当前已保存的免任课设置也会移除，操作不可恢复。
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setDeleteClassTarget(null)}>
              取消
            </Button>
            <Button
              variant="destructive"
              onClick={async () => {
                if (deleteClassTarget) {
                  await removeClass(deleteClassTarget.id);
                  setDeleteClassTarget(null);
                }
              }}
            >
              确认删除
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 弹窗 8：删除空学段二次确认 */}
      <Dialog
        open={deleteStageTarget !== null}
        onOpenChange={(v) => !v && setDeleteStageTarget(null)}
      >
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>
              删除学段「{deleteStageTarget?.name}」？
            </DialogTitle>
            <DialogDescription>
              该学段的作息与免任课设置将一并删除。
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setDeleteStageTarget(null)}>
              取消
            </Button>
            <Button
              variant="destructive"
              onClick={async () => {
                if (deleteStageTarget) {
                  await removeStage(deleteStageTarget.id);
                  setDeleteStageTarget(null);
                }
              }}
            >
              确认删除
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

/* ============================================================================
   子组件 1：新增 / 改名学段弹窗 (对齐 _StageNameDialog：带常用候选 Chips)
   ============================================================================ */
interface StageNameModalProps {
  open: boolean;
  stage: SchoolStage | null;
  existingNames: string[];
  onClose: () => void;
  onSave: (name: string) => Promise<void>;
}

const StageNameModal: React.FC<StageNameModalProps> = ({
  open,
  stage,
  existingNames,
  onClose,
  onSave,
}) => {
  const [name, setName] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setName(stage?.name ?? '');
    setError(null);
  }, [open, stage]);

  const candidates = STAGE_PRESETS.filter(
    (item) => item === stage?.name || !existingNames.includes(item)
  );

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      setError('学段名称不能为空');
      return;
    }
    if (trimmed !== stage?.name && existingNames.includes(trimmed)) {
      setError('该学段名称已存在');
      return;
    }
    await onSave(trimmed);
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{stage ? '修改学段名称' : '新增学段'}</DialogTitle>
          <DialogDescription>
            预置小学部 / 初中部 / 高中部，也可新增国际部等自定义学段。
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1.5">
            <label className="text-[12.5px] font-semibold text-ink">
              学段名称
            </label>
            <Input
              autoFocus
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                setError(null);
              }}
              placeholder="例如：高中部"
            />
          </div>

          {candidates.length > 0 && (
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-[12px] text-ink-secondary">常用：</span>
              {candidates.map((cand) => {
                const selected = name.trim() === cand;
                return (
                  <button
                    key={cand}
                    type="button"
                    onClick={() => {
                      setName(cand);
                      setError(null);
                    }}
                    className={`px-2.5 py-1 rounded text-[11.5px] border transition-colors ${
                      selected
                        ? 'bg-selection border-primary text-primary font-semibold'
                        : 'bg-surface border-border text-ink-secondary hover:border-control-border'
                    }`}
                  >
                    {cand}
                  </button>
                );
              })}
            </div>
          )}

          {error && (
            <div className="text-[12px] text-destructive font-medium">
              {error}
            </div>
          )}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>
              取消
            </Button>
            <Button type="submit">{stage ? '保存' : '创建'}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};

/* ============================================================================
   子组件 2：按模板批量新增年级弹窗 (对齐 _AddGradesDialog)
   ============================================================================ */
interface BatchAddGradesModalProps {
  open: boolean;
  stages: SchoolStage[];
  gradesByStage: Map<string, GradeGroup[]>;
  onClose: () => void;
  onAdd: (stageId: string, names: string[]) => Promise<void>;
}

const BatchAddGradesModal: React.FC<BatchAddGradesModalProps> = ({
  open,
  stages,
  gradesByStage,
  onClose,
  onAdd,
}) => {
  const [stageId, setStageId] = useState('');
  const [mode, setMode] = useState<GradeNamingMode>('中文数字');
  const [countDraft, dispatchCountDraft] = useReducer(
    numericInputDraftReducer,
    '3'
  );
  const [customTemplate, setCustomTemplate] = useState('{N}年级');

  useEffect(() => {
    if (!open) return;
    setStageId(stages[0]?.id ?? '');
    setMode('中文数字');
    dispatchCountDraft({ type: 'edit', value: '3' });
    setCustomTemplate('高{N}');
  }, [open, stages]);

  const template =
    mode === '自定义' ? customTemplate : GRADE_NAMING_TEMPLATES[mode];

  const existingNames = useMemo(
    () => (gradesByStage.get(stageId) ?? []).map((g) => g.name),
    [gradesByStage, stageId]
  );

  const parsedCount = parseNumericDraft(countDraft);
  const count =
    parsedCount === null ? 0 : normalizeNumericValue(parsedCount, 1, 9, 1);

  const previewNames = useMemo(
    () =>
      countDraft === ''
        ? []
        : generateGradeNames({
            template,
            count,
            existingNames,
          }),
    [template, count, countDraft, existingNames]
  );

  const selectedStageName =
    stages.find((s) => s.id === stageId)?.name ?? '当前学段';

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>批量新增年级</DialogTitle>
          <DialogDescription>
            支持中文数字（一、二、三）、阿拉伯数字或包含 &#123;n&#125; / &#123;N&#125; 的自定义命名模板，自动跳过已有重名年级。
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1.5">
            <label className="text-[12.5px] font-semibold text-ink">
              所属学段
            </label>
            <Select value={stageId} onValueChange={setStageId}>
              <SelectTrigger>
                <SelectValue placeholder="选择学段" />
              </SelectTrigger>
              <SelectContent>
                {stages.map((st) => (
                  <SelectItem key={st.id} value={st.id}>
                    {st.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="grid grid-cols-[1fr_120px] gap-3">
            <div className="space-y-1.5">
              <label className="text-[12.5px] font-semibold text-ink">
                命名方式
              </label>
              <Select
                value={mode}
                onValueChange={(v) => setMode(v as GradeNamingMode)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="中文数字">中文数字（一年级、二年级…）</SelectItem>
                  <SelectItem value="阿拉伯数字">阿拉伯数字（1 年级、2 年级…）</SelectItem>
                  <SelectItem value="自定义">自定义模板…</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <label className="text-[12.5px] font-semibold text-ink">
                数量 (1–9)
              </label>
              <Input
                type="number"
                min={1}
                max={9}
                value={countDraft}
                onChange={(e) =>
                  dispatchCountDraft({
                    type: 'edit',
                    value: e.currentTarget.value,
                  })
                }
                onBlur={() =>
                  dispatchCountDraft({
                    type: 'normalize',
                    min: 1,
                    max: 9,
                    fallback: 3,
                  })
                }
                className="font-mono"
              />
            </div>
          </div>

          {mode === '自定义' && (
            <div className="space-y-1.5">
              <label className="text-[12.5px] font-semibold text-ink">
                自定义模板（需含 &#123;n&#125; 或 &#123;N&#125;）
              </label>
              <Input
                value={customTemplate}
                onChange={(e) => setCustomTemplate(e.target.value)}
                placeholder="例如：高{N} 或 G{n}"
              />
            </div>
          )}

          <div className="p-3 rounded-control bg-table-header border border-table-divider space-y-1">
            <div className="text-[12px] text-ink">
              预览：
              <span className="font-semibold text-primary">
                {previewNames.length > 0
                  ? previewNames.join('、')
                  : '请确保模板包含占位符 {n} 或 {N}'}
              </span>
            </div>
            <div className="text-[11px] text-ink-secondary">
              将添加到「{selectedStageName}」，创建后仍可逐个改名或调整顺序。
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            取消
          </Button>
          <Button
            disabled={previewNames.length === 0}
            onClick={() => void onAdd(stageId, previewNames)}
          >
            添加 {previewNames.length} 个年级
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

/* ============================================================================
   子组件 3：编辑年级弹窗 (对齐 _GradeEditorDialog)
   ============================================================================ */
interface EditGradeModalProps {
  open: boolean;
  grade: GradeGroup | null;
  stages: SchoolStage[];
  gradesByStage: Map<string, GradeGroup[]>;
  onClose: () => void;
  onSave: (updated: GradeGroup) => Promise<void>;
}

const EditGradeModal: React.FC<EditGradeModalProps> = ({
  open,
  grade,
  stages,
  gradesByStage,
  onClose,
  onSave,
}) => {
  const [name, setName] = useState('');
  const [stageId, setStageId] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !grade) return;
    setName(grade.name);
    setStageId(grade.stageId);
    setError(null);
  }, [open, grade]);

  if (!grade) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      setError('年级名称不能为空');
      return;
    }
    const targetList = gradesByStage.get(stageId) ?? [];
    if (targetList.some((g) => g.id !== grade.id && g.name === trimmed)) {
      setError('目标学段已存在同名年级，请修改名称后再保存');
      return;
    }
    const nextOrder =
      stageId === grade.stageId
        ? grade.sortOrder
        : targetList.reduce((max, g) => Math.max(max, g.sortOrder), -1) + 1;

    await onSave({
      id: grade.id,
      stageId,
      name: trimmed,
      sortOrder: nextOrder,
    });
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>编辑年级</DialogTitle>
          <DialogDescription>
            修改所属学段会改变该年级在课表分组中的位置；名称修改不会影响旗下班级。
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1.5">
            <label className="text-[12.5px] font-semibold text-ink">
              年级名称
            </label>
            <Input
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                setError(null);
              }}
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-[12.5px] font-semibold text-ink">
              所属学段
            </label>
            <Select value={stageId} onValueChange={setStageId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {stages.map((st) => (
                  <SelectItem key={st.id} value={st.id}>
                    {st.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {error && (
            <div className="text-[12px] text-destructive font-medium">
              {error}
            </div>
          )}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>
              取消
            </Button>
            <Button type="submit">保存</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};

/* ============================================================================
   子组件 4：新增班级弹窗 (对齐 _AddClassesDialog)
   ============================================================================ */
interface AddClassesModalProps {
  open: boolean;
  grade: GradeGroup | null;
  existingClasses: ClassGroup[];
  onClose: () => void;
  onAdd: (grade: GradeGroup, names: string[]) => Promise<void>;
}

const AddClassesModal: React.FC<AddClassesModalProps> = ({
  open,
  grade,
  existingClasses,
  onClose,
  onAdd,
}) => {
  const [countDraft, dispatchCountDraft] = useReducer(
    numericInputDraftReducer,
    '2'
  );

  useEffect(() => {
    if (open) dispatchCountDraft({ type: 'edit', value: '2' });
  }, [open]);

  if (!grade) return null;

  const parsedCount = parseNumericDraft(countDraft);
  const count =
    parsedCount === null ? 0 : normalizeNumericValue(parsedCount, 1, 30, 1);

  const used = new Set(existingClasses.map((c) => c.name));
  const names: string[] = [];
  const short = grade.name.endsWith('年级')
    ? grade.name.slice(0, grade.name.length - 2)
    : grade.name;

  for (let ordinal = 1; names.length < count && ordinal < 200; ordinal++) {
    const candidate = `${short}(${ordinal})班`;
    if (!used.has(candidate)) {
      used.add(candidate);
      names.push(candidate);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>新增班级 · {grade.name}</DialogTitle>
          <DialogDescription>
            自动按连续班号补齐当前年级的班级，创建后可点击任意班级标签直接改名。
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1.5">
            <label className="text-[12.5px] font-semibold text-ink">
              新增班级数量 (1–30)
            </label>
            <Input
              type="number"
              min={1}
              max={30}
              value={countDraft}
              onChange={(e) =>
                dispatchCountDraft({
                  type: 'edit',
                  value: e.currentTarget.value,
                })
              }
              onBlur={() =>
                dispatchCountDraft({
                  type: 'normalize',
                  min: 1,
                  max: 30,
                  fallback: 2,
                })
              }
              className="font-mono"
            />
          </div>

          <div className="p-3 rounded-control bg-table-header text-[12px] text-ink-secondary">
            预览：{names.slice(0, 6).join('、')}
            {names.length > 6 ? ` … 共 ${names.length} 个班` : ''}
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            取消
          </Button>
          <Button disabled={count === 0} onClick={() => void onAdd(grade, names)}>
            添加 {names.length} 个班级
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

/* ============================================================================
   子组件 5：批量填充班级名称弹窗 (对齐 _BatchFillNamesDialog：模板 + 范围 + 预览 + 撤销)
   ============================================================================ */
interface BatchFillClassNamesModalProps {
  open: boolean;
  stages: SchoolStage[];
  gradesByStage: Map<string, GradeGroup[]>;
  classesByGrade: Map<string, ClassGroup[]>;
  canUndo: boolean;
  onClose: () => void;
  onUndo: () => Promise<void>;
  onApply: (
    renames: Array<{ target: ClassGroup; newName: string }>
  ) => Promise<void>;
}

const BatchFillClassNamesModal: React.FC<BatchFillClassNamesModalProps> = ({
  open,
  stages,
  gradesByStage,
  classesByGrade,
  canUndo,
  onClose,
  onUndo,
  onApply,
}) => {
  const [template, setTemplate] = useState<string>(CLASS_BATCH_TEMPLATES[0]);
  const [customRule, setCustomRule] = useState('{年级}（{n}）班');
  const [selectedStageIds, setSelectedStageIds] = useState<string[]>([]);

  useEffect(() => {
    if (!open) return;
    setSelectedStageIds(stages.map((s) => s.id));
  }, [open, stages]);

  const toggleStage = (id: string) => {
    setSelectedStageIds((prev) =>
      prev.includes(id) ? prev.filter((item) => item !== id) : [...prev, id]
    );
  };

  const selectedStages = stages.filter((s) => selectedStageIds.includes(s.id));
  const selectedGrades = selectedStages.flatMap(
    (s) => gradesByStage.get(s.id) ?? []
  );
  const totalSelectedClasses = selectedGrades.reduce(
    (sum, g) => sum + (classesByGrade.get(g.id)?.length ?? 0),
    0
  );

  const buildRenames = () => {
    const list: Array<{ target: ClassGroup; newName: string }> = [];
    for (const grade of selectedGrades) {
      const clsList = classesByGrade.get(grade.id) ?? [];
      const generated = generateClassNamesForGrade(
        grade.name,
        clsList.length,
        template,
        customRule
      );
      clsList.forEach((cls, idx) => {
        list.push({ target: cls, newName: generated[idx] });
      });
    }
    return list;
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <DialogTitle>批量填充班级名称</DialogTitle>
          <DialogDescription>
            按统一命名模板批量重命名所选学段下的全部班级，应用后支持一键撤销上次填充。
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5">
          {/* 1. 选择名称模板 */}
          <div className="space-y-2">
            <div className="text-[12px] font-semibold text-ink-secondary">
              1 · 选择名称模板
            </div>
            <div className="flex flex-wrap gap-2">
              {CLASS_BATCH_TEMPLATES.map((tpl) => {
                const active = template === tpl;
                return (
                  <button
                    key={tpl}
                    type="button"
                    onClick={() => setTemplate(tpl)}
                    className={`h-9 px-3 rounded-control border text-[13px] font-medium transition-colors ${
                      active
                        ? 'bg-selection border-primary text-primary font-semibold'
                        : 'bg-surface border-border text-ink-secondary hover:border-control-border'
                    }`}
                  >
                    {tpl}
                  </button>
                );
              })}
            </div>
            {template === '自定义…' && (
              <div className="pt-1">
                <Input
                  value={customRule}
                  onChange={(e) => setCustomRule(e.target.value)}
                  placeholder="可用 {n}、{N} 与 {年级}，如：{年级}（{n}）班"
                />
              </div>
            )}
          </div>

          {/* 2. 选择应用范围（多选学段） */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-[12px] font-semibold text-ink-secondary">
                2 · 应用范围（可多选学段）
              </span>
              <div className="flex items-center gap-3 text-[12px] text-primary">
                <button
                  type="button"
                  onClick={() => setSelectedStageIds(stages.map((s) => s.id))}
                  className="hover:underline"
                >
                  全选
                </button>
                <button
                  type="button"
                  onClick={() => setSelectedStageIds([])}
                  className="hover:underline"
                >
                  清空
                </button>
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              {stages.map((st) => {
                const active = selectedStageIds.includes(st.id);
                return (
                  <button
                    key={st.id}
                    type="button"
                    onClick={() => toggleStage(st.id)}
                    className={`h-8 px-3 rounded-md border text-[12.5px] font-medium inline-flex items-center gap-1.5 transition-colors ${
                      active
                        ? 'bg-selection border-primary text-primary font-semibold'
                        : 'bg-surface border-border text-ink-secondary'
                    }`}
                  >
                    <span>{st.name}</span>
                    {active && <Check className="h-3.5 w-3.5" />}
                  </button>
                );
              })}
            </div>

            <div className="text-[12px] text-primary font-medium">
              已选 {selectedStages.length} 个学段 · {selectedGrades.length} 个年级 ·{' '}
              {totalSelectedClasses} 个班级
            </div>
          </div>

          {/* 3. 按学段分组实时预览 */}
          <div className="space-y-2">
            <div className="text-[12px] font-semibold text-ink-secondary">
              3 · 实时预览（按学段分组展示，应用后仍可逐个修改）
            </div>
            <div className="p-3.5 rounded-control bg-table-header border border-border space-y-2 min-h-[84px]">
              {selectedStages.length === 0 ? (
                <div className="text-[12px] text-ink-secondary">
                  请先在上方选择要填充的学段
                </div>
              ) : (
                selectedStages.map((st) => {
                  const stGrades = gradesByStage.get(st.id) ?? [];
                  const previewList = stGrades.flatMap((g) =>
                    generateClassNamesForGrade(
                      g.name,
                      classesByGrade.get(g.id)?.length ?? 0,
                      template,
                      customRule
                    )
                  );
                  return (
                    <div
                      key={st.id}
                      className="flex flex-wrap items-center gap-1.5 text-[12px]"
                    >
                      <span className="text-ink-secondary font-medium">
                        {st.name}：
                      </span>
                      {previewList.slice(0, 4).map((name, i) => (
                        <Badge key={i} variant="secondary">
                          {name}
                        </Badge>
                      ))}
                      <span className="text-ink-secondary text-[11.5px]">
                        … 共 {previewList.length} 个班级
                      </span>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </div>

        <DialogFooter className="flex items-center justify-between sm:justify-between">
          <div>
            {canUndo && (
              <Button type="button" variant="ghost" onClick={() => void onUndo()}>
                <RotateCcw className="h-4 w-4" />
                撤销上次填充
              </Button>
            )}
          </div>
          <div className="flex items-center gap-2">
            <Button type="button" variant="outline" onClick={onClose}>
              取消
            </Button>
            <Button
              type="button"
              disabled={totalSelectedClasses === 0}
              onClick={() => void onApply(buildRenames())}
            >
              应用填充
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

/* ============================================================================
   子组件 6：删除年级二次确认弹窗 (对齐 _GradeDeleteDialog：明确列出连带删除项)
   ============================================================================ */
interface DeleteGradeConfirmModalProps {
  grade: GradeGroup | null;
  classCount: number;
  onClose: () => void;
  onConfirm: (gradeId: string) => Promise<void>;
}

const DeleteGradeConfirmModal: React.FC<DeleteGradeConfirmModalProps> = ({
  grade,
  classCount,
  onClose,
  onConfirm,
}) => {
  const [confirmedCascade, setConfirmedCascade] = useState(true);

  useEffect(() => {
    if (grade) setConfirmedCascade(true);
  }, [grade]);

  if (!grade) return null;

  return (
    <Dialog open={grade !== null} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-destructive">
            <AlertTriangle className="h-5 w-5" />
            删除年级「{grade.name}」
          </DialogTitle>
          <DialogDescription>
            将删除「{grade.name}」及其名下 {classCount} 个班级，同时连带删除以下关联数据，且不可恢复：
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="p-3 rounded-control bg-table-header border border-border text-[12.5px] text-ink-secondary space-y-1">
            <div>• 该年级与班级的科目节数需求及课程配对</div>
            <div>• 教师任课关系（含该范围下的免任课与科目预设）</div>
            <div>• 已排课表数据与锁定记录</div>
          </div>

          {classCount > 0 && (
            <label className="flex items-center gap-2 text-[12.5px] text-ink cursor-pointer">
              <input
                type="checkbox"
                checked={confirmedCascade}
                onChange={(e) => setConfirmedCascade(e.target.checked)}
                className="rounded border-control-border"
              />
              <span>我已知晓并同时删除旗下 {classCount} 个班级</span>
            </label>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            取消
          </Button>
          <Button
            variant="destructive"
            disabled={!confirmedCascade}
            onClick={() => void onConfirm(grade.id)}
          >
            确认删除
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
