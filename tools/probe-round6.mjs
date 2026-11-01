// 第六轮：对候选站做「章节页是否含服务端图片」的硬性判定。
// 同时顺带验证包子漫画 / WeebCentral / G站 的完整链路。
import { fetchFollow, DEFAULT_UA } from './http.mjs';
import fs from 'node:fs';

fs.mkdirSync(new URL('./dumps/r6/', import.meta.url), { recursive: true });

const IMG_RE = /(?:https?:)?\/\/[^"'\s\\)]+\.(?:jpg|jpeg|png|webp)[^"'\s\\)]*/gi;
const BAD = /logo|icon|avatar|favicon|banner|bg_|loading|placeholder|default|sprite|button|arrow/i;

function countImgs(html) {
  const all = html.match(IMG_RE) || [];
  const good = [...new Set(all)].filter((u) => !BAD.test(u));
  return { total: all.length, uniq: new Set(all).size, good: good.length, sample: good.slice(0, 5) };
}

const TARGETS = [
  ['包子-详情', 'https://baozimh.org/manga/manjiwanjiadedi100cihuigui'],
  ['G站-首页', 'https://godamh.com/'],
  ['Weeb-详情', 'https://weebcentral.com/series/01J76XY7N9XKRVQ8Z0R8N8VQ9Z'],
];

for (const [name, url] of TARGETS) {
  const r = await fetchFollow(url, { timeout: 20000 });
  console.log(`\n##### ${name} ${r.status ?? r.stage} ${r.len ?? ''} ${r.finalUrl || ''}`);
  if (!r.text) { console.log('  ! ' + (r.detail || 'empty')); continue; }
  fs.writeFileSync(new URL(`./dumps/r6/${name}.html`, import.meta.url), r.text, 'utf8');
  const c = countImgs(r.text);
  console.log(`  img total=${c.total} uniq=${c.uniq} good=${c.good}`);
  console.log('  ' + c.sample.join('\n  '));
  const links = [...new Set([...r.text.matchAll(/href="([^"]{2,110})"/g)].map((m) => m[1]))];
  const chapterish = links.filter((h) => /chapter|ch-|episode|\/\d+\/?$|chap/i.test(h)).slice(0, 8);
  console.log('  章节样式链接: ' + chapterish.join(' | '));
}

// 漫客栈读页接口探测：从 modules/read/content.js 找 page 列表接口
const js = await fetchFollow('https://static.mkzcdn.com/home/assets/script/modules/read/content.js?v=c3fc7265');
const s = js.text || '';
console.log('\n##### mkzhan content.js len=' + s.length);
const apis = [...new Set([...s.matchAll(/["']([^"']{0,90}(?:chapter|image|content|page)[^"']{0,60})["']/gi)].map((m) => m[1]))];
console.log('  候选接口: ' + apis.slice(0, 12).join(' | '));
const j = s.indexOf('httpApi');
if (j >= 0) console.log('  片段: ' + s.slice(Math.max(0, j - 200), j + 400).replace(/\s+/g, ' '));
