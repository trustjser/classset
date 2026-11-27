import React, { useEffect } from 'react';
import { AppShell } from './components/AppShell';
import { usePwaInstallAction } from './components/PwaInstallAction';
import { SetupWizardPage } from './features/setup/SetupWizardPage';
import { getSectionFromLocation, useAppStore } from './store/useAppStore';

export const App: React.FC = () => {
  const { initialized, runtimeMode, terms, setSelectedSection, bootstrap } = useAppStore();

  const installAction = usePwaInstallAction(runtimeMode === 'web-browser');

  useEffect(() => {
    void bootstrap();
  }, [bootstrap]);

  useEffect(() => {
    const syncSectionFromLocation = () => {
      const section = getSectionFromLocation();
      if (section !== useAppStore.getState().selectedSection) setSelectedSection(section);
    };
    window.addEventListener('hashchange', syncSectionFromLocation);
    return () => window.removeEventListener('hashchange', syncSectionFromLocation);
  }, [setSelectedSection]);

  useEffect(() => {
    if (runtimeMode !== 'web-browser') return;
    const handleBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = '';
    };
    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, [runtimeMode]);

  if (!initialized) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-canvas text-ink">
        <div className="text-[14px] text-ink-secondary">
          正在初始化课集本地数据库...
        </div>
      </div>
    );
  }

  // 空库默认进入初始化向导，并从初始页恢复本地备份。
  if (terms.length === 0) {
    return <SetupWizardPage installAction={installAction} />;
  }

  return <AppShell installAction={installAction} />;
};

export default App;
