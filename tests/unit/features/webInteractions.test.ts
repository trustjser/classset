import { describe, expect, it, vi } from 'vitest';
import { getSafariInstallTarget } from '@/lib/pwaInstall';
import { canStartSelection } from '@/lib/pointerSelection';

describe('Safari 安装引导', () => {
  const macSafari = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  it('识别 Mac Safari 和以桌面标识访问的 iPad', () => {
    expect(getSafariInstallTarget(macSafari, 0, false)).toBe('dock');
    expect(getSafariInstallTarget(macSafari, 5, false)).toBe('home-screen');
    expect(getSafariInstallTarget(macSafari.replace('Macintosh', 'iPhone'), 5, false)).toBe('home-screen');
  });

  it('已安装模式和其他浏览器不显示 Safari 专用指引', () => {
    expect(getSafariInstallTarget(macSafari, 5, true)).toBeNull();
    expect(getSafariInstallTarget(macSafari.replace('Version/26.0', 'Chrome/144.0.0.0'), 0, false)).toBeNull();
    expect(getSafariInstallTarget(macSafari.replace('Version/26.0', 'CriOS/144.0.0.0'), 5, false)).toBeNull();
  });
});

describe('拖动多选的指针入口', () => {
  it('直接接收手指和笔的主指针', () => {
    for (const pointerType of ['touch', 'pen']) {
      const event = { button: 0, pointerType, isPrimary: true };
      expect(canStartSelection(event)).toBe(true);
    }
  });

  it('保留鼠标左键并忽略右键及第二个触点', () => {
    expect(canStartSelection({ button: 0, isPrimary: true })).toBe(true);
    expect(canStartSelection({ button: 2, isPrimary: true })).toBe(false);
    expect(canStartSelection({ button: 0, isPrimary: false })).toBe(false);
  });
});

it('iPad 桌面模式能从安装入口打开主屏幕引导', async () => {
  const { act, createElement } = await import('react');
  const { createRoot } = await import('react-dom/client');
  const { usePwaInstallAction } = await import('@/components/PwaInstallAction');
  vi.stubGlobal('navigator', {
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/26.0 Safari/605.1.15',
    maxTouchPoints: 5,
  });
  const host = document.body.appendChild(document.createElement('div'));
  const root = createRoot(host);
  const Harness = () => usePwaInstallAction(true);
  vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
  try {
    await act(async () => root.render(createElement(Harness)));
    const button = host.querySelector('button');
    expect(button?.textContent).toContain('安装应用');
    await act(async () => button?.click());
    expect(document.querySelector('[role="dialog"]')?.textContent).toContain('添加到主屏幕');
    expect(document.querySelector('[role="dialog"]')?.textContent).not.toContain('添加到程序坞');
  } finally {
    await act(async () => root.unmount());
    host.remove();
    vi.unstubAllGlobals();
  }
});

