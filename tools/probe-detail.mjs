// 第四轮：详情页结构 + 章节列表 + 首章图片，验证四段链路是否可通。
import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

fs.mkdirSync(new URL('./dumps/detail/', import.meta.url), { recursive: true });

const TARGETS = [
  ['极速-海贼王', 'https://m.1kkk.com/manhua432/'],
  ['动漫屋-海贼王', 'https://m.dm5.com/manhua-haizeiwang-onepiece/'],
  ['漫客栈-217087', 'https://www.mkzhan.com/217087/'],
  ['腾讯-斗破', 'https://m.ac.qq.com/comic/index/id/531040'],
  ['包子-搜索', 'https://baozimh.org/search?q=' + encodeURIComponent('斗破苍穹')],
  ['包子-首页', 'https://baozimh.org/'],
];

for (const [name, url] of TARGETS) {
  const r = await fetchFollow(url);
  console.log(`\n########## ${name}  ${r.status ?? r.stage}  ${r.len ?? ''}  ${r.finalUrl || ''}`);
  if (!r.text) { console.log('  ! ' + (r.detail || 'no body')); continue; }
  const safe = name.replace(/[\/\\:*?"<>|]/g, '_');
  fs.writeFileSync(new URL(`./dumps/detail/${safe}.html`, import.meta.url), r.text, 'utf8');
  const cls = [...r.text.matchAll(/class="([^"]{2,44})"/g)].map((m) => m[1]);
  const cnt = {};
  for (const c of cls) cnt[c] = (cnt[c] || 0) + 1;
  console.log('  classes:', Object.entries(cnt).sort((a, b) => b[1] - a[1]).slice(0, 14).map(([k, v]) => `${k}:${v}`).join('  '));
  const links = [...new Set([...r.text.matchAll(/href="([^"]{2,90})"/g)].map((m) => m[1]))]
    .filter((h) => /\d/.test(h) && !/\.(css|js|png|jpg|ico)/.test(h)).slice(0, 12);
  console.log('  hrefs:', links.join(' | '));
}
