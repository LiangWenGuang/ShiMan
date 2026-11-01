// 引擎回归：对真实抓取下来的页面跑一遍 搜索→详情→章节→图片，
// 断言解析结果与人工观察一致。跑法：node --experimental-transform-types run.ts
import fs from 'node:fs';
import path from 'node:path';
import { parseHtml } from './Html.ts';
import { queryAll } from './Selector.ts';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems, parseDetailFields, parseChapters, parseImagesFromJson } from './Engine.ts';

const DUMPS = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/tools/dumps';
const SRC = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/resources/rawfile/sources';

let pass = 0;
let fail = 0;

function check(name: string, ok: boolean, detail: string) {
  if (ok) {
    pass++;
    console.log(`  PASS  ${name}  ${detail}`);
  } else {
    fail++;
    console.log(`  FAIL  ${name}  ${detail}`);
  }
}

const ruleText = fs.readFileSync(path.join(SRC, 'mkzhan.json'), 'utf8');
const rule = ruleFromJson(parseJson(ruleText));
console.log(`规则加载: id=${rule.id} name=${rule.name} base=${rule.baseUrl} browse=${rule.browse.length}`);

// 1) 搜索
const searchHtml = fs.readFileSync(path.join(DUMPS, '漫客栈-斗破.txt'), 'utf8');
const searchUrl = 'https://www.mkzhan.com/search/?keyword=%E6%96%97%E7%A0%B4';
const items = parseListItems(
  searchHtml, rule.search.listSelector, rule.id, searchUrl,
  rule.search.title, rule.search.cover, rule.search.link,
  rule.search.id, rule.search.author, rule.search.latest
);
check('搜索条数 >= 8', items.length >= 8, `${items.length} 条`);
if (items.length > 0) {
  const first = items[0];
  console.log('   样例:', JSON.stringify({
    id: first.comicId, title: first.title, cover: first.cover, url: first.url, latest: first.latest
  }).slice(0, 320));
  check('首条标题非空', first.title.length > 0, first.title);
  check('首条封面是绝对地址', first.cover.startsWith('http'), first.cover.slice(0, 60));
  check('首条详情地址是绝对地址', first.url.startsWith('http'), first.url);
  check('首条 id 是数字', /^\d+$/.test(first.comicId), first.comicId);
}

// 2) 详情
const detailHtml = fs.readFileSync(path.join(DUMPS, 'detail/漫客栈-217087.html'), 'utf8');
const detailUrl = 'https://www.mkzhan.com/217087/';
const doc = parseHtml(detailHtml);
const fields = parseDetailFields(doc, rule, detailUrl);
console.log('   详情:', JSON.stringify(fields).slice(0, 260));
check('详情标题', fields.title.length > 0, fields.title);
check('详情封面', fields.cover.startsWith('http'), fields.cover.slice(0, 60));
check('详情作者', fields.author.length > 0, fields.author);
check('详情简介长度 > 20', fields.description.length > 20, `len=${fields.description.length}`);
check('详情状态', fields.status.length > 0, fields.status);

// 3) 章节
const chapters = parseChapters(doc, rule, detailUrl);
check('章节数 >= 100', chapters.length >= 100, `${chapters.length} 章`);
if (chapters.length > 0) {
  console.log('   首章:', JSON.stringify(chapters[0]));
  console.log('   末章:', JSON.stringify(chapters[chapters.length - 1]));
  check('首章 id 数字', /^\d+$/.test(chapters[0].chapterId), chapters[0].chapterId);
  check('首章地址绝对', chapters[0].url.startsWith('http'), chapters[0].url);
  check('章节标题含「话」', chapters[0].title.indexOf('话') >= 0, chapters[0].title);
}

// 4) 图片（用真实接口返回体做解析回归）
const sampleJson = '{"code":"200","message":"x","data":{"page":[' +
  '{"page_id":"1","image":"http:\\/\\/content.mkzcdn.com\\/a\\/1-800x966.jpg!page-800?auth_key=1"},' +
  '{"page_id":"2","image":"http:\\/\\/content.mkzcdn.com\\/a\\/2-800x1397.jpg!page-800?auth_key=2"}' +
  ']}}';
const images = parseImagesFromJson(sampleJson, rule, detailUrl);
check('图片解析 2 张', images.length === 2, `${images.length} 张`);
if (images.length > 0) {
  check('反转义 \\/ 正确', images[0].url.indexOf('content.mkzcdn.com') > 0, images[0].url.slice(0, 60));
  check('auth_key 保留', images[0].url.indexOf('auth_key=') > 0, 'ok');
}

// 5) 选择器边界：不存在的选择器必须返回空而不是抛错
const missing = queryAll(parseHtml('<div class="a"><p>x</p></div>'), '.not-there');
check('空结果不抛错', missing.length === 0, 'ok');

// 6) 容错：残缺 HTML（未闭合标签、内嵌脚本）不应崩
const broken = parseHtml('<div class="x"><a href="/1.html">标题<span>1</span><script>var a="<div>";</script>');
const brokenItems = queryAll(broken, '.x a');
check('残缺 HTML 可解析', brokenItems.length === 1, `${brokenItems.length} 节点`);

console.log(`\n===== 结果: PASS ${pass} / FAIL ${fail} =====`);
process.exit(fail === 0 ? 0 : 1);
