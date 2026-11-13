// 离线引擎回归：从 app 当前源码生成临时 TypeScript 镜像，避免测试副本漂移。
// 网络图源验证请显式运行 live.ts。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const here = path.resolve(import.meta.dirname);
const repo = path.resolve(here, '..', '..');
const appRoot = path.join(repo, 'app', 'entry', 'src', 'main', 'ets');
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'shiman-engine-'));
function mirror(relative: string, output: string): void {
  let source = fs.readFileSync(path.join(appRoot, relative), 'utf8');
  source = source.replaceAll("'../parse/Html'", "'./Html.ts'")
    .replaceAll("'../parse/Selector'", "'./Selector.ts'")
    .replaceAll("'../parse/Json'", "'./Json.ts'")
    .replaceAll("'../util/Text'", "'./Text.ts'")
    .replaceAll("'../model/Models'", "'./Models.ts'")
    .replaceAll("'./Rules'", "'./Rules.ts'")
    .replaceAll("'./Html'", "'./Html.ts'")
    .replaceAll("'./Text'", "'./Text.ts'")
    .replaceAll("'@kit.CryptoArchitectureKit'", "'./kitshim.ts'")
    .replaceAll("'@kit.ArkTS'", "'./kitshim.ts'");
  fs.writeFileSync(path.join(tempRoot, output), source, 'utf8');
}

