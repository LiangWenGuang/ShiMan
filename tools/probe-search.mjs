// 第二轮：跟随跳转 + 直击各站搜索接口，输出最终 URL / 状态 / 体积 / 标题 / 片段，
// 用于判断站点是否真正可用并据此手写原创规则。
import https from 'node:https';
import http from 'node:http';
import zlib from 'node:zlib';
import { URL } from 'node:url';
import fs from 'node:fs';

const UA = 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

export function fetchFollow(urlStr, opts = {}) {
  const max = opts.maxRedirects ?? 6;
  let hops = 0;
  return new Promise((resolve) => {
    const go = (u) => {
      let url;
      try { url = new URL(u); } catch (e) { resolve({ ok: false, stage: 'bad-url', detail: u }); return; }
      const mod = url.protocol === 'http:' ? http : https;
      const req = mod.request({
        hostname: url.hostname,
        port: url.port || (url.protocol === 'http:' ? 80 : 443),
        path: url.pathname + url.search,
        method: 'GET',
        headers: {
          'User-Agent': opts.ua || UA,
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
          const next = new URL(res.headers.location, url).toString();
          res.resume();
          go(next);
          return;
        }
        const enc = String(res.headers['content-encoding'] || '').toLowerCase();
        let stream = res;
        if (enc === 'gzip') stream = res.pipe(zlib.createGunzip({ finishFlush: zlib.constants.Z_SYNC_FLUSH }));
        else if (enc === 'deflate') stream = res.pipe(zlib.createInflate({ finishFlush: zlib.constants.Z_SYNC_FLUSH }));
        else if (enc === 'br') stream = res.pipe(zlib.createBrotliDecompress({ finishFlush: zlib.constants.BROTLI_OPERATION_FLUSH }));
        const chunks = [];
        let size = 0;
        stream.on('data', (c) => { size += c.length; if (size <= 700 * 1024) chunks.push(c); });
        stream.on('end', () => {
          const buf = Buffer.concat(chunks);
          const ct = String(res.headers['content-type'] || '');
          const m = /charset=([\w-]+)/i.exec(ct);
          const charset = (m ? m[1] : 'utf-8').toLowerCase();
          let text;
          if (/gb/i.test(charset)) {
            try { text = new TextDecoder('gbk').decode(buf); } catch { text = buf.toString('latin1'); }
          } else text = buf.toString('utf8');
          resolve({ ok: sc >= 200 && sc < 400, status: sc, finalUrl: url.toString(), type: ct.split(';')[0], charset, len: size, text });
        });
        stream.on('error', (e) => resolve({ ok: false, stage: 'decode', detail: String(e.message).slice(0, 80), status: sc, finalUrl: url.toString() }));
      });
      req.on('timeout', () => { req.destroy(); resolve({ ok: false, stage: 'timeout', finalUrl: u }); });
      req.on('error', (e) => resolve({ ok: false, stage: e.code || 'error', detail: String(e.message).slice(0, 80), finalUrl: u }));
      req.end();
    };
    go(urlStr);
  });
}

const HIT = [
  ['漫客栈', 'https://www.mkzhan.com/search/?keyword=%E6%B5%B7%E8%B4%BC'],
  ['mhua5', 'https://www.mhua5.com/search/?keyword=%E6%B5%B7%E8%B4%BC'],
  ['极速漫画', 'https://www.1kkk.com/search?title=%E6%B5%B7%E8%B4%BC'],
  ['动漫屋', 'https://www.dm5.com/search?title=%E6%B5%B7%E8%B4%BC'],
  ['cola漫画', 'https://www.colamanga.com/search?keyword=%E6%B5%B7%E8%B4%BC'],
  ['包子漫画', 'https://www.baozimh.com/search?q=%E6%B5%B7%E8%B4%BC'],
  ['baozimh-api', 'https://api-bc.wtako.net/api/v1/comics?q=%E6%B5%B7%E8%B4%BC'],
  ['MangaDex', 'https://api.mangadex.org/manga?limit=3&title=one%20piece&includes[]=cover_art'],
  ['MangaKakalot', 'https://mangakakalot.com/search/story/one_piece'],
  ['MangaHere', 'https://www.mangahere.cc/search.php?name=one%20piece'],
  ['Bato', 'https://bato.to/search?word=one%20piece'],
  ['WeebCentral', 'https://weebcentral.com/search?text=one%20piece'],
  ['快看', 'https://www.kuaikanmanhua.com/search?keyword=%E6%B5%B7%E8%B4%BC'],
  ['腾讯动漫', 'https://ac.qq.com/Comic/searchList/search/%E6%B5%B7%E8%B4%BC'],
];

const only = process.argv[2];
fs.mkdirSync(new URL('./dumps/', import.meta.url), { recursive: true });
const rows = [];
for (const [name, url] of HIT) {
  if (only && !name.includes(only)) continue;
  const r = await fetchFollow(url);
  const title = (r.text || '').match(/<title[^>]*>([\s\S]{0,160}?)<\/title>/i)?.[1]?.replace(/\s+/g, ' ').trim() || '';
  const flag = r.ok ? 'OK  ' : 'FAIL';
  console.log(`${flag} ${name.padEnd(14)} ${String(r.status ?? r.stage).padEnd(7)} ${String(r.len ?? '').padEnd(9)} ${r.charset || ''} ${title.slice(0, 34)}`);
  if (r.finalUrl && r.finalUrl !== url) console.log(`     → ${r.finalUrl}`);
  if (r.detail) console.log(`     ! ${r.detail}`);
  rows.push({ name, url, ...r, text: undefined });
  if (r.text) fs.writeFileSync(new URL(`./dumps/${name}.html`, import.meta.url), r.text, 'utf8');
}
fs.mkdirSync(new URL('./dumps/', import.meta.url), { recursive: true });
for (const r of rows) {
  if (!r.text) continue;
}
