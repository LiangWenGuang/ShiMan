// 分类页 / 章节时间回归：拿真实抓取的页面跑 parseListItems / parseChapters，
// 断言条数与关键字段。跑法：
//   bash tools/sync-engine-tests.sh
//   cd tools/engine-test && node --experimental-transform-types test-browse.ts
import fs from 'node:fs';
import path from 'node:path';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseListItems, parseChapters, parseChaptersFromJson } from './Engine.ts';
import { parseHtml } from './Html.ts';

const ROOT = 'F:/AI/QoderCN-Data/output/harmony-comic-origin';
const SRC = path.join(ROOT, 'app/entry/src/main/resources/rawfile/sources');
const DUMPS = path.join(ROOT, 'tools/dumps');

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

function loadRule(file: string) {
  return ruleFromJson(parseJson(fs.readFileSync(path.join(SRC, file), 'utf8')));
}

function run(file: string, browseUrl: string, dump: string, expectMin: number) {
  const rule = loadRule(file);
  const entry = rule.browse.find((b) => b.url === browseUrl);
  if (!entry) {
    check(`${file} ${browseUrl}`, false, '规则里没有这个分类');
    return;
  }
  const html = fs.readFileSync(path.join(DUMPS, dump), 'utf8');
  const items = parseListItems(
    html, entry.listSelector, rule.id, rule.baseUrl + browseUrl,
    entry.title, entry.cover, entry.link, entry.id, entry.author, entry.latest
  );
  const first = items[0];
  const detail = first === undefined
    ? `${items.length} 条`
    : `${items.length} 条 | ${first.title} | 更新=${first.latest || '-'} | ${first.cover.slice(0, 40)}`;
  check(`${rule.name} / ${entry.name}`, items.length >= expectMin, detail);
}

function runChaptersHtml(file: string, dump: string, pageUrl: string, expectMin: number) {
  const rule = loadRule(file);
  const doc = parseHtml(fs.readFileSync(path.join(DUMPS, dump), 'utf8'));
  const chapters = parseChapters(doc, rule, pageUrl, false);
  const first = chapters[0];
  check(`${rule.name} 章节(HTML)`, chapters.length >= expectMin,
    `${chapters.length} 章 | ${first?.title ?? '-'} | 时间=${first?.time ?? ''}`);
  check(`${rule.name} 章节带时间`, (first?.time ?? '').length > 0, first?.time ?? '(空)');
}

function runChaptersJson(file: string, dump: string, comicId: string, expectMin: number) {
  const rule = loadRule(file);
  const text = fs.readFileSync(path.join(DUMPS, dump), 'utf8');
  const chapters = parseChaptersFromJson(text, rule, rule.baseUrl, comicId, false);
  const first = chapters[0];
  check(`${rule.name} 章节(JSON)`, chapters.length >= expectMin,
    `${chapters.length} 章 | ${first?.title ?? '-'} | 时间=${first?.time ?? ''} | ${first?.url ?? ''}`);
  check(`${rule.name} 章节带时间`, (first?.time ?? '').length > 0, first?.time ?? '(空)');
}

console.log('== 分类/榜单 ==');
run('rumanhua.json', '/rank/1', '如漫画-sort1.html', 20);
run('rumanhua.json', '/sort/1', '如漫画-sort1.html', 20);
run('dingmanhua.json', '/', '顶漫画-home.html', 10);
run('dingmanhua.json', '/new', '顶漫画-new.html', 10);
run('dingmanhua.json', '/hot', '顶漫画-hot.html', 10);
run('sisi.json', '/', '丝丝-home.html', 8);
run('aiguoman.json', '/custom/update', '爱国漫-update.html', 10);
run('aiguoman.json', '/category/tags/2572', '爱国漫-tag2572.html', 10);
run('guomanwang.json', '/category/list/1', '国漫网-list1.html', 10);

console.log('== 章节更新时间 ==');
runChaptersJson('dingmanhua.json', '顶漫画-chapters.json', '298', 100);
runChaptersHtml('didi.json', '滴滴-detail.html', 'https://www.didimh.com/comic/a8c0923b62/', 20);

console.log(`\n合计：PASS ${pass} / FAIL ${fail}`);
process.exit(fail === 0 ? 0 : 1);
