import { useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { SearchableSelect } from '@/components/ui/searchable-select';
import { SelectField } from '@/components/ui/select-field';
import type { ScheduleCondition, ScheduleLock, SchedulePreferences } from '@/domain/models';
import type { ScheduleData } from '@/domain/scheduling';
import { createId } from '@/domain/id';
import { weekdayName } from './TimetableGrid';

const kinds = [
  ['dailyLimit', '每日节数限制'], ['periodLimit', '时段节数限制'],
  ['teacherMutualExclusion', '教师不能同时任课'], ['subjectMutualExclusion', '科目不能同一天'], ['forbiddenAdjacency', '科目禁止相邻'],
] as const;

export function ScheduleRulesDialog({ data, onClose, onSave }: {
  data: ScheduleData;
  onClose: () => void;
  onSave: (rows: ScheduleCondition[], preferences: SchedulePreferences, locks: ScheduleLock[]) => Promise<void>;
}) {
  const [conditions, setConditions] = useState(data.conditions);
  const [preferences, setPreferences] = useState(data.preferences);
  const [locks, setLocks] = useState(data.locks);
  const [lockScope, setLockScope] = useState<ScheduleLock['scope']>('class');
  const [lockTarget, setLockTarget] = useState('');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const updateRule = (id: string, patch: Partial<ScheduleCondition>) =>
    setConditions((rows) => rows.map((row) => row.id === id ? { ...row, ...patch } : row));
  const save = async () => {
    for (const row of conditions) {
      const limit = row.kind === 'periodLimit' || row.kind === 'dailyLimit';
      if (!row.targetId || (row.kind === 'periodLimit' && !row.periodTypeId) ||
        (limit && [row.minCount, row.maxCount, row.exactCount].every((count) => count === null)) ||
        (!limit && (!row.otherId || row.targetId === row.otherId)) ||
        [row.minCount, row.maxCount, row.exactCount].some((count) => count !== null && (!Number.isInteger(count) || count < 0)) ||
        (row.minCount !== null && row.maxCount !== null && row.minCount > row.maxCount)) {
        setError('请补齐条件对象和节数，或检查两个互斥对象是否相同。');
        return;
      }
    }
    setSaving(true);
    try { await onSave(conditions, preferences, locks); }
    catch (reason) { setError(String(reason)); }
    finally { setSaving(false); }
  };
  const choice = (label: string, key: 'strength' | 'progressConsistency' | 'teacherDistribution' | 'consecutivePolicy', options: Array<[string, string]>) => (
    <label className="grid gap-1 text-sm">{label}
      <SelectField ariaLabel={label} className="w-full" value={preferences[key]}
        onValueChange={(value) => setPreferences({ ...preferences, [key]: value })}
        options={options.map(([id, name]) => ({ value: id, label: name }))} />
    </label>
  );
  const targets = lockScope === 'class' ? data.classes : data.teachers;
  return (
    <Dialog open onOpenChange={(open) => { if (!open && !saving) onClose(); }}>
      <DialogContent className="max-w-[760px] max-h-[86vh] overflow-auto">
        <DialogHeader><DialogTitle>排课偏好与规则</DialogTitle><DialogDescription>设置自动排课策略、硬条件和课表锁定。</DialogDescription></DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          {choice('排课强度', 'strength', [['fast', '快速'], ['normal', '标准'], ['high', '高强度']])}
          {choice('教学进度', 'progressConsistency', [['prefer', '优先保持一致'], ['require', '要求一致']])}
          {choice('教师课程分布', 'teacherDistribution', [['indifferent', '无偏好'], ['spread', '尽量分散'], ['concentrate', '尽量集中']])}
          {choice('连堂策略', 'consecutivePolicy', [['preferSeparate', '尽量不连堂'], ['requireSeparate', '禁止非必要连堂'], ['preferTogether', '尽量连堂']])}
          <label className="inline-flex items-center gap-2 text-sm"><Checkbox checked={preferences.lunchProtection}
            onCheckedChange={(checked) => setPreferences({ ...preferences, lunchProtection: checked === true })} />保护午间休息</label>
          <label className="inline-flex items-center gap-2 text-sm"><Checkbox checked={preferences.detectProgressConsistency}
            onCheckedChange={(checked) => setPreferences({ ...preferences, detectProgressConsistency: checked === true })} />检查教学进度一致性</label>
        </div>
        <section className="space-y-2 border-t border-border pt-3">
          <div className="flex items-center justify-between"><h3 className="font-semibold">自定义硬条件</h3>
            <Button type="button" size="sm" variant="outline" onClick={() => setConditions([...conditions, {
              id: createId(), termId: data.term.id, kind: 'dailyLimit', targetKind: 'subject',
              name: null, targetId: null, otherId: null, periodTypeId: null, weekday: null, minCount: null, maxCount: null, exactCount: null,
            }])}><Plus />添加条件</Button></div>
          {conditions.map((row) => {
            const limit = ['dailyLimit', 'periodLimit'].includes(row.kind);
            const options = row.targetKind === 'teacher' ? data.teachers : data.subjects;
            const entityOptions = options.map((item) => ({ value: item.id, label: item.name }));
            const renderEntitySelect = (value: string, placeholder: string, ariaLabel: string, onValueChange: (next: string) => void) =>
              row.targetKind === 'teacher'
                ? <SearchableSelect ariaLabel={ariaLabel} className="h-8 w-auto min-w-[9rem] max-w-[14rem]"
                    emptyText="没有匹配的教师" options={entityOptions} onValueChange={onValueChange}
                    placeholder={placeholder} searchPlaceholder="搜索教师" value={value} />
                : <SelectField ariaLabel={ariaLabel} className="h-8 w-auto min-w-[9rem] max-w-[14rem]"
                    emptyText="无可选科目" options={entityOptions} onValueChange={onValueChange}
                    placeholder={placeholder} value={value} />;
            return <div key={row.id} className="flex flex-wrap items-center gap-2 rounded-control border border-border p-2 text-sm">
              <SelectField ariaLabel="条件类型" className="h-8 w-auto min-w-[10rem]" value={row.kind}
                options={kinds.map(([value, label]) => ({ value, label }))} onValueChange={(value) => {
                const kind = value as ScheduleCondition['kind'];
                updateRule(row.id, { kind, targetKind: kind === 'teacherMutualExclusion' ? 'teacher' : 'subject', targetId: null,
                  otherId: null, periodTypeId: null, minCount: null, maxCount: null, exactCount: null });
              }} />
              <Input className="h-8 w-32" aria-label="条件名称" placeholder="条件名称" value={row.name ?? ''}
                onChange={(event) => updateRule(row.id, { name: event.target.value || null })} />
              {limit && <SelectField ariaLabel="对象类别" className="h-8 w-auto min-w-[6rem]" value={row.targetKind ?? 'subject'}
                onValueChange={(value) => updateRule(row.id, { targetKind: value as ScheduleCondition['targetKind'], targetId: null })}
                options={[{ value: 'subject', label: '科目' }, { value: 'teacher', label: '教师' }]} />}
              {renderEntitySelect(row.targetId ?? '', '选择对象', '对象 A', (value) => updateRule(row.id, { targetId: value || null }))}
              {!limit && renderEntitySelect(row.otherId ?? '', '选择另一对象', '对象 B', (value) => updateRule(row.id, { otherId: value || null }))}
              {row.kind === 'periodLimit' && <SelectField ariaLabel="限制时段" className="h-8 w-auto min-w-[10rem] max-w-[14rem]"
                value={row.periodTypeId ?? ''} onValueChange={(value) => updateRule(row.id, { periodTypeId: value || null })}
                placeholder="选择时段" emptyText="无可用时段" options={data.routines.flatMap((routine) => {
                  const stageName = data.stages.find((stage) => stage.id === routine.stageId)?.name ?? '学段';
                  return routine.periodTypes.map((period) => ({ value: period.id, label: `${stageName} · ${period.name}` }));
                })} />}
              <SelectField ariaLabel="适用日期" className="h-8 w-auto min-w-[6rem]" value={row.weekday === null ? '' : String(row.weekday)}
                onValueChange={(value) => updateRule(row.id, { weekday: value ? Number(value) : null })}
                options={[{ value: '', label: '每天' }, ...[1, 2, 3, 4, 5, 6, 7].map((day) => ({ value: String(day), label: weekdayName(day) }))]} />
              {limit && ([['minCount', '最少'], ['maxCount', '最多'], ['exactCount', '恰好']] as const).map(([key, label]) =>
                <Input key={key} className="h-8 w-[70px]" type="number" min="0" step="1" aria-label={label} placeholder={label}
                  value={row[key] ?? ''} onChange={(event) => updateRule(row.id, { [key]: event.target.value === '' ? null : Number(event.target.value) })} />)}
              <Button type="button" variant="ghost" size="sm" aria-label="删除条件" onClick={() => setConditions(conditions.filter((item) => item.id !== row.id))}><Trash2 /></Button>
            </div>;
          })}
          {!conditions.length && <p className="text-sm text-ink-secondary">没有自定义硬条件</p>}
        </section>
        <section className="space-y-2 border-t border-border pt-3">
          <h3 className="font-semibold">锁定已有课表</h3>
          <div className="flex flex-wrap gap-2">
            <SelectField ariaLabel="锁定范围" className="h-8 w-auto min-w-[7rem]" value={lockScope}
              onValueChange={(value) => { setLockScope(value as ScheduleLock['scope']); setLockTarget(''); }}
              options={[{ value: 'class', label: '班级' }, { value: 'teacher', label: '教师' }]} />
            <SearchableSelect ariaLabel="选择锁定对象" className="h-8 w-auto min-w-[10rem] max-w-[15rem]" value={lockTarget}
              onValueChange={setLockTarget} placeholder="选择对象" searchPlaceholder={lockScope === 'class' ? '搜索班级' : '搜索教师'}
              emptyText={lockScope === 'class' ? '没有匹配的班级' : '没有匹配的教师'}
              options={targets.filter((row) => data.items.some((item) => item.weekday !== null &&
                (lockScope === 'class' ? item.classId === row.id : item.teacherId === row.id))).map((row) => ({ value: row.id, label: row.name }))} />
            <Button variant="outline" size="sm" disabled={!lockTarget || locks.some((row) => row.scope === lockScope && row.targetId === lockTarget)} onClick={() =>
              setLocks([...locks, { id: `${data.term.id}:${lockScope}:${lockTarget}`, termId: data.term.id, scope: lockScope, targetId: lockTarget }])}>锁定</Button>
          </div>
          {locks.map((lock) => <div key={lock.id} className="flex items-center justify-between text-sm">
            <span>{(lock.scope === 'class' ? data.classes : data.teachers).find((row) => row.id === lock.targetId)?.name ?? lock.targetId}</span>
            <Button size="sm" variant="ghost" onClick={() => setLocks(locks.filter((row) => row.id !== lock.id))}>解除锁定</Button>
          </div>)}
        </section>
        {error && <p role="alert" className="schedule-error">{error}</p>}
        <DialogFooter><Button variant="ghost" disabled={saving} onClick={onClose}>取消</Button><Button disabled={saving} onClick={() => void save()}>{saving ? '保存中…' : '保存'}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
