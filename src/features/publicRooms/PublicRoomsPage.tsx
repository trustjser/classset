import React, { useEffect, useMemo, useState } from 'react';
import { Plus } from 'lucide-react';
import type { PublicRoom } from '@/domain/models';
import { createId } from '@/domain/id';
import {
  getRoomAssociations,
  PublicRoomTermData,
} from '@/features/publicRooms/publicRoomsData';
import { schoolRepository } from '@/repository/schoolRepository';
import { useAppStore } from '@/store/useAppStore';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

export const PublicRoomsPage: React.FC = () => {
  const {
    activeTermId,
    terms,
    stages,
    grades,
    classes,
    subjects,
    subjectRoomAssignments,
    publicRooms,
    savePublicRooms,
    deletePublicRoom,
  } = useAppStore();

  const [editorOpen, setEditorOpen] = useState(false);
  const [editingRoom, setEditingRoom] = useState<PublicRoom | null>(null);
  const [nameInput, setNameInput] = useState('');
  const [countInput, setCountInput] = useState('1');
  const [capacityInput, setCapacityInput] = useState('1');
  const [nameError, setNameError] = useState<string | null>(null);
  const [countError, setCountError] = useState<string | null>(null);
  const [capacityError, setCapacityError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const [deletingRoom, setDeletingRoom] = useState<PublicRoom | null>(null);
  const [deleteBindings, setDeleteBindings] = useState<string[] | null>(null);
  const [deleteLoading, setDeleteLoading] = useState(false);
  const [deleting, setDeleting] = useState(false);

  const termData = useMemo(() => {
    if (!activeTermId) return null;
    return new PublicRoomTermData({
      termId: activeTermId,
      stages,
      grades,
      classes,
      assignments: subjectRoomAssignments,
      subjects,
    });
  }, [
    activeTermId,
    stages,
    grades,
    classes,
    subjectRoomAssignments,
    subjects,
  ]);

  const openAddModal = () => {
    setEditingRoom(null);
    setNameInput('');
    setCountInput('1');
    setCapacityInput('1');
    setNameError(null);
    setCountError(null);
    setCapacityError(null);
    setEditorOpen(true);
  };

  const openEditModal = (room: PublicRoom) => {
    setEditingRoom(room);
    setNameInput(room.name);
    setCountInput(String(room.roomCount));
    setCapacityInput(String(room.capacityPerRoom));
    setNameError(null);
    setCountError(null);
    setCapacityError(null);
    setEditorOpen(true);
  };

  const handleSaveRoom = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmedName = nameInput.trim();
    let hasError = false;

    if (!trimmedName) {
      setNameError('请输入场室名称');
      hasError = true;
    } else {
      const lower = trimmedName.toLowerCase();
      const duplicate = publicRooms.some(
        (item) =>
          item.id !== editingRoom?.id && item.name.trim().toLowerCase() === lower
      );
      if (duplicate) {
        setNameError('已存在同名场室');
        hasError = true;
      } else {
        setNameError(null);
      }
    }

    const parsedCount = Number(countInput.trim());
    if (!Number.isInteger(parsedCount) || parsedCount <= 0) {
      setCountError('请输入正整数');
      hasError = true;
    } else {
      setCountError(null);
    }

    const parsedCapacity = Number(capacityInput.trim());
    if (!Number.isInteger(parsedCapacity) || parsedCapacity <= 0) {
      setCapacityError('请输入正整数');
      hasError = true;
    } else {
      setCapacityError(null);
    }

    if (hasError) return;

    const nextSortOrder = editingRoom
      ? editingRoom.sortOrder
      : publicRooms.length === 0
      ? 0
      : Math.max(...publicRooms.map((r) => r.sortOrder)) + 1;

    const room: PublicRoom = {
      id: editingRoom?.id ?? createId(),
      name: trimmedName,
      roomCount: parsedCount,
      capacityPerRoom: parsedCapacity,
      sortOrder: nextSortOrder,
    };

    setSaving(true);
    try {
      await savePublicRooms([room]);
      setEditorOpen(false);
    } finally {
      setSaving(false);
    }
  };

  useEffect(() => {
    if (!deletingRoom) {
      setDeleteBindings(null);
      setDeleteLoading(false);
      return;
    }
    let cancelled = false;
    setDeleteLoading(true);
    (async () => {
      try {
        const refs = await schoolRepository.loadRoomReferences(deletingRoom.id);
        const allTerms = terms.length > 0 ? terms : await schoolRepository.loadTerms();
        const termsById = new Map(allTerms.map((t) => [t.id, t]));
        const termIds = Array.from(new Set(refs.map((r) => r.termId)));
        const dataByTerm = new Map<string, PublicRoomTermData>();
        await Promise.all(
          termIds.map(async (tid) => {
            const data = await schoolRepository.loadPublicRoomTermData(tid);
            dataByTerm.set(tid, data);
          })
        );
        if (cancelled) return;
        const lines = refs.map((row) => {
          const termTitle = termsById.get(row.termId)?.title ?? '已移除学期';
          const data = dataByTerm.get(row.termId);
          return `${termTitle} · ${data ? data.bindingLabel(row) : row.subjectId}`;
        });
        setDeleteBindings(lines);
      } catch {
        if (!cancelled) setDeleteBindings([]);
      } finally {
        if (!cancelled) setDeleteLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [deletingRoom, terms]);

  const handleConfirmDelete = async () => {
    if (!deletingRoom) return;
    setDeleting(true);
    try {
      await deletePublicRoom(deletingRoom.id);
      setDeletingRoom(null);
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="rounded-card bg-surface overflow-hidden">
        {/* Top Header */}
        <div className="px-[18px] py-4 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-base font-bold text-ink">公共场室</h2>
            <p className="mt-1 text-xs text-ink-secondary">
              维护全校共用的行课场室，容量单位为班。
            </p>
          </div>
          {!activeTermId && (
            <span className="text-xs text-ink-secondary">
              选择学期后显示关联科目
            </span>
          )}
        </div>

        <div className="border-t border-border" />

        {/* Desktop Wide Table (>= 760px) */}
        <div className="hidden md:block">
          <div className="h-10 px-[18px] bg-table-header border-b border-border flex items-center text-[13px] font-semibold text-ink-secondary">
            <div className="flex-[26] min-w-0">场室</div>
            <div className="flex-[9] text-center">个数</div>
            <div className="flex-[15] text-center">容量（班）</div>
            <div className="flex-[22] text-center">同时段上限（个班）</div>
            <div className="flex-[23] min-w-0">关联科目</div>
            <div className="flex-[12] text-center">操作</div>
          </div>

          {publicRooms.length === 0 ? (
            <div className="h-24 flex items-center justify-center text-sm text-ink-secondary">
              暂无公共场室，点击下方添加
            </div>
          ) : (
            <div className="divide-y divide-border">
              {publicRooms.map((room) => {
                const total = room.roomCount * room.capacityPerRoom;
                const isShared = termData?.isSharedAcrossStages(room.id) ?? false;
                const associations = getRoomAssociations(room.id, termData);
                return (
                  <div
                    key={room.id}
                    className="px-[18px] py-3.5 flex items-center text-[13px] text-ink hover:bg-table-header/40 transition-colors"
                  >
                    <div className="flex-[26] min-w-0 pr-2 flex flex-wrap items-center gap-2">
                      <span className="text-[13.5px] font-semibold text-ink">
                        {room.name}
                      </span>
                      {isShared && (
                        <span className="px-2 py-0.5 rounded-full bg-selection text-primary text-[11px] font-semibold">
                          跨学段共用
                        </span>
                      )}
                    </div>
                    <div className="flex-[9] text-center">{room.roomCount}</div>
                    <div className="flex-[15] text-center">
                      {room.capacityPerRoom}
                    </div>
                    <div className="flex-[22] text-center text-ink-secondary">
                      {room.roomCount} × {room.capacityPerRoom} ={' '}
                      <span className="font-bold text-ink">{total} 班</span>
                    </div>
                    <div className="flex-[23] min-w-0 pr-2">
                      {associations.length === 0 ? (
                        <span className="text-[13px] text-ink-secondary">—</span>
                      ) : (
                        <div className="flex flex-wrap gap-1.5">
                          {associations.map((item, idx) => (
                            <span
                              key={`${item.label}_${idx}`}
                              title={item.tooltip}
                              className="px-2.5 py-0.5 rounded-full bg-selection text-primary text-xs font-medium cursor-default"
                            >
                              {item.label}
                            </span>
                          ))}
                        </div>
                      )}
                    </div>
                    <div className="flex-[12] flex items-center justify-center gap-3">
                      <button
                        type="button"
                        onClick={() => openEditModal(room)}
                        className="text-[13px] font-medium text-primary hover:underline"
                      >
                        编辑
                      </button>
                      <button
                        type="button"
                        onClick={() => setDeletingRoom(room)}
                        className="text-[13px] font-medium text-destructive hover:underline"
                      >
                        删除
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          <div className="border-t border-border">
            <button
              type="button"
              onClick={openAddModal}
              className="w-full h-11 bg-table-header hover:bg-selection/60 transition-colors flex items-center justify-center gap-1.5 text-[13px] font-semibold text-primary"
            >
              <Plus className="w-4 h-4" />
              <span>添加场室</span>
            </button>
          </div>
        </div>

        {/* Compact Mobile / Narrow View (< 760px) */}
        <div className="md:hidden p-4 space-y-3">
          {publicRooms.length === 0 ? (
            <div className="py-6 text-center text-sm text-ink-secondary">
              暂无公共场室，点击下方添加
            </div>
          ) : (
            publicRooms.map((room) => {
              const total = room.roomCount * room.capacityPerRoom;
              const isShared = termData?.isSharedAcrossStages(room.id) ?? false;
              const associations = getRoomAssociations(room.id, termData);
              return (
                <div
                  key={room.id}
                  className="p-3.5 rounded-[10px] border border-border bg-surface space-y-2.5"
                >
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex flex-wrap items-center gap-2 min-w-0">
                      <span className="text-sm font-semibold text-ink">
                        {room.name}
                      </span>
                      {isShared && (
                        <span className="px-2 py-0.5 rounded-full bg-selection text-primary text-[11px] font-semibold">
                          跨学段共用
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-3 shrink-0">
                      <button
                        type="button"
                        onClick={() => openEditModal(room)}
                        className="text-[13px] font-medium text-primary hover:underline"
                      >
                        编辑
                      </button>
                      <button
                        type="button"
                        onClick={() => setDeletingRoom(room)}
                        className="text-[13px] font-medium text-destructive hover:underline"
                      >
                        删除
                      </button>
                    </div>
                  </div>
                  <div className="flex flex-wrap gap-4 text-xs text-ink-secondary">
                    <div>
                      个数：<span className="font-semibold text-ink">{room.roomCount}</span>
                    </div>
                    <div>
                      每间容量：
                      <span className="font-semibold text-ink">
                        {room.capacityPerRoom} 班
                      </span>
                    </div>
                    <div>
                      同时段上限：
                      <span className="font-semibold text-ink">{total} 班</span>
                    </div>
                  </div>
                  <div className="flex flex-wrap items-center gap-1.5">
                    {associations.length === 0 ? (
                      <span className="text-xs text-ink-secondary">
                        关联科目：—
                      </span>
                    ) : (
                      associations.map((item, idx) => (
                        <span
                          key={`${item.label}_${idx}`}
                          title={item.tooltip}
                          className="px-2.5 py-0.5 rounded-full bg-selection text-primary text-xs font-medium"
                        >
                          {item.label}
                        </span>
                      ))
                    )}
                  </div>
                </div>
              );
            })
          )}
          <Button
            type="button"
            variant="outline"
            onClick={openAddModal}
            className="w-full"
          >
            <Plus className="w-4 h-4 mr-1.5" />
            添加场室
          </Button>
        </div>
      </div>

      {/* Add / Edit Room Dialog */}
      <Dialog open={editorOpen} onOpenChange={setEditorOpen}>
        <DialogContent className="sm:max-w-[420px]">
          <DialogHeader>
            <DialogTitle>
              {editingRoom ? '编辑场室' : '添加场室'}
            </DialogTitle>
            <DialogDescription>
              设置公共场室名称、间数及每间可同时容纳的班级数。
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleSaveRoom} className="space-y-4 py-1">
            <div className="space-y-1.5">
              <Label htmlFor="public-room-name">场室名称</Label>
              <Input
                id="public-room-name"
                value={nameInput}
                onChange={(e) => {
                  setNameInput(e.target.value);
                  if (nameError) setNameError(null);
                }}
                placeholder="例如：实验室"
                autoFocus
              />
              {nameError && (
                <p className="text-xs text-destructive">{nameError}</p>
              )}
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="public-room-count">场室个数</Label>
              <Input
                id="public-room-count"
                type="number"
                min={1}
                step={1}
                value={countInput}
                onChange={(e) => {
                  setCountInput(e.target.value);
                  if (countError) setCountError(null);
                }}
              />
              {countError && (
                <p className="text-xs text-destructive">{countError}</p>
              )}
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="public-room-capacity">每间容量（班）</Label>
              <Input
                id="public-room-capacity"
                type="number"
                min={1}
                step={1}
                value={capacityInput}
                onChange={(e) => {
                  setCapacityInput(e.target.value);
                  if (capacityError) setCapacityError(null);
                }}
              />
              {capacityError && (
                <p className="text-xs text-destructive">{capacityError}</p>
              )}
            </div>

            <DialogFooter className="pt-2">
              <Button
                type="button"
                variant="outline"
                onClick={() => setEditorOpen(false)}
                disabled={saving}
              >
                取消
              </Button>
              <Button type="submit" disabled={saving}>
                保存
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete Room Confirmation Dialog */}
      <Dialog
        open={deletingRoom !== null}
        onOpenChange={(open) => {
          if (!open && !deleting) setDeletingRoom(null);
        }}
      >
        <DialogContent className="sm:max-w-[460px]">
          <DialogHeader>
            <DialogTitle>
              {deletingRoom ? `删除“${deletingRoom.name}”？` : '删除场室'}
            </DialogTitle>
            <DialogDescription>
              此操作会同时移除所有学期中引用该场室的科目绑定。
            </DialogDescription>
          </DialogHeader>

          <div className="py-2">
            {deleteLoading || deleteBindings === null ? (
              <div className="py-4 text-center text-sm text-ink-secondary">
                正在检查场室绑定…
              </div>
            ) : deleteBindings.length === 0 ? (
              <div className="text-sm text-ink-secondary">
                此场室暂无科目绑定。
              </div>
            ) : (
              <div className="max-h-[220px] overflow-y-auto rounded-lg border border-border bg-table-header/40 p-3 space-y-1.5">
                {deleteBindings.map((item, idx) => (
                  <div key={`${item}_${idx}`} className="text-[13px] text-ink">
                    {item}
                  </div>
                ))}
              </div>
            )}
          </div>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => setDeletingRoom(null)}
              disabled={deleting}
            >
              取消
            </Button>
            <Button
              type="button"
              variant="destructive"
              onClick={handleConfirmDelete}
              disabled={deleteLoading || deleteBindings === null || deleting}
            >
              删除场室及绑定
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};
