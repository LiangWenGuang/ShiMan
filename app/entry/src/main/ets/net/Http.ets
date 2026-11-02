/**
 * HTTP 客户端。
 *
 * 三条硬规则（都是踩过的坑）：
 *  1. 非幂等请求（POST/PUT/DELETE）绝不重试，避免弱网下重复提交；
 *  2. 一律取字节流再按站点 charset 解码，不依赖框架默认的 UTF-8；
 *  3. 响应体设上限，防止异常大页面把内存打穿。
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

const MAX_BODY_BYTES: number = 8 * 1024 * 1024;
const DEFAULT_UA: string =
  'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/131.0.0.0 Mobile Safari/537.36';

export class HttpResponse {
  status: number = 0;
  body: string = '';
  finalUrl: string = '';
  contentType: string = '';
  byteLength: number = 0;
  ok: boolean = false;
  error: string = '';
}

export class HttpHeader {
  name: string;
  value: string;

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}

function isIdempotent(method: http.RequestMethod): boolean {
  return method === http.RequestMethod.GET || method === http.RequestMethod.HEAD;
}

/**
 * 把 catch 到的错误转成能给人看的文字。
 *
 * 鸿蒙的网络异常多是 BusinessError（普通对象，只有 code/message 字段），
 * 直接 `String(error)` 只会得到 `[object Object]`，界面上一片无语。
 */
export function describeError(error: Error): string {
  const message = error.message;
  if (message !== undefined && message !== null && message.length > 0) {
    return message;
  }
  const code = (error as BusinessError).code;
  if (code !== undefined && code !== null && code !== 0) {
    return `网络请求失败（错误码 ${code}）`;
  }
  return '网络请求失败';
}

function detectCharset(contentType: string, fallback: string): string {
  const lower = contentType.toLowerCase();
  const index = lower.indexOf('charset=');
  if (index < 0) {
    return fallback;
  }
  let charset = lower.substring(index + 8).trim();
  const semicolon = charset.indexOf(';');
  if (semicolon >= 0) {
    charset = charset.substring(0, semicolon);
  }
  charset = charset.replace(new RegExp('["\']', 'g'), '').trim();
  if (charset === 'gb2312' || charset === 'gbk') {
    return 'gbk';
  }
  return charset.length > 0 ? charset : fallback;
}

function decodeBody(data: ArrayBuffer, charset: string): string {
  const bytes = new Uint8Array(data);
  if (charset.length === 0 || charset === 'utf-8' || charset === 'utf8') {
    try {
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    } catch (error) {
      return '';
    }
  }
  try {
    const decoder = util.TextDecoder.create(charset);
    return decoder.decodeToString(bytes);
  } catch (error) {
    // 系统不支持该编码时退回 UTF-8，让页面至少能显示部分内容
    try {
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    } catch (inner) {
      return '';
    }
  }
}

/** 默认请求头 */
export function defaultHeaders(referer: string): HttpHeader[] {
  const headers: HttpHeader[] = [];
  headers.push(new HttpHeader('User-Agent', DEFAULT_UA));
  headers.push(new HttpHeader('Accept', 'text/html,application/json,application/xhtml+xml,*/*'));
  headers.push(new HttpHeader('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8'));
  if (referer.length > 0) {
    headers.push(new HttpHeader('Referer', referer));
  }
  return headers;
}

export class Http {
  /**
   * 发起 GET 请求。
   * @param fallbackCharset 站点声明的编码，用于响应头缺失 charset 时兜底
   */
  static async get(url: string, headers: HttpHeader[], fallbackCharset: string): Promise<HttpResponse> {
    return Http.send(url, http.RequestMethod.GET, headers, fallbackCharset);
  }

  /**
   * 发起 POST 请求。只给「取目录」这类重复调用且无副作用接口用；
   * 非幂等请求不会重试（见文件头第 1 条规则）。
   */
  static async post(
    url: string,
    headers: HttpHeader[],
    fallbackCharset: string,
    body: string
  ): Promise<HttpResponse> {
    return Http.send(url, http.RequestMethod.POST, headers, fallbackCharset, body);
  }

