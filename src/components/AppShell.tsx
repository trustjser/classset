import React, { useEffect, useRef, useState } from 'react';
import {
  ArrowLeftRight,
  Building2,
  Calculator,
  CalendarDays,
  Clock,
  LayoutDashboard,
  Lock,
  Moon,
  Network,
  Palette,
  PanelLeftClose,
  PanelLeftOpen,
  Sparkles,
  Sun,
  SunMoon,
  UserCheck,
  Users,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { getNavSectionAvailability } from '@/domain/models';
import type { AppSection, TemporaryCourseAdjustment } from '@/domain/models';
import { ClassesPage } from '@/features/classes/ClassesPage';
import { RoutinesPage } from '@/features/routines/RoutinesPage';
import { SubjectsPage } from '@/features/subjects/SubjectsPage';
import { TeachersPage } from '@/features/teachers/TeachersPage';
import { TermPage } from '@/features/terms/TermPage';
import { SchedulingPage } from '@/features/scheduling/SchedulingPage';
import { WorkbenchPage } from '@/features/workbench/WorkbenchPage';
import { seedDemoData } from '@/features/workbench/demoData';
import { SCHEMA_VERSION } from '@/adapter/db/schemaV19';
import { useAppStore } from '@/store/useAppStore';
import { schoolRepository } from '@/repository/schoolRepository';
import { PALETTE_OPTIONS } from '@/styles/subjectColors';
import classsetMark from '../../design/icon/classset/classset-mark.svg';
import { AppearanceDialog } from './AppearanceDialog';
import { SchoolNameDialog } from './SchoolNameDialog';

interface NavEntry {
  section: AppSection;
  label: string;
  group: 'root' | 'basic' | 'prep' | 'schedule';
  icon: React.ComponentType<{ className?: string }>;
  badge?: string;
}

const NAV_ITEMS: NavEntry[] = [
  { section: 'workbench', label: '工作台', group: 'root', icon: LayoutDashboard },
  { section: 'terms', label: '学期与日历', group: 'basic', icon: CalendarDays },
  { section: 'classes', label: '班级与学段', group: 'basic', icon: Network },
  { section: 'routines', label: '作息设置', group: 'basic', icon: Clock, badge: '分学段' },
  { section: 'publicRooms', label: '公共场室', group: 'basic', icon: Building2 },
  { section: 'subjects', label: '科目节数', group: 'prep', icon: Calculator },
  { section: 'teachers', label: '教师任课', group: 'prep', icon: UserCheck },
  { section: 'scheduling', label: '排课与课表', group: 'schedule', icon: Sparkles },
  { section: 'supervision', label: '带班安排', group: 'schedule', icon: Users },
  {
    section: 'temporaryAdjustments',
    label: '调代课',
    group: 'schedule',
    icon: ArrowLeftRight,
  },
];

const TemporaryAdjustmentsPage: React.FC<{
  adjustments: TemporaryCourseAdjustment[];
}> = ({ adjustments }) => (
  <section className="space-y-4">
    <p className="text-[13px] leading-5 text-ink-secondary">
      按自然日查看正课调代与带班替班，不按当前教学周翻页。
      <span className="ml-2 tabular-nums">共 {adjustments.length} 条</span>
    </p>

    {adjustments.length === 0 ? (
      <div className="py-10 text-center" role="status">
        <p className="text-[15px] font-medium text-ink">暂无课务调整记录</p>
        <p className="mt-1 text-[13.5px] text-ink-secondary">
          生成课表并进行调代课后，记录会显示在这里。
        </p>
      </div>
    ) : (
      <ol className="divide-y divide-table-divider">
        {adjustments.map((adjustment) => {
          let parsed: { summary?: string; date?: string } = {};
          try {
            parsed = JSON.parse(adjustment.changesJson);
          } catch {
            // Keep the original change description visible if older data is malformed.
          }

          return (
            <li
              className="flex flex-wrap items-center justify-between gap-4 py-4"
              key={adjustment.id}
            >
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="default">
                    {adjustment.kind === 'swap' ? '正课互换' : '带班替班'}
                  </Badge>
                  <span className="text-[14px] font-semibold text-ink">
                    {parsed.summary ?? adjustment.changesJson}
                  </span>
                </div>
                <p className="mt-1 text-[12.5px] leading-5 text-ink-secondary">
                  原因：{adjustment.reason} · 自然日：{parsed.date ?? '本学期'}
                </p>
              </div>
              <Badge
                variant={adjustment.cancelledAt === null ? 'success' : 'secondary'}
              >
                {adjustment.cancelledAt === null ? '生效中' : '已撤销'}
              </Badge>
            </li>
          );
        })}
      </ol>
    )}
  </section>
);

const PendingModulePage: React.FC<{
  onBackToWorkbench: () => void;
}> = ({ onBackToWorkbench }) => (
  <section className="max-w-3xl">
    <p className="text-[14px] leading-6 text-ink-secondary">
      这个模块正在接入新的课务工作区，目前不会在这里修改数据。你可以先在工作台查看本学期的准备进度。
    </p>
    <Button
      className="mt-5"
      onClick={onBackToWorkbench}
      type="button"
      variant="outline"
    >
      <LayoutDashboard aria-hidden="true" className="h-4 w-4" />
      返回工作台
    </Button>
  </section>
);

export const AppShell: React.FC = () => {
  const {
    runtimeMode,
    palette,
    mode,
    resolvedDark,
    sidebarExpanded,
    selectedSection,
    schoolName,
    activeTermId,
    terms,
    adjustments,
    summary,
    lastPersistedAt,
    setPalette,
    setMode,
    cycleThemeMode,
    setSidebarExpanded,
    toggleSidebar,
    setSelectedSection,
    updateSchoolName,
  } = useAppStore();

  const mainRef = useRef<HTMLElement>(null);
  const previousSection = useRef(selectedSection);

  useEffect(() => {
    const syncSectionFromLocation = () => {
      const route = window.location.hash
        .slice(1)
        .split('/')
        .filter(Boolean)[0];
      const destination = NAV_ITEMS.find((item) => item.section === route);
      if (destination) {
        if (destination.section !== useAppStore.getState().selectedSection) {
          setSelectedSection(destination.section);
        }
      } else {
        setSelectedSection('workbench');
      }
    };

    syncSectionFromLocation();
    window.addEventListener('hashchange', syncSectionFromLocation);
    return () =>
      window.removeEventListener('hashchange', syncSectionFromLocation);
  }, [setSelectedSection]);

  const autoCollapsedRef = useRef(false);

  useEffect(() => {
    if (typeof window === 'undefined' || !window.matchMedia) return;
    const mql = window.matchMedia('(max-width: 1079px)');
    const applyBreakpoint = (narrow: boolean) => {
      const expanded = useAppStore.getState().sidebarExpanded;
      if (narrow) {
        if (expanded) {
          autoCollapsedRef.current = true;
          setSidebarExpanded(false);
        }
      } else if (autoCollapsedRef.current) {
        autoCollapsedRef.current = false;
        setSidebarExpanded(true);
      }
    };
    applyBreakpoint(mql.matches);
    const onChange = (event: MediaQueryListEvent) => applyBreakpoint(event.matches);
    mql.addEventListener('change', onChange);
    return () => mql.removeEventListener('change', onChange);
  }, [setSidebarExpanded]);

  useEffect(() => {
    if (previousSection.current === selectedSection) return;
    previousSection.current = selectedSection;
    mainRef.current?.focus({ preventScroll: true });
  }, [selectedSection]);

  const [appearanceOpen, setAppearanceOpen] = useState(false);
  const [schoolNameDialogOpen, setSchoolNameDialogOpen] = useState(false);
  const schoolDisplayName = schoolName.trim() || '未命名学校';

  const activeTerm = terms.find((t) => t.id === activeTermId) ?? null;
  const activePaletteMeta =
    PALETTE_OPTIONS.find((p) => p.id === palette) ?? PALETTE_OPTIONS[0];
  const currentNav =
    NAV_ITEMS.find((n) => n.section === selectedSection) ?? NAV_ITEMS[0];

  const savedTimeText = lastPersistedAt
    ? `${String(lastPersistedAt.getHours()).padStart(2, '0')}:${String(
        lastPersistedAt.getMinutes()
      ).padStart(2, '0')}`
    : '--:--';

  const ModeIcon = mode === 'system' ? SunMoon : mode === 'dark' ? Moon : Sun;
  const handleSaveSchoolName = async (name: string) => {
    if (name !== schoolName.trim()) await updateSchoolName(name);
    setSchoolNameDialogOpen(false);
  };
  const isMacOS =
    typeof navigator !== 'undefined' &&
    (/Macintosh|Mac OS X/i.test(navigator.userAgent) ||
      /Mac/i.test(navigator.platform));
  const isWindows =
    typeof navigator !== 'undefined' &&
    (/Windows/i.test(navigator.userAgent) || /Win/i.test(navigator.platform));

  const renderNavButton = (item: NavEntry) => {
    const availability = getNavSectionAvailability(
      item.section,
      activeTermId !== null,
      summary
    );
    const isSelected = selectedSection === item.section;
    const disabled = !availability.enabled;
    const Icon = item.icon;

    const btn = (
      <button
        key={item.section}
        type="button"
        disabled={disabled}
        onClick={() => !disabled && setSelectedSection(item.section)}
        aria-current={isSelected ? 'page' : undefined}
        aria-label={item.label}
        className={`w-full h-11 px-3 rounded-[10px] flex items-center ${
          sidebarExpanded ? 'justify-between' : 'justify-center'
        } text-[13.5px] transition-colors duration-feedback ${
          disabled
            ? 'opacity-45 cursor-not-allowed text-sidebar-muted'
            : isSelected
            ? 'bg-sidebar-active text-primary font-semibold'
            : 'text-sidebar-text hover:bg-table-header hover:text-ink font-medium'
        }`}
      >
        <div className="flex items-center gap-2.5 min-w-0">
          <Icon className="h-[17px] w-[17px] shrink-0" />
          {sidebarExpanded && <span className="truncate">{item.label}</span>}
        </div>
        {sidebarExpanded && item.badge && !disabled && (
          <Badge variant="outline" className="bg-surface text-ink-secondary">
            {item.badge}
          </Badge>
        )}
        {sidebarExpanded && disabled && (
          <Lock className="h-3.5 w-3.5 text-ink-secondary shrink-0" />
        )}
      </button>
    );

    if (disabled || !sidebarExpanded) {
      return (
        <Tooltip key={item.section}>
          <TooltipTrigger asChild>
            <span className="block">{btn}</span>
          </TooltipTrigger>
          <TooltipContent side="right">
            {disabled ? availability.reason ?? '请先完成前置步骤' : item.label}
          </TooltipContent>
        </Tooltip>
      );
    }

    return btn;
  };

  return (
    <TooltipProvider delayDuration={150}>
      <div
        className={`app-shell-frame flex bg-canvas text-ink ${
          runtimeMode === 'tauri-desktop' && isMacOS ? 'tauri-macos' : ''
        } ${isWindows ? 'windows-scrollbars' : ''}`}
      >
        {/* 左侧导航保留全部业务步骤，内容区独立滚动，底部状态始终可见。 */}
        <aside
          className={`app-sidebar shrink-0 bg-surface flex flex-col transition-[width,padding] duration-page ${
            sidebarExpanded ? 'w-[244px] px-4 py-4' : 'w-[70px] px-2 py-3'
          }`}
          data-expanded={sidebarExpanded}
        >
          <div className="app-sidebar-scroll">
            {/* 品牌区 */}
            <div
              className={`app-sidebar-brand flex items-center ${
                sidebarExpanded ? 'justify-start gap-2.5 px-1' : 'justify-center'
              } pb-4`}
            >
              <img
                src={classsetMark}
                alt="课集 Logo"
                width={36}
                height={36}
                draggable={false}
                className="h-9 w-9 shrink-0"
              />
              {sidebarExpanded && (
                <div>
                  <div className="text-[16px] font-bold text-ink leading-tight">
                    课集
                  </div>
                  <div className="text-[12px] text-ink-secondary">ClassSet.app</div>
                </div>
              )}
            </div>

            {/* 学校与当前学期标识卡 */}
            <div className="mb-3">
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    type="button"
                    aria-label={`${schoolDisplayName}，编辑学校名称`}
                    onClick={() => setSchoolNameDialogOpen(true)}
                    className={`w-full rounded-control bg-canvas hover:bg-table-header border border-transparent hover:border-border flex items-center text-left transition-colors duration-feedback ${
                      sidebarExpanded
                        ? 'p-2.5 gap-2.5'
                        : 'justify-center p-1'
                    }`}
                  >
                    <div className="w-8 h-8 rounded-[9px] bg-selection text-primary font-bold text-[12px] flex items-center justify-center shrink-0">
                      {schoolDisplayName.slice(0, 1)}
                    </div>
                    {sidebarExpanded && (
                      <div className="min-w-0 flex-1">
                        <div className="text-[13px] font-semibold text-ink truncate">
                          {schoolDisplayName}
                        </div>
                        <div className="text-[12px] text-ink-secondary truncate mt-0.5">
                          {activeTerm?.title ?? '当前学期'}
                        </div>
                      </div>
                    )}
                  </button>
                </TooltipTrigger>
                <TooltipContent side="right">编辑学校名称</TooltipContent>
              </Tooltip>
            </div>

            {/* 级联导航菜单 */}
            <nav aria-label="主导航" className="app-sidebar-nav space-y-1">
              {NAV_ITEMS.filter((i) => i.group === 'root').map(renderNavButton)}

              {sidebarExpanded && (
                <div className="pt-3 pb-1 text-[12px] font-semibold text-ink-secondary">
                  基础设置
                </div>
              )}
              {NAV_ITEMS.filter((i) => i.group === 'basic').map(renderNavButton)}

              <Separator className="my-2" />
              {sidebarExpanded && (
                <div className="pt-1 pb-1 text-[12px] font-semibold text-ink-secondary">
                  排课准备
                </div>
              )}
              {NAV_ITEMS.filter((i) => i.group === 'prep').map(renderNavButton)}

              <Separator className="my-2" />
              {sidebarExpanded && (
                <div className="pt-1 pb-1 text-[12px] font-semibold text-ink-secondary">
                  课表与课务
                </div>
              )}
              {NAV_ITEMS.filter((i) => i.group === 'schedule').map(renderNavButton)}
            </nav>
          </div>

          {/* 底部本地 SQLite 持久化状态指示卡 */}
          {sidebarExpanded && (
            <div className="app-sidebar-status mt-3 px-2.5 py-2.5 rounded-[10px] bg-canvas flex items-center gap-2.5">
              <span className="w-2.5 h-2.5 rounded-full bg-success shrink-0" />
              <div className="min-w-0">
                <div className="text-[12px] font-semibold text-ink truncate">
                  本地数据 · 离线可用
                </div>
                <div className="text-[12px] text-ink-secondary truncate">
                  Schema v{SCHEMA_VERSION} · 最近保存 {savedTimeText}
                </div>
              </div>
            </div>
          )}
        </aside>

        {/* 右侧主内容区 */}
        <div className="app-work-area flex-1 flex flex-col min-w-0">
          {/* 全局上下文与外观操作保持单行，窄窗口隐藏次要运行信息。 */}
          <header
            className="app-top-bar px-4 bg-surface shrink-0"
            data-tauri-drag-region
          >
            <div className="app-toolbar-leading" data-tauri-drag-region>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    onClick={() => {
                      autoCollapsedRef.current = false;
                      toggleSidebar();
                    }}
                    aria-label={sidebarExpanded ? '收起侧边栏' : '展开侧边栏'}
                    className="h-9 w-9 shrink-0"
                  >
                    {sidebarExpanded ? (
                      <PanelLeftClose className="h-4 w-4" />
                    ) : (
                      <PanelLeftOpen className="h-4 w-4" />
                    )}
                  </Button>
                </TooltipTrigger>
                <TooltipContent>
                  {sidebarExpanded ? '收起侧边栏' : '展开侧边栏'}
                </TooltipContent>
              </Tooltip>

              <span
                className="app-toolbar-page text-[14px] font-semibold text-ink"
                data-tauri-drag-region
              >
                {currentNav.label}
              </span>

              <span
                className="app-term-context"
                data-tauri-drag-region
                aria-label={`当前学期：${activeTerm?.title ?? '未设置学期'}`}
                title={activeTerm?.title ?? '未设置学期'}
              >
                {activeTerm?.title ?? '未设置学期'}
              </span>
            </div>

            <div className="app-toolbar-actions" data-tauri-drag-region>
              <Badge
                variant="secondary"
                className="app-runtime-badge border-0 bg-transparent px-2 text-ink-secondary"
                data-tauri-drag-region
              >
                {runtimeMode === 'tauri-desktop'
                  ? '桌面端'
                  : '浏览器端'}
              </Badge>

              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() => setAppearanceOpen(true)}
                    aria-label={`主题与外观：${activePaletteMeta.label}`}
                    className="h-9 w-9 shrink-0 p-0"
                  >
                    <Palette aria-hidden="true" className="h-4 w-4" />
                  </Button>
                </TooltipTrigger>
                <TooltipContent>
                  主题与外观：{activePaletteMeta.label}
                </TooltipContent>
              </Tooltip>

              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    onClick={cycleThemeMode}
                    aria-label="切换明暗模式"
                    className="h-9 w-9"
                  >
                    <ModeIcon className="h-4 w-4" />
                  </Button>
                </TooltipTrigger>
                <TooltipContent>
                  当前主题：
                  {mode === 'system'
                    ? `跟随系统 (${resolvedDark ? '深色' : '浅色'})`
                    : mode === 'dark'
                    ? '深色'
                    : '浅色'}
                  ，点击切换
                </TooltipContent>
              </Tooltip>
            </div>
          </header>

          <main
            aria-label={`${currentNav.label}页面`}
            className="app-shell-main flex-1 min-w-0 overflow-y-auto"
            ref={mainRef}
            tabIndex={-1}
          >
            <h1 className="sr-only">{currentNav.label}</h1>
            <div className="app-main-content">
              <div className="app-view-enter space-y-6" key={selectedSection}>
                {selectedSection === 'workbench' ? (
                  <WorkbenchPage
                    activeTerm={activeTerm}
                    onNavigate={setSelectedSection}
                    onSeedDemoData={async () => {
                      if (!activeTerm) return;
                      await seedDemoData(schoolRepository, activeTerm.id);
                      await useAppStore.getState().refreshTermData(activeTerm.id);
                    }}
                    summary={summary}
                  />
                ) : selectedSection === 'terms' ? (
                  <TermPage />
                ) : selectedSection === 'classes' ? (
                  <ClassesPage />
                ) : selectedSection === 'routines' ? (
                  <RoutinesPage onOpenClasses={() => setSelectedSection('classes')} />
                ) : selectedSection === 'subjects' ? (
                  <SubjectsPage />
                ) : selectedSection === 'teachers' ? (
                  <TeachersPage />
                ) : selectedSection === 'scheduling' ? (
                  <SchedulingPage termId={activeTerm?.id ?? null} />
                ) : selectedSection === 'temporaryAdjustments' ? (
                  <TemporaryAdjustmentsPage adjustments={adjustments} />
                ) : (
                  <PendingModulePage
                    onBackToWorkbench={() => setSelectedSection('workbench')}
                  />
                )}
              </div>
            </div>
          </main>
        </div>

        <AppearanceDialog
          open={appearanceOpen}
          palette={palette}
          mode={mode}
          onSelectPalette={setPalette}
          onSelectMode={setMode}
          onClose={() => setAppearanceOpen(false)}
        />
        <SchoolNameDialog
          open={schoolNameDialogOpen}
          initialName={schoolName}
          onSave={handleSaveSchoolName}
          onClose={() => setSchoolNameDialogOpen(false)}
        />
      </div>
    </TooltipProvider>
  );
};
