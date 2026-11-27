import { useEffect, useRef, type PointerEvent } from 'react';

export function hasTouchInput(): boolean {
  return navigator.maxTouchPoints > 0 || window.matchMedia?.('(any-pointer: coarse)')?.matches === true;
}

export function canStartSelection(event: Pick<PointerEvent, 'button' | 'isPrimary'>): boolean {
  return event.button === 0 && event.isPrimary;
}

const SELECTION_PRESS_MS = 350;
const SCROLL_THRESHOLD_PX = 8;

interface SelectionPress {
  pointerId: number;
  x: number;
  y: number;
  timer: number;
  active: boolean;
}

export function useSelectionPress() {
  const pressRef = useRef<SelectionPress | null>(null);
  const suppressClickRef = useRef(false);

  useEffect(() => {
    const clearPress = () => {
      if (!pressRef.current) return;
      window.clearTimeout(pressRef.current.timer);
      pressRef.current = null;
    };
    const onPointerDown = (event: globalThis.PointerEvent) => {
      if (event.isPrimary) suppressClickRef.current = false;
    };
    const onPointerMove = (event: globalThis.PointerEvent) => {
      const press = pressRef.current;
      if (!press || press.active || press.pointerId !== event.pointerId) return;
      if (Math.hypot(event.clientX - press.x, event.clientY - press.y) > SCROLL_THRESHOLD_PX) {
        clearPress();
      }
    };
    const onPointerEnd = (event: globalThis.PointerEvent) => {
      if (pressRef.current?.pointerId === event.pointerId) clearPress();
    };
    // Safari decides whether to scroll at the first touchmove. Cancel it only
    // after the hold has activated selection so regular swipes still scroll.
    const onTouchMove = (event: TouchEvent) => {
      if (event.touches.length !== 1) {
        clearPress();
      } else if (pressRef.current?.active) {
        event.preventDefault();
      }
    };
    const onContextMenu = (event: MouseEvent) => {
      if (!pressRef.current?.active) return;
      event.preventDefault();
      event.stopPropagation();
    };
    const onClick = (event: MouseEvent) => {
      if (!suppressClickRef.current || event.detail === 0) return;
      suppressClickRef.current = false;
      event.preventDefault();
      event.stopPropagation();
    };

    window.addEventListener('pointerdown', onPointerDown, true);
    window.addEventListener('pointermove', onPointerMove, true);
    window.addEventListener('pointerup', onPointerEnd, true);
    window.addEventListener('pointercancel', onPointerEnd, true);
    document.addEventListener('touchmove', onTouchMove, { capture: true, passive: false });
    window.addEventListener('contextmenu', onContextMenu, true);
    window.addEventListener('click', onClick, true);
    window.addEventListener('blur', clearPress);
    return () => {
      clearPress();
      window.removeEventListener('pointerdown', onPointerDown, true);
      window.removeEventListener('pointermove', onPointerMove, true);
      window.removeEventListener('pointerup', onPointerEnd, true);
      window.removeEventListener('pointercancel', onPointerEnd, true);
      document.removeEventListener('touchmove', onTouchMove, true);
      window.removeEventListener('contextmenu', onContextMenu, true);
      window.removeEventListener('click', onClick, true);
      window.removeEventListener('blur', clearPress);
    };
  }, []);

  return (event: PointerEvent, start: () => void) => {
    if (!canStartSelection(event)) return;
    if (event.pointerType !== 'touch') {
      start();
      return;
    }
    if (pressRef.current) return;
    const press: SelectionPress = {
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      active: false,
      timer: window.setTimeout(() => {
        if (pressRef.current !== press) return;
        press.active = true;
        suppressClickRef.current = true;
        start();
      }, SELECTION_PRESS_MS),
    };
    pressRef.current = press;
  };
}
