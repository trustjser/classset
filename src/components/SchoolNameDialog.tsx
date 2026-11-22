import React, { useEffect, useState } from 'react';
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

interface SchoolNameDialogProps {
  open: boolean;
  initialName: string;
  onSave: (name: string) => Promise<void>;
  onClose: () => void;
}

export const SchoolNameDialog: React.FC<SchoolNameDialogProps> = ({
  open,
  initialName,
  onSave,
  onClose,
}) => {
  const [name, setName] = useState(initialName);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setName(initialName);
    setError(null);
    setSaving(false);
  }, [initialName, open]);

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (saving) return;

    setSaving(true);
    setError(null);
    try {
      await onSave(name.trim());
    } catch (saveError) {
      setError(
        saveError instanceof Error ? saveError.message : '保存学校名称失败'
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen && !saving) onClose();
      }}
    >
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>编辑学校名称</DialogTitle>
          <DialogDescription>
            保存后会立即更新侧栏中的学校信息。
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4 pt-1">
          <div className="space-y-1.5">
            <label
              htmlFor="school-name-input"
              className="text-[12.5px] font-semibold text-ink"
            >
              学校名称
            </label>
            <Input
              id="school-name-input"
              autoFocus
              value={name}
              onChange={(event) => {
                setName(event.currentTarget.value);
                setError(null);
              }}
              placeholder="请输入学校名称"
              aria-describedby="school-name-hint"
            />
            <p
              id="school-name-hint"
              className="text-[11px] leading-5 text-muted"
            >
              留空将显示“未命名学校”。
            </p>
          </div>

          {error && (
            <p
              role="alert"
              className="rounded-md bg-destructive-surface px-3 py-2 text-[12px] text-destructive"
            >
              保存学校名称失败：{error}
            </p>
          )}

          <DialogFooter>
            <Button
              type="button"
              variant="ghost"
              onClick={onClose}
              disabled={saving}
            >
              取消
            </Button>
            <Button type="submit" disabled={saving}>
              {saving ? '保存中…' : '保存'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
