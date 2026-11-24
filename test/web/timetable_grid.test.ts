import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

test('weekly timetable renders a single common-period strip and accessible placement states', async () => {
  const { outputFiles } = await build({
    stdin: {
      contents: `
        import { renderToStaticMarkup } from 'react-dom/server';
        import { Provider } from '@radix-ui/react-tooltip';
        import { TimetableGrid } from '../../src/features/scheduling/TimetableGrid';
        const base = { stageId: 'stage', periodTypeId: 'am', lessonIndex: 1, order: 1,
          label: '第 1 节', periodName: '上午', startMinute: 480, endMinute: 525 };
        const slots = [1, 2].map(weekday => ({ ...base, weekday }));
        const preview = new Map([['stage:2:am:1', { status: 'blocked', reason: '教师已有课' }]]);
        module.exports = renderToStaticMarkup(<Provider><TimetableGrid title="班级课表"
          slots={slots} selectedSlot={slots[0]} preview={preview}
          commonPeriods={[{ id: 'eye', name: '眼保健操', insertAfterLessonId: 'time', sortOrder: 0,
            stageId: 'stage', durationMinutes: 5, startMinute: 525, endMinute: 530 }]}
          anchors={new Map([['time', 'am:1']])} render={() => null} onActivate={() => {}} /></Provider>);
      `,
      resolveDir: fileURLToPath(new URL('.', import.meta.url)),
      loader: 'tsx',
    },
    bundle: true,
    format: 'cjs',
    jsx: 'automatic',
    packages: 'external',
    platform: 'node',
    write: false,
  });
  const module = { exports: '' };
  new Function('require', 'module', outputFiles[0].text)(createRequire(import.meta.url), module);
  const html = module.exports;
  assert.match(html, /colSpan="3"[^>]*><div>眼保健操<\/div>/);
  assert.equal(html.match(/眼保健操/g)?.length, 1);
  assert.equal(html.match(/data-axis-active="true"/g)?.length, 2);
  assert.equal(html.match(/class="schedule-empty-slot"/g)?.length, 2);
  assert.match(html, /aria-label="周二 上午第 1 节，教师已有课" aria-disabled="true"/);
  assert.doesNotMatch(html, /class="schedule-drop-hint"/);
});
