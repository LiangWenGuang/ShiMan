import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

const r = await fetchFollow('https://www.mhw1.com/index.php/chapter/3385184', {
  timeout: 20000, headers: { Referer: 'https://www.mhw1.com/index.php/comic/doupocangkong' }
});
console.log('云北章节', r.status, r.len);
const t = r.text || '';
fs.writeFileSync('dumps/all/yunbei-chapter.html', t, 'utf8');
const imgs = [...new Set([...t.matchAll(/<img[^>]*?(?:data-src|data-original|src)="([^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"/gi)].map(m => m[1]))]
  .filter(u => !/logo|icon|avatar|banner/i.test(u));
console.log('图片数:', imgs.length, imgs.slice(0, 4).join('\n'));
const i = t.indexOf(imgs[0] || '###');
console.log('[图片容器]', t.slice(Math.max(0, i - 400), i + 200).replace(/\s+/g, ' '));

// 云北详情页字段
const d = fs.readFileSync('dumps/all/yunbei-detail.html', 'utf8');
const h1 = d.match(/<h1[^>]*>([\s\S]{0,80}?)<\/h1>/);
console.log('\n[标题h1]', h1 ? h1[0].replace(/\s+/g, ' ') : 'none');
for (const kw of ['comic-cover', 'detail-cover', '作者', 'author', 'comic-intro', 'intro']) {
  const j = d.indexOf(kw);
  if (j >= 0) console.log(`[${kw}]`, d.slice(Math.max(0, j - 120), j + 180).replace(/\s+/g, ' '));
}
