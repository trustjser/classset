import { useId, useMemo, useState } from 'react';
import { Bar, BarChart, CartesianGrid, Rectangle, XAxis, YAxis, type BarShapeProps } from 'recharts';
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from '@/components/ui/chart';
import { Button } from '@/components/ui/button';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import type { AcademicTerm, ScheduleItem } from '@/domain/models';
import {
  buildTeacherWorkload,
  selectWorkloadDays,
  type WorkloadDay,
  type TeacherWorkloadMode,
  type WorkloadSupervisionPlan,
  type WorkloadTeacher,
} from './teacherWorkload';
import './teacherWorkloadChart.css';

const dayConfig = {
  day1: { label: '周一', color: 'var(--workload-day1)' },
  day2: { label: '周二', color: 'var(--workload-day2)' },
  day3: { label: '周三', color: 'var(--workload-day3)' },
  day4: { label: '周四', color: 'var(--workload-day4)' },
  day5: { label: '周五', color: 'var(--workload-day5)' },
  day6: { label: '周六', color: 'var(--workload-day6)' },
  day7: { label: '周日', color: 'var(--workload-day7)' },
} satisfies Record<WorkloadDay, ChartConfig[string]>;

const days = Object.keys(dayConfig) as WorkloadDay[];
const plotMargin = { top: 24, right: 8, bottom: 8, left: 4 };
const teacherAxisHeight = 32;

const workloadModes = [
  { value: 'combined', label: '正课＋带班' },
  { value: 'teaching', label: '仅正课' },
  { value: 'supervision', label: '仅带班' },
] as const;

interface TeacherWorkloadChartProps {
  teachers: readonly WorkloadTeacher[];
  items: readonly ScheduleItem[];
  supervisionPlan?: WorkloadSupervisionPlan;
  cycleMode?: AcademicTerm['cycleMode'];
}

