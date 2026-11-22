import React, { useEffect } from 'react';
import { AppShell } from './components/AppShell';
import { useAppStore } from './store/useAppStore';

export const App: React.FC = () => {
  const { initialized, bootstrap } = useAppStore();

  useEffect(() => {
    void bootstrap();
  }, [bootstrap]);

  if (!initialized) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-canvas text-ink">
        <div className="text-[14px] text-ink-secondary">
          正在初始化课集 Schema v19 本地数据库...
        </div>
      </div>
    );
  }

  return <AppShell />;
};

export default App;
