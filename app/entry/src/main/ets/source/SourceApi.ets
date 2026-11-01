/**
 * 图源调用门面：把「规则 + 网络 + 解析」串成一次可用的数据请求。
 * 页面层只跟这里打交道，不关心某个源是 JSON 接口还是 HTML 页面。
 */

import { SourceRule, BrowseRule } from '../rule/Rules';
import { Http, HttpResponse, HttpHeader, defaultHeaders } from '../net/Http';
import {
  parseListItems, parseDetailFields, parseChapters,
  parseImagesFromJson, parseImagesFromHtml, parseImagesFromRegex, parseImagesFromSequence, UrlVars,
  readEmbeddedJson, parseChaptersFromJson
} from '../rule/Engine';
import { parseHtml, HtmlDocument } from '../parse/Html';
import { Outcome, ComicBrief, ComicDetail, ChapterBrief, PageImage } from '../model/Models';
import { resolveUrl } from '../util/Text';

/** 图片请求结果：普通源的 images 直接可用；web 源需要页面层做一次无头提取 */
export class ImageResult {
  images: PageImage[] = [];
  needsHarvest: boolean = false;
  harvestUrl: string = '';
  readySelector: string = '';
  extract: string = '';
  settleMs: number = 1200;
  referer: string = '';
}

function buildHeaders(rule: SourceRule, referer: string): HttpHeader[] {
  const headers = defaultHeaders(referer.length > 0 ? referer : rule.baseUrl);
  for (let i = 0; i < rule.headers.length; i++) {
    const pair = rule.headers[i];
    if (pair.name.length > 0) {
      headers.push(new HttpHeader(pair.name, pair.value));
    }
  }
  return headers;
}

export class SourceApi {
  /** 搜索 */
  static async search(rule: SourceRule, keyword: string, page: number): Promise<Outcome<ComicBrief[]>> {
    const vars = new UrlVars()
      .set('kw', encodeURIComponent(keyword))
      .set('keyword', encodeURIComponent(keyword))
      .set('page', String(page));
    const url = resolveUrl(rule.baseUrl, vars.apply(rule.search.url));
    const response = await Http.get(url, buildHeaders(rule, rule.baseUrl), rule.charset);
    if (!response.ok) {
      return Outcome.failure<ComicBrief[]>(`${rule.name}：${response.error}`);
    }
    if (rule.search.emptyMarker.length > 0 && response.body.indexOf(rule.search.emptyMarker) >= 0) {
      return Outcome.failure<ComicBrief[]>(`${rule.name}：没有这本`);
    }
    try {
      const items = parseListItems(
        response.body,
        rule.search.listSelector,
        rule.id,
        url,
        rule.search.title,
        rule.search.cover,
        rule.search.link,
        rule.search.id,
        rule.search.author,
        rule.search.latest
      );
      if (items.length === 0) {
        return Outcome.failure<ComicBrief[]>(`${rule.name}：没有匹配结果`);
      }
      return Outcome.success(items);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return Outcome.failure<ComicBrief[]>(`${rule.name}：解析失败 ${message}`);
    }
  }

  /** 分类 / 首页列表 */
  static async browse(rule: SourceRule, entry: BrowseRule, page: number): Promise<Outcome<ComicBrief[]>> {
    const vars = new UrlVars().set('page', String(page));
    const url = resolveUrl(rule.baseUrl, vars.apply(entry.url));
    const response = await Http.get(url, buildHeaders(rule, rule.baseUrl), rule.charset);
    if (!response.ok) {
      return Outcome.failure<ComicBrief[]>(`${rule.name}：${response.error}`);
    }
    try {
      const items = parseListItems(
        response.body,
        entry.listSelector,
        rule.id,
        url,
        entry.title,
        entry.cover,
        entry.link,
        entry.id,
        entry.author,
        entry.latest
      );
      return Outcome.success(items);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return Outcome.failure<ComicBrief[]>(`${rule.name}：解析失败 ${message}`);
    }
  }

