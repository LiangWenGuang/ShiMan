/**
 * 图源规则模型。
 *
 * 这是一套自定义的声明式 DSL —— 不是任何现有阅读器的规则格式。
 * 设计目标是「一个 JSON 描述一个站点」，配合 parse/ 下的解析与取值能力，
 * 让新增图源不需要改代码。
 *
 * 字段取值语法（FieldExpr）：
 *   `.title@text`            取后代 .title 的文本
 *   `img@attr:data-src`      取后代 img 的 data-src 属性
 *   `@text`                  取作用域自身文本
 *   `@attr:data-cid`         取作用域自身属性
 *   `@html`                  取作用域内部 HTML
 *   `A||B`                   备选链，A 取不到再试 B
 *   `...~s|正则|替换|`       末尾正则替换（g 全局，i 忽略大小写）
 */

import { JsonNode, JsonKind } from '../parse/Json';

export class HeaderPair {
  name: string = '';
  value: string = '';

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}

/** 搜索 */
export class SearchRule {
  url: string = '';
  listSelector: string = '';
  id: string = '';
  title: string = '';
  cover: string = '';
  author: string = '';
  latest: string = '';
  link: string = '';
  paged: boolean = false;
  /**
   * 空结果标记：页面里出现这段文字就说明「站点没搜到，给你看的是推荐位」。
   * 不做这个判断的话，聚合搜索会被推荐内容污染。
   */
  emptyMarker: string = '';
}

/** 列表型页面（分类 / 首页 / 排行） */
export class BrowseRule {
  name: string = '';
  url: string = '';
  listSelector: string = '';
  id: string = '';
  title: string = '';
  cover: string = '';
  author: string = '';
  latest: string = '';
  link: string = '';
}

/** 详情 */
export class DetailRule {
  title: string = '';
  cover: string = '';
  author: string = '';
  desc: string = '';
  status: string = '';
  tags: string = '';
  alias: string = '';
}

/** 章节列表 */
export class ChapterRule {
  /** 章节目录页模板；留空表示直接在详情页解析 */
  url: string = '';
  listSelector: string = '';
  id: string = '';
  title: string = '';
  link: string = '';
  reverse: boolean = false;
  /** 章节地址是否需要从详情页的基础地址拼接 */
  fromDetailPage: boolean = true;
  /** 可选：章节来自 JSON（页面内嵌 / 远程接口） */
  json: JsonChapterRule = new JsonChapterRule();
}

/**
 * JSON 型章节列表。
 * 有些站把整份目录塞进 <script type="text/plain" id="xxx"> 里，
 * 也有些站单独给一个接口，这里统一处理两种情况。
 */
export class JsonChapterRule {
  /** inline = 页面内嵌；remote = 单独请求 */
  source: string = '';
  /** inline：承载 JSON 的节点选择器 */
  selector: string = '';
  /** remote：接口地址模板 */
  url: string = '';
  path: string = '$';
  idField: string = 'id';
  titleField: string = 'title';
  linkField: string = 'url';
  /** link 是相对地址时的基准；留空用页面地址 */
  baseUrl: string = '';
  /** get（默认）/ post：少数站点用 POST 返回整份目录 */
  method: string = 'get';
  /** method=post 时的请求体 */
  body: string = '';
  /**
   * 目录接口只给 id、不给地址时，用模板拼：
   * `/chapter/{contentId}-{id}.html`，花括号里是 JSON 字段名。
   */
  linkTemplate: string = '';
  enabled(): boolean {
    return this.source.length > 0;
  }
}

/** 图片列表 */
export class ImageRule {
  /** json | html | web | regex */
  type: string = 'json';
  /** 支持 {chapterUrl} {comicUrl} {chapterId} {comicId} {id} 模板 */
  url: string = '';
  /** JSON: path；HTML: 选择器 */
  list: string = '';
  /** JSON: 字段名；HTML: FieldExpr */
  field: string = '';
  /** web 模式：等待出现的选择器 */
  readySelector: string = '';
  /** web 模式：提取表达式，如 attr:data-src / text */
  extract: string = '';
  /** web 模式：加载后额外等待毫秒 */
  settleMs: number = 1200;
  /**
   * regex 模式的正则。有捕获组时取第 1 组，否则取整个匹配。
   * 专门对付「图片只出现在 JSON-LD / 内联 JS 数组里、没有 img 标签」的站点。
   */
  pattern: string = '';
  /**
   * sequence 模式：图片是「一个前缀 + 序号」拼出来的，只给个数不给地址。
   * 典型是 `var num = 45` + `var pasd = "https://cdn/xxx/"`，
   * 正文图地址就是 pasd + 1..num + 后缀。
   */
  countPattern: string = '';
  /** sequence 模式的地址模板，支持 {base} {i} {chapterUrl} {comicId} {chapterId} */
  template: string = '';
  /** sequence 模式没匹配到数量时的兜底上限，避免产出 0 张 */
  maxCount: number = 300;
}

export class SourceRule {
  id: string = '';
  name: string = '';
  baseUrl: string = '';
  charset: string = 'utf-8';
  /** 该源的可用性备注，展示在源管理里，便于用户判断 */
  note: string = '';
  headers: HeaderPair[] = [];
  search: SearchRule = new SearchRule();
  detail: DetailRule = new DetailRule();
  chapters: ChapterRule = new ChapterRule();
  images: ImageRule = new ImageRule();
  browse: BrowseRule[] = [];

