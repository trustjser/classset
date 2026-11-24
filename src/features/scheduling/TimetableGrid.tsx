import { useState, type DragEvent, type ReactNode } from 'react';
import * as Tooltip from '@radix-ui/react-tooltip';
import { Ban, CircleCheck, Info } from 'lucide-react';
import type { CommonPeriod } from '../../domain/models';
import { slotKey, type PlacementPreview, type ScheduleSlot } from '../../domain/scheduling';
import { WEEKDAY_SHORT_NAMES } from '../../domain/routineUtils';

export const weekdayName = (day: number) => `周${WEEKDAY_SHORT_NAMES[day - 1]}`;
export const slotName = (slot: ScheduleSlot) => `${weekdayName(slot.weekday)} ${slot.periodName}${slot.label}`;

export function clockLabel(start: number | null, end: number | null) {
  if (start === null || end === null) return '';
  const format = (minute: number) => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
  return `${format(start)}–${format(end)}`;
}

interface TimetableGridProps {
  title: string;
  slots: ScheduleSlot[];
  commonPeriods?: CommonPeriod[];
  anchors?: Map<string, string>;
  periodIds?: string[];
  render: (slot: ScheduleSlot) => ReactNode;
  preview?: Map<string, PlacementPreview>;
  onActivate?: (slot: ScheduleSlot) => void;
  onHover?: (slot: ScheduleSlot | null) => void;
  onDrop?: (slot: ScheduleSlot, event: DragEvent) => void;
  highlight?: (slot: ScheduleSlot) => boolean;
  selectedSlot?: ScheduleSlot;
  dragSourceSlot?: ScheduleSlot;
  previewSlot?: ScheduleSlot | null;
}

