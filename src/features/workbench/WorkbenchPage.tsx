import React from 'react';
import { ArrowRight, Check, Sparkles } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { getNavSectionAvailability } from '@/domain/models';
import type { AppSection, WorkbenchSummary } from '@/domain/models';
import { getWorkbenchProgress } from './workbenchModel';
import type { WorkbenchProgress } from './workbenchModel';
import './workbench.css';

type WorkbenchTerm = {
  title: string;
  firstTeachingWeekStart: string | null;
  teachingWeekCount: number;
};

interface WorkbenchPageProps {
  activeTerm: WorkbenchTerm | null;
  summary: WorkbenchSummary | null;
  onNavigate: (section: AppSection) => void;
}

const getStepBadge = (completed: boolean, available: boolean) => {
  if (completed) return { label: '已完成', variant: 'success' as const };
  if (!available) return { label: '待解锁', variant: 'secondary' as const };
  return { label: '待完成', variant: 'warning' as const };
};

export const WorkbenchPage: React.FC<WorkbenchPageProps> = ({
  activeTerm,
  summary,
  onNavigate,
}) => {
  const hasTerm = activeTerm !== null;
  const progress: WorkbenchProgress = getWorkbenchProgress(hasTerm, summary);
  const nextStep = progress.steps.find(
    (step) => step.section === progress.nextSection
  );
  const nextAvailability = progress.nextSection
    ? getNavSectionAvailability(progress.nextSection, hasTerm, summary)
    : null;
  const completion = progress.completeCount / progress.totalCount;
  const supportSections: {
    section: AppSection;
    title: string;
    description: string;
  }[] = [
    {
      section: 'supervision',
      title: '带班安排',
      description: '安排日常带班岗位与教师',
    },
    {
      section: 'temporaryAdjustments',
      title: '调代课',
      description: '查看与处理本学期课务调整',
    },
  ];

  return (
    <div className="workbench-container">
      <div className="workbench-layout">
        <section aria-labelledby="workbench-steps-title" className="min-w-0">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
            <h2
              className="text-[16px] font-semibold text-ink"
              id="workbench-steps-title"
            >
              排课准备
            </h2>
            <div className="flex w-full max-w-[320px] items-center gap-3 sm:w-[320px]">
              <span className="shrink-0 text-[12.5px] tabular-nums text-ink-secondary">
                {progress.completeCount} / {progress.totalCount} 项
              </span>
              <div
                aria-label="排课准备进度"
                aria-valuemax={progress.totalCount}
                aria-valuemin={0}
                aria-valuenow={progress.completeCount}
                aria-valuetext={`已完成 ${progress.completeCount} 项，共 ${progress.totalCount} 项`}
                className="workbench-progress-track flex-1"
                role="progressbar"
              >
                <span
                  className="workbench-progress-fill"
                  style={{ transform: `scaleX(${completion})` }}
                />
              </div>
            </div>
          </div>

          <ol className="workbench-step-list">
            {progress.steps.map((step, index) => {
              const availability = getNavSectionAvailability(
                step.section,
                hasTerm,
                summary
              );
              const badge = getStepBadge(step.completed, availability.enabled);

              return (
                <li className="workbench-step" key={step.section}>
                  <span
                    aria-hidden="true"
                    className={`workbench-step-marker ${
                      step.completed ? 'workbench-step-marker-complete' : ''
                    }`}
                  >
                    {step.completed ? (
                      <Check className="h-4 w-4" />
                    ) : (
                      <span>{index + 1}</span>
                    )}
                  </span>
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <h3 className="text-[14px] font-semibold text-ink">
                        {step.title}
                      </h3>
                      <Badge variant={badge.variant}>{badge.label}</Badge>
                    </div>
                    <p className="mt-1 text-[13px] leading-5 text-ink-secondary">
                      {step.description}
                    </p>
                    {!availability.enabled && availability.reason && (
                      <p className="mt-1 text-[12.5px] text-warning">
                        {availability.reason}
                      </p>
                    )}
                  </div>
                  {availability.enabled && (
                    <Button
                      aria-label={`${step.completed ? '查看' : '前往'}${step.title}`}
                      className="workbench-step-action"
                      onClick={() => onNavigate(step.section)}
                      size="sm"
                      type="button"
                      variant="ghost"
                    >
                      {step.completed ? '查看' : '前往'}
                      <ArrowRight aria-hidden="true" className="h-3.5 w-3.5" />
                    </Button>
                  )}
                </li>
              );
            })}
          </ol>
        </section>

        <aside className="min-w-0 space-y-5">
          <section
            aria-labelledby="workbench-next-title"
            className="workbench-next-panel"
          >
            {progress.isLoading ? (
              <div aria-live="polite" role="status">
                <h2
                  className="text-[20px] font-semibold text-ink"
                  id="workbench-next-title"
                >
                  正在读取本学期进度
                </h2>
                <p className="mt-2 text-[14px] leading-6 text-ink">
                  数据载入后会显示建议的下一步。
                </p>
              </div>
            ) : nextStep && nextAvailability?.enabled ? (
              <>
                <p className="text-[13px] font-medium text-ink-secondary">
                  建议下一步
                </p>
                <h2
                  className="mt-2 text-[20px] font-semibold text-ink"
                  id="workbench-next-title"
                >
                  {nextStep.title}
                </h2>
                <p className="mt-2 text-[14px] leading-6 text-ink-secondary">
                  {nextStep.description}
                </p>
                <Button
                  className="mt-5 w-full"
                  onClick={() => onNavigate(nextStep.section)}
                  type="button"
                >
                  {activeTerm ? '继续设置' : '创建学期'}
                  <ArrowRight aria-hidden="true" className="h-4 w-4" />
                </Button>
              </>
            ) : nextStep ? (
              <>
                <p className="text-[13px] font-medium text-warning">等待前置步骤</p>
                <h2
                  className="mt-2 text-[20px] font-semibold text-ink"
                  id="workbench-next-title"
                >
                  {nextStep.title}
                </h2>
                <p className="mt-2 text-[14px] leading-6 text-ink-secondary">
                  {nextAvailability?.reason ?? '请先完成前面的设置。'}
                </p>
              </>
            ) : (
              <>
                <div className="flex items-center gap-2 text-success">
                  <Sparkles aria-hidden="true" className="h-4 w-4" />
                  <p className="text-[13px] font-semibold">排课准备已完成</p>
                </div>
                <h2
                  className="mt-2 text-[20px] font-semibold text-ink"
                  id="workbench-next-title"
                >
                  继续安排带班
                </h2>
                <p className="mt-2 text-[14px] leading-6 text-ink-secondary">
                  核心排课设置已齐备，可以接着处理带班岗位与课务调整。
                </p>
                <Button
                  className="mt-5 w-full"
                  onClick={() => onNavigate('supervision')}
                  type="button"
                >
                  打开带班安排
                  <ArrowRight aria-hidden="true" className="h-4 w-4" />
                </Button>
              </>
            )}
          </section>

          <section aria-labelledby="workbench-followups-title">
            <h2
              className="mb-2 text-[14px] font-semibold text-ink"
              id="workbench-followups-title"
            >
              课务安排
            </h2>
            <ul className="divide-y divide-table-divider border-y border-table-divider">
              {supportSections.map((item) => {
                const availability = getNavSectionAvailability(
                  item.section,
                  hasTerm,
                  summary
                );

                return (
                  <li
                    className="flex flex-wrap items-center justify-between gap-3 py-3"
                    key={item.section}
                  >
                    <div className="min-w-0">
                      <div className="text-[13.5px] font-medium text-ink">
                        {item.title}
                      </div>
                      <p className="mt-0.5 text-[12.5px] text-ink-secondary">
                        {availability.enabled
                          ? item.description
                          : availability.reason}
                      </p>
                    </div>
                    {availability.enabled ? (
                      <Button
                        aria-label={`前往${item.title}`}
                        className="shrink-0"
                        onClick={() => onNavigate(item.section)}
                        size="sm"
                        type="button"
                        variant="ghost"
                      >
                        打开
                        <ArrowRight
                          aria-hidden="true"
                          className="h-3.5 w-3.5"
                        />
                      </Button>
                    ) : (
                      <Badge className="shrink-0" variant="secondary">
                        待解锁
                      </Badge>
                    )}
                  </li>
                );
              })}
            </ul>
          </section>
        </aside>
      </div>
    </div>
  );
};
