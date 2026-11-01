import { fetchFollow } from './http.mjs';
import fs from 'node:fs';
const CASES = [
  ['206章节', 'https://www.m206.com/chapter_70407_2688546.html', 'https://www.m206.com/comic_70407.html'],
  ['云漫画章节', 'https://www.yunmanhua.com/chapter/7yV2NH2X77.html', 'https://www.yunmanhua.com/6Q0Ja3WRkO'],
];
const NOISE = /logo|icon|avatar|banner|advert|\/ads?\/|qrcode|placeholder|\.gif/i;
for (const [name, url, ref] of CASES) {
  const r = await fetchFollow(url, { timeout: 20000, headers: { Referer: ref } });
  console.log(`\n##### ${name} ${r.status} ${r.len}`);
  const t = r.text || '';
  fs.writeFileSync(`dumps/all/${name}.html`, t, 'utf8');
  const imgs = [...new Set([...t.matchAll(/<img[^>]*?(?:data-src|data-original|src)="([^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"/gi)].map(m => m[1]))]
    .filter(u => !NOISE.test(u));
  console.log('<img> 命中:', imgs.length);
  console.log(imgs.slice(0, 5).join('\n'));
  const raw = [...new Set([...t.matchAll(/https?:\/\/[^"'\s\\<>()]+\.(?:jpg|jpeg|png|webp)/gi)].map(m => m[0]))]
    .filter(u => !NOISE.test(u));
  console.log('裸地址:', raw.length, raw.slice(0, 3).join('  '));
  // 找图片容器
  for (const kw of ['comic-img', 'chapter-img', 'image-list', 'img-list', 'chapterContent', 'reader']) {
    const i = t.indexOf(kw);
    if (i >= 0) console.log(`[${kw}]`, t.slice(Math.max(0, i - 100), i + 180).replace(/\s+/g, ' '));
  }
}