  /** 详情 + 章节 */
  static async detail(rule: SourceRule, comicId: string, pageUrl: string): Promise<Outcome<ComicDetail>> {
    const url = pageUrl.length > 0 ? pageUrl : resolveUrl(rule.baseUrl, '/' + comicId);
    const response = await Http.get(url, buildHeaders(rule, rule.baseUrl), rule.charset);
    if (!response.ok) {
      return Outcome.failure<ComicDetail>(`${rule.name}：${response.error}`);
    }
    try {
      const doc: HtmlDocument = parseHtml(response.body);
      const fields = parseDetailFields(doc, rule, url);
      const detail = new ComicDetail();
      detail.sourceId = rule.id;
      detail.comicId = comicId;
      detail.url = url;
      detail.title = fields.title.length > 0 ? fields.title : comicId;
      detail.cover = fields.cover;
      detail.author = fields.author;
      detail.description = fields.description;
      detail.status = fields.status;
      detail.tags = fields.tags.length > 0 ? fields.tags.split(new RegExp('[,，/|\\s]+')) : [];

      if (rule.chapters.json.enabled()) {
        if (rule.chapters.json.source === 'inline') {
          const jsonText = readEmbeddedJson(doc, rule.chapters.json.selector);
          detail.chapters = parseChaptersFromJson(jsonText, rule, url);
        } else {
          const jsonUrl = new UrlVars()
            .set('comicId', comicId)
            .set('id', comicId)
            .set('url', url)
            .apply(rule.chapters.json.url);
          const targetJsonUrl = resolveUrl(rule.baseUrl, jsonUrl);
          const jsonResponse = rule.chapters.json.method === 'post'
            ? await Http.post(targetJsonUrl, buildHeaders(rule, url), rule.charset, rule.chapters.json.body)
            : await Http.get(targetJsonUrl, buildHeaders(rule, url), rule.charset);
          if (jsonResponse.ok) {
            const base = rule.chapters.json.baseUrl.length > 0
              ? rule.chapters.json.baseUrl : targetJsonUrl;
            detail.chapters = parseChaptersFromJson(jsonResponse.body, rule, base);
          }
        }
      } else if (rule.chapters.url.length > 0) {
        // 有些站点把章节目录单独放一页
        const chapterUrl = new UrlVars()
          .set('comicId', comicId)
          .set('id', comicId)
          .set('url', url)
          .apply(rule.chapters.url);
        const chapterResponse = await Http.get(
          resolveUrl(rule.baseUrl, chapterUrl), buildHeaders(rule, url), rule.charset);
        if (chapterResponse.ok) {
          detail.chapters = parseChapters(parseHtml(chapterResponse.body), rule,
            resolveUrl(rule.baseUrl, chapterUrl));
        }
      } else {
        detail.chapters = parseChapters(doc, rule, url);
      }

      if (detail.chapters.length === 0) {
        return Outcome.failure<ComicDetail>(`${rule.name}：未解析到章节`);
      }
      return Outcome.success(detail);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return Outcome.failure<ComicDetail>(`${rule.name}：解析失败 ${message}`);
    }
  }

  /** 章节图片 */
  static async images(
    rule: SourceRule,
    comicId: string,
    chapter: ChapterBrief
  ): Promise<Outcome<ImageResult>> {
    const result = new ImageResult();
    result.referer = chapter.url;

    if (rule.images.type === 'web') {
      const vars = new UrlVars()
        .set('chapterUrl', chapter.url)
        .set('chapterId', chapter.chapterId)
        .set('comicId', comicId)
        .set('url', chapter.url);
      result.needsHarvest = true;
      result.harvestUrl = vars.apply(rule.images.url).length > 0
        ? vars.apply(rule.images.url) : chapter.url;
      result.readySelector = rule.images.readySelector;
      result.extract = rule.images.extract;
      result.settleMs = rule.images.settleMs;
      return Outcome.success(result);
    }

    const vars = new UrlVars()
      .set('chapterUrl', chapter.url)
      .set('chapterId', chapter.chapterId)
      .set('comicId', comicId)
      .set('url', chapter.url);
    const target = vars.apply(rule.images.url).length > 0
      ? vars.apply(rule.images.url) : chapter.url;
    const response: HttpResponse = await Http.get(target, buildHeaders(rule, chapter.url), rule.charset);
    if (!response.ok) {
      return Outcome.failure<ImageResult>(`${rule.name}：${response.error}`);
    }
    try {
      if (rule.images.type === 'html') {
        result.images = parseImagesFromHtml(response.body, rule, target);
      } else if (rule.images.type === 'regex') {
        result.images = parseImagesFromRegex(response.body, rule, chapter.url);
      } else if (rule.images.type === 'sequence') {
        result.images = parseImagesFromSequence(response.body, rule, chapter.url);
      } else {
        result.images = parseImagesFromJson(response.body, rule, chapter.url);
      }
      if (result.images.length === 0) {
        return Outcome.failure<ImageResult>(`${rule.name}：本章未取到图片`);
      }
      return Outcome.success(result);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return Outcome.failure<ImageResult>(`${rule.name}：图片解析失败 ${message}`);
    }
  }
}