export function TimetableGrid({ title, slots, commonPeriods = [], anchors, periodIds = [], render, preview, onActivate, onHover, onDrop, highlight, selectedSlot, dragSourceSlot, previewSlot }: TimetableGridProps) {
  const [pointedSlot, setPointedSlot] = useState<ScheduleSlot | null>(null);
  const activeSlot = pointedSlot ?? selectedSlot;
  const pointAt = (slot: ScheduleSlot | null) => {
    setPointedSlot(slot);
    onHover?.(slot);
  };
  const days = [...new Set(slots.map((slot) => slot.weekday))].sort((a, b) => a - b);
  const rowKey = (slot: ScheduleSlot) => `${slot.periodTypeId}:${slot.lessonIndex}`;
  const periodOrder = new Map(periodIds.map((id, index) => [id, index]));
  const rows = [...new Map(slots.map((slot) => [rowKey(slot), slot])).values()].sort((a, b) =>
    (periodOrder.get(a.periodTypeId) ?? a.order) - (periodOrder.get(b.periodTypeId) ?? b.order) || a.lessonIndex - b.lessonIndex);
  const cells = new Map(slots.map((slot) => [slotKey(slot), slot]));
  const rowKeys = new Set(rows.map(rowKey));
  const legacyAnchors = new Map(rows.map((row) => [`${row.periodTypeId}_${row.lessonIndex}`, rowKey(row)]));
  const anchorFor = (row: CommonPeriod) => row.insertAfterLessonId &&
    (anchors?.get(row.insertAfterLessonId) ?? legacyAnchors.get(row.insertAfterLessonId) ?? row.insertAfterLessonId);
  const inserted = [...commonPeriods].sort((a, b) => a.sortOrder - b.sortOrder);
  const commonRow = (row: CommonPeriod) => (
    <tr key={row.id} className="schedule-common">
      <td colSpan={days.length + 1} title={clockLabel(row.startMinute, row.endMinute)}>
        <div>{row.name}</div>
      </td>
    </tr>
  );
  if (!days.length) return <p className="schedule-empty">当前范围没有已配置的上课节次。</p>;
  return (
    <div className="schedule-table-scroll">
      <table className="schedule-grid schedule-grid-cards schedule-grid-week" aria-label={title}>
        <thead><tr><th scope="col">节次</th>{days.map((day) => (
          <th key={day} scope="col" data-axis-active={activeSlot?.weekday === day || undefined}>{weekdayName(day)}</th>
        ))}</tr></thead>
        <tbody>
          {inserted.filter((common) => !common.insertAfterLessonId).map(commonRow)}
          {rows.flatMap((row) => [
            <tr key={rowKey(row)}>
              <th scope="row" data-axis-active={!!activeSlot && rowKey(activeSlot) === rowKey(row) || undefined}>
                <div className="schedule-period-label" title={[row.periodName, row.label, clockLabel(row.startMinute, row.endMinute)].filter(Boolean).join(' · ')}>
                  <span>{row.periodName}</span>
                  <small>{[row.label, clockLabel(row.startMinute, row.endMinute)].filter(Boolean).join(' · ')}</small>
                </div>
              </th>
              {days.map((day) => {
                const time = cells.get(slotKey({ ...row, weekday: day }));
                if (!time) return <td key={day} className="schedule-no-slot" aria-label="未设课节">—</td>;
                const content = render(time);
                const dragSource = dragSourceSlot !== undefined && dragSourceSlot.stageId === time.stageId && slotKey(dragSourceSlot) === slotKey(time);
                const offer = dragSource ? undefined : preview?.get(slotKey(time));
                const blocked = offer?.status === 'blocked';
                const pointed = !!pointedSlot && pointedSlot.stageId === time.stageId && slotKey(pointedSlot) === slotKey(time);
                const shimmerTarget = !dragSource && pointed && !!offer && !blocked;
                const hintOpen = !!offer && !!previewSlot && previewSlot.stageId === time.stageId && slotKey(previewSlot) === slotKey(time);
                const success = offer?.status === 'available';
                return (
                  <td key={day} data-drop={offer?.status} data-drag-source={dragSource || undefined}
                    data-shimmer-target={shimmerTarget || undefined}
                    data-linked={highlight?.(time) || undefined}
                    data-pointed={pointed || undefined}
                    onMouseEnter={() => pointAt(time)} onMouseLeave={() => pointAt(null)}
                    onFocus={() => pointAt(time)}
                    onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget)) pointAt(null); }}
                    onDragOver={onDrop ? (event) => {
                      pointAt(time);
                      if (offer && !blocked) {
                        event.preventDefault();
                        event.dataTransfer.dropEffect = 'move';
                      }
                    } : undefined}
                    onDragLeave={onDrop ? (event) => {
                      if (!(event.relatedTarget instanceof Node) || !event.currentTarget.contains(event.relatedTarget)) pointAt(null);
                    } : undefined}
                    onDrop={onDrop ? (event) => onDrop(time, event) : undefined}>
                    <Tooltip.Root open={hintOpen} disableHoverableContent>
                      <Tooltip.Trigger asChild>
                        <div className="schedule-slot">
                          <div className="schedule-slot-content">{content ?? <span className="schedule-empty-slot" aria-hidden="true" />}</div>
                          {onActivate && offer && (
                            <button type="button" className="schedule-drop-target"
                              aria-label={`${slotName(time)}，${offer.reason}`} aria-disabled={blocked}
                              onClick={() => { pointAt(time); if (!blocked) onActivate(time); }}>
                              {blocked && <Ban size={14} aria-hidden="true" />}
                            </button>
                          )}
                        </div>
                      </Tooltip.Trigger>
                      {offer && hintOpen && <Tooltip.Portal>
                        <Tooltip.Content className="schedule-drop-hint" data-tone={success ? 'success' : 'warning'}
                          side="top" sideOffset={8} collisionPadding={12}>
                          {success ? <CircleCheck size={15} aria-hidden="true" /> : <Info size={15} aria-hidden="true" />}
                          <span>{offer.reason}</span>
                          <Tooltip.Arrow className="schedule-drop-hint-arrow" width={12} height={6} />
                        </Tooltip.Content>
                      </Tooltip.Portal>}
                    </Tooltip.Root>
                  </td>
                );
              })}
            </tr>,
            ...inserted.filter((common) => anchorFor(common) === rowKey(row)).map(commonRow),
          ])}
          {inserted.filter((common) => !!common.insertAfterLessonId && !rowKeys.has(anchorFor(common) ?? '')).map(commonRow)}
        </tbody>
      </table>
    </div>
  );
}
