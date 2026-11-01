// 最小 HTTP 客户端：跟随跳转、解 gzip/deflate/br、按 charset 解码。
// 仅用于开发期探测，不参与 App 构建。
import https from 'node:https';
import http from 'node:http';
import zlib from 'node:zlib';
import { URL } from 'node:url';

export const DEFAULT_UA =
  'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

export function fetchFollow(urlStr, opts = {}) {
  const max = opts.maxRedirects ?? 6;
  let hops = 0;
  return new Promise((resolve) => {
    const go = (u) => {
      let url;
      try { url = new URL(u); } catch { resolve({ ok: false, stage: 'bad-url', detail: u }); return; }
      const mod = url.protocol === 'http:' ? http : https;
      const req = mod.request({
        hostname: url.hostname,
        port: url.port || (url.protocol === 'http:' ? 80 : 443),
        path: url.pathname + url.search,
        method: opts.method || 'GET',
        headers: {
          'User-Agent': opts.ua || DEFAULT_UA,
          'Accept': 'text/html,application/json,*/*',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          ...(opts.headers || {}),
        },
        timeout: opts.timeout ?? 15000,
        rejectUnauthorized: false,
      }, (res) => {
        const sc = res.statusCode || 0;
        if (sc >= 300 && sc < 400 && res.headers.location && hops < max) {
          hops++;
          res.resume();
          go(new URL(res.headers.location, url).toString());
          return;
        }
        const enc = String(res.headers['content-encoding'] || '').toLowerCase();
        let stream = res;
        if (enc === 'gzip') stream = res.pipe(zlib.createGunzip({ finishFlush: zlib.constants.Z_SYNC_FLUSH }));
        else if (enc === 'deflate') stream = res.pipe(zlib.createInflate({ finishFlush: zlib.constants.Z_SYNC_FLUSH }));
        else if (enc === 'br') stream = res.pipe(zlib.createBrotliDecompress({ finishFlush: zlib.constants.BROTLI_OPERATION_FLUSH }));
        const chunks = [];
        let size = 0;
        stream.on('data', (c) => { size += c.length; if (size <= 800 * 1024) chunks.push(c); });
        stream.on('end', () => {
          const buf = Buffer.concat(chunks);
          const ct = String(res.headers['content-type'] || '');
          const m = /charset=([\w-]+)/i.exec(ct);
          const charset = (m ? m[1] : 'utf-8').toLowerCase();
          let text;
          if (/gb/i.test(charset)) {
            try { text = new TextDecoder('gbk').decode(buf); } catch { text = buf.toString('latin1'); }
          } else text = buf.toString('utf8');
          resolve({ ok: sc >= 200 && sc < 400, status: sc, finalUrl: url.toString(), type: ct.split(';')[0], charset, len: size, text, headers: res.headers });
        });
        stream.on('error', (e) => resolve({ ok: false, stage: 'decode', detail: String(e.message).slice(0, 80), status: sc, finalUrl: url.toString() }));
      });
      req.on('timeout', () => { req.destroy(); resolve({ ok: false, stage: 'timeout', finalUrl: u }); });
      req.on('error', (e) => resolve({ ok: false, stage: e.code || 'error', detail: String(e.message).slice(0, 80), finalUrl: u }));
      if (opts.body) req.write(opts.body);
      req.end();
    };
    go(urlStr);
  });
}
