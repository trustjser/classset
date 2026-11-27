import { act, createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { App } from '@/App';
import { useAppStore } from '@/store/useAppStore';
import { schoolRepository } from '@/repository/schoolRepository';

const term = {
  id: 'existing', title: '原学期', academicYear: '2026', semesterLabel: '秋',
  firstTeachingWeekStart: null, teachingWeekCount: 20, cycleMode: 'every_week' as const, createdAt: 1,
};

beforeEach(() => {
  vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
  history.replaceState(null, '', '#/workbench');
  useAppStore.setState({
    initialized: true, terms: [term], activeTermId: term.id, sidebarExpanded: true,
    bootstrap: async () => {},
  });
});

afterEach(() => {
  useAppStore.setState(useAppStore.getInitialState(), true);
  vi.unstubAllGlobals();
});

function button(label: string, root: ParentNode = document) {
  const found = [...root.querySelectorAll('button')].find((element) => element.textContent?.trim() === label);
  expect(found, label).toBeDefined();
  return found!;
}

async function renderApp(run: () => Promise<void>) {
  const host = document.body.appendChild(document.createElement('div'));
  const root = createRoot(host);
  try {
    await act(async () => root.render(createElement(App)));
    await run();
  } finally {
    await act(async () => root.unmount());
    host.remove();
  }
}

async function openSettings() {
  await act(async () => {
    button('设置').click();
  });
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 120)); });
}

it('空库初始页直接提供本地备份导入，不展示设置入口', async () => {
  useAppStore.setState({ terms: [], activeTermId: null });
  await renderApp(async () => {
    expect(button('从备份文件导入')).toBeDefined();
    expect([...document.querySelectorAll('button')].some((item) => item.textContent?.trim() === '设置')).toBe(false);
    expect(document.querySelector('input[type="file"]')).toBeDefined();
  });
});

it('取消清空保留数据，完整原文输入后才允许清空一次', async () => {
  await renderApp(async () => {
    await openSettings();
    const clear = vi.spyOn(schoolRepository, 'clearAllData').mockResolvedValue();
    await act(async () => button('清空所有数据').click());
    let dialog = document.querySelector('[role="dialog"]')!;
    expect(button('确认清空', dialog).disabled).toBe(true);
    await act(async () => button('取消', dialog).click());
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
    expect(document.activeElement).toBe(button('清空所有数据'));
    expect(clear).not.toHaveBeenCalled();

    await act(async () => button('清空所有数据').click());
    dialog = document.querySelector('[role="dialog"]')!;
    const input = dialog.querySelector('input')!;
    async function enter(value: string) {
      await act(async () => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(input, value);
        input.dispatchEvent(new Event('input', { bubbles: true }));
      });
    }
    await enter('清空我的所有数据 ');
    expect(button('确认清空', dialog).disabled).toBe(true);
    await enter('清空我的所有数据');
    expect(button('确认清空', dialog).disabled).toBe(false);
    await act(async () => button('确认清空', dialog).click());
    expect(clear).toHaveBeenCalledTimes(1);
    useAppStore.setState({ terms: [], activeTermId: null });
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 150)); });
    expect(button('从备份文件导入')).toBeDefined();
    expect(document.querySelector('[role="dialog"]')).toBeNull();
  });
});

it('初始页选中备份文件后直接执行导入', async () => {
  useAppStore.setState({ terms: [], activeTermId: null });
  const restore = vi.spyOn(schoolRepository, 'importSqliteBytes').mockResolvedValue();
  await renderApp(async () => {
    const file = new File([new Uint8Array([1, 2, 3])], '从桌面导出的备份.sqlite');
    const picker = document.querySelector<HTMLInputElement>('input[type="file"]')!;
    Object.defineProperty(picker, 'files', { value: [file], configurable: true });
    await act(async () => picker.dispatchEvent(new Event('change', { bubbles: true })));
    expect(restore).toHaveBeenCalledTimes(1);
    expect(restore.mock.calls[0][0]).toEqual(new Uint8Array([1, 2, 3]));
    expect(document.body.textContent).toContain('备份已导入');
  });
});

it('选择文件后须确认覆盖，导入失败保留重试入口', async () => {
  const restore = vi.spyOn(schoolRepository, 'importSqliteBytes').mockRejectedValue(new Error('备份文件不完整'));
  await renderApp(async () => {
    await openSettings();
    const picker = document.querySelector<HTMLInputElement>('input[type="file"]')!;
    const file = new File([], '浏览器备份.sqlite');
    Object.defineProperty(picker, 'files', { value: [file] });
    await act(async () => picker.dispatchEvent(new Event('change', { bubbles: true })));
    const dialog = document.querySelector('[role="dialog"]')!;
    expect(dialog.textContent).toContain('浏览器备份.sqlite');
    expect(restore).not.toHaveBeenCalled();
    await act(async () => button('确认覆盖', dialog).click());
    expect(restore).toHaveBeenCalledTimes(1);
    expect(dialog.querySelector('[role="alert"]')?.textContent).toContain('备份文件不完整');
    expect(button('确认覆盖', dialog).disabled).toBe(false);
  });
});

it('空库通过历史导航进入设置路径时仍展示初始页', async () => {
  useAppStore.setState({ terms: [], activeTermId: null });
  history.replaceState(null, '', '#/settings');
  useAppStore.setState({ selectedSection: 'settings' });
  await renderApp(async () => {
    expect(button('从备份文件导入')).toBeDefined();
    expect([...document.querySelectorAll('button')].some((item) => item.textContent?.trim() === '设置')).toBe(false);
  });
});

it('浏览器 AI 由用户开启，离开设置后保留连接，关闭时注销', async () => {
  const registerTool = vi.fn();
  Object.defineProperty(document, 'modelContext', { configurable: true, value: { registerTool } });
  try {
    await renderApp(async () => {
      await openSettings();
      expect(registerTool).not.toHaveBeenCalled();
      const toggle = document.querySelector<HTMLButtonElement>('button[role=switch][aria-labelledby]');
      expect(toggle).not.toBeNull();
      await act(async () => { toggle!.click(); });
      expect(registerTool.mock.calls.map(([tool]) => tool.name)).toContain('classset_get_context_and_gates');
      const options = registerTool.mock.calls[0][1];
      await act(async () => { button('工作台').click(); });
      expect(options.signal.aborted).toBe(false);
      await openSettings();
      const current = document.querySelector<HTMLButtonElement>('button[role=switch][aria-labelledby]');
      await act(async () => { current!.click(); });
      expect(options.signal.aborted).toBe(true);
    });
  } finally {
    Reflect.deleteProperty(document, 'modelContext');
  }
});
