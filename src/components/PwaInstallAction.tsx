import { useEffect, useState } from 'react';
import { Download } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { getSafariInstallTarget } from '@/lib/pwaInstall';

interface InstallPromptEvent extends Event {
  prompt(): Promise<unknown>;
}

export function usePwaInstallAction(enabled: boolean) {
  const [prompt, setPrompt] = useState<InstallPromptEvent | null>(null);
  const [guideOpen, setGuideOpen] = useState(false);
  const [installed, setInstalled] = useState(false);
  const standalone = installed ||
    window.matchMedia?.('(display-mode: standalone)')?.matches === true ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true;
  const target = enabled
    ? getSafariInstallTarget(navigator.userAgent, navigator.maxTouchPoints, standalone)
    : null;

  useEffect(() => {
    if (!enabled) return;
    const onBeforeInstall = (event: Event) => {
      event.preventDefault();
      setPrompt(event as InstallPromptEvent);
    };
    const onInstalled = () => {
      setInstalled(true);
      setPrompt(null);
    };
    window.addEventListener('beforeinstallprompt', onBeforeInstall);
    window.addEventListener('appinstalled', onInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', onBeforeInstall);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, [enabled]);

  useEffect(() => {
    if (target && window.location.hash === '#install') setGuideOpen(true);
  }, [target]);

  if (!enabled || standalone || (!prompt && !target)) return null;

  return (
    <>
      <Button
        type="button"
        variant="ghost"
        size="sm"
        className="h-7 shrink-0 gap-1.5 px-2.5 text-xs"
        onClick={() => {
          if (prompt) {
            setPrompt(null);
            void prompt.prompt().catch(() => {});
          } else {
            setGuideOpen(true);
          }
        }}
      >
        <Download aria-hidden="true" className="h-3.5 w-3.5" />
        安装应用
      </Button>
      {target && (
        <Dialog open={guideOpen} onOpenChange={setGuideOpen}>
          <DialogContent className="sm:max-w-[420px]">
            <DialogHeader>
              <DialogTitle>安装课集</DialogTitle>
              <DialogDescription>
                在 Safari 中将课集添加为独立应用。
              </DialogDescription>
            </DialogHeader>
            <ol className="list-decimal space-y-2 pl-5 text-sm">
              {target === 'home-screen' ? (
                <>
                  <li>轻点 Safari 工具栏的「分享」，选择「添加到主屏幕」。如果未显示，可在更多操作中查找。</li>
                  <li>如果显示「作为网页 App 打开」，请开启它，然后轻点「添加」。</li>
                </>
              ) : (
                <>
                  <li>在 Safari 的「文件」或「分享」菜单中选择「添加到程序坞」。</li>
                  <li>点击「添加」。此功能需要 macOS Sonoma 14 或更新版本。</li>
                </>
              )}
            </ol>
          </DialogContent>
        </Dialog>
      )}
    </>
  );
}
