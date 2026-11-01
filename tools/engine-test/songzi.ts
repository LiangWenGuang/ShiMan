// 松子漫画图源验证：搜索 → 详情 → 章节 → 正则取图
import { fetchFollow } from '../http.mjs';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems, parseDetailFields, parseChapters, parseImagesFromRegex } from './Engine.ts';
import { parseHtml } from './Html.ts';
import fs from 'node:fs';

const SRC = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/resources/rawfile/sources/songzi.json';
const rule = ruleFromJson(parseJson(fs.readFileSync(SRC, 'utf8')));
const headers = { Referer: rule.baseUrl + '/' };
let pass = 0, fail = 0;
const check = (n, ok, d) => { if (ok) { pass++; console.log(`  PASS  ${n}  ${d}`); } else { fail++; console.log(`  FAIL  ${n}  ${d}`); } };

const kw = '斗破';
const url = `${rule.baseUrl}/search?keyword=${encodeURIComponent(kw)}`;
const res = await fetchFollow(url, { headers, timeout: 25000 });
check('搜索 HTTP 200', res.status === 200, `len=${res.len}`);
const items = parseListItems(res.text, rule.search.listSelector, rule.id, url,
  rule.search.title, rule.search.cover, rule.search.link, rule.search.id, rule.search.author, rule.search.latest);
check('搜索有结果', items.length > 0, `${items.length} 条`);
if (!items.length) process.exit(1);
console.log(`        首条: ${items[0].title} | ${items[0].url} | cover=${items[0].cover.slice(0, 50)}`);

const detailUrl = items[0].url;
const d = await fetchFollow(detailUrl, { headers, timeout: 25000 });
const doc = parseHtml(d.text);
const f = parseDetailFields(doc, rule, detailUrl);
check('详情标题', f.title.length > 0, f.title);
check('详情封面', f.cover.startsWith('http'), f.cover.slice(0, 52));
check('详情作者', f.author.length > 0, f.author);

const chs = parseChapters(doc, rule, detailUrl);
check('章节数 > 0', chs.length > 0, `${chs.length} 章`);
if (chs.length) console.log(`        首章: ${chs[0].title} | ${chs[0].url}`);
if (chs.length) console.log(`        末章: ${chs[chs.length - 1].title}`);

const ch = await fetchFollow(chs[0].url, { headers, timeout: 25000 });
const imgs = parseImagesFromRegex(ch.text, rule, chs[0].url);
check('正则取图 >= 3', imgs.length >= 3, `${imgs.length} 张`);
if (imgs.length) {
  console.log(`        首图: ${imgs[0].url}`);
  check('图片 https', imgs.every((i) => i.url.startsWith('https://')), 'ok');
}

console.log(`\n===== 松子漫画: PASS ${pass} / FAIL ${fail} =====`);
process.exit(fail === 0 ? 0 : 1);