  static async send(
    url: string,
    method: http.RequestMethod,
    headers: HttpHeader[],
    fallbackCharset: string,
    body: string = ''
  ): Promise<HttpResponse> {
    const result = new HttpResponse();
    if (url.length === 0) {
      result.error = '空地址';
      return result;
    }
    const headerObject: Record<string, string> = {};
    for (let i = 0; i < headers.length; i++) {
      const item = headers[i];
      if (item.name.length > 0) {
        headerObject[item.name] = item.value;
      }
    }
    // POST 带 body 时补 Content-Type：JSON 体用 application/json，其余按表单编码。
    // 否则部分站（如如漫画）收不到表单参数，返回空结果。
    if (method === http.RequestMethod.POST && body.length > 0) {
      let hasContentType = false;
      for (let i = 0; i < headers.length; i++) {
        if (headers[i].name.toLowerCase() === 'content-type') {
          hasContentType = true;
          break;
        }
      }
      if (!hasContentType) {
        const trimmed = body.trimStart();
        headerObject['Content-Type'] =
          (trimmed.startsWith('{') || trimmed.startsWith('['))
            ? 'application/json; charset=utf-8'
            : 'application/x-www-form-urlencoded; charset=utf-8';
      }
    }
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: method,
        header: headerObject,
        extraData: body.length > 0 ? body : undefined,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        connectTimeout: 15000,
        readTimeout: 25000
      });
      result.status = response.responseCode;
      result.contentType = String(response.header['content-type'] === undefined ? '' : response.header['content-type']);
      const raw = response.result;
      if (raw instanceof ArrayBuffer) {
        if (raw.byteLength > MAX_BODY_BYTES) {
          result.error = `响应体过大（${raw.byteLength} 字节），已丢弃`;
          return result;
        }
        result.byteLength = raw.byteLength;
        const charset = detectCharset(result.contentType, fallbackCharset);
        result.body = decodeBody(raw, charset);
      } else if (typeof raw === 'string') {
        result.body = raw;
        result.byteLength = raw.length;
      }
      result.finalUrl = response.header['location'] === undefined ? url : String(response.header['location']);
      result.ok = result.status >= 200 && result.status < 400;
      if (!result.ok) {
        result.error = `HTTP ${result.status}`;
      }
      return result;
    } catch (error) {
      const message = describeError(error);
      result.error = message;
      result.ok = false;
      // 幂等请求重试一次：多数是首包握手抖动
      if (isIdempotent(method)) {
        return Http.retryOnce(url, method, headers, fallbackCharset);
      }
      return result;
    } finally {
      request.destroy();
    }
  }

  private static async retryOnce(
    url: string,
    method: http.RequestMethod,
    headers: HttpHeader[],
    fallbackCharset: string
  ): Promise<HttpResponse> {
    const result = new HttpResponse();
    const headerObject: Record<string, string> = {};
    for (let i = 0; i < headers.length; i++) {
      headerObject[headers[i].name] = headers[i].value;
    }
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: method,
        header: headerObject,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        connectTimeout: 15000,
        readTimeout: 25000
      });
      result.status = response.responseCode;
      result.contentType = String(response.header['content-type'] === undefined ? '' : response.header['content-type']);
      const raw = response.result;
      if (raw instanceof ArrayBuffer) {
        result.byteLength = raw.byteLength;
        result.body = decodeBody(raw, detectCharset(result.contentType, fallbackCharset));
      } else if (typeof raw === 'string') {
        result.body = raw;
      }
      result.finalUrl = url;
      result.ok = result.status >= 200 && result.status < 400;
      if (!result.ok) {
        result.error = `HTTP ${result.status}（重试后仍失败）`;
      }
      return result;
    } catch (error) {
      result.error = describeError(error);
      result.ok = false;
      return result;
    } finally {
      request.destroy();
    }
  }

  /** 下载二进制（图片等） */
  static async getBytes(url: string, headers: HttpHeader[]): Promise<ArrayBuffer | null> {
    const headerObject: Record<string, string> = {};
    for (let i = 0; i < headers.length; i++) {
      headerObject[headers[i].name] = headers[i].value;
    }
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headerObject,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        connectTimeout: 15000,
        readTimeout: 30000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return null;
      }
      const raw = response.result;
      if (raw instanceof ArrayBuffer) {
        return raw;
      }
      return null;
    } catch (error) {
      return null;
    } finally {
      request.destroy();
    }
  }
}
