// 程序化生成应用图标：深色圆角底 + 三层错位「书页」，不依赖任何外部素材。
import zlib from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';

const S = 512;
const buf = Buffer.alloc(S * S * 4);

function crc32(bufIn) {
  let c;
  const table = crc32.table || (crc32.table = (() => {
    const t = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c;
    }
    return t;
  })());
  let crc = -1;
  for (let i = 0; i < bufIn.length; i++) crc = (crc >>> 8) ^ table[(crc ^ bufIn[i]) & 0xff];
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const t = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([len, t, data, crc]);
}

// 圆角矩形覆盖率（带 1px 抗锯齿）
function roundRectCoverage(x, y, rx0, ry0, rx1, ry1, r) {
  const cx = Math.max(rx0 + r, Math.min(x, rx1 - r));
  const cy = Math.max(ry0 + r, Math.min(y, ry1 - r));
  const dx = x - cx;
  const dy = y - cy;
  const dist = Math.sqrt(dx * dx + dy * dy);
  const inside = x >= rx0 && x <= rx1 && y >= ry0 && y <= ry1;
  if (!inside) return 0;
  const edge = r - dist;
  return Math.max(0, Math.min(1, edge + 0.5));
}

function blend(i, r, g, b, a) {
  if (a <= 0) return;
  const oa = buf[i + 3] / 255;
  const na = a + oa * (1 - a);
  if (na <= 0) return;
  buf[i] = Math.round((r * a + buf[i] * oa * (1 - a)) / na);
  buf[i + 1] = Math.round((g * a + buf[i + 1] * oa * (1 - a)) / na);
  buf[i + 2] = Math.round((b * a + buf[i + 2] * oa * (1 - a)) / na);
  buf[i + 3] = Math.round(na * 255);
}

const PAGES = [
  { dx: 0, dy: 0, color: [0x2B, 0x5F, 0xC4] },
  { dx: -26, dy: -26, color: [0x3F, 0x7F, 0xEA] },
  { dx: -52, dy: -52, color: [0x7C, 0xB2, 0xFF] },
];

for (let y = 0; y < S; y++) {
  for (let x = 0; x < S; x++) {
    const i = (y * S + x) * 4;
    // 背景圆角底
    const bg = roundRectCoverage(x, y, 0, 0, S, S, 108);
    if (bg > 0) {
      const t = y / S;
      const r = Math.round(0x14 + 6 * (1 - t));
      const g = Math.round(0x18 + 8 * (1 - t));
      const b = Math.round(0x20 + 12 * (1 - t));
      blend(i, r, g, b, bg);
    }
    // 三层书页
    for (const p of PAGES) {
      const x0 = 132 + p.dx, y0 = 176 + p.dy, x1 = 388 + p.dx, y1 = 372 + p.dy;
      const cov = roundRectCoverage(x, y, x0, y0, x1, y1, 34);
      if (cov > 0) blend(i, p.color[0], p.color[1], p.color[2], cov * 0.96);
    }
    // 最上层书页上的「文字行」，暗示漫画分镜
    const tx0 = 176, ty0 = 214, tx1 = 344, ty1 = 330;
    if (x >= tx0 && x <= tx1 && y >= ty0 && y <= ty1) {
      const lines = [0, 1, 2, 3];
      for (const li of lines) {
        const ly = ty0 + 22 + li * 26;
        const lw = li === 3 ? 0.55 : 1;
        if (y >= ly && y <= ly + 9 && x <= tx0 + (tx1 - tx0) * lw) {
          blend(i, 0x10, 0x13, 0x18, 0.55);
        }
      }
    }
  }
}

// PNG 编码
const raw = Buffer.alloc(S * (S * 4 + 1));
for (let y = 0; y < S; y++) {
  raw[y * (S * 4 + 1)] = 0;
  buf.copy(raw, y * (S * 4 + 1) + 1, y * S * 4, (y + 1) * S * 4);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(S, 0);
ihdr.writeUInt32BE(S, 4);
ihdr[8] = 8;
ihdr[9] = 6;
ihdr[10] = 0;
ihdr[11] = 0;
ihdr[12] = 0;
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0)),
]);

const targets = [
  'app/AppScope/resources/base/media/app_icon.png',
  'app/entry/src/main/resources/base/media/app_icon.png',
  'app/entry/src/main/resources/base/media/startIcon.png',
];
for (const t of targets) {
  const abs = path.resolve(process.cwd(), '..', t);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, png);
  console.log('written', abs, png.length, 'bytes');
}
