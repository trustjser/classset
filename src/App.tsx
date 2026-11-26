import React, { useEffect } from 'react';
import { AppShell } from './components/AppShell';
import { SetupWizardPage } from './features/setup/SetupWizardPage';
import { useAppStore } from './store/useAppStore';

export const App: React.FC = () => {
  const { initialized, terms, bootstrap } = useAppStore();

  useEffect(() => {
    void bootstrap();
  }, [bootstrap]);

  if (!initialized) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-canvas text-ink">
        <div className="text-[14px] text-ink-secondary">
          正在初始化课集本地数据库...
        </div>
      </div>
    );
  }

  // 本地尚无任何学期时，进入全屏两步初始化引导（不展示侧边栏与顶部栏）
  if (terms.length === 0) {
    return <SetupWizardPage />;
  }

  return <AppShell />;
};

export default App;