it('手指直接滑动可滚动，长按岗位后拖动才多选', async () => {
  const { act, createElement, useState } = await import('react');
  const { createRoot } = await import('react-dom/client');
  const { SupervisionWeekGrid } = await import('@/features/supervision/SupervisionWeekGrid');
  type Props = import('react').ComponentProps<typeof SupervisionWeekGrid>;
  const posts: Props['posts'] = [1, 2].map((weekday) => ({
    id: String(weekday), kind: 'custom', name: '午间带班', groupName: '',
    location: '', stageId: 'stage', weekday, periodTypeId: 'afternoon',
    lessonIndices: [1], classIds: [],
  }));
  const Harness = () => {
    const [selected, setSelected] = useState(new Set<string>());
    return createElement(SupervisionWeekGrid, {
      snapshot: { stages: [], routines: [] } as unknown as Props['snapshot'],
      draft: { posts, assignments: {} } as Props['draft'],
      posts,
      classMap: new Map(),
      teacherMap: new Map(),
      selectedPostIds: selected,
      matching: null,
      allocator: {} as Props['allocator'],
      isHistorical: false,
      onTogglePostSelection: () => {},
      onSetPostSelection: setSelected,
      onSelectTeacher: () => {},
      onEditRules: () => {},
      onDeletePost: () => {},
    });
  };
  vi.useFakeTimers();
  vi.stubGlobal('navigator', { maxTouchPoints: 5 });
  vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
  vi.stubGlobal('ResizeObserver', class {
    observe() {}
    unobserve() {}
    disconnect() {}
  });
  const host = document.body.appendChild(document.createElement('div'));
  const root = createRoot(host);
  const pointer = (type: string, x: number, pointerId = 1) => new PointerEvent(type, {
    pointerId, pointerType: 'touch', isPrimary: pointerId === 1, bubbles: true,
    cancelable: true, clientX: x, clientY: 80, button: 0,
  });
  try {
    await act(async () => root.render(createElement(Harness)));
    const first = host.querySelector<HTMLElement>('[data-post-id="1"]')!;
    const second = host.querySelector<HTMLElement>('[data-post-id="2"]')!;
    const viewport = host.querySelector<HTMLElement>('[tabindex="-1"]')!;
    Object.defineProperties(viewport, {
      clientWidth: { value: 500 },
      clientHeight: { value: 300 },
    });
    vi.spyOn(viewport, 'getBoundingClientRect').mockReturnValue(new DOMRect(0, 0, 500, 300));
    vi.spyOn(first, 'getBoundingClientRect').mockReturnValue(new DOMRect(200, 50, 100, 100));
    vi.spyOn(second, 'getBoundingClientRect').mockReturnValue(new DOMRect(320, 50, 100, 100));
    const checked = () => host.querySelectorAll('[role="checkbox"][aria-checked="true"]').length;
    const header = [...host.querySelectorAll('div')].find((item) => item.textContent?.trim() === '周一')!;
    expect(host.textContent).not.toContain('拖动多选');
    expect(viewport.classList.contains('touch-none')).toBe(false);
    expect(first.closest('.touch-none')).toBeNull();
    expect(header.closest('.touch-none')).toBeNull();

    await act(async () => {
      header.dispatchEvent(pointer('pointerdown', 240));
      header.dispatchEvent(pointer('pointermove', 380));
      header.dispatchEvent(pointer('pointerup', 380));
    });
    expect(checked()).toBe(0);

    await act(async () => {
      first.dispatchEvent(pointer('pointerdown', 240));
      first.dispatchEvent(pointer('pointermove', 380));
      vi.advanceTimersByTime(500);
      first.dispatchEvent(pointer('pointerup', 380));
    });
    expect(checked()).toBe(0);

    await act(async () => {
      first.dispatchEvent(pointer('pointerdown', 240));
      vi.advanceTimersByTime(500);
      const touchMove = new Event('touchmove', { bubbles: true, cancelable: true });
      Object.defineProperty(touchMove, 'touches', { value: [{}] });
      first.dispatchEvent(touchMove);
      expect(touchMove.defaultPrevented).toBe(true);
      first.dispatchEvent(pointer('pointermove', 350));
      first.dispatchEvent(pointer('pointerup', 350, 2));
      first.dispatchEvent(pointer('pointermove', 380));
      first.dispatchEvent(pointer('pointerup', 380));
    });
    expect(checked()).toBe(2);

    await act(async () => {
      first.dispatchEvent(pointer('pointerdown', 240));
      vi.advanceTimersByTime(500);
      first.dispatchEvent(pointer('pointermove', 260));
      first.dispatchEvent(pointer('pointercancel', 260));
    });
    expect(checked()).toBe(2);
  } finally {
    await act(async () => root.unmount());
    host.remove();
    vi.useRealTimers();
    vi.unstubAllGlobals();
  }
});

