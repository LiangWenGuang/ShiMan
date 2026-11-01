// 新增两源（云北漫画 / 206漫画）四段链路验证
import { fetchFollow } from '../http.mjs';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems, parseDetailFields, parseChapters, parseImagesFromHtml } from './Engine.ts';
import { parseHtml } from './Html.ts';
import fs from 'node:fs';

const DIR = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/resources/rawfile/sources';
let pass = 0, fail = 0;
const check = (n, ok, d) => {
  if (ok) { pass++; console.log(`  PASS  ${n}  ${d}`); } else { fail++; console.log(`  FAIL  ${n}  ${d}`); }
};

for (const file of ['mhw1.json', 'm206.json']) {
  const rule = ruleFromJson(parseJson(fs.readFileSync(`${DIR}/${file}`, 'utf8')));
  console.log(`\n===== ${rule.name} (${rule.id}) =====`);
  const headers = { Referer: rule.baseUrl + '/' };

  for (const kw of ['斗破', '海贼']) {
    const url = `${rule.baseUrl}/search?key=${encodeURIComponent(kw)}`;
    const r = await fetchFollow(url, { headers, timeout: 25000 });
    check(`搜索「${kw}」HTTP 200`, r.status === 200, `len=${r.len}`);
    if (!r.text) continue;
    const items = parseListItems(r.text, rule.search.listSelector, rule.id, url,
      rule.search.title, rule.search.cover, rule.search.link, rule.search.id, rule.search.author, rule.search.latest);
    check(`搜索「${kw}」有结果`, items.length > 0, `${items.length} 条`);
    if (!items.length) continue;
    console.log(`        首条: ${items[0].title} | ${items[0].url}`);
    check(`搜索「${kw}」封面`, items[0].cover.startsWith('http'), items[0].cover.slice(0, 60));

    if (kw !== '斗破') continue; // 只对第一个词跑完整链路
    const durl = items[0].url;
    const d = await fetchFollow(durl, { headers, timeout: 25000 });
    const doc = parseHtml(d.text);
    const f = parseDetailFields(doc, rule, durl);
    check('详情标题', f.title.length > 0, f.title);
    check('详情封面', f.cover.startsWith('http'), f.cover.slice(0, 60));
    check('详情简介', f.description.length > 10, `${f.description.length} 字`);
    console.log(`        作者: ${f.author}`);

    const chs = parseChapters(doc, rule, durl);
    check('章节数 > 0', chs.length > 0, `${chs.length} 章`);
    if (!chs.length) continue;
    console.log(`        首章: ${chs[0].title} | 末章: ${chs[chs.length - 1].title}`);

    const ch = await fetchFollow(chs[0].url, { headers, timeout: 25000 });
    const imgs = parseImagesFromHtml(ch.text, rule, chs[0].url);
    check('正文图片 >= 3', imgs.length >= 3, `${imgs.length} 张`);
    if (imgs.length) {
      console.log(`        首图: ${imgs[0].url.slice(0, 80)}`);
      const probe = await fetchFollow(imgs[0].url, { headers: { Referer: chs[0].url }, timeout: 20000 });
      check('首图可下载', probe.status === 200 && (probe.len || 0) > 5000, `${probe.status} ${probe.len} 字节 ${probe.type || ''}`);
    }
  }

  // 分类页
  for (const b of rule.browse) {
    const u = rule.baseUrl + b.url;
    const r = await fetchFollow(u, { headers, timeout: 25000 });
    const items = parseListItems(r.text, b.listSelector, rule.id, u,
      b.title, b.cover, b.link, b.id, b.author, b.latest);
    check(`分类「${b.name}」`, items.length > 0, `${items.length} 条`);
  }
}

console.log(`\n===== 合计: PASS ${pass} / FAIL ${fail} =====`);
process.exit(fail === 0 ? 0 : 1);
