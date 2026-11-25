import { useCallback, useRef } from 'react';

// Attach scroll tracking only after each toolbar is mounted, including delayed page content.
export function useStickyToolbar<T extends HTMLElement>() {
  const cleanupRef = useRef<(() => void) | null>(null);

  const ref = useCallback((toolbar: T | null) => {
    cleanupRef.current?.();
    cleanupRef.current = null;
    if (!toolbar) return;

    let scrollRoot = toolbar.parentElement;
    while (scrollRoot) {
      const overflowY = getComputedStyle(scrollRoot).overflowY;
      if (overflowY === 'auto' || overflowY === 'scroll' || overflowY === 'overlay') break;
      scrollRoot = scrollRoot.parentElement;
    }
    const updateStuckState = () => {
      const scrollRootTop = scrollRoot
        ? scrollRoot.getBoundingClientRect().top + scrollRoot.clientTop
        : 0;
      const stickyTop = Number.parseFloat(getComputedStyle(toolbar).top) || 0;
      const rootTop = scrollRootTop + stickyTop;
      const toolbarTop = toolbar.getBoundingClientRect().top;
      toolbar.dataset.stuck = String(Math.abs(toolbarTop - rootTop) <= 2);
    };

    const resizeObserver = typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver(updateStuckState);
    if (scrollRoot) resizeObserver?.observe(scrollRoot);
    resizeObserver?.observe(toolbar);

    const scrollTarget = scrollRoot ?? window;
    scrollTarget.addEventListener('scroll', updateStuckState, { passive: true });
    window.addEventListener('resize', updateStuckState);
    updateStuckState();

    cleanupRef.current = () => {
      scrollTarget.removeEventListener('scroll', updateStuckState);
      window.removeEventListener('resize', updateStuckState);
      resizeObserver?.disconnect();
    };
  }, []);

  return ref;
}
