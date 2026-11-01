import { fetchFollow } from '../http.mjs';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems } from './Engine.ts';
import fs from 'node:fs';

const SRC = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/resources/rawfile/sources/songzi.json';
const rule = ruleFromJson(parseJson(fs.readFileSync(SRC, 'utf8')));
for (const kw of ['重生帝女乱天下', '重生医妃狠角色', '重生巨星']) {
  const url = `${rule.baseUrl}/search?keyword=${encodeURIComponent(kw)}`;
  const r = await fetchFollow(url, { headers: { Referer: rule.baseUrl + '/' }, timeout: 25000 });
  const items = parseListItems(r.text, rule.search.listSelector, rule.id, url,
    rule.search.title, rule.search.cover, rule.search.link, rule.search.id, rule.search.author, rule.search.latest);
  console.log(kw, '→', items.length, items.slice(0, 3).map(i => i.title).join(' | '));
}