export function TeacherWorkloadChart({
  teachers, items, supervisionPlan, cycleMode,
}: TeacherWorkloadChartProps) {
  const titleId = useId();
  const plotId = useId();
  const [mode, setMode] = useState<TeacherWorkloadMode>('combined');
  const [week, setWeek] = useState<'odd' | 'even'>('odd');
  const [hiddenDays, setHiddenDays] = useState<ReadonlySet<WorkloadDay>>(() => new Set());
  const alternating = cycleMode === 'alternating';
  const displayWeek = alternating ? week : 'weekly';
  const allRows = useMemo(
    () => buildTeacherWorkload(teachers, items, supervisionPlan, mode, displayWeek),
    [teachers, items, supervisionPlan, mode, displayWeek],
  );
  const visibleDays = useMemo(() => days.filter((day) => !hiddenDays.has(day)), [hiddenDays]);
  const rows = useMemo(() => selectWorkloadDays(allRows, visibleDays), [allRows, visibleDays]);
  const maxTotal = allRows[0]?.total ?? 0;
  const tickStep = Math.max(1, Math.ceil(maxTotal / 4));
  const tickCount = Math.ceil(maxTotal / tickStep);
  const ticks = Array.from({ length: tickCount + 1 }, (_, index) => index * tickStep);
  const teachersById = useMemo(() => new Map(rows.map((row) => [row.teacherId, row])), [rows]);

  const toggleDay = (day: WorkloadDay) => {
    setHiddenDays((previous) => {
      const next = new Set(previous);
      if (!next.delete(day)) next.add(day);
      return next;
    });
  };

  return (
    <section aria-labelledby={titleId} className="teacher-workload-chart min-w-0 rounded-xl bg-surface p-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 id={titleId} className="text-base font-semibold text-ink">教师任课负载</h2>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {alternating && (
            <Tabs value={week} onValueChange={(value) => setWeek(value as typeof week)}>
              <TabsList aria-label="课时统计周次" className="inline-flex">
                <TabsTrigger value="odd" className="px-2.5 text-xs data-[state=active]:shadow-none">单周</TabsTrigger>
                <TabsTrigger value="even" className="px-2.5 text-xs data-[state=active]:shadow-none">双周</TabsTrigger>
              </TabsList>
            </Tabs>
          )}
          <Tabs value={mode} onValueChange={(value) => setMode(value as TeacherWorkloadMode)}>
            <TabsList aria-label="课时统计范围" className="inline-flex">
              {workloadModes.map(({ value, label }) => (
                <TabsTrigger key={value} value={value} className="px-2.5 text-xs data-[state=active]:shadow-none">{label}</TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        </div>
      </div>

      {maxTotal > 0 && (
        <div role="group" aria-label="按星期显示课时" className="mt-4 flex flex-wrap items-center gap-1.5">
          {days.map((day) => {
            const visible = !hiddenDays.has(day);
            return (
              <Button
                key={day}
                type="button"
                variant="ghost"
                size="sm"
                aria-pressed={visible}
                aria-controls={plotId}
                onClick={() => toggleDay(day)}
                className="h-8 cursor-pointer gap-1.5 px-2 text-xs hover:bg-table-header aria-pressed:bg-canvas aria-pressed:text-ink"
              >
                <span
                  aria-hidden="true"
                  className="flex size-2.5 shrink-0 items-center"
                >
                  <span
                    className={visible ? 'size-full rounded-[3px]' : 'h-px w-full bg-control-border'}
                    style={visible ? { backgroundColor: dayConfig[day].color } : undefined}
                  />
                </span>
                <span className={visible ? undefined : 'line-through'}>{dayConfig[day].label}</span>
              </Button>
            );
          })}
        </div>
      )}

      <div id={plotId}>
        {rows[0]?.total > 0 ? (
          <div className="mt-3 grid min-w-0 grid-cols-[2rem_minmax(0,1fr)]">
            <div aria-hidden="true" className="relative h-60 border-r border-table-divider pr-2 text-right text-xs tabular-nums text-ink-secondary">
              <span className="absolute right-2 top-0">节</span>
              <div
                className="absolute right-2 flex flex-col-reverse justify-between leading-none"
                style={{ top: plotMargin.top - 6, bottom: plotMargin.bottom + teacherAxisHeight - 6 }}
              >
                {ticks.map((tick) => <span key={tick}>{tick}</span>)}
              </div>
            </div>
            <div
              role="region"
              aria-label="教师课时绘图区，可横向滚动"
              tabIndex={0}
              className="min-w-0 overflow-x-auto pb-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
            >
              <ChartContainer
                config={dayConfig}
                initialDimension={{ width: -1, height: -1 }}
                className="aspect-auto h-60 w-full [&_.recharts-surface:focus-visible]:outline [&_.recharts-surface:focus-visible]:outline-2 [&_.recharts-surface:focus-visible]:-outline-offset-2 [&_.recharts-surface:focus-visible]:outline-ring"
                style={{ minWidth: rows.length * 84 + plotMargin.left + plotMargin.right }}
              >
                <BarChart accessibilityLayer data={rows} margin={plotMargin}>
                  <CartesianGrid vertical={false} horizontalValues={ticks} stroke="var(--color-table-divider)" strokeDasharray="3 4" />
                  <XAxis
                    dataKey="teacherId"
                    height={teacherAxisHeight}
                    interval={0}
                    tick={{ fill: 'var(--color-ink)', fontSize: 12 }}
                    tickLine={false}
                    axisLine={false}
                    tickMargin={10}
                    tickFormatter={(id: string) => {
                      const name = teachersById.get(id)?.teacherName ?? '';
                      return name.length > 7 ? `${name.slice(0, 6)}…` : name;
                    }}
                  />
                  <YAxis hide type="number" domain={[0, tickCount * tickStep]} ticks={ticks} allowDataOverflow />
                  <ChartTooltip
                    content={
                      <ChartTooltipContent
                        className="border-border bg-popover"
                        labelFormatter={(id) => {
                          const row = teachersById.get(String(id));
                          return row && `${row.teacherName} · 合计 ${row.total} 节`;
                        }}
                      />
                    }
                    cursor={{ fill: 'var(--color-table-header)', radius: 6 }}
                    itemSorter="dataKey"
                  />
                  {visibleDays.map((day) => (
                    <Bar
                      key={day}
                      dataKey={day}
                      stackId="week"
                      fill={`var(--color-${day})`}
                      maxBarSize={34}
                      isAnimationActive={false}
                      shape={(props: BarShapeProps) => {
                        const { x, y, width, height, fill, payload, value } = props;
                        const row = payload as (typeof rows)[number];
                        const stackRange = Array.isArray(value) ? value : null;
                        const hasLowerSegment = stackRange !== null && stackRange[0] > 0;
                        const isTop = height > 0 && stackRange !== null && stackRange[1] === row.total;
                        return (
                          <g>
                            <Rectangle x={x} y={y} width={width}
                              height={height + (hasLowerSegment ? 1 : 0)} fill={fill}
                            />
                            {isTop && (
                              <text aria-hidden="true" x={x + width / 2} y={y - 7} textAnchor="middle"
                                className="pointer-events-none fill-ink text-xs font-semibold tabular-nums"
                              >
                                {row.total}
                              </text>
                            )}
                          </g>
                        );
                      }}
                    />
                  ))}
                </BarChart>
              </ChartContainer>
            </div>
          </div>
        ) : (
          <p role="status" className="py-12 text-center text-sm text-ink-secondary">
            {maxTotal > 0 ? '所选星期暂无课时' : '当前范围暂无课时'}
          </p>
        )}
      </div>
    </section>
  );
}
