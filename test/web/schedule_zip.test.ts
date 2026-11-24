import assert from 'node:assert/strict';
import test from 'node:test';
import { timetableZip } from '../../src/features/scheduling/timetableZip.ts';

test('timetable ZIP declares UTF-8 names in both local and central headers', () => {
  const name = '班级课表/三(1)班.xlsx';
  const content = new Uint8Array([1, 2, 3]);
  const zip = timetableZip([{ name, content }]);
  const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);
  const end = zip.length - 22;
  const central = view.getUint32(end + 16, true);
  const nameLength = view.getUint16(26, true);
  assert.equal(view.getUint32(0, true), 0x04034b50);
  assert.equal(view.getUint32(central, true), 0x02014b50);
  assert.equal(view.getUint16(6, true) & 0x800, 0x800);
  assert.equal(view.getUint16(central + 8, true) & 0x800, 0x800);
  assert.equal(view.getUint32(14, true), 0x55bc801d);
  assert.equal(new TextDecoder().decode(zip.subarray(30, 30 + nameLength)), name);
  assert.equal(new TextDecoder().decode(zip.subarray(central + 46, central + 46 + nameLength)), name);
  assert.deepEqual(zip.subarray(30 + nameLength, central), content);
});
