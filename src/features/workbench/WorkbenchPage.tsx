import React from 'react';
import {
  CalendarX2,
  Check,
  CheckCircle2,
  ChevronRight,
  Sparkles,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import type { AcademicTerm, AppSection, WorkbenchSummary } from '@/domain/models';
import {
  getTeachingWeekEnd,
  getTeachingWeekOfDate,
  getWeekCycleLabel,
  parseLocalDate,
} from '@/features/terms/calendarUtils';
import {
  getCompletedPreparationCount,
  getCompletedPreparationSteps,
  getCurrentPreparationStep,
  getPreparationStepStatus,
  getScheduleEntryCopy,
  getStepCopyFor,
  PREPARATION_STEP_TOTAL,
  PREPARATION_STEPS,
} from './workbenchModel';
import type { PreparationStepKey, PreparationStepMeta } from './workbenchModel';
import './workbench.css';

interface WorkbenchPageProps {
  activeTerm: AcademicTerm | null;
  summary: WorkbenchSummary | null;
  onNavigate: (section: AppSection) => void;
  onSeedDemoData: () => Promise<void>;
}

const GUIDE_STEPS: readonly {
  number: number;
  title: string;
  description: string;
}[] = [
  {
    number: 1,
    title: '学段与班级',
    description: '先创建学期并设置教学日历，再搭好学段、年级与班级。',
  },
  {
    number: 2,
    title: '作息设置',
    description: '按学段设置上课日、各时段节数与节次时间。',
  },
  {
    number: 3,
    title: '科目节数',
    description: '填写各年级每周各科所需的课时。',
  },
  {
    number: 4,
    title: '教师任课',
    description: '为各班科目分配教师，补齐所需节数，完成后即可前往排课与课表。',
  },
];

function formatZhDate(date: Date): string {
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
}

function formatTermDateRange(term: AcademicTerm): string {
  if (!term.firstTeachingWeekStart) return '尚未设置教学日历';
  const start = parseLocalDate(term.firstTeachingWeekStart);
  const end = getTeachingWeekEnd(term, term.teachingWeekCount);
  if (!end) return '尚未设置教学日历';
  return `${formatZhDate(start)} — ${formatZhDate(end)}`;
}

export const WorkbenchPage: React.FC<WorkbenchPageProps> = ({
  activeTerm,
  summary,
  onNavigate,
  onSeedDemoData,
}) => {
  const [seeding, setSeeding] = React.useState(false);
  const [seedMessage, setSeedMessage] = React.useState('');
  const [selectedStepKey, setSelectedStepKey] =
    React.useState<PreparationStepKey | null>(null);
  const [guideOpen, setGuideOpen] = React.useState(false);

  const doneCount = getCompletedPreparationCount(summary);
  const currentStep = getCurrentPreparationStep(summary);
  const completedSteps = getCompletedPreparationSteps(summary);

  // 学期切换或当前进度推进时，重置手动回看的选择状态
  React.useEffect(() => {
    setSelectedStepKey(null);
  }, [activeTerm?.id, currentStep?.key, doneCount]);

  if (!activeTerm) {
    return (
      <div className="flex min-h-[360px] flex-col items-center justify-center rounded-card bg-surface p-8 text-center">
        <CalendarX2
          aria-hidden="true"
          className="h-10 w-10 text-muted-foreground"
        />
        <h2 className="mt-3 text-[16px] font-semibold text-ink">
          先创建一个学期
        </h2>
        <p className="mt-2 text-[12.5px] text-ink-secondary">
          排课准备从学期开始：设置学年学期与教学日历。
        </p>
        <Button
          className="mt-4"
          onClick={() => onNavigate('terms')}
          type="button"
        >
          前往学期与日历
        </Button>
      </div>
    );
  }

  const maxUnlockedIndex = currentStep
    ? currentStep.index
    : PREPARATION_STEP_TOTAL - 1;

  const selectedStep: PreparationStepMeta | null = selectedStepKey
    ? (PREPARATION_STEPS.find(
        (item) => item.key === selectedStepKey && item.index <= maxUnlockedIndex
      ) ?? null)
    : null;

  const activeStep: PreparationStepMeta | null = selectedStep ?? currentStep;
  const isPreviewingDoneStep =
    selectedStep !== null && selectedStep.index < doneCount;

  const heroCopy = activeStep
    ? getStepCopyFor(activeStep, summary)
    : getScheduleEntryCopy(summary);

  const handleSelectStep = (step: PreparationStepMeta) => {
    if (step.index > maxUnlockedIndex) return;
    setSelectedStepKey((prev) => {
      if (currentStep && step.key === currentStep.key) return null;
      return prev === step.key ? null : step.key;
    });
  };

  const handleSeedDemoData = async () => {
    if (summary && summary.gradeCount > 0) {
      setSeedMessage('当前学期已有年级数据，未生成演示数据。');
      return;
    }
    setSeeding(true);
    setSeedMessage('');
    try {
      await onSeedDemoData();
      setSeedMessage(
        '已生成演示数据：小学 36 个班、初中 24 个班，并配置作息、科目和教师任课。'
      );
    } catch (error) {
      setSeedMessage(
        `生成演示数据失败：${
          error instanceof Error ? error.message : String(error)
        }`
      );
    } finally {
      setSeeding(false);
    }
  };

  const now = new Date();
  const currentWeek = getTeachingWeekOfDate(activeTerm, now);
  const termDisplayTitle =
    activeTerm.academicYear && activeTerm.semesterLabel
      ? `${activeTerm.academicYear} 学年 · ${activeTerm.semesterLabel}`
      : activeTerm.title;
  const completionRatio =
    PREPARATION_STEP_TOTAL === 0 ? 0 : doneCount / PREPARATION_STEP_TOTAL;

  return (
    <div className="workbench-container space-y-5">
      {/* 顶部标题区：先把新学期的基础搭起来 + 演示数据按钮 */}
      <div className="workbench-page-header">
        <div className="min-w-0">
          <h2 className="text-[26px] font-bold leading-[1.25] text-ink">
            先把新学期的基础搭起来
          </h2>
          <p className="mt-1.5 text-[13.5px] leading-5 text-ink-secondary">
            跟着步骤完成准备，课集会在合适的时候解锁下一步。
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <Button
            className="rounded-full px-4"
            disabled={seeding}
            onClick={handleSeedDemoData}
            size="sm"
            type="button"
            variant="outline"
          >
            {seeding ? '正在生成…' : '演示数据'}
          </Button>
        </div>
      </div>

      {seedMessage && (
        <p
          aria-live="polite"
          className="rounded-control bg-surface px-4 py-2.5 text-[12.5px] text-ink-secondary"
          role="status"
        >
          {seedMessage}
        </p>
      )}

      {/* 新学期排课准备：进度条 + 4 步横向指示卡片 */}
      <section
        aria-labelledby="workbench-steps-title"
        className="rounded-card bg-surface px-5 pb-5 pt-[18px]"
      >
        <div className="flex items-center justify-between gap-3">
          <h3
            className="text-[14px] font-semibold text-ink"
            id="workbench-steps-title"
          >
            新学期排课准备
          </h3>
          <Badge
            className="border-0 bg-table-header px-2.5 py-0.5 text-[12px] font-medium tabular-nums text-ink-secondary"
            variant="secondary"
          >
            {doneCount} / {PREPARATION_STEP_TOTAL} 完成
          </Badge>
        </div>

        <div
          aria-label="新学期排课准备进度"
          aria-valuemax={PREPARATION_STEP_TOTAL}
          aria-valuemin={0}
          aria-valuenow={doneCount}
          aria-valuetext={`已完成 ${doneCount} 步，共 ${PREPARATION_STEP_TOTAL} 步`}
          className="workbench-progress-track mt-3"
          role="progressbar"
        >
          <span
            className="workbench-progress-fill"
            style={{ transform: `scaleX(${completionRatio})` }}
          />
        </div>

        <div className="workbench-steps-grid mt-3.5">
          {PREPARATION_STEPS.map((step) => {
            const status = getPreparationStepStatus(
              step,
              doneCount,
              currentStep
            );
            const isLocked = status === 'locked';
            const isSelected = activeStep?.key === step.key;
            const isHighlighted = isSelected || status === 'current';

            const statusLabel =
              status === 'done'
                ? '已完成'
                : status === 'current'
                  ? '当前步骤'
                  : '完成前一步后解锁';

            const tileStateClass = isSelected
              ? 'workbench-step-tile-selected'
              : status === 'current'
                ? 'workbench-step-tile-current'
                : status === 'done'
                  ? 'workbench-step-tile-done'
                  : 'workbench-step-tile-locked';

            const dotStateClass =
              status === 'done'
                ? 'workbench-step-dot-done'
                : status === 'current'
                  ? 'workbench-step-dot-current'
                  : 'workbench-step-dot-locked';

            const titleColorClass =
              status === 'locked'
                ? 'text-muted-foreground'
                : status === 'done' && !isSelected
                  ? 'text-ink-secondary'
                  : 'text-ink';

            const statusColorClass =
              status === 'done'
                ? 'text-success'
                : status === 'current'
                  ? 'text-primary'
                  : 'text-muted-foreground';

            return (
              <button
                aria-current={status === 'current' ? 'step' : undefined}
                aria-label={`第 ${step.number} 步：${step.title}（${statusLabel}）`}
                className={`workbench-step-tile ${tileStateClass}`}
                disabled={isLocked}
                key={step.key}
                onClick={() => handleSelectStep(step)}
                type="button"
              >
                <div className="flex w-full items-center gap-2">
                  <span
                    aria-hidden="true"
                    className={`workbench-step-dot ${dotStateClass}`}
                  >
                    {status === 'done' ? (
                      <Check className="h-3 w-3 stroke-[2.6]" />
                    ) : (
                      <span>{step.number}</span>
                    )}
                  </span>
                  <span
                    className={`truncate text-[12.5px] ${
                      isHighlighted ? 'font-semibold' : 'font-medium'
                    } ${titleColorClass}`}
                  >
                    {step.title}
                  </span>
                </div>
                <span
                  className={`mt-1.5 truncate text-[11px] ${statusColorClass}`}
                >
                  {statusLabel}
                </span>
              </button>
            );
          })}
        </div>
      </section>

      {/* 第二行：接下来/排课入口引导卡 (5) + 当前学期卡片 (4) */}
      <div className="workbench-dual-row">
        <section
          aria-labelledby="workbench-next-title"
          className="workbench-hero-card"
        >
          <div>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <Badge
                  className="bg-surface px-2.5 py-0.5 text-[12px] font-semibold text-primary"
                  variant="default"
                >
                  {isPreviewingDoneStep
                    ? '回看调整'
                    : activeStep
                      ? '接下来'
                      : '基础已就绪'}
                </Badge>
                <span className="text-[12px] font-semibold text-primary">
                  {activeStep
                    ? `第 ${activeStep.number} 步`
                    : '可前往排课与课表'}
                </span>
              </div>

              {isPreviewingDoneStep && (
                <button
                  className="rounded-full bg-surface/90 px-2.5 py-1 text-[11px] font-semibold text-primary transition-colors hover:bg-surface"
                  onClick={() => setSelectedStepKey(null)}
                  type="button"
                >
                  回到当前进度
                </button>
              )}
            </div>

            <h3
              className="mt-3 text-[18px] font-bold leading-[1.3] text-ink"
              id="workbench-next-title"
            >
              {heroCopy.title}
            </h3>
            <p className="mt-1.5 text-[13px] leading-[1.55] text-ink-secondary">
              {heroCopy.description}
            </p>
            <p className="mt-3.5 text-[12px] text-muted-foreground">
              {heroCopy.meta}
            </p>
          </div>

          <div className="mt-4 flex flex-wrap items-center gap-3">
            <Button
              onClick={() => onNavigate(heroCopy.targetSection)}
              type="button"
            >
              {!activeStep && (
                <Sparkles aria-hidden="true" className="h-4 w-4" />
              )}
              {heroCopy.actionLabel}
            </Button>
          </div>
        </section>

        <section
          aria-labelledby="workbench-term-title"
          className="workbench-surface-card workbench-surface-card-interactive"
        >
          <div>
            <div className="flex items-center justify-between gap-3">
              <h3
                className="text-[14px] font-semibold text-ink"
                id="workbench-term-title"
              >
                当前学期
              </h3>
              <Badge
                variant={currentWeek !== null ? 'success' : 'secondary'}
              >
                {currentWeek !== null ? '进行中' : '未开始'}
              </Badge>
            </div>

            <div className="mt-3 text-[15.5px] font-semibold text-ink">
              {termDisplayTitle}
            </div>
            <p className="mt-1 text-[12px] text-muted-foreground">
              {formatTermDateRange(activeTerm)}
            </p>

            <div className="mt-3">
              {currentWeek !== null ? (
                <div className="flex items-center gap-2">
                  <span className="inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-[12px] font-bold tabular-nums text-primary-foreground">
                    {currentWeek}
                  </span>
                  <span className="text-[12.5px] text-ink-secondary">
                    第 {currentWeek} 教学周 ·{' '}
                    {getWeekCycleLabel(activeTerm, currentWeek)}
                  </span>
                </div>
              ) : (
                <p className="text-[12px] text-muted-foreground">
                  {activeTerm.firstTeachingWeekStart
                    ? '当前日期不在本学期教学周范围内。'
                    : '尚未设置第 1 教学周起始日，暂无法定位教学周。'}
                </p>
              )}
            </div>
          </div>

          <div className="mt-3.5">
            <Button
              className="-ml-3 px-3 text-[13px] font-semibold text-ink hover:text-primary"
              onClick={() => onNavigate('terms')}
              size="sm"
              type="button"
              variant="ghost"
            >
              查看学期与日历
              <ChevronRight aria-hidden="true" className="h-4 w-4" />
            </Button>
          </div>
        </section>
      </div>

      {/* 第三行：已完成的准备 (5) + 数据只保存在这台设备 (4) */}
      <div className="workbench-dual-row">
        <section
          aria-labelledby="workbench-completed-title"
          className="workbench-surface-card"
        >
          <div>
            <div className="flex items-center justify-between gap-3">
              <h3
                className="text-[14px] font-semibold text-ink"
                id="workbench-completed-title"
              >
                已完成的准备
              </h3>
              <span className="text-[11.5px] text-muted-foreground">
                随时可调整
              </span>
            </div>

            <div className="mt-3.5">
              {completedSteps.length === 0 ? (
                <p className="text-[12.5px] leading-[1.5] text-muted-foreground">
                  还没有完成的准备，从「学段与班级」开始吧。
                </p>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {completedSteps.map((step) => {
                    const isChipSelected = selectedStep?.key === step.key;
                    return (
                      <button
                        className={`workbench-completed-chip ${
                          isChipSelected
                            ? 'workbench-completed-chip-selected'
                            : ''
                        }`}
                        key={step.key}
                        onClick={() => handleSelectStep(step)}
                        type="button"
                      >
                        <CheckCircle2
                          aria-hidden="true"
                          className="h-3.5 w-3.5 shrink-0 text-success"
                        />
                        <span>{step.title} · 已完成</span>
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </section>

        <section
          aria-labelledby="workbench-local-data-title"
          className="workbench-surface-card"
        >
          <div>
            <h3
              className="text-[14px] font-semibold text-ink"
              id="workbench-local-data-title"
            >
              数据只保存在这台设备
            </h3>
            <p className="mt-2 text-[12.5px] leading-[1.55] text-ink-secondary">
              离线也能排课，数据文件可随时备份。
            </p>
          </div>

          <div className="mt-3">
            <Button
              className="-ml-3 px-3 text-[13px] font-semibold text-ink hover:text-primary"
              onClick={() => setGuideOpen(true)}
              size="sm"
              type="button"
              variant="ghost"
            >
              查看四步上手指南
              <ChevronRight aria-hidden="true" className="h-4 w-4" />
            </Button>
          </div>
        </section>
      </div>

      {/* 四步上手指南弹窗 */}
      <Dialog onOpenChange={setGuideOpen} open={guideOpen}>
        <DialogContent className="max-w-[440px]">
          <DialogHeader>
            <DialogTitle>四步上手指南</DialogTitle>
          </DialogHeader>
          <div className="space-y-3 py-1">
            {GUIDE_STEPS.map((item) => (
              <div className="flex items-start gap-2.5" key={item.number}>
                <span className="mt-0.5 inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-selection text-[11px] font-bold text-primary">
                  {item.number}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="text-[13px] font-semibold text-ink">
                    {item.title}
                  </div>
                  <p className="mt-0.5 text-[12px] leading-[1.5] text-ink-secondary">
                    {item.description}
                  </p>
                </div>
              </div>
            ))}
          </div>
          <DialogFooter>
            <Button onClick={() => setGuideOpen(false)} type="button">
              知道了
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};
