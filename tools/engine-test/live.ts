// 真实网络全链路回归：搜索 → 详情 → 章节 → 图片，全部走实时请求。
// 这是「数据源是否可访问」的直接证据。
import { fetchFollow } from '../http.mjs';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems, parseDetailFields, parseChapters, parseImagesFromJson } from './Engine.ts';
import { parseHtml } from './Html.ts';
import fs from 'node:fs';
import path from 'node:path';

// 图源规则从当前仓库定位，迁移工作目录后不依赖旧电脑盘符。
const SRC = path.resolve(import.meta.dirname, '../../app/entry/src/main/resources/rawfile/sources/mkzhan.json');
const rule = ruleFromJson(parseJson(fs.readFileSync(SRC, 'utf8')));
const headers = { Referer: 'https://www.mkzhan.com/' };
let pass = 0;
let fail = 0;
const check = (name: string, ok: boolean, detail: string) => {
  if (ok) { pass++; console.log(`  PASS  ${name}  ${detail}`); }
  else { fail++; console.log(`  FAIL  ${name}  ${detail}`); }
};

// 1) 搜索
const kw = '斗破';
const searchUrl = `https://www.mkzhan.com/search/?keyword=${encodeURIComponent(kw)}`;
const searchRes = await fetchFollow(searchUrl, { headers });
check('搜索页 HTTP 200', searchRes.status === 200, `status=${searchRes.status} len=${searchRes.len}`);
const items = parseListItems(
  searchRes.text, rule.search.listSelector, rule.id, searchUrl,
  rule.search.title, rule.search.cover, rule.search.link,
  rule.search.id, rule.search.author, rule.search.latest
);
check('搜索出结果', items.length > 0, `${items.length} 条`);
const target = items[0];
console.log('   命中:', target.title, target.comicId, target.url);

// 2) 详情 + 章节
const detailRes = await fetchFollow(target.url, { headers });
check('详情页 HTTP 200', detailRes.status === 200, `status=${detailRes.status} len=${detailRes.len}`);
const doc = parseHtml(detailRes.text);
const fields = parseDetailFields(doc, rule, target.url);
const chapters = parseChapters(doc, rule, target.url);
check('详情标题', fields.title.length > 0, fields.title);
check('详情封面 https', fields.cover.startsWith('https://'), fields.cover.slice(0, 56));
check('章节数 > 0', chapters.length > 0, `${chapters.length} 章`);
check('章节升序', chapters.length < 2 || chapters[0].index === 0, chapters[0].title);

// 3) 章节图片（走真实接口）
const chapter = chapters[0];
const apiUrl = `https://comic.mkzcdn.com/chapter/content/v1/?chapter_id=${chapter.chapterId}` +
  `&comic_id=${target.comicId}&quality=1&type=1&format=0`;
const imgRes = await fetchFollow(apiUrl, { headers: { Referer: chapter.url } });
check('图片接口 HTTP 200', imgRes.status === 200 && imgRes.type.indexOf('json') >= 0,
  `status=${imgRes.status} type=${imgRes.type}`);
const images = parseImagesFromJson(imgRes.text, rule, chapter.url);
check('图片数 >= 3', images.length >= 3, `${images.length} 张`);
check('图片全部 https', images.every((i) => i.url.startsWith('https://')), images[0]?.url.slice(0, 56) ?? '');

// 4) 真有像素可下（取第一张）
const probe = await fetchFollow(images[0].url, { headers: { Referer: chapter.url } });
check('首图可下载', probe.status === 200 && probe.len > 5000, `${probe.status} ${probe.type} ${probe.len}B`);

console.log(`\n===== 真实链路: PASS ${pass} / FAIL ${fail} =====`);
process.exit(fail === 0 ? 0 : 1);
