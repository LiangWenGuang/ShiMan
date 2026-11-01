// 新增图源离线回归：顶漫画（sequence 取图）与云漫画（web 取图）。
// 跑法：node --experimental-transform-types newsrc.ts
import fs from 'node:fs';
import path from 'node:path';
import { parseHtml } from './Html.ts';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import {
  parseListItems, parseDetailFields, parseChapters, parseChaptersFromJson, parseImagesFromSequence
} from './Engine.ts';

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

function load(name: string) {
  return ruleFromJson(parseJson(fs.readFileSync(path.join(SRC, name), 'utf8')));
}

function read(name: string) {
  return fs.readFileSync(path.join(DUMPS, name), 'utf8');
}

// ───────────── 顶漫画 ─────────────
console.log('== 顶漫画 dingmanhua ==');
const ding = load('dingmanhua.json');
check('规则加载', ding.id === 'dingmanhua', `${ding.name} | ${ding.images.type} | 章节倒序=${ding.chapters.reverse}`);

const dSearchUrl = 'https://www.dingmanhua.com/search?query=%E7%81%AB%E5%BD%B1';
const dItems = parseListItems(
  read('顶漫画-搜索.txt'), ding.search.listSelector, ding.id, dSearchUrl,
  ding.search.title, ding.search.cover, ding.search.link,
  ding.search.id, ding.search.author, ding.search.latest
);
check('搜索条数 >= 2', dItems.length >= 2, `${dItems.length} 条`);
if (dItems.length > 0) {
  const first = dItems[0];
  console.log('   样例:', JSON.stringify({
    id: first.comicId, title: first.title, cover: first.cover, url: first.url
  }).slice(0, 300));
  check('搜索标题非空', first.title.length > 0, first.title);
  check('搜索封面绝对地址', first.cover.startsWith('http'), first.cover.slice(0, 60));
  check('详情地址绝对化', first.url.startsWith('https://www.dingmanhua.com/comic/'), first.url);
}

const dDetailUrl = 'https://www.dingmanhua.com/comic/7281.html';
const dDoc = parseHtml(read('顶漫画-详情.txt'));
const dFields = parseDetailFields(dDoc, ding, dDetailUrl);
console.log('   详情:', JSON.stringify(dFields).slice(0, 260));
check('详情标题', dFields.title.length > 0, dFields.title);
check('详情封面', dFields.cover.startsWith('http'), dFields.cover.slice(0, 60));
check('详情作者', dFields.author.length > 0, dFields.author);
check('详情简介长度 > 20', dFields.description.length > 20, `len=${dFields.description.length}`);
check('详情状态去掉「状态:」', dFields.status.length > 0 && dFields.status.indexOf('状态') < 0, dFields.status);

const dChapters = parseChapters(dDoc, ding, dDetailUrl);
check('HTML 目录 24 章（站点只内嵌最近 24 章）', dChapters.length === 24, `${dChapters.length} 章`);

// 真正的目录来自 POST /comic/{id}，比 HTML 多得多
const dJsonChapters = parseChaptersFromJson(
  read('顶漫画-目录.json'), ding, 'https://www.dingmanhua.com/comic/7281');
check('JSON 目录 >= 80 章', dJsonChapters.length >= 80, `${dJsonChapters.length} 章`);
if (dJsonChapters.length > 0) {
  console.log('   JSON 首章:', JSON.stringify(dJsonChapters[0]));
  console.log('   JSON 末章:', JSON.stringify(dJsonChapters[dJsonChapters.length - 1]));
  check('首章是第01卷（已按正序翻转）', dJsonChapters[0].title === '第01卷', dJsonChapters[0].title);
  check('章节地址由模板拼出', dJsonChapters[0].url ===
    'https://www.dingmanhua.com/chapter/7281-564427.html', dJsonChapters[0].url);
  check('章节 id 来自 JSON 字段', dJsonChapters[0].chapterId === '564427', dJsonChapters[0].chapterId);
}

if (dChapters.length > 0) {
  console.log('   首章:', JSON.stringify(dChapters[0]));
  console.log('   末章:', JSON.stringify(dChapters[dChapters.length - 1]));
  check('章节地址绝对', dChapters[0].url.startsWith('http'), dChapters[0].url);
  check('章节标题非空', dChapters[0].title.length > 0, dChapters[0].title);
}

const dImages = parseImagesFromSequence(read('顶漫画-章节.txt'), ding, 'https://www.dingmanhua.com/chapter/7281-564509.html');
check('正文图 45 张', dImages.length === 45, `${dImages.length} 张`);
if (dImages.length > 0) {
  console.log('   首图:', dImages[0].url);
  check('首图地址正确', dImages[0].url ===
    'https://image1.dingmanhua.com/mh/87d8c7f657de4e01ae09757537208b4d/891ce514-5254-402b-b5a4-9e653880c8e9/1.webp',
    dImages[0].url.slice(-40));
  check('末图序号正确', dImages[dImages.length - 1].url.endsWith('/45.webp'), dImages[dImages.length - 1].url.slice(-12));
}

// ───────────── 云漫画 ─────────────
console.log('');
console.log('== 云漫画 yunmanhua ==');
const yun = load('yunmanhua.json');
check('规则加载', yun.id === 'yunmanhua', `${yun.name} | ${yun.images.type} | 抽取=${yun.images.extract}`);

const ySearchUrl = 'https://www.yunmanhua.com/index.php/search?key=%E7%81%AB%E5%BD%B1';
const yItems = parseListItems(
  read('云漫画-搜索.txt'), yun.search.listSelector, yun.id, ySearchUrl,
  yun.search.title, yun.search.cover, yun.search.link,
  yun.search.id, yun.search.author, yun.search.latest
);
check('搜索条数 >= 2', yItems.length >= 2, `${yItems.length} 条`);
if (yItems.length > 0) {
  const first = yItems[0];
  console.log('   样例:', JSON.stringify({
    id: first.comicId, title: first.title, cover: first.cover, url: first.url, author: first.author
  }).slice(0, 300));
  check('搜索标题非空', first.title.length > 0, first.title);
  check('搜索封面绝对地址', first.cover.startsWith('http'), first.cover.slice(0, 60));
  check('详情地址绝对化', first.url.startsWith('https://www.yunmanhua.com/'), first.url);
}

const yDetailUrl = 'https://www.yunmanhua.com/62kD4weNke';
const yDoc = parseHtml(read('云漫画-详情.txt'));
const yFields = parseDetailFields(yDoc, yun, yDetailUrl);
console.log('   详情:', JSON.stringify(yFields).slice(0, 260));
check('详情标题', yFields.title.length > 0, yFields.title);
check('详情封面', yFields.cover.startsWith('http'), yFields.cover.slice(0, 60));
check('详情作者去掉「作者：」', yFields.author.length > 0 && yFields.author.indexOf('作者') < 0, yFields.author);
check('详情状态', yFields.status.length > 0, yFields.status);

const yChapters = parseChapters(yDoc, yun, yDetailUrl);
check('章节数 >= 100', yChapters.length >= 100, `${yChapters.length} 章`);
if (yChapters.length > 0) {
  console.log('   首章:', JSON.stringify(yChapters[0]));
  console.log('   末章:', JSON.stringify(yChapters[yChapters.length - 1]));
  check('章节地址绝对', yChapters[0].url.startsWith('http'), yChapters[0].url);
  check('章节标题非空', yChapters[0].title.length > 0, yChapters[0].title);
}

console.log('');
console.log(`结果：${pass} 通过 / ${fail} 失败`);
if (fail > 0) {
  process.exit(1);
}
