import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

// 云北漫画详情
const u1 = 'https://www.mhw1.com/index.php/comic/doupocangkong';
const r1 = await fetchFollow(u1, { timeout: 20000, headers: { Referer: 'https://www.mhw1.com/' } });
fs.writeFileSync('dumps/all/yunbei-detail.html', r1.text || '', 'utf8');
console.log('云北详情', r1.status, r1.len);
const t1 = r1.text || '';
const i1 = t1.indexOf('chapter');
console.log('[章节片段]', t1.slice(Math.max(0, i1 - 300), i1 + 400).replace(/\s+/g, ' '));

// 206详情
const t2 = fs.readFileSync('dumps/all/206详情.html', 'utf8');
console.log('\n206详情 len', t2.length);
for (const kw of ['comic-title', 'detail', '封面', 'author', '简介']) {
  const i = t2.indexOf(kw);
  if (i >= 0) console.log(`[${kw}]`, t2.slice(Math.max(0, i - 150), i + 200).replace(/\s+/g, ' '));
}
