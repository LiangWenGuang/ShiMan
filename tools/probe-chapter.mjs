// 第五轮：抓章节页，提取图片地址，并实测图片能否直接下载（含 Referer 差异）。
import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

fs.mkdirSync(new URL('./dumps/chapter/', import.meta.url), { recursive: true });

const CHAPTERS = [
  ['极速', 'https://m.1kkk.com/ch1-6-1722522/'],
  ['动漫屋', 'https://m.dm5.com/m1722522/'],
  ['漫客栈', 'https://www.mkzhan.com/217087/1069798.html'],
  ['腾讯', 'https://m.ac.qq.com/chapter/index/id/531040/cid/1'],
];

for (const [name, url] of CHAPTERS) {
  const r = await fetchFollow(url, { headers: { Referer: url } });
  console.log(`\n########## ${name}  ${r.status ?? r.stage}  ${r.len ?? ''}  ${r.finalUrl || ''}`);
  if (!r.text) { console.log('  ! ' + (r.detail || 'empty')); continue; }
  fs.writeFileSync(new URL(`./dumps/chapter/${name}.html`, import.meta.url), r.text, 'utf8');
  const t = r.text;

  // 常见图片承载方式
  const m1 = t.match(/(?:chapterImages|chapter_images|images|imgData|pageImages)\s*=\s*(\[[\s\S]{0,4000}?\])/);
  if (m1) console.log('  JS数组:', m1[1].slice(0, 260).replace(/\s+/g, ' '));

  const imgs = [...t.matchAll(/<img[^>]+(?:data-src|data-original|src)="([^"]+)"/gi)].map((m) => m[1]);
  const real = [...new Set(imgs)].filter((s) => /\.(jpg|jpeg|png|webp)/i.test(s) && !/logo|icon|avatar|banner|bg_/i.test(s));
  console.log('  img候选:', real.slice(0, 6).join('\n            '));

  const lazyAttrs = [...new Set([...t.matchAll(/(?:data-[a-z-]+)="([^"]*\.(?:jpg|jpeg|png|webp)[^"]*)"/gi)].map((m) => m[1]))];
  if (lazyAttrs.length) console.log('  lazy属性:', lazyAttrs.slice(0, 5).join('\n            '));

  const cls = [...t.matchAll(/class="([^"]{2,40})"/g)].map((m) => m[1]);
  const cnt = {};
  for (const c of cls) cnt[c] = (cnt[c] || 0) + 1;
  console.log('  classes:', Object.entries(cnt).sort((a, b) => b[1] - a[1]).slice(0, 10).map(([k, v]) => `${k}:${v}`).join('  '));
}