  header(name: string): string {
    const lower = name.toLowerCase();
    for (let i = 0; i < this.headers.length; i++) {
      if (this.headers[i].name.toLowerCase() === lower) {
        return this.headers[i].value;
      }
    }
    return '';
  }
}

function str(node: JsonNode | null, key: string, fallback: string): string {
  if (node === null) {
    return fallback;
  }
  const value = node.get(key);
  if (value === null || value.kind !== JsonKind.String) {
    return fallback;
  }
  return value.text;
}

function num(node: JsonNode | null, key: string, fallback: number): number {
  if (node === null) {
    return fallback;
  }
  const value = node.get(key);
  if (value === null || value.kind !== JsonKind.Number) {
    return fallback;
  }
  return value.number;
}

function bool(node: JsonNode | null, key: string, fallback: boolean): boolean {
  if (node === null) {
    return fallback;
  }
  const value = node.get(key);
  if (value === null || value.kind !== JsonKind.Bool) {
    return fallback;
  }
  return value.flag;
}

/** 把 JSON 节点组装成 SourceRule */
export function ruleFromJson(root: JsonNode): SourceRule {
  const rule = new SourceRule();
  rule.id = str(root, 'id', '');
  rule.name = str(root, 'name', rule.id);
  rule.baseUrl = str(root, 'baseUrl', '');
  rule.charset = str(root, 'charset', 'utf-8');
  rule.note = str(root, 'note', '');

  const headers = root.get('headers');
  if (headers !== null && headers.kind === JsonKind.Array) {
    for (let i = 0; i < headers.items.length; i++) {
      const item = headers.items[i];
      rule.headers.push(new HeaderPair(str(item, 'name', ''), str(item, 'value', '')));
    }
  }

  const search = root.get('search');
  if (search !== null) {
    const target = rule.search;
    target.url = str(search, 'url', '');
    target.listSelector = str(search, 'list', '');
    target.id = str(search, 'id', '');
    target.title = str(search, 'title', '');
    target.cover = str(search, 'cover', '');
    target.author = str(search, 'author', '');
    target.latest = str(search, 'latest', '');
    target.link = str(search, 'link', '');
    target.paged = bool(search, 'paged', false);
    target.emptyMarker = str(search, 'emptyMarker', '');
  }

  const detail = root.get('detail');
  if (detail !== null) {
    const target = rule.detail;
    target.title = str(detail, 'title', '');
    target.cover = str(detail, 'cover', '');
    target.author = str(detail, 'author', '');
    target.desc = str(detail, 'desc', '');
    target.status = str(detail, 'status', '');
    target.tags = str(detail, 'tags', '');
    target.alias = str(detail, 'alias', '');
  }

  const chapters = root.get('chapters');
  if (chapters !== null) {
    const target = rule.chapters;
    target.url = str(chapters, 'url', '');
    target.listSelector = str(chapters, 'list', '');
    target.id = str(chapters, 'id', '');
    target.title = str(chapters, 'title', '');
    target.link = str(chapters, 'link', '');
    target.reverse = bool(chapters, 'reverse', false);
    target.fromDetailPage = bool(chapters, 'fromDetailPage', true);
    const jsonRule = chapters.get('json');
    if (jsonRule !== null) {
      target.json.source = str(jsonRule, 'source', '');
      target.json.selector = str(jsonRule, 'selector', '');
      target.json.url = str(jsonRule, 'url', '');
      target.json.path = str(jsonRule, 'path', '$');
      target.json.idField = str(jsonRule, 'idField', 'id');
      target.json.titleField = str(jsonRule, 'titleField', 'title');
      target.json.linkField = str(jsonRule, 'linkField', 'url');
      target.json.baseUrl = str(jsonRule, 'baseUrl', '');
      target.json.method = str(jsonRule, 'method', 'get');
      target.json.body = str(jsonRule, 'body', '');
      target.json.linkTemplate = str(jsonRule, 'linkTemplate', '');
    }
  }

  const images = root.get('images');
  if (images !== null) {
    const target = rule.images;
    target.type = str(images, 'type', 'json');
    target.url = str(images, 'url', '');
    target.list = str(images, 'list', '');
    target.field = str(images, 'field', '');
    target.readySelector = str(images, 'readySelector', '');
    target.extract = str(images, 'extract', '');
    target.settleMs = num(images, 'settleMs', 1200);
    target.pattern = str(images, 'pattern', '');
    target.countPattern = str(images, 'countPattern', '');
    target.template = str(images, 'template', '');
    target.maxCount = num(images, 'maxCount', 300);
  }

  const browse = root.get('browse');
  if (browse !== null && browse.kind === JsonKind.Array) {
    for (let i = 0; i < browse.items.length; i++) {
      const item = browse.items[i];
      const entry = new BrowseRule();
      entry.name = str(item, 'name', '分类');
      entry.url = str(item, 'url', '');
      entry.listSelector = str(item, 'list', rule.search.listSelector);
      entry.id = str(item, 'id', rule.search.id);
      entry.title = str(item, 'title', rule.search.title);
      entry.cover = str(item, 'cover', rule.search.cover);
      entry.author = str(item, 'author', rule.search.author);
      entry.latest = str(item, 'latest', rule.search.latest);
      entry.link = str(item, 'link', rule.search.link);
      rule.browse.push(entry);
    }
  }
  return rule;
}
