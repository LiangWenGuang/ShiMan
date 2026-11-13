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
  'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWeb statKit/537.36 (KHTML, like Gecko) ' +
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

/** 图片请求结果，保留失败阶段供图片占位提示使用。 */
export class BytesResponse {
  bytes: ArrayBuffer | null = null;
  status: number = 0;
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
  static async get(url: string, headers: HttpHeader[], fallbackCharset: string): Promise<HttpResponse> {
    return Http.send(url, http.RequestMethod.GET, headers, fallbackCharset);
  }

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
        if (raw.length > MAX_BODY_BYTES) {
          result.error = `响应体过大（${raw.length} 字符），已丢弃`;
          return result;
        }
        result.body = raw;
        result.byteLength = raw.length;
      }
      result.finalUrl = response.header['location'] === undefined ? url : String(response.header['location']);
      result.ok = result.status >= 200 && result.status < 300;
      if (!result.ok) {
        result.error = `HTTP ${result.status}`;
      }
      return result;
    } catch (error) {
      const message = describeError(error);
      result.error = message;
      result.ok = false;
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
        if (raw.byteLength > MAX_BODY_BYTES) {
          result.error = `响应体过大（${raw.byteLength} 字节），已丢弃`;
          return result;
        }
        result.byteLength = raw.byteLength;
        result.body = decodeBody(raw, detectCharset(result.contentType, fallbackCharset));
      } else if (typeof raw === 'string') {
        if (raw.length > MAX_BODY_BYTES) {
          result.error = `响应体过大（${raw.length} 字符），已丢弃`;
          return result;
        }
        result.body = raw;
        result.byteLength = raw.length;
      }
      result.finalUrl = response.header['location'] === undefined ? url : String(response.header['location']);
      result.ok = result.status >= 200 && result.status < 300;
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

  /** 下载二进制（图片等），失败重试一次，并限制体积 */
  static async getBytes(url: string, headers: HttpHeader[]): Promise<ArrayBuffer | null> {
    const result = await Http.getBytesDetailed(url, headers);
    return result.bytes;
  }

  static async getBytesDetailed(url: string, headers: HttpHeader[]): Promise<BytesResponse> {
    let result = await Http.getBytesOnceDetailed(url, headers);
    // 只重试网络错误、限流或服务端故障；404/403 和超大响应重试不会恢复。
    const retryable = result.status === 408 || result.status === 429 || result.status >= 500 ||
      (result.status === 0 && result.error !== '空地址');
    if (result.bytes === null && retryable) {
      const retry = await Http.getBytesOnceDetailed(url, headers);
      if (retry.bytes !== null) return retry;
      result.error = retry.error.length > 0 ? retry.error : result.error;
    }
    return result;
  }

  private static async getBytesOnce(url: string, headers: HttpHeader[]): Promise<ArrayBuffer | null> {
    const result = await Http.getBytesOnceDetailed(url, headers);
    return result.bytes;
  }

  private static async getBytesOnceDetailed(url: string, headers: HttpHeader[]): Promise<BytesResponse> {
    const result = new BytesResponse();
    if (url.length === 0) {
      result.error = '空地址';
      return result;
    }
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
      result.status = response.responseCode;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        result.error = `HTTP ${response.responseCode}`;
        // 失败也返回完整 BytesResponse，调用方统一读取 bytes/error，避免 ArkTS 空值类型错误。
        return result;
      }
      const raw = response.result;
      if (raw instanceof ArrayBuffer) {
        if (raw.byteLength > MAX_BODY_BYTES) {
          result.error = `图片过大（${raw.byteLength} 字节）`;
          return result;
        }
        result.bytes = raw;
        return result;
      }
      result.error = '响应不是图片字节流';
      return result;
    } catch (error) {
      result.error = describeError(error as Error);
      return result;
    } finally {
      request.destroy();
    }
  }
}
