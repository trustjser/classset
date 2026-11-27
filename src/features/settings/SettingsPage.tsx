import {
  useId,
  useRef,
  useState,
  type ChangeEvent,
  type DragEvent,
  type FormEvent,
} from 'react';
import {
  AlertTriangle,
  Check,
  CheckCircle2,
  Database,
  Download,
  FileArchive,
  HardDrive,
  Loader2,
  Moon,
  Pencil,
  Sun,
  SunMoon,
  Trash2,
  Upload,
  X,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { formatDateYmd } from '@/features/terms/calendarUtils';
import { schoolRepository } from '@/repository/schoolRepository';
import { useAppStore } from '@/store/useAppStore';
import { WebAgentSettings } from './WebAgentSettings';
import { DesktopAgentSettings } from './DesktopAgentSettings';
import { AgentPendingOperations } from './AgentPendingOperations';
import { agentProposals } from '@/agent/agentProposals';
import {
  PALETTE_OPTIONS,
  type AppAppearanceMode,
} from '@/styles/subjectColors';

const CLEAR_PHRASE = '清空我的所有数据';
const ACCEPTED_EXTENSIONS = ['.sqlite', '.sqlite3', '.db'];
const controlClass = 'h-10 w-full shrink-0 sm:w-auto';

type Confirmation = { kind: 'import'; file: File } | { kind: 'clear' };

const MODE_OPTIONS: Array<{
  id: AppAppearanceMode;
  label: string;
  icon: typeof Sun;
}> = [
  { id: 'system', label: '跟随系统', icon: SunMoon },
  { id: 'light', label: '浅色模式', icon: Sun },
  { id: 'dark', label: '深色模式', icon: Moon },
];

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  return fallback;
}

function formatFileSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function formatTimeHm(date: Date | null): string {
  if (!date) return '--:--';
  return `${String(date.getHours()).padStart(2, '0')}:${String(
    date.getMinutes()
  ).padStart(2, '0')}`;
}

function isSupportedBackupFile(fileName: string): boolean {
  const lower = fileName.trim().toLowerCase();
  return ACCEPTED_EXTENSIONS.some((ext) => lower.endsWith(ext));
}

