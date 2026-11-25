import React, { useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  CalendarCheck,
  CheckCircle2,
  Clock,
  XCircle,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import type { ScheduleData } from '@/domain/scheduling';
import type { SupervisionPreview } from '@/domain/supervision';
import { schoolRepository } from '@/repository/schoolRepository';
import { SupervisionPublishDiff } from './SupervisionPublishDiff';

interface PublishDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  termId: string;
  snapshot: ScheduleData;
  onPublishSuccess: () => void;
}

function formatDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export const PublishDialog: React.FC<PublishDialogProps> = ({
  open,
  onOpenChange,
  termId,
  snapshot,
  onPublishSuccess,
}) => {
  // Generate candidate effective dates: upcoming Mondays
  const candidateDates = useMemo(() => {
    const dates: { dateStr: string; label: string }[] = [];
    const today = new Date();
    // Start from upcoming Monday (or today if today is Monday)
    const current = new Date(today);
    const dayOfWeek = current.getDay();
    const distanceToMonday = (8 - (dayOfWeek === 0 ? 7 : dayOfWeek)) % 7;
    current.setDate(current.getDate() + (distanceToMonday === 0 ? 7 : distanceToMonday));

    for (let i = 0; i < 6; i++) {
      const d = new Date(current);
      d.setDate(d.getDate() + i * 7);
      const str = formatDate(d);
      dates.push({
        dateStr: str,
        label: `${str} (周一)`,
      });
    }
    return dates;
  }, []);

  const [selectedDate, setSelectedDate] = useState<string>(
    candidateDates[0]?.dateStr ?? formatDate(new Date())
  );
  const [loading, setLoading] = useState<boolean>(true);
  const [preview, setPreview] = useState<SupervisionPreview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [publishing, setPublishing] = useState<boolean>(false);

  useEffect(() => {
    if (!open) return;
    let isMounted = true;
    setLoading(true);
    setError(null);

    schoolRepository
      .previewSupervisionPublish(termId, selectedDate)
      .then((res) => {
        if (isMounted) {
          setPreview(res);
          setLoading(false);
        }
      })
      .catch((err) => {
        if (isMounted) {
          setError(String(err));
          setLoading(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [open, termId, selectedDate]);

  const handleConfirmPublish = async () => {
    if (!preview || !preview.canPublish) return;
    setPublishing(true);
    try {
      await schoolRepository.publishSupervision(termId, preview);
      onPublishSuccess();
      onOpenChange(false);
    } catch (err) {
      setError(String(err));
    } finally {
      setPublishing(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[85vh] flex flex-col p-6 overflow-hidden">
        <DialogHeader className="pb-3 border-b border-border">
          <DialogTitle className="text-lg font-semibold text-ink flex items-center gap-2">
            <CalendarCheck className="h-5 w-5 text-primary" />
            确认并发布带班方案
          </DialogTitle>
          <DialogDescription className="text-xs text-ink-secondary">
            确认当前带班方案后，系统将正式归档生效版本，并与日历和课表联动。
          </DialogDescription>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto py-3 space-y-4 text-xs">
          {/* Effective date selector */}
          <div className="space-y-1.5 p-3 rounded-lg bg-canvas/40 border border-border">
            <label className="text-xs font-medium text-ink block">方案生效日期</label>
            <Select value={selectedDate} onValueChange={setSelectedDate}>
              <SelectTrigger className="h-9 text-xs bg-surface">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {candidateDates.map((item) => (
                  <SelectItem key={item.dateStr} value={item.dateStr}>
                    {item.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <span className="text-[11px] text-ink-secondary block">
              已确认的方案将自该日起正式执行。若该日之后存在旧版本，将被本次发布覆盖。
            </span>
          </div>

          {/* Loading or Preview */}
          {loading ? (
            <div className="py-12 text-center text-xs text-ink-secondary space-y-2">
              <Clock className="h-5 w-5 animate-spin mx-auto text-primary" />
              <span>正在校验带班方案与时间冲突...</span>
            </div>
          ) : error ? (
            <div className="p-3 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive text-xs space-y-1">
              <div className="font-semibold flex items-center gap-1.5">
                <XCircle className="h-4 w-4" />
                校验遇到错误
              </div>
              <p>{error}</p>
            </div>
          ) : preview ? (
            <div className="space-y-3">
              {/* Validation Status Banner */}
              {preview.canPublish ? (
                <div className="p-3 rounded-lg bg-emerald-50 dark:bg-emerald-950/30 border border-emerald-200 dark:border-emerald-800 text-emerald-800 dark:text-emerald-300 flex items-start gap-2.5">
                  <CheckCircle2 className="h-4 w-4 shrink-0 mt-0.5" />
                  <div className="text-xs space-y-0.5">
                    <span className="font-semibold block">方案校验通过，可以确认发布</span>
                    <span>所有 {preview.draft.posts.length} 个岗位均已分配教师，且无正课或带班冲突。</span>
                  </div>
                </div>
              ) : (
                <div className="p-3 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive flex items-start gap-2.5">
                  <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
                  <div className="text-xs space-y-1.5 flex-1">
                    <span className="font-semibold block">
                      存在未安排岗位或规则冲突，请解决后再确认
                    </span>
                    {preview.missingPostIds.length > 0 && (
                      <div>
                        尚有 <span className="font-bold">{preview.missingPostIds.length}</span>{' '}
                        个岗位未分配带班教师。
                      </div>
                    )}
                    {preview.errors.length > 0 && (
                      <ul className="list-disc list-inside space-y-0.5">
                        {preview.errors.map((err, i) => (
                          <li key={i}>{err}</li>
                        ))}
                      </ul>
                    )}
                  </div>
                </div>
              )}

              <SupervisionPublishDiff snapshot={snapshot} preview={preview} />
            </div>
          ) : null}
        </div>

        <DialogFooter className="pt-3 border-t border-border flex items-center justify-between">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => onOpenChange(false)}
          >
            取消
          </Button>
          <Button
            type="button"
            size="sm"
            disabled={!preview?.canPublish || publishing || loading}
            onClick={handleConfirmPublish}
          >
            {publishing ? '正在发布...' : '确认发布此方案'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
