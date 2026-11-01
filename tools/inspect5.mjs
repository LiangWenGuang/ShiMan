import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

const CASES = [
  ['206详情', 'https://www.m206.com/comic_70407.html'],
  ['云漫画详情', 'https://www.yunmanhua.com/6Q0Ja3WRkO'],
];
for (const [name, url] of CASES) {
  const r = await fetchFollow(url, { timeout: 15000 });
  console.log(`\n##### ${name} ${r.status} ${r.len}`);
  const t = r.text || '';
  fs.writeFileSync(`dumps/all/${name}.html`, t, 'utf8');
  const hrefs = [...new Set([...t.matchAll(/href="([^"]+)"/g)].map(m => m[1]))];
  const ch = hrefs.filter(h => /chapter|read|\/ch\d|\/c\d|episode|第.*话/i.test(h));
  console.log('章节候选数:', ch.length);
  console.log(ch.slice(0, 6).join('\n'));
  // 找 js 里的章节接口
  for (const kw of ['chapter-list', 'chapterList', 'chapters', '/api/', 'ajax']) {
    const i = t.indexOf(kw);
    if (i >= 0) console.log(`[${kw}]`, t.slice(Math.max(0, i - 120), i + 160).replace(/\s+/g, ' '));
  }
}