async function saveBackup(): Promise<boolean> {
  const filename = '课集备份-' + formatDateYmd(new Date()) + '.sqlite';
  if (schoolRepository.isDesktop) {
    const { save } = await import('@tauri-apps/plugin-dialog');
    const destination = await save({
      defaultPath: filename,
      filters: [{ name: 'SQLite 数据库', extensions: ['sqlite'] }],
    });
    if (!destination) return false;
    const bytes = await schoolRepository.exportSqliteBytes();
    if (!bytes) throw new Error('本地数据库尚未就绪，请稍后重试。');
    const { writeFile } = await import('@tauri-apps/plugin-fs');
    await writeFile(destination, bytes);
  } else {
    const bytes = await schoolRepository.exportSqliteBytes();
    if (!bytes)
      throw new Error('浏览器数据库尚未就绪，请检查浏览器的本地存储权限。');
    const url = URL.createObjectURL(
      new Blob([new Uint8Array(bytes)], { type: 'application/vnd.sqlite3' })
    );
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  return true;
}

export function SettingsPage() {
  const runtimeMode = useAppStore((state) => state.runtimeMode);
  const schoolName = useAppStore((state) => state.schoolName);
  const updateSchoolName = useAppStore((state) => state.updateSchoolName);
  const palette = useAppStore((state) => state.palette);
  const mode = useAppStore((state) => state.mode);
  const resolvedDark = useAppStore((state) => state.resolvedDark);
  const setPalette = useAppStore((state) => state.setPalette);
  const setMode = useAppStore((state) => state.setMode);
  const terms = useAppStore((state) => state.terms);
  const activeTermId = useAppStore((state) => state.activeTermId);
  const stages = useAppStore((state) => state.stages);
  const classes = useAppStore((state) => state.classes);
  const teachers = useAppStore((state) => state.teachers);
  const publicRooms = useAppStore((state) => state.publicRooms);
  const lastPersistedAt = useAppStore((state) => state.lastPersistedAt);
  const reloadAfterDatabaseChange = useAppStore(
    (state) => state.reloadAfterDatabaseChange
  );
  const setSelectedSection = useAppStore((state) => state.setSelectedSection);

  const hasTerms = terms.length > 0;
  const activeTerm = terms.find((t) => t.id === activeTermId) ?? null;
  const schoolDisplayName = schoolName.trim() || '未命名学校';
  const defaultBackupName = `课集备份-${formatDateYmd(new Date())}.sqlite`;

  const [editingSchoolName, setEditingSchoolName] = useState(false);
  const [schoolNameDraft, setSchoolNameDraft] = useState(schoolName);
  const [savingSchoolName, setSavingSchoolName] = useState(false);

  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [phrase, setPhrase] = useState('');
  const [busy, setBusy] = useState(false);
  const [lastExportedAt, setLastExportedAt] = useState<Date | null>(null);
  const [dragActive, setDragActive] = useState(false);
  const [feedback, setFeedback] = useState<{
    error: boolean;
    message: string;
  } | null>(null);
  const [dialogError, setDialogError] = useState<string | null>(null);

  const operation = useRef(false);
  const picker = useRef<HTMLInputElement>(null);
  const importButton = useRef<HTMLButtonElement>(null);
  const clearButton = useRef<HTMLButtonElement>(null);
  const cancelButton = useRef<HTMLButtonElement>(null);
  const returnFocus = useRef<HTMLButtonElement | null>(null);
  const phraseId = useId();
  const errorId = useId();
  const schoolInputId = useId();

  const isClear = confirmation?.kind === 'clear';
  const canConfirm = dialogOpen && (!isClear || phrase === CLEAR_PHRASE);

  function openDialog(next: Confirmation, trigger: HTMLButtonElement | null) {
    returnFocus.current = trigger;
    setConfirmation(next);
    setPhrase('');
    setDialogError(null);
    setDialogOpen(true);
  }

  function handleCandidateFile(file: File | undefined) {
    if (!file || operation.current) return;
    if (!isSupportedBackupFile(file.name)) {
      setFeedback({
        error: true,
        message: '请选择 .sqlite、.sqlite3 或 .db 格式的课集数据库备份文件。',
      });
      return;
    }
    openDialog({ kind: 'import', file }, importButton.current);
  }

  function selectBackup(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    handleCandidateFile(file);
  }

  function handleDragOver(event: DragEvent<HTMLDivElement>) {
    event.preventDefault();
    event.stopPropagation();
    if (!busy && !operation.current) {
      setDragActive(true);
    }
  }

  function handleDragLeave(event: DragEvent<HTMLDivElement>) {
    event.preventDefault();
    event.stopPropagation();
    setDragActive(false);
  }

  function handleDrop(event: DragEvent<HTMLDivElement>) {
    event.preventDefault();
    event.stopPropagation();
    setDragActive(false);
    if (busy || operation.current) return;
    const file = event.dataTransfer.files?.[0];
    handleCandidateFile(file);
  }

  async function exportBackup() {
    if (operation.current) return;
    operation.current = true;
    setBusy(true);
    setFeedback(null);
    try {
      if (await saveBackup()) {
        setLastExportedAt(new Date());
        setFeedback({ error: false, message: '数据库备份已导出。' });
      }
    } catch (error) {
      setFeedback({
        error: true,
        message: '导出失败。' + errorMessage(error, '请重试。'),
      });
    } finally {
      operation.current = false;
      setBusy(false);
    }
  }

  async function handleSaveSchoolName(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (savingSchoolName) return;
    setSavingSchoolName(true);
    setFeedback(null);
    try {
      const trimmed = schoolNameDraft.trim();
      if (trimmed !== schoolName.trim()) {
        await updateSchoolName(trimmed);
      }
      setEditingSchoolName(false);
      setFeedback({
        error: false,
        message: trimmed
          ? `学校名称已更新为「${trimmed}」。`
          : '已恢复为默认名称「未命名学校」。',
      });
    } catch (error) {
      setFeedback({
        error: true,
        message: '保存学校名称失败：' + errorMessage(error, '请重试。'),
      });
    } finally {
      setSavingSchoolName(false);
    }
  }

  async function confirmChange() {
    if (!confirmation || !canConfirm || operation.current) return;
    operation.current = true;
    setBusy(true);
    setDialogError(null);
    setFeedback(null);
    try {
      agentProposals.invalidate(() => true);
      if (confirmation.kind === 'clear') await schoolRepository.clearAllData();
      else
        await schoolRepository.importSqliteBytes(
          new Uint8Array(await confirmation.file.arrayBuffer())
        );
    } catch (error) {
      setDialogError(errorMessage(error, '操作失败，请重试。'));
      operation.current = false;
      setBusy(false);
      return;
    }

    try {
      await reloadAfterDatabaseChange(confirmation.kind === 'clear');
      if (confirmation.kind === 'clear') setSelectedSection('workbench');
      setFeedback({
        error: false,
        message:
          confirmation.kind === 'clear'
            ? '所有数据已清空。'
            : '备份已导入，本地数据已替换。',
      });
    } catch {
      setFeedback({
        error: true,
        message: '数据库已更新，页面刷新失败。请重新打开应用。',
      });
    } finally {
      operation.current = false;
      setBusy(false);
      setDialogOpen(false);
    }
  }

  const showBanner = Boolean(feedback?.message) || (busy && !dialogOpen);

  return (
    <div className="grid max-w-5xl gap-6">
      {/* 状态与结果通知横幅 */}
      <div
        role={feedback?.error ? 'alert' : 'status'}
        aria-live="polite"
        className={
          showBanner
            ? `flex items-center justify-between gap-3 rounded-control border px-4 py-3 text-[13.5px] transition-colors ${
                feedback?.error
                  ? 'border-destructive/30 bg-destructive-surface text-destructive'
                  : 'border-primary/20 bg-selection text-ink'
              }`
            : 'sr-only'
        }
      >
        <div className="flex min-w-0 items-center gap-2.5">
          {busy && !dialogOpen ? (
            <Loader2
              aria-hidden="true"
              className="h-4 w-4 shrink-0 animate-spin text-primary"
            />
          ) : feedback?.error ? (
            <AlertTriangle
              aria-hidden="true"
              className="h-4 w-4 shrink-0 text-destructive"
            />
          ) : (
            <CheckCircle2
              aria-hidden="true"
              className="h-4 w-4 shrink-0 text-success"
            />
          )}
          <span className="leading-5">
            {feedback?.message}
            {busy && !dialogOpen && '正在导出数据库…'}
          </span>
        </div>
        {feedback && !(busy && !dialogOpen) && (
          <button
            type="button"
            aria-label="关闭提示"
            onClick={() => setFeedback(null)}
            className="rounded-md p-1 text-ink-secondary transition-colors hover:bg-surface/60 hover:text-ink"
          >
            <X aria-hidden="true" className="h-4 w-4" />
          </button>
        )}
      </div>

      {schoolRepository.isDesktop ? <DesktopAgentSettings /> : <WebAgentSettings />}
      <AgentPendingOperations />

      {/* 模块一：学校与本地数据概览 */}
      <section
        aria-labelledby="storage-overview-heading"
        className="rounded-card bg-surface px-5 py-5 sm:px-6"
      >
        <header className="flex flex-wrap items-start justify-between gap-3 pb-4 border-b border-border">
          <div>
            <div className="flex items-center gap-2">
              <h2
                id="storage-overview-heading"
                className="text-base font-semibold text-ink"
              >
                学校与本地数据
              </h2>
              <Badge variant="secondary">
                {runtimeMode === 'tauri-desktop'
                  ? '桌面端 · 本地 SQLite'
                  : '浏览器端 · 本地存储'}
              </Badge>
            </div>
            <p className="mt-1 text-sm leading-6 text-ink-secondary">
              所有排课与课务数据均保存在当前设备本地，离线也可随时查看与编排。
            </p>
          </div>
          <div className="flex items-center gap-2 rounded-control bg-table-header px-3 py-1.5 text-xs text-ink-secondary">
            <span className="h-2 w-2 rounded-full bg-success" />
            <span>最近保存 {formatTimeHm(lastPersistedAt)}</span>
          </div>
        </header>

        {/* 学校名称内联设置 */}
        <div className="py-4 border-b border-border">
          {!editingSchoolName ? (
            <div className="flex flex-wrap items-center justify-between gap-4">
              <div className="min-w-0">
                <div className="text-xs font-medium text-ink-secondary">
                  学校名称
                </div>
                <div className="mt-1 flex flex-wrap items-center gap-2.5">
                  <span className="text-[15px] font-semibold text-ink">
                    {schoolDisplayName}
                  </span>
                  {activeTerm && (
                    <span className="text-xs text-ink-secondary">
                      当前学期：{activeTerm.title}
                    </span>
                  )}
                </div>
              </div>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => {
                  setSchoolNameDraft(schoolName);
                  setEditingSchoolName(true);
                }}
              >
                <Pencil aria-hidden="true" className="h-3.5 w-3.5" />
                修改学校名称
              </Button>
            </div>
          ) : (
            <form
              onSubmit={(event) => void handleSaveSchoolName(event)}
              className="flex flex-col gap-3 sm:flex-row sm:items-end"
            >
              <div className="flex-1 space-y-1.5">
                <label
                  htmlFor={schoolInputId}
                  className="text-xs font-semibold text-ink"
                >
                  学校名称
                </label>
                <Input
                  id={schoolInputId}
                  autoFocus
                  value={schoolNameDraft}
                  onChange={(event) =>
                    setSchoolNameDraft(event.currentTarget.value)
                  }
                  placeholder="请输入学校名称（留空显示“未命名学校”）"
                  className="h-9 max-w-md"
                />
              </div>
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  disabled={savingSchoolName}
                  onClick={() => setEditingSchoolName(false)}
                >
                  取消
                </Button>
                <Button type="submit" size="sm" disabled={savingSchoolName}>
                  {savingSchoolName ? '保存中…' : '保存名称'}
                </Button>
              </div>
            </form>
          )}
        </div>

        {/* 本地数据库规模统计 */}
        <div className="pt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div className="rounded-control bg-table-header px-3.5 py-2.5">
            <div className="text-xs text-ink-secondary">学期总数</div>
            <div className="mt-1 text-base font-semibold tabular-nums text-ink">
              {terms.length}{' '}
              <span className="text-xs font-normal text-ink-secondary">个</span>
            </div>
          </div>
          <div className="rounded-control bg-table-header px-3.5 py-2.5">
            <div className="text-xs text-ink-secondary">当前学期班级</div>
            <div className="mt-1 text-base font-semibold tabular-nums text-ink">
              {classes.length}{' '}
              <span className="text-xs font-normal text-ink-secondary">
                个班（{stages.length} 学段）
              </span>
            </div>
          </div>
          <div className="rounded-control bg-table-header px-3.5 py-2.5">
            <div className="text-xs text-ink-secondary">全校教师</div>
            <div className="mt-1 text-base font-semibold tabular-nums text-ink">
              {teachers.length}{' '}
              <span className="text-xs font-normal text-ink-secondary">人</span>
            </div>
          </div>
          <div className="rounded-control bg-table-header px-3.5 py-2.5">
            <div className="text-xs text-ink-secondary">公共场室</div>
            <div className="mt-1 text-base font-semibold tabular-nums text-ink">
              {publicRooms.length}{' '}
              <span className="text-xs font-normal text-ink-secondary">间</span>
            </div>
          </div>
        </div>
      </section>

      {/* 模块二：数据库备份与恢复 */}
      <section
        aria-labelledby="backup-settings-heading"
        className="rounded-card bg-surface px-5 py-5 sm:px-6"
      >
        <header className="flex flex-wrap items-start justify-between gap-3 pb-4">
          <div>
            <h2
              id="backup-settings-heading"
              className="text-base font-semibold text-ink"
            >
              数据库备份
            </h2>
            <p className="mt-1 text-sm leading-6 text-ink-secondary">
              桌面端和浏览器端可互相导入课集的 .sqlite 备份文件。
            </p>
          </div>
          {lastExportedAt && (
            <Badge variant="success">
              本次已备份 {formatTimeHm(lastExportedAt)}
            </Badge>
          )}
        </header>

        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {/* 导出数据库卡片 */}
          <div className="flex flex-col justify-between rounded-control border border-border bg-canvas/40 p-4">
            <div>
              <div className="flex items-center justify-between gap-2">
                <h3 className="text-sm font-semibold text-ink">导出数据库</h3>
                <Database
                  aria-hidden="true"
                  className="h-4 w-4 text-ink-secondary"
                />
              </div>
              <p className="mt-1.5 text-sm leading-6 text-ink-secondary">
                保存当前所有学期、课表和课务记录。
              </p>
              <div className="mt-3 rounded-md bg-table-header px-3 py-2 text-xs text-ink-secondary">
                默认文件名：
                <span className="font-mono text-ink">{defaultBackupName}</span>
              </div>
            </div>

            <div className="mt-4 pt-2">
              <Button
                type="button"
                className={controlClass}
                disabled={busy}
                onClick={() => void exportBackup()}
              >
                <Download aria-hidden="true" />
                导出备份
              </Button>
            </div>
          </div>

          {/* 导入数据库卡片（支持点击或拖拽 .sqlite 文件） */}
          <div
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
            className={`flex flex-col justify-between rounded-control border p-4 transition-colors ${
              dragActive
                ? 'border-primary bg-selection/60'
                : 'border-border bg-canvas/40'
            }`}
          >
            <div>
              <div className="flex items-center justify-between gap-2">
                <h3 className="text-sm font-semibold text-ink">导入数据库</h3>
                <HardDrive
                  aria-hidden="true"
                  className="h-4 w-4 text-ink-secondary"
                />
              </div>
              <p className="mt-1.5 text-sm leading-6 text-ink-secondary">
                导入后，备份中的数据将完全替换本地数据。
              </p>
              <div className="mt-3 rounded-md bg-table-header px-3 py-2 text-xs text-ink-secondary">
                支持将 <span className="font-mono text-ink">.sqlite</span>{' '}
                备份文件拖入此处，或点击下方按钮选择文件
              </div>
            </div>

            <div className="mt-4 pt-2">
              <input
                ref={picker}
                type="file"
                accept=".sqlite,.sqlite3,.db"
                hidden
                onChange={selectBackup}
              />
              <Button
                ref={importButton}
                type="button"
                variant="outline"
                className={controlClass}
                disabled={busy}
                onClick={() => picker.current?.click()}
              >
                <Upload aria-hidden="true" />
                选择备份文件
              </Button>
            </div>
          </div>
        </div>
      </section>

      {/* 模块三：主题与外观 */}
      <section
        aria-labelledby="appearance-settings-heading"
        className="rounded-card bg-surface px-5 py-5 sm:px-6"
      >
        <header className="flex flex-wrap items-start justify-between gap-3 pb-4 border-b border-border">
          <div>
            <h2
              id="appearance-settings-heading"
              className="text-base font-semibold text-ink"
            >
              主题与外观
            </h2>
            <p className="mt-1 text-sm leading-6 text-ink-secondary">
              内置三套日程配色方案，配色与明暗模式独立选择并自动保存在本机。
            </p>
          </div>
          <div className="flex items-center gap-1 rounded-control bg-table-header p-1">
            {MODE_OPTIONS.map((item) => {
              const active = mode === item.id;
              const Icon = item.icon;
              return (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => setMode(item.id)}
                  aria-pressed={active}
                  className={`inline-flex h-8 items-center gap-1.5 rounded-[9px] px-3 text-xs font-medium transition-colors ${
                    active
                      ? 'bg-surface text-primary font-semibold'
                      : 'text-ink-secondary hover:text-ink'
                  }`}
                >
                  <Icon aria-hidden="true" className="h-3.5 w-3.5" />
                  <span>{item.label}</span>
                </button>
              );
            })}
          </div>
        </header>

        <div className="pt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
          {PALETTE_OPTIONS.map((item) => {
            const active = palette === item.id;
            const preview = resolvedDark ? item.darkPreview : item.lightPreview;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => setPalette(item.id)}
                aria-pressed={active}
                className={`flex flex-col justify-between rounded-control border p-3.5 text-left transition-colors ${
                  active
                    ? 'border-primary bg-selection'
                    : 'border-border bg-surface hover:border-control-border'
                }`}
              >
                <div>
                  <div className="flex items-center justify-between gap-2">
                    <span
                      className={`text-sm font-semibold ${
                        active ? 'text-primary' : 'text-ink'
                      }`}
                    >
                      {item.label}
                    </span>
                    <div className="flex items-center gap-1">
                      <span
                        className="h-4 w-4 rounded-full border border-border"
                        style={{ backgroundColor: preview.accent }}
                        title="主色"
                      />
                      <span
                        className="h-4 w-4 rounded-full border border-border"
                        style={{ backgroundColor: preview.canvas }}
                        title="画布"
                      />
                      <span
                        className="h-4 w-4 rounded-full border border-border"
                        style={{ backgroundColor: preview.surface }}
                        title="面板"
                      />
                    </div>
                  </div>
                  <p className="mt-1.5 text-xs leading-5 text-ink-secondary">
                    {item.description}
                  </p>
                </div>
                <div className="mt-3 flex items-center gap-1 text-xs font-medium">
                  {active ? (
                    <span className="inline-flex items-center gap-1 text-primary">
                      <Check aria-hidden="true" className="h-3.5 w-3.5" />
                      当前使用
                    </span>
                  ) : (
                    <span className="text-ink-secondary">点击切换</span>
                  )}
                </div>
              </button>
            );
          })}
        </div>
      </section>

      {/* 模块四：清空数据（高危操作区） */}
      <section
        aria-labelledby="clear-data-heading"
        className="rounded-card border border-destructive/25 bg-surface px-5 py-5 sm:px-6"
      >
        <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-4">
          <div className="min-w-0 flex-1 basis-64">
            <div className="flex items-center gap-2">
              <h2
                id="clear-data-heading"
                className="text-base font-semibold text-ink"
              >
                清空数据
              </h2>
              <Badge variant="destructive">不可撤销</Badge>
            </div>
            <p className="mt-1 text-sm leading-6 text-ink-secondary">
              删除当前设备上的全部课集数据。此操作无法撤销，建议清空前先导出一份数据库备份。
            </p>
          </div>
          <Button
            ref={clearButton}
            type="button"
            variant="outline"
            className={
              controlClass +
              ' border-destructive/40 text-destructive hover:bg-destructive/10 hover:text-destructive'
            }
            disabled={busy}
            onClick={() => openDialog({ kind: 'clear' }, clearButton.current)}
          >
            <Trash2 aria-hidden="true" />
            清空所有数据
          </Button>
        </div>
      </section>

      {!hasTerms && (
        <div>
          <Button
            type="button"
            variant="outline"
            className={controlClass}
            onClick={() => setSelectedSection('workbench')}
          >
            返回初始设置
          </Button>
        </div>
      )}

      {/* 覆盖导入 / 清空数据 确认对话框 */}
      <Dialog
        open={dialogOpen}
        onOpenChange={(open) => {
          if (!open && !operation.current) setDialogOpen(false);
        }}
      >
        <DialogContent
          showCloseButton={false}
          className="max-h-[90dvh] w-[calc(100%-2rem)] max-w-md overflow-y-auto"
          onOpenAutoFocus={(event) => {
            event.preventDefault();
            cancelButton.current?.focus();
          }}
          onCloseAutoFocus={(event) => {
            event.preventDefault();
            returnFocus.current?.focus();
          }}
        >
          <DialogHeader>
            <DialogTitle>
              {isClear ? '清空所有数据' : '覆盖导入数据库'}
            </DialogTitle>
            <DialogDescription className="text-sm leading-6">
              {isClear
                ? '学期、教师、课表和课务记录等本地数据将永久删除。'
                : '此操作会替换当前设备上的全部课集数据。'}
            </DialogDescription>
          </DialogHeader>

          <form
            className="grid gap-4 pt-1"
            onSubmit={(event) => {
              event.preventDefault();
              void confirmChange();
            }}
          >
            {isClear ? (
              <div className="grid gap-3">
                <div className="rounded-control bg-destructive-surface px-3.5 py-2.5 text-xs leading-5 text-destructive">
                  即将清除当前设备上的{' '}
                  <span className="font-semibold">{terms.length} 个学期</span>、
                  <span className="font-semibold">{classes.length} 个班级</span>{' '}
                  及{' '}
                  <span className="font-semibold">
                    {teachers.length} 名教师
                  </span>
                  的全部排课与课务记录。
                </div>

                <div className="grid gap-2">
                  <div className="flex items-center justify-between gap-2">
                    <label htmlFor={phraseId} className="text-sm font-medium">
                      输入「{CLEAR_PHRASE}」以确认
                    </label>
                    <button
                      type="button"
                      disabled={busy || phrase === CLEAR_PHRASE}
                      onClick={() => setPhrase(CLEAR_PHRASE)}
                      className="text-xs font-medium text-primary hover:underline disabled:opacity-45"
                    >
                      填入确认口令
                    </button>
                  </div>
                  <Input
                    id={phraseId}
                    className="h-10"
                    value={phrase}
                    onChange={(event) => setPhrase(event.target.value)}
                    placeholder={CLEAR_PHRASE}
                    disabled={busy}
                    autoComplete="off"
                    aria-describedby={dialogError ? errorId : undefined}
                  />
                </div>
              </div>
            ) : (
              confirmation?.kind === 'import' && (
                <div className="grid gap-3">
                  <div className="flex items-start gap-2.5 rounded-control bg-table-header px-3.5 py-3">
                    <FileArchive
                      aria-hidden="true"
                      className="mt-0.5 h-4 w-4 shrink-0 text-primary"
                    />
                    <div className="min-w-0 flex-1">
                      <p className="break-all text-sm font-medium text-ink">
                        {confirmation.file.name}
                      </p>
                      <p className="mt-0.5 text-xs text-ink-secondary">
                        文件大小：{formatFileSize(confirmation.file.size)}
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center justify-between gap-3 rounded-control border border-border px-3.5 py-2.5 text-xs text-ink-secondary">
                    <span>覆盖前可先保存当前数据快照</span>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void exportBackup()}
                      className="shrink-0 font-semibold text-primary hover:underline disabled:opacity-45"
                    >
                      先导出当前备份
                    </button>
                  </div>
                </div>
              )
            )}

            {dialogError && (
              <p
                id={errorId}
                role="alert"
                className="rounded-md bg-destructive-surface px-3 py-2 text-sm text-destructive"
              >
                {dialogError}
              </p>
            )}

            <DialogFooter className="flex-col gap-2 sm:flex-row sm:space-x-0">
              <Button
                ref={cancelButton}
                type="button"
                variant="outline"
                className={controlClass}
                disabled={busy}
                onClick={() => setDialogOpen(false)}
              >
                取消
              </Button>
              <Button
                type="submit"
                variant="destructive"
                className={controlClass}
                disabled={!canConfirm || busy}
              >
                {isClear
                  ? busy
                    ? '正在清空…'
                    : '确认清空'
                  : busy
                    ? '正在导入…'
                    : '确认覆盖'}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