try {
  mirror('parse/Html.ets', 'Html.ts'); mirror('parse/Selector.ets', 'Selector.ts');
  mirror('parse/Json.ets', 'Json.ts'); mirror('util/Text.ets', 'Text.ts');
  mirror('model/Models.ets', 'Models.ts'); mirror('rule/Rules.ets', 'Rules.ts');
  mirror('rule/Engine.ets', 'Engine.ts');
  mirror('util/ChapterOrder.ets', 'ChapterOrder.ts');
  fs.copyFileSync(path.join(here, 'kitshim.ts'), path.join(tempRoot, 'kitshim.ts'));
  const html = await import(pathToFileURL(path.join(tempRoot, 'Html.ts')).href);
  const selector = await import(pathToFileURL(path.join(tempRoot, 'Selector.ts')).href);
  const json = await import(pathToFileURL(path.join(tempRoot, 'Json.ts')).href);
  const textUtil = await import(pathToFileURL(path.join(tempRoot, 'Text.ts')).href);
  const rules = await import(pathToFileURL(path.join(tempRoot, 'Rules.ts')).href);
  const engine = await import(pathToFileURL(path.join(tempRoot, 'Engine.ts')).href);
  let pass = 0; let fail = 0;
  const check = (name: string, ok: boolean, detail: string): void => {
    if (ok) { pass++; console.log(`  PASS  ${name}  ${detail}`); }
    else { fail++; console.log(`  FAIL  ${name}  ${detail}`); }
  };
  const order = await import(pathToFileURL(path.join(tempRoot, 'ChapterOrder.ts')).href);
  const model = await import(pathToFileURL(path.join(tempRoot, 'Models.ts')).href);
  const makeChapters = (titles: string[]): any[] => titles.map((title: string, index: number): any => {
    const item = new model.ChapterBrief();
    item.chapterId = 'chapter_' + index;
    item.title = title;
    item.url = 'https://example.test/' + index;
    item.index = index;
    return item;
  });
  const labels = makeChapters(['第1话', '第2话', '番外：纪念篇', '第3话', '第2话（重制）', '第4话']);
  const asc = order.normalizeChapterOrder(labels, true);
  check('夹杂番外/重复章仍识别正序', asc[0].title === '第1话' &&
    asc[asc.length - 1].title === '第4话', asc.map((x: any) => x.title).join('|'));
  const descInput = makeChapters(['第5回', '第4回', '特别篇', '第3回', '第2回', '第1回']);
  const chronological = order.normalizeChapterOrder(descInput, false);
  check('目录倒序可覆盖错误配置', chronological[0].title === '第1回' &&
    chronological[chronological.length - 1].title === '第5回', chronological.map((x: any) => x.title).join('|'));
  const chinese = order.normalizeChapterOrder(makeChapters(['第十二话', '第十一话', '第十话']), false);
  check('中文数字章节识别', chinese[0].title === '第十话' && chinese[2].title === '第十二话', 'ok');
  const japanese = order.normalizeChapterOrder(makeChapters(['第３話', '第２話', '第１話']), false);
  check('全角日文章节识别', japanese[0].title === '第１話', 'ok');
  const extras = order.normalizeChapterOrder(makeChapters(['2026-11-14 上架公告', '番外篇', '完结感言']), true);
  check('没有可信编号时按图源配置兜底', extras[0].title === '完结感言', 'ok');
  const ambiguous = order.detectChapterDirection(makeChapters(['第1话', '第2话', '第1话', '第2话']));
  check('反复重置的目录不盲猜方向', ambiguous === null, String(ambiguous));
  const repaired = order.flipChapterOrder(asc);
  const anchor = asc[2];
  const remapped = order.findChapterIndex(repaired, anchor.chapterId, anchor.title, 2);
  check('手动反向后旧章节 ID 仍能续读', repaired[remapped].chapterId === anchor.chapterId &&
    repaired.every((x: any, i: number) => x.index === i), String(remapped));
  const reverseDisplay = order.chaptersForDisplay(asc, true);
  check('目录展示反向不影响阅读索引', asc[0].index === 0 &&
    reverseDisplay[0].chapterId === asc[asc.length - 1].chapterId, 'ok');
  check('日期和卷号不会误认为章节序号',
    order.chapterOrderNumber('2026-11-14 最新公告') === -1 &&
    order.chapterOrderNumber('Vol.2 纪念画') === -1, 'ok');
  const doc = html.parseHtml('<div class="comic"><a href="/comic/12345"><img src="/cover.jpg">测试漫画</a></div>');
  const nodes = selector.queryAll(doc, '.comic a');
  check('当前源码 HTML/CSS 解析', nodes.length === 1, `nodes=${nodes.length}`);
  check('当前源码实体解码', textUtil.decodeEntities('&lt;a&gt;&#128512;') === '<a>😀', 'ok');
  check('当前源码 URL 解析', textUtil.resolveUrl('https://a.test/x/detail.html', '../img/1.jpg') === 'https://a.test/img/1.jpg', 'ok');
  check('零宽正则不会死循环', textUtil.allCapturesOf('abc', '(?=b)').length === 0, 'ok');
  check('正常正则捕获保持兼容', textUtil.allCapturesOf('a1 b2', '([a-z])\\d').join(',') === 'a,b', 'ok');
  check('当前源码 JSON 解析', json.parseJson('{"data":[1,2]}').get('data').items.length === 2, 'ok');
  const rule = new rules.SourceRule(); rule.id = 'fixture'; rule.name = '离线样例'; rule.baseUrl = 'https://a.test/';
  rule.search.listSelector = '.comic'; rule.search.id = 'a@attr:data-id||a@attr:href';
  rule.search.title = 'a@text'; rule.search.cover = 'img@attr:src'; rule.search.link = 'a@attr:href';
  rule.images.list = '$.data.page'; rule.images.field = 'image';
  const items = engine.parseListItems('<div class="comic"><a data-id="12345" href="/comic/12345"><img src="/cover.jpg">测试漫画</a></div>',
    rule.search.listSelector, rule.id, rule.baseUrl, rule.search.title, rule.search.cover, rule.search.link,
    rule.search.id, rule.search.author, rule.search.latest);
  check('当前源码列表解析', items.length === 1 && items[0].comicId === '12345', `${items.length} 条`);
  const images = engine.parseImagesFromJson('{"data":{"page":[{"image":"http:\\/\\/cdn.test\\/1.jpg?auth_key=x"}]}}', rule, rule.baseUrl);
  check('当前源码图片解析', images.length === 1 && images[0].url.indexOf('auth_key=x') >= 0, `${images.length} 张`);
  const ganmaPath = path.join(repo, 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'sources', 'ganma.json');
  const ganma = rules.ruleFromJson(json.parseJson(fs.readFileSync(ganmaPath, 'utf8')));
  const ganmaSearch = '<ul><li class="grid"><a href="/web/magazine/kaidanloop">' +
    '<img alt="怪談ルゥプ" src="https://cdn.example/cover.jpg"><h2>怪談ルゥプ</h2></a></li></ul>';
  const ganmaResults = engine.parseListItems(ganmaSearch, ganma.search.listSelector, ganma.id, ganma.baseUrl,
    ganma.search.title, ganma.search.cover, ganma.search.link,
    ganma.search.id, ganma.search.author, ganma.search.latest);
  check('GANMA 搜索规则可解析卡片', ganmaResults.length === 1 &&
    ganmaResults[0].url === 'https://ganma.jp/web/magazine/kaidanloop', String(ganmaResults.length) + ' 条');

  const ganmaChapters = '<a href="/web/reader/kaidanloop/story-one/0">第1話を読む</a>' +
    '<div><a href="/web/reader/kaidanloop/story-one/0">第1話</a>' +
    '<a href="/web/reader/kaidanloop/story-two/0">第2話</a></div>';
  const chapterItems = engine.parseChapters(html.parseHtml(ganmaChapters), ganma,
    'https://ganma.jp/web/magazine/kaidanloop');
  check('GANMA 章节 CTA 与目录链接去重', chapterItems.length === 2, String(chapterItems.length) + ' 话');

  const signedBase = 'https://d1bzi54d5ruxfk.cloudfront.net/story_' +
    '936237d0-d2b2-11e9-b339-5e26199913ba_pages_1605685833000_orig/';
  const imageOne = signedBase + '1.jpg?Policy=p\\u0026Signature=s\\u0026Key-Pair-Id=k';
  const imageTwo = signedBase + '2.jpg?Policy=p\\u0026Signature=s\\u0026Key-Pair-Id=k';
  const ganmaPages = '"url":"' + imageOne + '","url":"' + imageOne + '","url":"' + imageTwo + '"';
  const decodedPages = engine.parseImagesFromRegex(ganmaPages, ganma, 'https://ganma.jp/web/reader/test');
  check('GANMA CDN 签名正确解码与正文去重', decodedPages.length === 2 &&
    decodedPages[0].url.includes('&Signature=s&Key-Pair-Id=k') &&
    decodedPages[1].url.includes('/2.jpg?'), String(decodedPages.length) + ' 张');

  console.log(`\n===== 当前 app 源码离线回归: PASS ${pass} / FAIL ${fail} =====`);
  process.exitCode = fail === 0 ? 0 : 1;
} finally { fs.rmSync(tempRoot, { recursive: true, force: true }); }
