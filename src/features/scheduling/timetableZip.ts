const checksumTable = Uint32Array.from({ length: 256 }, (_, index) => {
  let value = index;
  for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ (value & 1 ? 0xedb88320 : 0);
  return value;
});

/** XLSX entries are already compressed. Store them in ZIP with UTF-8 filenames. */
export function timetableZip(entries: Array<{ name: string; content: Uint8Array }>) {
  const encoder = new TextEncoder();
  const files = entries.map(({ name, content }) => ({ name: encoder.encode(name), content }));
  const localLength = files.reduce((size, file) => size + 30 + file.name.length + file.content.length, 0);
  const centralLength = files.reduce((size, file) => size + 46 + file.name.length, 0);
  if (files.length > 0xffff || localLength + centralLength + 22 > 0xffffffff || files.some((file) => file.name.length > 0xffff)) {
    throw new Error('课表压缩包太大，请减少导出范围');
  }
  const bytes = new Uint8Array(localLength + centralLength + 22);
  const view = new DataView(bytes.buffer);
  const short = (offset: number, value: number) => view.setUint16(offset, value, true);
  const long = (offset: number, value: number) => view.setUint32(offset, value, true);
  const version = 20;
  const utf8Flag = 0x0800;
  const dosDate = 0x0021;
  let local = 0;
  let central = localLength;

  for (const { name, content } of files) {
    let checksum = 0xffffffff;
    for (const byte of content) checksum = (checksum >>> 8) ^ checksumTable[(checksum ^ byte) & 0xff];
    checksum ^= 0xffffffff;

    long(local, 0x04034b50);
    short(local + 4, version);
    short(local + 6, utf8Flag);
    short(local + 12, dosDate);
    long(local + 14, checksum);
    long(local + 18, content.length);
    long(local + 22, content.length);
    short(local + 26, name.length);
    bytes.set(name, local + 30);
    bytes.set(content, local + 30 + name.length);

    long(central, 0x02014b50);
    short(central + 4, version);
    short(central + 6, version);
    short(central + 8, utf8Flag);
    short(central + 14, dosDate);
    long(central + 16, checksum);
    long(central + 20, content.length);
    long(central + 24, content.length);
    short(central + 28, name.length);
    long(central + 42, local);
    bytes.set(name, central + 46);

    local += 30 + name.length + content.length;
    central += 46 + name.length;
  }

  long(central, 0x06054b50);
  short(central + 8, files.length);
  short(central + 10, files.length);
  long(central + 12, centralLength);
  long(central + 16, localLength);
  return bytes;
}
