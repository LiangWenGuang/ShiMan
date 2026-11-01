// 验证腾讯动漫图源规则：搜索 → 详情 → 内嵌 JSON 章节。
import { fetchFollow } from '../http.mjs';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems, parseDetailFields, parseChapters } from './Engine.ts';
import { parseHtml } from './Html.ts';
import fs from 'node:fs';

const SRC = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/resources/rawfile/sources/tencent.json';
const rule = ruleFromJson(parseJson(fs.readFileSync(SRC, 'utf8')));
const headers = { Referer: 'https://m.ac.qq.com/' };

let pass = 0;
let fail = 0;
const check = (n, ok, d) => {
  if (ok) { pass++; console.log(`  PASS  ${n}  ${d}`); }
  else { fail++; console.log(`  FAIL  ${n}  ${d}`); }
};

console.log(`规则: ${rule.id} / ${rule.name} / images.type=${rule.images.type}`);

// 1) 搜索
const kw = '斗破苍穹';
const url = `https://m.ac.qq.com/search/result?word=${encodeURIComponent(kw)}`;
const res = await fetchFollow(url, { headers, timeout: 25000 });
check('搜索页 HTTP 200', res.status === 200, `status=${res.status} len=${res.len}`);
const items = parseListItems(
  res.text, rule.search.listSelector, rule.id, url,
  rule.search.title, rule.search.cover, rule.search.link,
  rule.search.id, rule.search.author, rule.search.latest
);
check('搜索结果', items.length > 0, `${items.length} 条`);
if (items.length === 0) { console.log(`\n===== 腾讯: PASS ${pass} / FAIL ${fail} =====`); process.exit(1); }
console.log(`        首条: ${items[0].title} | id=${items[0].comicId} | ${items[0].url}`);

// 2) 详情
const detail = await fetchFollow(items[0].url, { headers, timeout: 25000 });
check('详情页 HTTP 200', detail.status === 200, `status=${detail.status} len=${detail.len}`);
const doc = parseHtml(detail.text);
const fields = parseDetailFields(doc, rule, items[0].url);
check('详情标题', fields.title.length > 0, fields.title);
check('详情封面', fields.cover.startsWith('http'), fields.cover.slice(0, 56));

// 3) 章节（CSS 选择器）
const chapters = parseChapters(doc, rule, items[0].url);
check('章节数 > 10', chapters.length > 10, `${chapters.length} 章`);
if (chapters.length > 0) {
  console.log(`        首章: ${chapters[0].title} | ${chapters[0].url}`);
  console.log(`        末章: ${chapters[chapters.length - 1].title}`);
  check('章节地址绝对', chapters[0].url.startsWith('http'), chapters[0].url);
}

console.log(`\n===== 腾讯动漫: PASS ${pass} / FAIL ${fail} =====`);
process.exit(fail === 0 ? 0 : 1);
