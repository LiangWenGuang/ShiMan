// comicId 抽取回归：域名带数字不能污染 id，且同一列表里的 id 必须唯一
import { extractNumericId } from './Text.ts';
import { fetchFollow } from '../http.mjs';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems } from './Engine.ts';
import fs from 'node:fs';

let pass = 0, fail = 0;
const check = (n, ok, d) => { if (ok) { pass++; console.log(`  PASS  ${n}  ${d}`); } else { fail++; console.log(`  FAIL  ${n}  ${d}`); } };

check('域名数字不污染', extractNumericId('https://www.m206.com/comic_6927.html') === '6927',
  extractNumericId('https://www.m206.com/comic_6927.html'));
check('短域名同样', extractNumericId('https://m206.com/comic_12.html') === '12',
  extractNumericId('https://m206.com/comic_12.html'));
check('取最长而非末位', extractNumericId('https://x.com/comic/12345/2.html') === '12345',
  extractNumericId('https://x.com/comic/12345/2.html'));
check('路径尾段 id', extractNumericId('https://www.mkzhan.com/217087/') === '217087',
  extractNumericId('https://www.mkzhan.com/217087/'));
check('查询串不参与', extractNumericId('https://x.com/book/5310/?page=99') === '5310',
  extractNumericId('https://x.com/book/5310/?page=99'));

// 真实列表：id 必须全部唯一
const DIR = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/resources/rawfile/sources';
for (const file of ['m206.json', 'mhw1.json', 'songzi.json']) {
  const rule = ruleFromJson(parseJson(fs.readFileSync(`${DIR}/${file}`, 'utf8')));
  const b = rule.browse[0];
  if (!b) continue;
  const u = rule.baseUrl + b.url;
  const r = await fetchFollow(u, { headers: { Referer: rule.baseUrl + '/' }, timeout: 25000 });
  const items = parseListItems(r.text, b.listSelector, rule.id, u, b.title, b.cover, b.link, b.id, b.author, b.latest);
  const ids = items.map((i) => i.comicId);
  const unique = new Set(ids).size;
  check(`${rule.name} 列表 id 唯一`, items.length > 0 && unique === items.length, `${unique}/${items.length}`);
}

console.log(`\n===== id 回归: PASS ${pass} / FAIL ${fail} =====`);
process.exit(fail === 0 ? 0 : 1);
