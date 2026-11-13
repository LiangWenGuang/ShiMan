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
