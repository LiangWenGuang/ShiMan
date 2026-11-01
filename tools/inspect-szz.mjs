// 摸清松子漫画的搜索 / 详情 / 章节 / 图片结构，用于手写规则。
import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

const HOST = 'https://www.songzimanhua.com';
fs.mkdirSync(new URL('./dumps/szz/', import.meta.url), { recursive: true });

const KW = encodeURIComponent('斗破');

// 1) 找搜索入口
const searchCandidates = [
  `${HOST}/search/?keyword=${KW}`,
  `${HOST}/search?keyword=${KW}`,
  `${HOST}/search/${KW}/`,
  `${HOST}/search.php?keyword=${KW}`,
  `${HOST}/index.php/search?keyword=${KW}`,
];
let searchUrl = '';
for (const url of searchCandidates) {
  const r = await fetchFollow(url, { timeout: 15000 });
  const len = r.len || 0;
  console.log(`搜索候选 ${r.status} len=${len}  ${url}`);
  if (r.ok && len > 8000) {
    searchUrl = url;
    fs.writeFileSync(new URL('./dumps/szz/search.html', import.meta.url), r.text, 'utf8');
    break;
  }
}

// 2) 首页取详情链接
const home = await fetchFollow(HOST, { timeout: 15000 });
fs.writeFileSync(new URL('./dumps/szz/home.html', import.meta.url), home.text || '', 'utf8');
const hrefs = [...new Set([...home.text.matchAll(/href="([^"]{2,80})"/g)].map((m) => m[1]))]
  .filter((h) => /\d/.test(h) && !/login|search|tag|css|js|#/.test(h));
console.log('\n首页详情链接样例:', hrefs.slice(0, 6));

// 3) 详情页
let detailUrl = '';
if (searchUrl) {
  const html = fs.readFileSync(new URL('./dumps/szz/search.html', import.meta.url), 'utf8');
  const links = [...new Set([...html.matchAll(/href="([^"]{2,80})"/g)].map((m) => m[1]))]
    .filter((h) => /\d/.test(h) && !/login|search|tag|css|js|#/.test(h));
  console.log('搜索结果里的链接样例:', links.slice(0, 6));
  if (links.length) detailUrl = links[0].startsWith('http') ? links[0] : HOST + (links[0].startsWith('/') ? links[0] : '/' + links[0]);
}
if (!detailUrl && hrefs.length) detailUrl = HOST + (hrefs[0].startsWith('/') ? hrefs[0] : '/' + hrefs[0]);

const detail = await fetchFollow(detailUrl, { timeout: 15000 });
fs.writeFileSync(new URL('./dumps/szz/detail.html', import.meta.url), detail.text || '', 'utf8');
console.log(`\n详情 ${detail.status} len=${detail.len}  ${detailUrl}`);

const dcls = {};
for (const m of (detail.text || '').matchAll(/class="([^"]{2,36})"/g)) dcls[m[1]] = (dcls[m[1]] || 0) + 1;
console.log('详情页高频 class:', Object.entries(dcls).sort((a, b) => b[1] - a[1]).slice(0, 12).map(([k, v]) => `${k}:${v}`).join('  '));

const chLinks = [...new Set([...detail.text.matchAll(/href="([^"]{2,80})"/g)].map((m) => m[1]))]
  .filter((h) => /chapter|\/\d+\.html|\/ch/i.test(h));
console.log('章节链接样例:', chLinks.slice(0, 6));

if (chLinks.length) {
  const chUrl = chLinks[0].startsWith('http') ? chLinks[0] : HOST + (chLinks[0].startsWith('/') ? chLinks[0] : '/' + chLinks[0]);
  const ch = await fetchFollow(chUrl, { timeout: 15000 });
  fs.writeFileSync(new URL('./dumps/szz/chapter.html', import.meta.url), ch.text || '', 'utf8');
  console.log(`\n章节 ${ch.status} len=${ch.len}  ${chUrl}`);
  const imgs = [...new Set((ch.text || '').match(/(?:https?:)?\/\/[^"'\s\\)]+\.(?:jpg|jpeg|png|webp)[^"'\s\\)]*/gi) || [])];
  const good = imgs.filter((u) => !/logo|icon|avatar|banner|ads?/i.test(u));
  console.log(`图片 ${imgs.length} 张，过滤后 ${good.length} 张`);
  console.log(good.slice(0, 5).join('\n'));
  const i = (ch.text || '').indexOf(good[0] || '');
  console.log('\n上下文:\n' + (ch.text || '').slice(Math.max(0, i - 400), i + 200).replace(/\s+/g, ' '));
}
