import React, { useEffect, useMemo, useReducer, useState } from 'react';
import {
  ArrowRight,
  Calendar as CalendarIcon,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Clock,
  Copy,
  MoreHorizontal,
  Pencil,
  Plus,
  Trash2,
  X,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { DatePicker } from '@/components/ui/date-picker';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { numericInputDraftReducer, parseNumericDraft } from '@/lib/numberInput';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { AcademicTerm, CalendarException, CycleMode } from '@/domain/models';
import { useAppStore } from '@/store/useAppStore';
import {
  buildMonthGridDates,
  CalendarExceptionRange,
  formatDateMd,
  formatDateYmd,
  formatDateYmdWithWeekday,
  formatExceptionRangeLabel,
  getExceptionRangesForWeek,
  getIsoWeekday,
  getTeachingWeekEnd,
  getTeachingWeekOfDate,
  getTeachingWeekStart,
  getWeekCycleLabel,
  isOddWeek,
  parseLocalDate,
  WEEKDAY_SHORT_NAMES,
} from './calendarUtils';

const calendarViewButtonClassName = (selected: boolean) =>
  `h-7 px-2.5 text-[12px] ${selected ? 'bg-selection text-primary' : 'text-ink-secondary'}`;

export const TermPage: React.FC = () => {
  const {
    terms,
    activeTermId,
    calendarExceptions,
    selectTerm,
    saveOrCloneTerm,
    removeTerm,
    saveWeekCalendarExceptions,
    loadCalendarExceptionsForTerm,
    setSelectedSection,
  } = useAppStore();

  const activeTerm = useMemo(
    () => terms.find((t) => t.id === activeTermId) ?? terms[0] ?? null,
    [terms, activeTermId]
  );

  // 右侧视图模式：月历网格 vs 逐周教学日历表
  const [calendarViewMode, setCalendarViewMode] = useState<'month' | 'table'>('month');
  // 教学日历表超过 6 周折叠状态
  const [tableExpanded, setTableExpanded] = useState(false);

  // 当前可见月份 (year, monthIndex0)
  const [visibleMonth, setVisibleMonth] = useState<{ year: number; month: number }>(() => {
    if (activeTerm?.firstTeachingWeekStart) {
      const d = parseLocalDate(activeTerm.firstTeachingWeekStart);
      return { year: d.getFullYear(), month: d.getMonth() };
    }
    const now = new Date();
    return { year: now.getFullYear(), month: now.getMonth() };
  });

  useEffect(() => {
    if (activeTerm?.firstTeachingWeekStart) {
      const d = parseLocalDate(activeTerm.firstTeachingWeekStart);
      setVisibleMonth({ year: d.getFullYear(), month: d.getMonth() });
    }
  }, [activeTerm?.id, activeTerm?.firstTeachingWeekStart]);

  // 弹窗状态
  const [termEditorOpen, setTermEditorOpen] = useState(false);
  const [editingTerm, setEditingTerm] = useState<AcademicTerm | null>(null);
  const [editingTermExceptions, setEditingTermExceptions] = useState<CalendarException[]>([]);
  const [termManageOpen, setTermManageOpen] = useState(false);
  const [deletingTerm, setDeletingTerm] = useState<AcademicTerm | null>(null);
  const [termActionError, setTermActionError] = useState<string | null>(null);

  const [exceptionEditorOpen, setExceptionEditorOpen] = useState(false);
  const [editingWeekNumber, setEditingWeekNumber] = useState<number>(1);
  const [editingInitialDate, setEditingInitialDate] = useState<string | null>(null);

  const termEditor = (
    <TermEditorModal
      open={termEditorOpen}
      term={editingTerm}
      availableTerms={terms}
      existingExceptions={editingTermExceptions}
      onClose={() => setTermEditorOpen(false)}
      onSave={async (newTerm, cloneSourceId) => {
        await saveOrCloneTerm(newTerm, cloneSourceId);
        setTermEditorOpen(false);
      }}
    />
  );

  if (!activeTerm) {
    return (
      <>
        <Card className="p-12 text-center space-y-4">
          <div className="mx-auto w-11 h-11 rounded-full bg-selection text-primary flex items-center justify-center">
            <CalendarIcon className="h-5 w-5" />
          </div>
          <div>
            <h2 className="text-[16px] font-semibold text-ink">还没有学期资料</h2>
            <p className="text-[13px] text-ink-secondary mt-1">
              新建学期后即可建立学段、班级和教学日历。
            </p>
          </div>
          <Button
            onClick={() => {
              setEditingTerm(null);
              setTermEditorOpen(true);
            }}
          >
            <Plus className="h-4 w-4" />
            新建第一个学期
          </Button>
        </Card>
        {termEditor}
      </>
    );
  }

  const firstWeekStart = getTeachingWeekStart(activeTerm, 1);
  const lastWeekEnd = getTeachingWeekEnd(activeTerm, activeTerm.teachingWeekCount);

  const monthDates = buildMonthGridDates(visibleMonth.year, visibleMonth.month);
  const monthExceptions = calendarExceptions.filter((ex) => {
    const d = parseLocalDate(ex.date);
    return d.getFullYear() === visibleMonth.year && d.getMonth() === visibleMonth.month;
  });

  const canGoPrevMonth =
    firstWeekStart != null &&
    (visibleMonth.year > firstWeekStart.getFullYear() ||
      (visibleMonth.year === firstWeekStart.getFullYear() &&
        visibleMonth.month > firstWeekStart.getMonth()));

  const canGoNextMonth =
    lastWeekEnd != null &&
    (visibleMonth.year < lastWeekEnd.getFullYear() ||
      (visibleMonth.year === lastWeekEnd.getFullYear() &&
        visibleMonth.month < lastWeekEnd.getMonth()));

  const shiftMonth = (delta: number) => {
    const next = new Date(visibleMonth.year, visibleMonth.month + delta, 1);
    setVisibleMonth({ year: next.getFullYear(), month: next.getMonth() });
  };

  const openWeekExceptionModal = (weekNum: number, initialDate?: string) => {
    setEditingWeekNumber(weekNum);
    setEditingInitialDate(initialDate ?? null);
    setExceptionEditorOpen(true);
  };

  const visibleTableWeeks =
    tableExpanded || activeTerm.teachingWeekCount <= 6
      ? activeTerm.teachingWeekCount
      : 6;

  return (
    <div>
      {/* 宽屏左右分栏；单列时先展示教学日历，再展示学期摘要。 */}
      <div className="grid grid-cols-1 xl:grid-cols-[365px_1fr] gap-6 items-start">
        {/* 左侧：学期设置摘要卡 */}
        <Card className="order-2 p-5 space-y-5 xl:order-1">
          <div className="flex items-center justify-between">
            <span className="text-[14px] font-semibold text-ink">学期设置</span>
            <div className="flex items-center gap-2">
              <Badge variant="success">当前学期</Badge>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8"
                onClick={() => setTermManageOpen(true)}
                aria-label="管理学期"
                title="管理学期"
              >
                <MoreHorizontal className="h-4 w-4" />
              </Button>
            </div>
          </div>

          <div>
            <h2 className="text-[18px] font-semibold text-ink leading-snug">
              {activeTerm.title}
            </h2>
          </div>

          <div className="grid grid-cols-2 gap-2.5">
            <div className="p-3 rounded-[10px] bg-canvas border border-border">
              <div className="text-[11px] text-ink-secondary">第 1 教学周起始</div>
              <div className="text-[12.5px] font-semibold text-primary mt-1 font-mono">
                {formatDateYmdWithWeekday(activeTerm.firstTeachingWeekStart)}
              </div>
            </div>
            <div className="p-3 rounded-[10px] bg-canvas border border-border">
              <div className="text-[11px] text-ink-secondary">课表周期</div>
              <div className="text-[12.5px] font-semibold text-ink mt-1 font-mono">
                {activeTerm.teachingWeekCount} 周 ·{' '}
                {activeTerm.cycleMode === 'alternating' ? '单双周交替' : '每周相同'}
              </div>
            </div>
          </div>

          {/* 统计胶囊 */}
          <div className="p-3.5 rounded-[10px] bg-table-header border border-table-divider flex items-center justify-between text-[12.5px]">
            <span className="text-ink-secondary">已登记日历例外</span>
            <span className="font-mono font-semibold text-ink">
              停课 {calendarExceptions.filter((e) => e.kind === 'holiday').length} 天 · 补课{' '}
              {calendarExceptions.filter((e) => e.kind === 'makeup').length} 天
            </span>
          </div>

          {/* 作息设置关联提示卡 */}
          <div className="p-3.5 rounded-[11px] bg-selection/85 space-y-2">
            <div className="flex items-center gap-1.5 text-[12.5px] font-semibold text-primary">
              <Clock className="h-3.5 w-3.5" />
              <span>上课日与每日节数按学段设置</span>
            </div>
            <p className="text-[11.5px] text-ink-secondary leading-relaxed">
              同一学校不同学段可使用不同作息。学期日历只管理教学周锚点与停课、补课等例外。
            </p>
            <div className="flex justify-end pt-1">
              <Button
                variant="ghost"
                size="sm"
                className="text-primary hover:bg-surface/60 h-7 px-2.5 text-[12px]"
                onClick={() => setSelectedSection('routines')}
              >
                前往作息设置
                <ArrowRight className="h-3.5 w-3.5" />
              </Button>
            </div>
          </div>
        </Card>

        {/* 右侧：教学日历（支持「月历网格」与「逐周教学日历表」双模式无缝切换） */}
        <Card className="order-1 p-5 space-y-4 xl:order-2">
          {/* 日历顶栏 */}
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <h2 className="text-[15px] font-semibold text-ink">教学日历</h2>

              {/* 图例圆点 */}
              <div className="hidden sm:flex items-center gap-3 ml-2 text-[11.5px] text-ink-secondary">
                <span className="inline-flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-primary" />
                  单周
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-purple" />
                  双周
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-success" />
                  补课
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-destructive" />
                  停课
                </span>
              </div>
            </div>
            <div className="ml-auto flex flex-wrap items-center justify-end gap-2">
              <div
                role="group"
                aria-label="切换教学日历视图"
                className="inline-flex items-center rounded-control border border-border bg-canvas p-0.5"
              >
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  aria-pressed={calendarViewMode === 'month'}
                  className={calendarViewButtonClassName(calendarViewMode === 'month')}
                  onClick={() => setCalendarViewMode('month')}
                >
                  月历
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  aria-pressed={calendarViewMode === 'table'}
                  className={calendarViewButtonClassName(calendarViewMode === 'table')}
                  onClick={() => setCalendarViewMode('table')}
                >
                  周表
                </Button>
              </div>
              {calendarViewMode === 'month' && (
                <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  size="icon"
                  className="h-8 w-8"
                  disabled={!canGoPrevMonth}
                  onClick={() => shiftMonth(-1)}
                  aria-label="上个月"
                >
                  <ChevronLeft className="h-4 w-4" />
                </Button>
                <span className="px-2 text-[13.5px] font-semibold text-ink font-mono">
                  {visibleMonth.year}年{visibleMonth.month + 1}月
                </span>
                <Button
                  variant="outline"
                  size="icon"
                  className="h-8 w-8"
                  disabled={!canGoNextMonth}
                  onClick={() => shiftMonth(1)}
                  aria-label="下个月"
                >
                  <ChevronRight className="h-4 w-4" />
                </Button>
                </div>
              )}
            </div>
          </div>

          {/* 视图 A：教学月历网格 (严格遵循 DESIGN.md 第 9 节：周一至周日排列，每行左侧只显示一次教学周与单双周标记) */}
          {calendarViewMode === 'month' ? (
            <div className="space-y-3">
              <div className="grid grid-cols-[58px_repeat(7,minmax(0,1fr))] gap-1.5 text-center text-[11.5px] font-medium text-ink-secondary">
                <div className="py-1">教学周</div>
                {WEEKDAY_SHORT_NAMES.map((w) => (
                  <div key={w} className="py-1">
                    周{w}
                  </div>
                ))}
              </div>

              <div className="space-y-1.5">
                {Array.from({ length: 6 }, (_, rowIdx) => {
                  const rowDates = monthDates.slice(rowIdx * 7, rowIdx * 7 + 7);
                  let weekNum: number | null = null;
                  for (const d of rowDates) {
                    const w = getTeachingWeekOfDate(activeTerm, d);
                    if (w != null) {
                      weekNum = w;
                      break;
                    }
                  }
                  const odd = weekNum != null ? isOddWeek(weekNum) : true;

                  return (
                    <div
                      key={rowIdx}
                      className="grid grid-cols-[58px_repeat(7,minmax(0,1fr))] gap-1.5"
                    >
                      {/* 左侧教学周与单双周徽章（支持点击编辑该周例外） */}
                      <button
                        type="button"
                        disabled={weekNum == null}
                        onClick={() => weekNum != null && openWeekExceptionModal(weekNum)}
                        title={
                          weekNum != null
                            ? `点击编辑第 ${weekNum} 周例外安排`
                            : '非教学周'
                        }
                        className={`min-h-[68px] rounded-[10px] bg-canvas flex flex-col items-center justify-center transition-colors duration-feedback ${
                          weekNum != null
                            ? 'hover:bg-selection/70 cursor-pointer'
                            : 'opacity-50 cursor-default'
                        }`}
                      >
                        <span className="font-mono text-[11px] text-ink-secondary">
                          {weekNum == null
                            ? '—'
                            : `W${String(weekNum).padStart(2, '0')}`}
                        </span>
                        {weekNum != null && (
                          <span
                            className={`text-[11px] font-semibold mt-0.5 ${
                              activeTerm.cycleMode === 'every_week'
                                ? 'text-primary'
                                : odd
                                ? 'text-primary'
                                : 'text-purple'
                            }`}
                          >
                            {activeTerm.cycleMode === 'every_week'
                              ? '每周'
                              : odd
                              ? '单周'
                              : '双周'}
                          </span>
                        )}
                      </button>

                      {/* 周一至周日 7 个单元格 */}
                      {rowDates.map((dateObj) => {
                        const ymd = formatDateYmd(dateObj);
                        const inMonth = dateObj.getMonth() === visibleMonth.month;
                        const cellWeek = getTeachingWeekOfDate(activeTerm, dateObj);
                        const inTerm = cellWeek != null;
                        const ex = calendarExceptions.find((item) => item.date === ymd);
                        const isMakeup = ex?.kind === 'makeup';

                        return (
                          <button
                            key={ymd}
                            type="button"
                            disabled={!inTerm}
                            onClick={() =>
                              cellWeek != null && openWeekExceptionModal(cellWeek, ymd)
                            }
                            className={`min-h-[68px] p-2 rounded-[10px] border text-left flex flex-col justify-between transition-colors duration-feedback ${
                              ex
                                ? isMakeup
                                  ? 'bg-success-surface border-success text-success'
                                  : 'bg-destructive-surface border-destructive text-destructive'
                                : inMonth && inTerm
                                ? 'bg-surface border-border hover:border-control-border text-ink'
                                : 'bg-canvas/60 border-border/60 text-ink-secondary/50'
                            }`}
                          >
                            <div className="flex items-center justify-between w-full">
                              <span
                                className={`font-mono text-[12.5px] ${
                                  inTerm ? 'font-semibold' : 'font-normal'
                                }`}
                              >
                                {dateObj.getDate()}
                              </span>
                              {ex && (
                                <span className="text-[10px] font-semibold px-1.5 py-0.2 rounded bg-surface/80">
                                  {isMakeup ? '补课' : '停课'}
                                </span>
                              )}
                            </div>

                            {ex && (
                              <div className="mt-1 text-[11px] font-medium leading-tight line-clamp-2">
                                {ex.note.trim() ||
                                  (isMakeup && ex.makeupForDate
                                    ? `补 ${formatDateMd(ex.makeupForDate)}`
                                    : isMakeup
                                    ? '补课'
                                    : '停课')}
                              </div>
                            )}
                          </button>
                        );
                      })}
                    </div>
                  );
                })}
              </div>

              {/* 本月例外汇总条 */}
              <div className="p-3.5 rounded-[10px] bg-canvas flex flex-wrap items-center justify-between gap-2">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-[12px] font-semibold text-ink-secondary">
                    本月例外：
                  </span>
                  {monthExceptions.length === 0 ? (
                    <span className="text-[12px] text-ink-secondary">
                      暂无例外安排（点击上方任意教学日即可设置停课或补课映射）
                    </span>
                  ) : (
                    monthExceptions.map((ex) => {
                      const w = getTeachingWeekOfDate(activeTerm, ex.date);
                      const isMakeup = ex.kind === 'makeup';
                      return (
                        <button
                          key={ex.id}
                          type="button"
                          onClick={() => w != null && openWeekExceptionModal(w, ex.date)}
                          className={`px-2.5 py-1 rounded-full text-[11.5px] font-medium transition-opacity hover:opacity-85 ${
                            isMakeup
                              ? 'bg-selection text-primary'
                              : 'bg-destructive-surface text-destructive'
                          }`}
                        >
                          {formatDateMd(ex.date)}{' '}
                          {ex.note.trim() || (isMakeup ? '补课' : '停课')}
                          {w ? ` · 第${w}周` : ''}
                        </button>
                      );
                    })
                  )}
                </div>
              </div>
            </div>
          ) : (
            /* 视图 B：逐周教学日历表 (对齐 TeachingCalendarTable，超过 6 周可折叠展开) */
            <div className="rounded-control border border-border overflow-hidden">
              <div className="grid grid-cols-[100px_110px_210px_1fr_90px] items-center h-10 px-4 bg-table-header text-[12px] font-semibold text-ink-secondary border-b border-table-divider">
                <div>教学周</div>
                <div>单 / 双周</div>
                <div>日期范围</div>
                <div>例外安排（停课 / 补课 / 节假日）</div>
                <div className="text-center">操作</div>
              </div>

              <div className="divide-y divide-table-divider">
                {Array.from({ length: visibleTableWeeks }, (_, idx) => {
                  const weekNum = idx + 1;
                  const start = getTeachingWeekStart(activeTerm, weekNum);
                  const end = getTeachingWeekEnd(activeTerm, weekNum);
                  const ranges = getExceptionRangesForWeek(
                    activeTerm,
                    weekNum,
                    calendarExceptions
                  );
                  const hasMakeup = ranges.some((r) => r.kind === 'makeup');
                  const hasHoliday = ranges.some((r) => r.kind === 'holiday');
                  const odd = isOddWeek(weekNum);

                  return (
                    <div
                      key={weekNum}
                      className={`grid grid-cols-[100px_110px_210px_1fr_90px] items-center min-h-[42px] px-4 py-1.5 text-[13px] ${
                        hasMakeup
                          ? 'bg-warning-surface/55'
                          : hasHoliday
                          ? 'bg-destructive-surface/45'
                          : 'bg-surface'
                      }`}
                    >
                      <div className="font-mono font-semibold text-ink">
                        第 {weekNum} 周
                      </div>
                      <div>
                        <Badge
                          variant={
                            activeTerm.cycleMode === 'every_week'
                              ? 'secondary'
                              : odd
                              ? 'default'
                              : 'outline'
                          }
                          className={
                            activeTerm.cycleMode === 'alternating' && !odd
                              ? 'border-purple/40 text-purple bg-purple/10'
                              : ''
                          }
                        >
                          {getWeekCycleLabel(activeTerm, weekNum)}
                        </Badge>
                      </div>
                      <div className="font-mono text-[12.5px] text-ink-secondary">
                        {start && end
                          ? `${formatDateMd(start)} – ${formatDateMd(end)}`
                          : '未设置起始日'}
                      </div>
                      <div className="flex flex-wrap gap-1.5 pr-2">
                        {ranges.length === 0 ? (
                          <span className="text-ink-secondary text-[12px]">—</span>
                        ) : (
                          ranges.map((r) => (
                            <Badge
                              key={r.id}
                              variant={r.kind === 'makeup' ? 'warning' : 'destructive'}
                            >
                              {formatExceptionRangeLabel(activeTerm, r)}
                            </Badge>
                          ))
                        )}
                      </div>
                      <div className="text-center">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="text-primary h-7 px-2.5"
                          onClick={() => openWeekExceptionModal(weekNum)}
                        >
                          编辑
                        </Button>
                      </div>
                    </div>
                  );
                })}
              </div>

              {activeTerm.teachingWeekCount > 6 && (
                <button
                  type="button"
                  onClick={() => setTableExpanded(!tableExpanded)}
                  className="w-full h-9 bg-table-header hover:bg-selection/50 text-primary text-[12.5px] font-medium flex items-center justify-center gap-1.5 border-t border-table-divider transition-colors duration-feedback"
                >
                  {tableExpanded ? (
                    <>
                      <ChevronUp className="h-4 w-4" />
                      收起教学周
                    </>
                  ) : (
                    <>
                      <ChevronDown className="h-4 w-4" />
                      第 7 – {activeTerm.teachingWeekCount} 周 未展开（
                      {activeTerm.cycleMode === 'every_week'
                        ? '每周相同'
                        : '单双周自动交替'}
                      ）
                    </>
                  )}
                </button>
              )}
            </div>
          )}
        </Card>
      </div>

      {/* 弹窗 1：新建 / 编辑 / 复制学期对话框 */}
      {termEditor}

      {/* 弹窗 2：所有学期管理对话框 */}
      <TermManagementModal
        open={termManageOpen}
        terms={terms}
        activeTermId={activeTerm.id}
        error={termActionError}
        onClose={() => setTermManageOpen(false)}
        onSelect={async (id) => {
          setTermActionError(null);
          try {
            await selectTerm(id);
            setTermManageOpen(false);
          } catch (error) {
            setTermActionError(error instanceof Error ? error.message : '切换学期失败');
          }
        }}
        onEdit={async (t) => {
          setTermActionError(null);
          try {
            const exceptions = t.id === activeTerm.id
              ? calendarExceptions
              : await loadCalendarExceptionsForTerm(t.id);
            setEditingTermExceptions(exceptions);
            setEditingTerm(t);
            setTermManageOpen(false);
            setTermEditorOpen(true);
          } catch (error) {
            setTermActionError(error instanceof Error ? error.message : '读取学期日历失败');
          }
        }}
        onDelete={(t) => {
          setTermActionError(null);
          setTermManageOpen(false);
          setDeletingTerm(t);
        }}
        onCreate={() => {
          setTermManageOpen(false);
          setEditingTerm(null);
          setEditingTermExceptions([]);
          setTermEditorOpen(true);
        }}
      />

      <Dialog
        open={deletingTerm !== null}
        onOpenChange={(open) => {
          if (!open) {
            setDeletingTerm(null);
            setTermManageOpen(true);
          }
        }}
      >
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>删除学期</DialogTitle>
            <DialogDescription>
              确认删除「{deletingTerm?.title}」？该学期的学段、班级、作息和日历例外将一并移除。
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => {
              setDeletingTerm(null);
              setTermManageOpen(true);
            }}>
              取消
            </Button>
            <Button
              type="button"
              variant="destructive"
              onClick={async () => {
                if (!deletingTerm) return;
                try {
                  await removeTerm(deletingTerm.id);
                  setDeletingTerm(null);
                  setTermManageOpen(true);
                } catch (error) {
                  setDeletingTerm(null);
                  setTermManageOpen(true);
                  setTermActionError(error instanceof Error ? error.message : '删除学期失败');
                }
              }}
            >
              删除学期
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 弹窗 3：按教学周编辑停课区间与补课原课表映射弹窗 */}
      <WeekExceptionEditorModal
        open={exceptionEditorOpen}
        term={activeTerm}
        weekNumber={editingWeekNumber}
        initialDate={editingInitialDate}
        allExceptions={calendarExceptions}
        onClose={() => setExceptionEditorOpen(false)}
        onSave={async (upserts, deleteIds) => {
          await saveWeekCalendarExceptions(upserts, deleteIds);
          setExceptionEditorOpen(false);
        }}
      />
    </div>
  );
};

