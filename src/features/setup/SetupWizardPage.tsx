import React, { useReducer, useState } from 'react';
import {
  AlertCircle,
  ArrowLeftRight,
  CalendarDays,
  Check,
  Repeat,
  Upload,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DatePicker } from '@/components/ui/date-picker';
import { Input } from '@/components/ui/input';
import type { CycleMode } from '@/domain/models';
import { numericInputDraftReducer } from '@/lib/numberInput';
import { useAppStore } from '@/store/useAppStore';
import { schoolRepository } from '@/repository/schoolRepository';
import classsetMark from '../../../design/icon/classset/classset-mark.svg';
import {
  buildInitialTermFromWizard,
  clampSetupWeekCount,
  getDefaultTermTitle,
  getSchoolIdentityPreview,
  getTermRangePreview,
  SCHOOL_NAME_SUGGESTIONS,
  SETUP_WIZARD_TOTAL_STEPS,
  validateSetupTermDraft,
} from './setupWizardLogic';

/**
 * 空数据创建向导：本地尚无任何学期时的全屏引导，不显示侧边栏与顶部栏。
 *
 * 两步：填写学校名称（可留空跳过）→ 创建第一个学期；完成后写入本地数据并进入系统。
 */
export const SetupWizardPage: React.FC<{ installAction?: React.ReactNode }> = ({ installAction }) => {
  const { schoolName: initialSchoolName, completeInitialSetup, reloadAfterDatabaseChange } = useAppStore();

  const [step, setStep] = useState<1 | 2>(1);
  const [slideDirection, setSlideDirection] = useState<'forward' | 'backward'>('forward');
  const [schoolName, setSchoolName] = useState<string>(initialSchoolName ?? '');
  const [termTitle, setTermTitle] = useState<string>(() => getDefaultTermTitle());
  const [firstTeachingWeekStart, setFirstTeachingWeekStart] = useState<string>('');
  const [weekCountDraft, dispatchWeekCountDraft] = useReducer(
    numericInputDraftReducer,
    '20'
  );
  const [cycleMode, setCycleMode] = useState<CycleMode>('alternating');

  const [titleError, setTitleError] = useState<string | null>(null);
  const [dateError, setDateError] = useState<string | null>(null);
  const [weekCountError, setWeekCountError] = useState<string | null>(null);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [saving, setSaving] = useState<boolean>(false);
  const [importing, setImporting] = useState<boolean>(false);
  const [importMessage, setImportMessage] = useState<string | null>(null);
  const [importError, setImportError] = useState<string | null>(null);
  const backupPicker = React.useRef<HTMLInputElement>(null);

  const handleBackupSelected = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file || importing) return;

    setImporting(true);
    setImportMessage(null);
    setImportError(null);
    try {
      await schoolRepository.importSqliteBytes(new Uint8Array(await file.arrayBuffer()));
      await reloadAfterDatabaseChange(false);
      setImportMessage('备份已导入，正在打开课集。');
    } catch (error) {
      setImportError(error instanceof Error ? `导入失败：${error.message}` : '导入失败，请重试。');
    } finally {
      setImporting(false);
    }
  };

  const identity = getSchoolIdentityPreview(schoolName);
  const termDisplay = termTitle.trim() || '新建第一个学期';
  const clampedWeeks = clampSetupWeekCount(weekCountDraft);
  const rangePreview = getTermRangePreview({
    startDate: firstTeachingWeekStart,
    weekCount: clampedWeeks,
    cycleMode,
  });

  const goToStep = (target: 1 | 2) => {
    if (saving || target === step) return;
    setSlideDirection(target > step ? 'forward' : 'backward');
    setSubmitError(null);
    setStep(target);
  };

  const handleFinish = async (event: React.FormEvent) => {
    event.preventDefault();
    if (saving) return;

    const validation = validateSetupTermDraft({
      termTitle,
      firstTeachingWeekStart,
      weekCountText: weekCountDraft,
    });
    setTitleError(validation.titleError);
    setDateError(validation.dateError);
    setWeekCountError(validation.weekCountError);
    setSubmitError(null);

    if (!validation.valid) return;

    setSaving(true);
    try {
      const term = buildInitialTermFromWizard({
        termTitle,
        firstTeachingWeekStart,
        weekCountText: weekCountDraft,
        cycleMode,
      });
      await completeInitialSetup(schoolName.trim(), term);
    } catch (error) {
      setSaving(false);
      setSubmitError(
        error instanceof Error ? `初始化保存失败：${error.message}` : '初始化保存失败，请重试'
      );
    }
  };

  const stepAnimationClass =
    slideDirection === 'forward' ? 'wizard-step-forward' : 'wizard-step-backward';

  return (
    <div
      className="min-h-screen w-full bg-canvas text-ink flex items-center justify-center p-8 overflow-y-auto"
      data-tauri-drag-region
    >
      <div className="w-full max-w-[600px] rounded-card bg-surface border border-border/70 px-8 sm:px-10 pt-[34px] pb-8 transition-[height] duration-page">
        {/* 顶部品牌栏 */}
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2.5">
            <img
              src={classsetMark}
              alt="课集 Logo"
              width={36}
              height={36}
              draggable={false}
              className="h-9 w-9 shrink-0"
            />
            <div>
              <div className="text-[16px] font-bold text-ink leading-tight">
                课集
              </div>
              <div className="text-[12px] text-ink-secondary mt-0.5">
                ClassSet.app
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {installAction}
            <input
              ref={backupPicker}
              type="file"
              accept=".sqlite,.sqlite3,.db"
              hidden
              onChange={(event) => void handleBackupSelected(event)}
            />
            <div className="flex flex-wrap items-center gap-3">
              <Button
                type="button"
                variant="secondary"
                className="h-7 shrink-0 gap-1.5 px-2.5 text-xs"
                disabled={saving || importing}
                onClick={() => backupPicker.current?.click()}
              >
                <Upload aria-hidden="true" />
                {importing ? '正在导入…' : '从备份文件导入'}
              </Button>
              {importMessage && <span role="status" className="text-sm text-ink-secondary">{importMessage}</span>}
              {importError && <span role="alert" className="text-sm text-destructive">{importError}</span>}
            </div>
          </div>
        </div>

        {/* 步骤指示条与交互式步骤卡片 */}
        <div className="mt-[22px] space-y-2.5">
          <div className="flex items-center justify-between text-[12px]">
            <span
              key={`step-label-${step}`}
              className="font-semibold text-ink-secondary app-view-enter"
            >
              初始设置 · 第 {step} 步 / 共 {SETUP_WIZARD_TOTAL_STEPS} 步
            </span>
            <span
              key={`step-desc-${step}`}
              className="text-ink-secondary app-view-enter"
            >
              {step === 1 ? '填写学校信息' : '配置学期日历'}
            </span>
          </div>

          {/* 双段进度条 */}
          <div className="grid grid-cols-2 gap-1.5">
            <div className="h-1 rounded-[3px] bg-table-header overflow-hidden">
              <div
                className={`h-full transition-all duration-page ease-out ${
                  step > 1 ? 'w-full bg-success' : 'w-full bg-primary'
                }`}
              />
            </div>
            <div className="h-1 rounded-[3px] bg-table-header overflow-hidden">
              <div
                className={`h-full bg-primary transition-all duration-page ease-out ${
                  step === 2 ? 'w-full' : 'w-0'
                }`}
              />
            </div>
          </div>

          {/* 两步交互式步骤卡 */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 pt-1">
            <button
              type="button"
              disabled={step === 1 || saving}
              onClick={() => goToStep(1)}
              className={`rounded-[12px] border px-3 py-2.5 text-left flex items-center gap-2.5 transition-all duration-page ${
                step === 1
                  ? 'bg-selection border-primary/35 cursor-default'
                  : 'bg-table-header border-success/30 hover:border-success/55 hover:bg-selection/40 cursor-pointer'
              }`}
            >
              <span
                className={`w-[22px] h-[22px] rounded-full flex items-center justify-center text-[11px] font-bold shrink-0 transition-colors duration-page ${
                  step > 1
                    ? 'bg-success text-primary-foreground'
                    : 'bg-primary text-primary-foreground'
                }`}
              >
                {step > 1 ? (
                  <Check key="step1-done" className="h-3.5 w-3.5 wizard-badge-pop" />
                ) : (
                  <span key="step1-num" className="wizard-badge-pop">
                    1
                  </span>
                )}
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[12.5px] font-semibold text-ink truncate">
                    学校信息
                  </span>
                  {step > 1 && (
                    <span className="text-[11px] font-semibold text-primary shrink-0">
                      修改
                    </span>
                  )}
                </div>
                <div
                  className={`text-[11px] truncate mt-0.5 transition-colors duration-page ${
                    step > 1 ? 'text-success' : 'text-primary'
                  }`}
                >
                  {step > 1 ? identity.displayName : '当前步骤 · 可选填'}
                </div>
              </div>
            </button>

            <div
              className={`rounded-[12px] border px-3 py-2.5 text-left flex items-center gap-2.5 transition-all duration-page ${
                step === 2
                  ? 'bg-selection border-primary/35'
                  : 'bg-table-header border-border/50'
              }`}
            >
              <span
                className={`w-[22px] h-[22px] rounded-full border flex items-center justify-center text-[11px] font-bold shrink-0 transition-colors duration-page ${
                  step === 2
                    ? 'bg-primary border-primary text-primary-foreground'
                    : 'bg-surface border-border text-ink-secondary'
                }`}
              >
                <span key={`step2-${step}`} className="wizard-badge-pop">
                  2
                </span>
              </span>
              <div className="min-w-0 flex-1">
                <div
                  className={`text-[12.5px] truncate transition-colors duration-page ${
                    step === 2
                      ? 'font-semibold text-ink'
                      : 'font-medium text-ink-secondary'
                  }`}
                >
                  第一个学期
                </div>
                <div
                  className={`text-[11px] truncate mt-0.5 transition-colors duration-page ${
                    step === 2 ? 'text-primary' : 'text-ink-secondary'
                  }`}
                >
                  {step === 2 ? termDisplay : '完成第 1 步后继续'}
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* 步骤主体内容（带方向感知滑入淡入过渡） */}
        <div className="mt-6 -mx-1 overflow-hidden px-1">
          {step === 1 ? (
            <form
              key="setup-wizard-school-step"
              onSubmit={(event) => {
                event.preventDefault();
                goToStep(2);
              }}
              className={`space-y-5 ${stepAnimationClass}`}
            >
              <div>
                <h1 className="text-[28px] font-semibold text-ink leading-[1.25]">
                  欢迎使用课集
                </h1>
                <p className="mt-2 text-[14px] text-ink-secondary leading-relaxed">
                  先告诉课集你的学校名称。也可以留空，稍后在左侧学校卡中补填。
                </p>
              </div>

              {/* 实时学校名片预览 */}
              <div
                className={`rounded-[14px] border px-3.5 py-3 flex items-center gap-3 transition-colors duration-feedback ${
                  identity.hasCustomName
                    ? 'bg-canvas border-primary/30'
                    : 'bg-canvas border-border'
                }`}
              >
                <div
                  className={`w-[38px] h-[38px] rounded-[11px] flex items-center justify-center text-[15px] font-bold shrink-0 transition-colors duration-feedback ${
                    identity.hasCustomName
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-selection text-primary'
                  }`}
                >
                  <span
                    key={`${identity.initial}-${identity.hasCustomName}`}
                    className="wizard-badge-pop"
                  >
                    {identity.initial}
                  </span>
                </div>
                <div className="min-w-0 flex-1">
                  <div
                    className={`text-[14px] font-semibold truncate transition-colors duration-feedback ${
                      identity.hasCustomName ? 'text-ink' : 'text-ink-secondary'
                    }`}
                  >
                    {identity.displayName}
                  </div>
                  <div className="text-[12px] text-ink-secondary truncate mt-0.5">
                    {termDisplay} · 侧栏学校卡预览
                  </div>
                </div>
                <Badge
                  variant={identity.hasCustomName ? 'default' : 'secondary'}
                  className="text-[11px] shrink-0"
                >
                  {identity.hasCustomName ? '已填写' : '默认占位'}
                </Badge>
              </div>

              {/* 学校名称输入与快捷示例 */}
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  <label
                    htmlFor="wizard-school-name"
                    className="text-[13.5px] font-semibold text-ink"
                  >
                    学校名称
                  </label>
                  <Badge variant="secondary" className="text-[11px]">
                    选填
                  </Badge>
                </div>

                <Input
                  id="wizard-school-name"
                  autoFocus
                  value={schoolName}
                  onChange={(event) => setSchoolName(event.currentTarget.value)}
                  placeholder="如：阳光实验小学"
                />

                <div className="flex flex-wrap items-center gap-2 pt-1">
                  <span className="text-[12px] text-ink-secondary">
                    快捷示例：
                  </span>
                  {SCHOOL_NAME_SUGGESTIONS.map((item) => {
                    const selected = schoolName.trim() === item;
                    return (
                      <button
                        key={item}
                        type="button"
                        onClick={() => setSchoolName(item)}
                        className={`px-2.5 py-1 rounded-[8px] border text-[12px] transition-colors duration-feedback ${
                          selected
                            ? 'bg-selection border-primary/45 text-primary font-semibold'
                            : 'bg-table-header border-border text-ink-secondary hover:border-control-border'
                        }`}
                      >
                        {item}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* 第 1 步底栏 */}
              <div className="pt-2 flex items-center justify-between gap-3">
                <span className="text-[12px] text-ink-secondary">
                  {identity.hasCustomName
                    ? '按回车或点击下一步继续'
                    : '可留空直接进入下一步'}
                </span>
                <Button type="submit">下一步</Button>
              </div>
            </form>
          ) : (
            <form
              key="setup-wizard-term-step"
              onSubmit={handleFinish}
              className={`space-y-4 ${stepAnimationClass}`}
            >
              <div>
                <h1 className="text-[28px] font-semibold text-ink leading-[1.25]">
                  创建第一个学期
                </h1>
                <p className="mt-2 text-[14px] text-ink-secondary leading-relaxed">
                  学期决定教学周与课表范围。新建后会自动带一个默认学段，可随时调整。
                </p>
              </div>

              {/* 学期基础字段面板 */}
              <div className="rounded-[14px] bg-canvas/65 border border-border p-[18px] space-y-3.5">
                <div className="grid grid-cols-1 sm:grid-cols-[130px_1fr] sm:items-center gap-2">
                  <label
                    htmlFor="wizard-term-title"
                    className="text-[13px] font-semibold text-ink"
                  >
                    学期名称
                  </label>
                  <div className="space-y-1">
                    <Input
                      id="wizard-term-title"
                      value={termTitle}
                      onChange={(event) => {
                        setTermTitle(event.currentTarget.value);
                        setTitleError(null);
                      }}
                      placeholder="如：2027 学年 · 春季学期"
                    />
                    {titleError && (
                      <p className="text-[12px] text-destructive">{titleError}</p>
                    )}
                  </div>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-[130px_1fr] sm:items-center gap-2">
                  <label className="text-[13px] font-semibold text-ink">
                    第 1 教学周起始
                  </label>
                  <div>
                    <DatePicker
                      ariaLabel="第 1 教学周起始"
                      placeholder="选择日期"
                      value={firstTeachingWeekStart}
                      onChange={(date) => {
                        setFirstTeachingWeekStart(date);
                        setDateError(null);
                      }}
                    />
                  </div>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-[130px_1fr] sm:items-center gap-2">
                  <label
                    htmlFor="wizard-week-count"
                    className="text-[13px] font-semibold text-ink"
                  >
                    总周数
                  </label>
                  <div className="space-y-1">
                    <Input
                      id="wizard-week-count"
                      type="number"
                      min={1}
                      max={52}
                      value={weekCountDraft}
                      onChange={(event) => {
                        dispatchWeekCountDraft({
                          type: 'edit',
                          value: event.currentTarget.value,
                        });
                        setWeekCountError(null);
                      }}
                      onBlur={() =>
                        dispatchWeekCountDraft({
                          type: 'restore-empty',
                          fallback: 20,
                        })
                      }
                      className="font-mono"
                    />
                    {weekCountError && (
                      <p className="text-[12px] text-destructive">
                        {weekCountError}
                      </p>
                    )}
                  </div>
                </div>
              </div>

              {/* 课表周期可视化选择卡 */}
              <div className="space-y-2">
                <div>
                  <div className="text-[13px] font-semibold text-ink">
                    课表周期
                  </div>
                  <p className="text-[12px] text-ink-secondary mt-0.5">
                    单双周交替时第 1 教学周固定为单周；每周相同则所有周使用同一套周课表。
                  </p>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                  <button
                    type="button"
                    aria-pressed={cycleMode === 'every_week'}
                    onClick={() => setCycleMode('every_week')}
                    className={`rounded-[12px] border p-3 text-left transition-colors duration-feedback ${
                      cycleMode === 'every_week'
                        ? 'bg-selection border-primary'
                        : 'bg-table-header border-border hover:border-control-border'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <span
                          className={`w-4 h-4 rounded-full border flex items-center justify-center ${
                            cycleMode === 'every_week'
                              ? 'border-primary'
                              : 'border-control-border'
                          }`}
                        >
                          {cycleMode === 'every_week' && (
                            <span className="w-2 h-2 rounded-full bg-primary" />
                          )}
                        </span>
                        <span className="text-[13px] font-semibold text-ink">
                          每周相同
                        </span>
                      </div>
                      <Repeat
                        className={`h-4 w-4 ${
                          cycleMode === 'every_week'
                            ? 'text-primary'
                            : 'text-ink-secondary'
                        }`}
                      />
                    </div>
                    <p className="mt-1.5 text-[11.5px] text-ink-secondary leading-relaxed">
                      所有教学周共用同一套周课表
                    </p>
                  </button>

                  <button
                    type="button"
                    aria-pressed={cycleMode === 'alternating'}
                    onClick={() => setCycleMode('alternating')}
                    className={`rounded-[12px] border p-3 text-left transition-colors duration-feedback ${
                      cycleMode === 'alternating'
                        ? 'bg-selection border-primary'
                        : 'bg-table-header border-border hover:border-control-border'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <span
                          className={`w-4 h-4 rounded-full border flex items-center justify-center ${
                            cycleMode === 'alternating'
                              ? 'border-primary'
                              : 'border-control-border'
                          }`}
                        >
                          {cycleMode === 'alternating' && (
                            <span className="w-2 h-2 rounded-full bg-primary" />
                          )}
                        </span>
                        <span className="text-[13px] font-semibold text-ink">
                          单双周交替
                        </span>
                      </div>
                      <ArrowLeftRight
                        className={`h-4 w-4 ${
                          cycleMode === 'alternating'
                            ? 'text-primary'
                            : 'text-ink-secondary'
                        }`}
                      />
                    </div>
                    <p className="mt-1.5 text-[11.5px] text-ink-secondary leading-relaxed">
                      第 1 周为单周，单双周按周次自动轮换
                    </p>
                  </button>
                </div>
              </div>

              {/* 教学周历实时预览条 */}
              <div
                className={`rounded-[12px] border px-3.5 py-3 flex items-center gap-3 transition-colors duration-feedback ${
                  rangePreview.hasDate
                    ? 'bg-selection border-primary/25'
                    : 'bg-table-header border-border'
                }`}
              >
                <div
                  className={`w-8 h-8 rounded-[9px] flex items-center justify-center shrink-0 transition-colors duration-feedback ${
                    rangePreview.hasDate
                      ? 'bg-surface text-primary'
                      : 'bg-canvas text-ink-secondary'
                  }`}
                >
                  <CalendarDays className="h-4 w-4" />
                </div>
                <div className="min-w-0 flex-1">
                  <div
                    key={`${firstTeachingWeekStart}-${clampedWeeks}`}
                    className={`text-[12.5px] font-semibold tabular-nums truncate app-view-enter ${
                      rangePreview.hasDate ? 'text-ink' : 'text-ink-secondary'
                    }`}
                  >
                    {rangePreview.rangeLabel}
                  </div>
                  <div className="text-[11.5px] text-ink-secondary tabular-nums truncate mt-0.5">
                    {rangePreview.summaryLabel}
                  </div>
                </div>
              </div>

              {/* 错误提示条 */}
              {(dateError || submitError) && (
                <div
                  role="alert"
                  className="rounded-[10px] bg-destructive-surface border border-destructive/35 px-3 py-2.5 flex items-center gap-2 text-[12px] font-medium text-destructive app-view-enter"
                >
                  <AlertCircle className="h-4 w-4 shrink-0" />
                  <span>{dateError ?? submitError}</span>
                </div>
              )}

              {/* 第 2 步底栏 */}
              <div className="pt-3 flex items-center justify-between gap-3">
                <Button
                  type="button"
                  variant="secondary"
                  disabled={saving}
                  onClick={() => goToStep(1)}
                >
                  上一步
                </Button>
                <Button type="submit" disabled={saving}>
                  {saving ? '正在创建…' : '完成设置，进入工作台'}
                </Button>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
};
