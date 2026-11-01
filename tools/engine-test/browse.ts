// 验证分类/发现页的列表选择器在真实页面上能取到数据。
import { fetchFollow } from '../http.mjs';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems } from './Engine.ts';
import fs from 'node:fs';

const SRC = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/resources/rawfile/sources/mkzhan.json';
const rule = ruleFromJson(parseJson(fs.readFileSync(SRC, 'utf8')));
const headers = { Referer: 'https://www.mkzhan.com/' };

let pass = 0;
let fail = 0;
const check = (name, ok, detail) => {
  if (ok) { pass++; console.log(`  PASS  ${name}  ${detail}`); }
  else { fail++; console.log(`  FAIL  ${name}  ${detail}`); }
};

console.log(`browse 条目: ${rule.browse.length}`);

for (const entry of rule.browse.slice(0, 4)) {
  const url = rule.baseUrl + entry.url;
  const res = await fetchFollow(url, { headers, timeout: 20000 });
  const items = parseListItems(
    res.text, entry.listSelector, rule.id, url,
    entry.title, entry.cover, entry.link, entry.id, entry.author, entry.latest
  );
  check(`${entry.name}`, res.status === 200 && items.length > 0,
    `status=${res.status} 条数=${items.length}`);
  if (items.length > 0) {
    console.log(`        首条: ${items[0].title} | ${items[0].cover.slice(0, 54)}`);
  }
}

console.log(`\n===== 分类页: PASS ${pass} / FAIL ${fail} =====`);
process.exit(fail === 0 ? 0 : 1);
