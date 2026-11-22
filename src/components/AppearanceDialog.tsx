import React from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  AppAppearanceMode,
  AppPalette,
  PALETTE_OPTIONS,
} from '@/styles/subjectColors';

interface AppearanceDialogProps {
  open: boolean;
  palette: AppPalette;
  mode: AppAppearanceMode;
  onSelectPalette: (palette: AppPalette) => void;
  onSelectMode: (mode: AppAppearanceMode) => void;
  onClose: () => void;
}

const MODE_LABELS: Array<{ id: AppAppearanceMode; label: string }> = [
  { id: 'system', label: '跟随系统' },
  { id: 'light', label: '浅色模式' },
  { id: 'dark', label: '深色模式' },
];

export const AppearanceDialog: React.FC<AppearanceDialogProps> = ({
  open,
  palette,
  mode,
  onSelectPalette,
  onSelectMode,
  onClose,
}) => {
  return (
    <Dialog open={open} onOpenChange={(nextOpen) => !nextOpen && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>主题与外观</DialogTitle>
          <DialogDescription>
            内置“晴空蓝”“海盐青”“云白墨灰”三套配色，配色与明暗模式独立选择，自动保存到本机
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5 pt-1">
          <div>
            <div className="text-[13px] font-semibold text-ink mb-2.5">
              明暗模式
            </div>
            <div className="grid grid-cols-3 gap-2.5">
              {MODE_LABELS.map((item) => {
                const active = mode === item.id;
                return (
                  <Button
                    key={item.id}
                    type="button"
                    variant={active ? 'default' : 'secondary'}
                    onClick={() => onSelectMode(item.id)}
                    className="w-full"
                  >
                    {item.label}
                  </Button>
                );
              })}
            </div>
          </div>

          <div>
            <div className="text-[13px] font-semibold text-ink mb-2.5">
              内置配色方案
            </div>
            <div className="space-y-2.5">
              {PALETTE_OPTIONS.map((item) => {
                const active = palette === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => onSelectPalette(item.id)}
                    className={`w-full flex items-center justify-between p-3.5 rounded-control border text-left transition-colors duration-feedback ${
                      active
                        ? 'bg-selection border-primary'
                        : 'bg-surface border-border hover:border-control-border'
                    }`}
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <span
                          className={`text-[14px] font-semibold ${
                            active ? 'text-primary' : 'text-ink'
                          }`}
                        >
                          {item.label}
                        </span>
                        {active && <Badge variant="default">当前使用</Badge>}
                      </div>
                      <p className="text-[12px] text-ink-secondary mt-1">
                        {item.description}
                      </p>
                    </div>

                    <div className="flex items-center gap-1.5 shrink-0 ml-4">
                      <span
                        className="w-6 h-6 rounded-full border border-border"
                        style={{ backgroundColor: item.lightPreview.accent }}
                        title="浅色主色"
                      />
                      <span
                        className="w-6 h-6 rounded-full border border-border"
                        style={{ backgroundColor: item.lightPreview.canvas }}
                        title="浅色画布"
                      />
                      <span
                        className="w-6 h-6 rounded-full border border-border"
                        style={{ backgroundColor: item.darkPreview.surface }}
                        title="深色面板"
                      />
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};
