import { fetchFollow } from '../http.mjs';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems } from './Engine.ts';
import fs from 'node:fs';

const SRC = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/resources/rawfile/sources/songzi.json';
const rule = ruleFromJson(parseJson(fs.readFileSync(SRC, 'utf8')));
const headers = { Referer: rule.baseUrl + '/' };

for (const kw of ['斗破', '晓风残月', '不存在的关键词XYZ']) {
  const url = `${rule.baseUrl}/search/?q=${encodeURIComponent(kw)}`;
  const r = await fetchFollow(url, { headers, timeout: 25000 });
  const empty = rule.search.emptyMarker.length > 0 && r.text.includes(rule.search.emptyMarker);
  const items = empty ? [] : parseListItems(r.text, rule.search.listSelector, rule.id, url,
    rule.search.title, rule.search.cover, rule.search.link, rule.search.id, rule.search.author, rule.search.latest);
  console.log(`搜索「${kw}」→ ${items.length} 条${empty ? '（判定为空）' : ''} ${items.slice(0, 3).map(i => i.title).join(' | ')}`);
}

const br = rule.browse[0];
const u2 = rule.baseUrl + br.url;
const r2 = await fetchFollow(u2, { headers, timeout: 25000 });
const list2 = parseListItems(r2.text, br.listSelector, rule.id, u2,
  rule.search.title, rule.search.cover, rule.search.link, rule.search.id, rule.search.author, rule.search.latest);
console.log(`分类「${br.name}」→ ${list2.length} 条 ${list2.slice(0, 3).map(i => i.title).join(' | ')}`);