it.each(['touch', 'mouse'])('科目节数 %s 框选松手打开快捷菜单，选择统一设置后才打开弹窗', async (pointerType) => {
  const { act, createElement } = await import('react');
  const { createRoot } = await import('react-dom/client');
  const { SubjectsPage } = await import('@/features/subjects/SubjectsPage');
  const { useAppStore } = await import('@/store/useAppStore');
  const previousState = useAppStore.getState();
  vi.useFakeTimers();
  vi.stubGlobal('navigator', { maxTouchPoints: pointerType === 'touch' ? 5 : 0 });
  vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
  const hitTest = Object.getOwnPropertyDescriptor(document, 'elementFromPoint');
  const grades = ['1', '2'].map((id, sortOrder) => ({
    id, stageId: 'stage', name: `年级 ${id}`, sortOrder,
  }));
  useAppStore.setState({
    activeTermId: 'term',
    stages: [{ id: 'stage', termId: 'term', name: '小学', sortOrder: 0 }],
    grades,
    classes: grades.map(({ id }) => ({ id: `class-${id}`, gradeId: id, name: '一班', sortOrder: 0 })),
    subjects: [{ id: 'math', termId: 'term', name: '数学', shortName: '数', sortOrder: 0 }],
    subjectRequirements: [],
    loadFreeSlotsForStages: async () => {},
  });
  const host = document.body.appendChild(document.createElement('div'));
  const root = createRoot(host);
  const pointer = (type: string, x: number) => new PointerEvent(type, {
    pointerId: 1, pointerType, isPrimary: true, bubbles: true,
    cancelable: true, clientX: x, clientY: 80, button: 0,
  });

  try {
    await act(async () => root.render(createElement(SubjectsPage)));
    const cells = [...host.querySelectorAll<HTMLButtonElement>('[data-matrix-row]')];
    const [first, second] = cells;
    expect(cells).toHaveLength(2);
    const originalValues = cells.map((cell) => cell.textContent);
    vi.spyOn(first.closest('table')!.parentElement!, 'getBoundingClientRect')
      .mockReturnValue(new DOMRect(0, 0, 500, 300));
    Object.defineProperty(document, 'elementFromPoint', {
      configurable: true, value: (x: number) => x < 200 ? first : second,
    });
    const hold = () => act(async () => {
      first.dispatchEvent(pointer('pointerdown', 140));
      if (pointerType === 'touch') vi.advanceTimersByTime(500);
    });
    const dialog = () => document.querySelector('[role="dialog"]');
    await hold();
    await act(async () => first.dispatchEvent(pointer('pointerup', 140)));
    expect(document.querySelector('[role="menu"]')).toBeNull();
    await hold();
    await act(async () => {
      first.dispatchEvent(pointer('pointermove', 270));
      first.dispatchEvent(pointer('pointercancel', 270));
    });
    expect(dialog()).toBeNull();
    await hold();
    await act(async () => {
      first.dispatchEvent(pointer('pointermove', 270));
      first.dispatchEvent(pointer('pointerup', 270));
    });
    expect(dialog()).toBeNull();
    const menu = document.querySelector('[role="menu"][aria-label="科目节数快捷操作"]');
    const actions = [...(menu?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]') ?? [])];
    expect(actions.map((action) => action.textContent)).toEqual([
      '复制', '粘贴', '统一设置 2 格', '清空所选格',
    ]);
    await act(async () => actions.find((action) => action.textContent === '统一设置 2 格')?.click());
    expect(dialog()?.textContent).toContain('统一设置 2 个格子');
    expect([...host.querySelectorAll('button')].some((button) =>
      button.textContent?.includes('统一设置')
    )).toBe(false);
    await act(async () => {
      const cancel = [...dialog()!.querySelectorAll('button')].find((button) => button.textContent === '取消');
      cancel?.click();
    });
    expect(dialog()).toBeNull();
    expect(cells.map((cell) => cell.textContent)).toEqual(originalValues);
  } finally {
    await act(async () => root.unmount());
    host.remove();
    useAppStore.setState(previousState, true);
    if (hitTest) Object.defineProperty(document, 'elementFromPoint', hitTest);
    else Reflect.deleteProperty(document, 'elementFromPoint');
    vi.useRealTimers();
    vi.unstubAllGlobals();
  }
});

it.each(['touch', 'mouse'])('免任课 %s 框选松手打开批量菜单，选中操作后只修改框选课节', async (pointerType) => {
  const { act, createElement } = await import('react');
  const { createRoot } = await import('react-dom/client');
  const { FreeSlotEditor } = await import('@/features/routines/FreeSlotEditor');
  const { useAppStore } = await import('@/store/useAppStore');
  const previousState = useAppStore.getState();
  const hitTest = Object.getOwnPropertyDescriptor(document, 'elementFromPoint');
  const stage = { id: 'stage', termId: 'term', name: '小学', sortOrder: 0 };
  const routine = {
    stageId: stage.id,
    teachingDays: [1, 2, 3].map((weekday) => ({
      id: `d-${weekday}`, stageId: stage.id, weekday, isTeachingDay: true,
    })),
    periodTypes: [{ id: 'am', stageId: stage.id, name: '上午', defaultLessonCount: 1, sortOrder: 0 }],
    dailyOverrides: [],
    lessonTimes: [],
  };
  const host = document.body.appendChild(document.createElement('div'));
  const root = createRoot(host);
  const pointer = (type: string, x: number) => new PointerEvent(type, {
    pointerId: 1, pointerType, isPrimary: true, bubbles: true,
    cancelable: true, clientX: x, clientY: 80, button: 0,
  });
  const draft = () => Object.values(useAppStore.getState().freeSlotDraftsByTerm.term ?? {});

  vi.useFakeTimers();
  vi.stubGlobal('navigator', { maxTouchPoints: pointerType === 'touch' ? 5 : 0 });
  vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
  useAppStore.setState({ freeSlotsByStage: {}, freeSlotDraftsByTerm: {}, loadFreeSlotsForStages: async () => {} });
  try {
    await act(async () => root.render(createElement(FreeSlotEditor, {
      termId: 'term', stages: [stage], grades: [], classes: [],
      routinesByStage: { [stage.id]: routine }, routineDraftsByStage: {}, routine,
      scope: { scopeType: 'stage', scopeId: stage.id, stageId: stage.id, parentGradeId: null },
      runHistory: (_label, action) => action(),
      onUpdateRoutine: () => {},
    })));
    const cells = [...host.querySelectorAll<HTMLButtonElement>('[data-matrix-cell]')];
    expect(cells).toHaveLength(3);
    const [first, second, third] = cells;
    Object.defineProperty(document, 'elementFromPoint', {
      configurable: true, value: (x: number) => x < 200 ? first : second,
    });
    const hold = () => act(async () => {
      first.dispatchEvent(pointer('pointerdown', 140));
      if (pointerType === 'touch') vi.advanceTimersByTime(500);
    });
    await hold();
    await act(async () => first.dispatchEvent(pointer('pointerup', 140)));
    expect(document.querySelector('[role="menu"]')).toBeNull();
    await hold();
    await act(async () => {
      first.dispatchEvent(pointer('pointermove', 270));
      first.dispatchEvent(pointer('pointercancel', 270));
    });
    expect(document.querySelector('[role="menu"]')).toBeNull();

    await hold();
    await act(async () => {
      first.dispatchEvent(pointer('pointermove', 270));
      first.dispatchEvent(pointer('pointerup', 270));
    });
    const menu = document.querySelector('[role="menu"]');
    expect(menu?.textContent ?? '').toContain('统一设置 2 个格子');
    expect(draft()).toEqual([]);
    const action = [...menu!.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')]
      .find((button) => button.textContent === '自习');
    await act(async () => action?.click());
    expect(document.querySelector('[role="menu"]')).toBeNull();
    expect(draft()).toEqual([
      expect.objectContaining({ weekday: 1, lessonIndex: 1, label: '自习' }),
      expect.objectContaining({ weekday: 2, lessonIndex: 1, label: '自习' }),
    ]);
    expect(third.textContent).toBe('');
  } finally {
    await act(async () => root.unmount());
    host.remove();
    useAppStore.setState(previousState, true);
    if (hitTest) Object.defineProperty(document, 'elementFromPoint', hitTest);
    else Reflect.deleteProperty(document, 'elementFromPoint');
    vi.useRealTimers();
    vi.unstubAllGlobals();
  }
});
