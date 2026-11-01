// 第三轮：换关键词验证搜索语义 + 探测 JSON 接口型数据源。
import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

const KW_A = encodeURIComponent('斗破苍穹');
const KW_B = encodeURIComponent('火影');

const HIT = [
  ['漫客栈-斗破', `https://www.mkzhan.com/search/?keyword=${KW_A}`],
  ['漫客栈-q', `https://www.mkzhan.com/search/?q=${KW_A}`],
  ['漫客栈-路径', `https://www.mkzhan.com/search/${KW_A}/`],
  ['mhua5-斗破', `https://www.mhua5.com/search?keyword=${KW_A}`],
  ['mhua5-火影', `https://www.mhua5.com/search?keyword=${KW_B}`],
  ['极速-斗破', `https://m.1kkk.com/search?title=${KW_A}`],
  ['动漫屋-斗破', `https://m.dm5.com/search?title=${KW_A}`],
  ['腾讯-搜索页', `https://m.ac.qq.com/search/result?word=${KW_A}`],
  ['腾讯-接口', `https://m.ac.qq.com/search/result?word=${KW_A}&type=1`],
  ['bilimanga-搜索', 'https://manga.bilibili.com/twirp/comic.v1.Comic/Search?device=pc&platform=web'],
  ['godamh', `https://godamh.com/search?keyword=${KW_A}`],
  ['baozimh-org', 'https://baozimh.org/'],
  ['copymanga-site', 'https://copymanga.site/'],
  ['mangacopy-api', 'https://api.mangacopy.com/api/v3/comic/search?q=test&limit=1'],
  ['36mh', `https://www.36mh.com/search?keyword=${KW_A}`],
  ['178', `https://www.178mh.com/search?keyword=${KW_A}`],
  ['manhuagui-m', `https://m.manhuagui.com/s/${KW_A}.html`],
  ['WeebCentral-搜', 'https://weebcentral.com/search?text=one%20piece'],
  ['MangaDex-直连', 'https://api.mangadex.org/ping'],
];

for (const [name, url] of HIT) {
  const init = url.includes('twirp')
    ? { method: 'POST', headers: { 'Content-Type': 'application/json', 'Referer': 'https://manga.bilibili.com/' }, body: JSON.stringify({ keyword: '斗破', page_num: 1, page_size: 8 }) }
    : {};
  const r = await fetchFollow(url, init);
  const title = (r.text || '').match(/<title[^>]*>([\s\S]{0,120}?)<\/title>/i)?.[1]?.replace(/\s+/g, ' ').trim() || '';
  console.log(`${r.ok ? 'OK  ' : 'FAIL'} ${name.padEnd(16)} ${String(r.status ?? r.stage).padEnd(6)} ${String(r.len ?? '').padEnd(8)} ${(r.type || '').padEnd(18)} ${title.slice(0, 30)} ${r.detail || ''}`);
  if (r.finalUrl && r.finalUrl !== url) console.log(`     → ${r.finalUrl}`);
  const safe = name.replace(/[\/\\:*?"<>|]/g, '_');
  if (r.text) fs.writeFileSync(new URL(`./dumps/${safe}.txt`, import.meta.url), r.text, 'utf8');
}