/* ============================================================================
   子组件 1：新建 / 编辑 / 复制学期弹窗 (对齐 TermEditorDialog)
   ============================================================================ */
interface TermEditorModalProps {
  open: boolean;
  term: AcademicTerm | null;
  availableTerms: AcademicTerm[];
  existingExceptions: CalendarException[];
  onClose: () => void;
  onSave: (term: AcademicTerm, cloneSourceId?: string | null) => Promise<void>;
}

const TermEditorModal: React.FC<TermEditorModalProps> = ({
  open,
  term,
  availableTerms,
  existingExceptions,
  onClose,
  onSave,
}) => {
  const isCreating = term === null;
  const [creationMode, setCreationMode] = useState<'blank' | 'clone'>('blank');
  const [cloneSourceId, setCloneSourceId] = useState<string>(
    availableTerms[0]?.id ?? ''
  );
  const [title, setTitle] = useState('');
  const [firstWeekStart, setFirstWeekStart] = useState('');
  const [weekCountDraft, dispatchWeekCountDraft] = useReducer(
    numericInputDraftReducer,
    '20'
  );
  const [cycleMode, setCycleMode] = useState<CycleMode>('alternating');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setError(null);
    if (term) {
      setTitle(term.title);
      setFirstWeekStart(term.firstTeachingWeekStart ?? '');
      dispatchWeekCountDraft({
        type: 'edit',
        value: String(term.teachingWeekCount),
      });
      setCycleMode(term.cycleMode);
      setCreationMode('blank');
    } else {
      const now = new Date();
      setTitle(`${now.getFullYear()} 学年 · ${now.getMonth() >= 6 ? '秋季学期' : '春季学期'}`);
      setFirstWeekStart('');
      dispatchWeekCountDraft({ type: 'edit', value: '20' });
      setCycleMode('alternating');
      setCreationMode('blank');
      setCloneSourceId(availableTerms[0]?.id ?? '');
    }
  }, [open, term, availableTerms]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const weekCount = parseNumericDraft(weekCountDraft) ?? 20;
    const trimmed = title.trim();
    if (!trimmed) {
      setError('请输入学期名称');
      return;
    }
    if (isCreating && !firstWeekStart) {
      setError('请选择第 1 教学周起始日期');
      return;
    }
    if (weekCount < 1 || weekCount > 52) {
      setError('请输入 1–52 之间的总周数');
      return;
    }

    const now = new Date();
    const titleUnchanged = term?.title === trimmed;
    const yearMatch = trimmed.match(/\d{4}(?:-\d{4})?/);
    const academicYear = titleUnchanged
      ? term.academicYear
      : yearMatch?.[0] ?? term?.academicYear ?? `${now.getFullYear()}-${now.getFullYear() + 1}`;
    const semesterLabel = titleUnchanged
      ? term.semesterLabel
      : trimmed.includes('春')
        ? '春季学期'
        : trimmed.includes('秋')
          ? '秋季学期'
          : term?.semesterLabel ?? (now.getMonth() >= 6 ? '秋季学期' : '春季学期');

    const candidate: AcademicTerm = {
      id: term?.id ?? `term_${Date.now()}`,
      title: trimmed,
      academicYear,
      semesterLabel,
      firstTeachingWeekStart: firstWeekStart || null,
      teachingWeekCount: weekCount,
      cycleMode,
      createdAt: term?.createdAt ?? Date.now(),
    };

    // 编辑既有学期时校验例外日期是否越界
    if (!isCreating) {
      const outOfRange = existingExceptions.filter(
        (ex) =>
          getTeachingWeekOfDate(candidate, ex.date) === null ||
          (ex.makeupForDate != null &&
            getTeachingWeekOfDate(candidate, ex.makeupForDate) === null)
      );
      if (outOfRange.length > 0) {
        setError(
          `以下已登记的例外日期超出新的教学周范围，请先调整或删除：${outOfRange
            .map((i) => i.date)
            .join('、')}`
        );
        return;
      }
    }

    try {
      await onSave(
        candidate,
        isCreating && creationMode === 'clone' ? cloneSourceId : null
      );
    } catch (error) {
      setError(error instanceof Error ? error.message : '保存学期失败，请重试');
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{isCreating ? '新建学期' : '编辑学期信息'}</DialogTitle>
          <DialogDescription>
            设置第 1 教学周起始日（固定定义为单周）与总教学周数，此后单双周自动交替。
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4 pt-1">
          {isCreating && availableTerms.length > 0 && (
            <div className="space-y-2">
              <label className="text-[12.5px] font-semibold text-ink">
                创建方式
              </label>
              <div className="grid grid-cols-2 gap-2.5">
                <button
                  type="button"
                  onClick={() => setCreationMode('blank')}
                  className={`h-9 px-3 rounded-control border text-[12.5px] font-medium flex items-center justify-center gap-1.5 transition-colors ${
                    creationMode === 'blank'
                      ? 'bg-selection border-primary text-primary font-semibold'
                      : 'bg-surface border-border text-ink-secondary'
                  }`}
                >
                  <Plus className="h-3.5 w-3.5" />
                  空白创建
                </button>
                <button
                  type="button"
                  onClick={() => setCreationMode('clone')}
                  className={`h-9 px-3 rounded-control border text-[12.5px] font-medium flex items-center justify-center gap-1.5 transition-colors ${
                    creationMode === 'clone'
                      ? 'bg-selection border-primary text-primary font-semibold'
                      : 'bg-surface border-border text-ink-secondary'
                  }`}
                >
                  <Copy className="h-3.5 w-3.5" />
                  复制既有学期结构与日历
                </button>
              </div>

              {creationMode === 'clone' && (
                <div className="pt-1">
                  <Select value={cloneSourceId} onValueChange={setCloneSourceId}>
                    <SelectTrigger>
                      <SelectValue placeholder="选择要复制的源学期" />
                    </SelectTrigger>
                    <SelectContent>
                      {availableTerms.map((t) => (
                        <SelectItem key={t.id} value={t.id}>
                          复制自：{t.title}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
            </div>
          )}

          <div className="space-y-1.5">
            <label className="text-[12.5px] font-semibold text-ink">
              学期名称
            </label>
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="如：2026-2027 学年第一学期"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <label className="text-[12.5px] font-semibold text-ink">
                第 1 教学周起始日
              </label>
              <DatePicker
                ariaLabel="第 1 教学周起始日"
                value={firstWeekStart}
                onChange={setFirstWeekStart}
                className="font-mono"
              />
            </div>

            <div className="space-y-1.5">
              <label className="text-[12.5px] font-semibold text-ink">
                总教学周数 (1–52)
              </label>
              <Input
                type="number"
                min={1}
                max={52}
                value={weekCountDraft}
                onChange={(e) =>
                  dispatchWeekCountDraft({
                    type: 'edit',
                    value: e.currentTarget.value,
                  })
                }
                onBlur={() =>
                  dispatchWeekCountDraft({
                    type: 'restore-empty',
                    fallback: 20,
                  })
                }
                className="font-mono"
              />
            </div>
          </div>

          <div className="space-y-1.5">
            <label className="text-[12.5px] font-semibold text-ink">
              课表周期模式
            </label>
            <div className="grid grid-cols-2 gap-2.5">
              <button
                type="button"
                onClick={() => setCycleMode('alternating')}
                className={`h-9 px-3 rounded-control border text-[12.5px] font-medium transition-colors ${
                  cycleMode === 'alternating'
                    ? 'bg-selection border-primary text-primary font-semibold'
                    : 'bg-surface border-border text-ink-secondary'
                }`}
              >
                单双周交替（第 1 周为单周）
              </button>
              <button
                type="button"
                onClick={() => setCycleMode('every_week')}
                className={`h-9 px-3 rounded-control border text-[12.5px] font-medium transition-colors ${
                  cycleMode === 'every_week'
                    ? 'bg-selection border-primary text-primary font-semibold'
                    : 'bg-surface border-border text-ink-secondary'
                }`}
              >
                每周相同
              </button>
            </div>
          </div>

          {error && (
            <div className="p-2.5 rounded-md bg-destructive-surface text-destructive text-[12px]">
              {error}
            </div>
          )}

          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onClose}>
              取消
            </Button>
            <Button type="submit">{isCreating ? '创建学期' : '保存修改'}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};

/* ============================================================================
   子组件 2：所有学期管理弹窗 (对齐 TermManagementDialog)
   ============================================================================ */
interface TermManagementModalProps {
  open: boolean;
  terms: AcademicTerm[];
  activeTermId: string;
  error: string | null;
  onClose: () => void;
  onSelect: (termId: string) => Promise<void>;
  onEdit: (term: AcademicTerm) => Promise<void>;
  onDelete: (term: AcademicTerm) => void;
  onCreate: () => void;
}

const TermManagementModal: React.FC<TermManagementModalProps> = ({
  open,
  terms,
  activeTermId,
  error,
  onClose,
  onSelect,
  onEdit,
  onDelete,
  onCreate,
}) => {
  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>所有学期管理</DialogTitle>
          <DialogDescription>
            切换当前工作学期，或对历史学期进行编辑与清理（当前使用中的学期不可直接删除）。
          </DialogDescription>
        </DialogHeader>

        {error && <p role="alert" className="text-[12px] text-destructive">{error}</p>}
        <div className="space-y-2 max-h-[340px] overflow-y-auto py-1">
          {terms.map((t) => {
            const isCurrent = t.id === activeTermId;
            return (
              <div
                key={t.id}
                className={`p-3.5 rounded-control border flex items-center justify-between gap-3 ${
                  isCurrent
                    ? 'bg-selection/60 border-primary'
                    : 'bg-surface border-border'
                }`}
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-[14px] font-semibold text-ink truncate">
                      {t.title}
                    </span>
                    {isCurrent && <Badge variant="success">当前</Badge>}
                  </div>
                  <div className="text-[12px] text-ink-secondary font-mono mt-0.5">
                    起始：{t.firstTeachingWeekStart ?? '未设'} · {t.teachingWeekCount} 周
                  </div>
                </div>

                <div className="flex items-center gap-1.5 shrink-0">
                  {!isCurrent && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => void onSelect(t.id)}
                    >
                      切换至此学期
                    </Button>
                  )}
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => void onEdit(t)}
                  >
                    编辑
                  </Button>
                  {!isCurrent && (
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-destructive hover:text-destructive"
                      onClick={() => onDelete(t)}
                      title="删除此学期"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        <DialogFooter className="flex items-center justify-between sm:justify-between">
          <Button type="button" variant="outline" onClick={onCreate}>
            <Plus className="h-4 w-4" />
            新建学期
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            关闭
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

/* ============================================================================
   子组件 3：按教学周编辑停课区间与补课原课表映射弹窗 (对齐 ExceptionEditorDialog)
   ============================================================================ */
interface WeekExceptionEditorModalProps {
  open: boolean;
  term: AcademicTerm;
  weekNumber: number;
  initialDate: string | null;
  allExceptions: CalendarException[];
  onClose: () => void;
  onSave: (upserts: CalendarException[], deleteIds: string[]) => Promise<void>;
}

const WeekExceptionEditorModal: React.FC<WeekExceptionEditorModalProps> = ({
  open,
  term,
  weekNumber,
  initialDate,
  allExceptions,
  onClose,
  onSave,
}) => {
  const weekStart = getTeachingWeekStart(term, weekNumber);
  const weekEnd = getTeachingWeekEnd(term, weekNumber);
  const weekStartYmd = weekStart ? formatDateYmd(weekStart) : '';
  const weekEndYmd = weekEnd ? formatDateYmd(weekEnd) : '';

  const termStartYmd = weekStart ? formatDateYmd(getTeachingWeekStart(term, 1)!) : '';
  const termEndYmd = weekEnd
    ? formatDateYmd(getTeachingWeekEnd(term, term.teachingWeekCount)!)
    : '';

  const existingInWeek = useMemo(
    () =>
      allExceptions.filter(
        (ex) => getTeachingWeekOfDate(term, ex.date) === weekNumber
      ),
    [allExceptions, term, weekNumber]
  );

  const [drafts, setDrafts] = useState<CalendarException[]>([]);
  const [kind, setKind] = useState<'makeup' | 'holiday'>('makeup');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [makeupDate, setMakeupDate] = useState('');
  const [makeupForDate, setMakeupForDate] = useState('');
  const [note, setNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [editingRange, setEditingRange] = useState<CalendarExceptionRange | null>(null);
  const [formDirty, setFormDirty] = useState(false);

  useEffect(() => {
    if (!open) return;
    setDrafts(existingInWeek);
    const defaultD = initialDate ?? weekStartYmd;
    setStartDate(defaultD);
    setEndDate(defaultD);
    setMakeupDate(defaultD);
    setMakeupForDate('');
    setNote('');
    setError(null);
    setEditingRange(null);
    setFormDirty(false);
  }, [open, existingInWeek, initialDate, weekStartYmd]);

  const ranges = useMemo(
    () => getExceptionRangesForWeek(term, weekNumber, drafts),
    [term, weekNumber, drafts]
  );

  const handleAddRangeToDraft = (): CalendarException[] | null => {
    setError(null);
    const eventDates: string[] = [];

    if (kind === 'holiday') {
      if (!startDate || !endDate || startDate > endDate) {
        setError('停课结束日期不能早于开始日期');
        return null;
      }
      const cur = parseLocalDate(startDate);
      const last = parseLocalDate(endDate);
      while (cur <= last) {
        const ymd = formatDateYmd(cur);
        if (getTeachingWeekOfDate(term, ymd) !== weekNumber) {
          setError('停课区间必须位于当前第 ' + weekNumber + ' 教学周内');
          return null;
        }
        eventDates.push(ymd);
        cur.setDate(cur.getDate() + 1);
      }
    } else {
      if (!makeupDate || getTeachingWeekOfDate(term, makeupDate) !== weekNumber) {
        setError('补课日期必须位于当前第 ' + weekNumber + ' 教学周内');
        return null;
      }
      if (!makeupForDate || getTeachingWeekOfDate(term, makeupForDate) === null) {
        setError('请选择本学期内被补的原课日期');
        return null;
      }
      eventDates.push(makeupDate);
    }

    const dateSet = new Set(eventDates);
    const editingIds = new Set(editingRange?.exceptions.map((item) => item.id) ?? []);
    const remaining = drafts.filter((item) => !editingIds.has(item.id));
    if (remaining.some((item) => dateSet.has(item.date))) {
      setError('同一天只能设置一条例外，请调整日期范围');
      return null;
    }
    const oldByDate = new Map(
      editingRange?.exceptions.map((item) => [item.date, item] as const) ?? []
    );

    const added: CalendarException[] = eventDates.map((d, idx) => ({
      id: oldByDate.get(d)?.id ?? `cal_${term.id}_${d}_${Date.now()}_${idx}`,
      termId: term.id,
      date: d,
      kind,
      makeupWeekday: kind === 'makeup' ? getIsoWeekday(makeupForDate) : null,
      makeupForDate: kind === 'makeup' ? makeupForDate : null,
      note: note.trim(),
    }));

    const nextDrafts = [...remaining, ...added].sort((a, b) => a.date.localeCompare(b.date));
    setDrafts(nextDrafts);
    setEditingRange(null);
    setFormDirty(false);
    setNote('');
    return nextDrafts;
  };

  const handleRemoveRange = (range: CalendarExceptionRange) => {
    const removeIds = new Set(range.exceptions.map((e) => e.id));
    setDrafts(drafts.filter((d) => !removeIds.has(d.id)));
    if (editingRange?.id === range.id) {
      setEditingRange(null);
      setFormDirty(false);
    }
  };

  const handleSaveAll = async () => {
    const nextDrafts = formDirty ? handleAddRangeToDraft() : drafts;
    if (!nextDrafts) return;
    const origIds = new Set(existingInWeek.map((e) => e.id));
    const draftIds = new Set(nextDrafts.map((d) => d.id));
    const deleteIds = Array.from(origIds).filter((id) => !draftIds.has(id));
    try {
      await onSave(nextDrafts, deleteIds);
    } catch (error) {
      setError(error instanceof Error ? error.message : '保存日历例外失败');
    }
  };

  const makeupTargetWeek = makeupForDate
    ? getTeachingWeekOfDate(term, makeupForDate)
    : null;

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <DialogTitle>
            编辑教学周例外 · 第 {weekNumber} 周（{getWeekCycleLabel(term, weekNumber)}）
          </DialogTitle>
          <DialogDescription>
            本周范围：{weekStart ? formatDateMd(weekStart) : ''} –{' '}
            {weekEnd ? formatDateMd(weekEnd) : ''}。停课日不排课；补课日明确映射采用哪一天、哪一周的课表。
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {/* 当前周已添加的例外胶囊列表 */}
          <div>
            <div className="text-[12px] font-semibold text-ink-secondary mb-2">
              本周已配置的例外安排
            </div>
            {ranges.length === 0 ? (
              <div className="p-3 rounded-control bg-canvas text-[12px] text-ink-secondary">
                本周暂无停课或补课安排。
              </div>
            ) : (
              <div className="flex flex-wrap gap-2">
                {ranges.map((r) => (
                  <div
                    key={r.id}
                    className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md text-[12px] font-medium ${
                      r.kind === 'makeup'
                        ? 'bg-warning-surface text-warning'
                        : 'bg-destructive-surface text-destructive'
                    }`}
                  >
                    <span>{formatExceptionRangeLabel(term, r)}</span>
                    <button
                      type="button"
                      onClick={() => {
                        setEditingRange(r);
                        setKind(r.kind);
                        setStartDate(r.startDate);
                        setEndDate(r.endDate);
                        setMakeupDate(r.startDate);
                        setMakeupForDate(r.exceptions[0]?.makeupForDate ?? '');
                        setNote(r.note);
                        setFormDirty(true);
                        setError(null);
                      }}
                      className="p-0.5 hover:opacity-75"
                      title="编辑此例外"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                    <button
                      type="button"
                      onClick={() => handleRemoveRange(r)}
                      className="p-0.5 hover:opacity-75"
                      title="移除此例外"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* 新增/覆盖本周例外表单 */}
          <div className="p-4 rounded-control bg-table-header border border-table-divider space-y-3.5">
            <div className="flex items-center gap-4">
              <span className="text-[12.5px] font-semibold text-ink w-16">
                例外类型
              </span>
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  size="sm"
                  variant={kind === 'holiday' ? 'default' : 'outline'}
                  onClick={() => {
                    setKind('holiday');
                    setFormDirty(true);
                  }}
                >
                  停课 / 节假日
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={kind === 'makeup' ? 'default' : 'outline'}
                  onClick={() => {
                    setKind('makeup');
                    setFormDirty(true);
                  }}
                >
                  补课（映射原课表）
                </Button>
              </div>
            </div>

            {kind === 'holiday' ? (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <label className="text-[12px] text-ink-secondary">
                      停课开始日期
                    </label>
                    <DatePicker
                      ariaLabel="停课开始日期"
                      min={weekStartYmd}
                      max={weekEndYmd}
                      value={startDate}
                      onChange={(value) => {
                        setStartDate(value);
                        setFormDirty(true);
                      }}
                      className="bg-surface font-mono"
                    />
                  </div>
                  <div className="space-y-1">
                    <label className="text-[12px] text-ink-secondary">
                      停课结束日期
                    </label>
                    <DatePicker
                      ariaLabel="停课结束日期"
                      min={weekStartYmd}
                      max={weekEndYmd}
                      value={endDate}
                      onChange={(value) => {
                        setEndDate(value);
                        setFormDirty(true);
                      }}
                      className="bg-surface font-mono"
                    />
                  </div>
                </div>
                <div className="space-y-1">
                  <label className="text-[12px] text-ink-secondary">
                    节假日 / 停课说明（选填）
                  </label>
                  <Input
                    value={note}
                    onChange={(e) => {
                      setNote(e.target.value);
                      setFormDirty(true);
                    }}
                    placeholder="例如：国庆节假期、运动会停课"
                    className="bg-surface"
                  />
                </div>
              </>
            ) : (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <label className="text-[12px] text-ink-secondary">
                      本周补课日期
                    </label>
                    <DatePicker
                      ariaLabel="本周补课日期"
                      min={weekStartYmd}
                      max={weekEndYmd}
                      value={makeupDate}
                      onChange={(value) => {
                        setMakeupDate(value);
                        setFormDirty(true);
                      }}
                      className="bg-surface font-mono"
                    />
                  </div>
                  <div className="space-y-1">
                    <label className="text-[12px] text-ink-secondary">
                      采用哪一天的原课表
                    </label>
                    <DatePicker
                      ariaLabel="补课对应的原课表日期"
                      min={termStartYmd}
                      max={termEndYmd}
                      value={makeupForDate}
                      onChange={(value) => {
                        setMakeupForDate(value);
                        setFormDirty(true);
                      }}
                      className="bg-surface font-mono"
                    />
                  </div>
                </div>
                {makeupForDate && (
                  <div className="text-[12px] text-primary font-medium">
                    映射预览：{formatDateMd(makeupDate)} 将执行{' '}
                    {formatDateMd(makeupForDate)}（周
                    {WEEKDAY_SHORT_NAMES[getIsoWeekday(makeupForDate) - 1]} ·{' '}
                    {makeupTargetWeek
                      ? `第${makeupTargetWeek}周${getWeekCycleLabel(
                          term,
                          makeupTargetWeek
                        )}`
                      : '本学期'}
                    课表）
                  </div>
                )}
                <div className="space-y-1">
                  <label className="text-[12px] text-ink-secondary">
                    补课说明（选填）
                  </label>
                  <Input
                    value={note}
                    onChange={(e) => {
                      setNote(e.target.value);
                      setFormDirty(true);
                    }}
                    className="bg-surface"
                  />
                </div>
              </>
            )}

            {error && (
              <div className="text-[12px] text-destructive font-medium">
                {error}
              </div>
            )}

            <div className="flex justify-end">
              <Button
                type="button"
                variant="secondary"
                size="sm"
                onClick={handleAddRangeToDraft}
              >
                <Plus className="h-3.5 w-3.5" />
                {editingRange ? '更新本周例外' : '加入本周例外清单'}
              </Button>
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button type="button" variant="ghost" onClick={onClose}>
            取消
          </Button>
          <Button type="button" onClick={() => void handleSaveAll()}>
            保存本周例外
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
