// 站点可达性探测：判断候选漫画站能否从当前网络访问，作为原创图源选型依据。
// 仅做 HTTP 层探测（状态码 / 内容类型 / 页面标题 / 是否被墙或 Cloudflare 拦截）。
import https from 'node:https';
import http from 'node:http';
import { URL } from 'node:url';

const UA = 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

const CANDIDATES = [
  // —— 中文漫画站（网页）——
  ['动漫之家', 'https://www.dmzj.com/'],
  ['动漫之家-api', 'https://api.mangacopy.com/api/v3/search/comic?q=test'],
  ['拷贝漫画', 'https://www.copymanga.tv/'],
  ['拷贝漫画-copy', 'https://api.mangacopy.com/api/v3/comic/search?q=test'],
  ['包子漫画', 'https://cn.baozimh.com/'],
  ['包子漫画-intl', 'https://www.baozimh.com/'],
  ['漫画柜', 'https://www.manhuagui.com/'],
  ['极速漫画', 'https://www.1kkk.com/'],
  ['漫画DB', 'https://www.manhuadb.com/'],
  ['古风漫画', 'https://www.gufengmh.com/'],
  ['动漫屋', 'https://www.dm5.com/'],
  ['漫客栈', 'https://www.mkzhan.com/'],
  ['腾讯动漫', 'https://ac.qq.com/'],
  ['哔哩哔哩漫画', 'https://manga.bilibili.com/'],
  ['快看漫画', 'https://www.kuaikanmanhua.com/'],
  ['177漫画', 'https://www.177pn.com/'],
  ['神漫画', 'https://www.taomanhua.com/'],
  ['好漫8', 'https://www.haoman8.com/'],
  ['cola漫画', 'https://www.colamanga.com/'],
  ['mhua5', 'https://www.mhua5.com/'],
  ['55漫画', 'https://www.55comic.com/'],
  ['亲亲漫画', 'https://www.qinqinmanhua.com/'],
  ['漫画1234', 'https://www.mangacopy.com/'],
  ['zeg漫画', 'https://www.zeg.cz/'],
  ['baozimh-api', 'https://api-bc.wtako.net/api/v1/comics?q=test'],
  // —— 国际 API（有中文章节，稳定性高）——
  ['MangaDex', 'https://api.mangadex.org/manga?limit=1&title=test'],
  ['Comick', 'https://api.comick.fun/v1.0/search?q=test&limit=1'],
  ['MangaKakalot', 'https://mangakakalot.com/search/story/test'],
  ['MangaHere', 'https://www.mangahere.cc/search.php?name=test'],
  ['Bato', 'https://bato.to/search?word=test'],
  ['WeebCentral', 'https://weebcentral.com/search?text=test'],
];

function probe(name, urlStr, timeoutMs = 12000) {
  return new Promise((resolve) => {
    let url;
    try { url = new URL(urlStr); } catch (e) {
      resolve({ name, url: urlStr, ok: false, stage: 'bad-url', detail: String(e.message) });
      return;
    }
    const mod = url.protocol === 'http:' ? http : https;
    const req = mod.request({
      hostname: url.hostname,
      port: url.port || (url.protocol === 'http:' ? 80 : 443),
      path: url.pathname + url.search,
      method: 'GET',
      headers: {
        'User-Agent': UA,
        'Accept': 'text/html,application/json,application/xhtml+xml,*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Accept-Encoding': 'identity',
      },
      timeout: timeoutMs,
      rejectUnauthorized: false,
    }, (res) => {
      const chunks = [];
      let size = 0;
      res.on('data', (c) => {
        size += c.length;
        if (size <= 200 * 1024) chunks.push(c);
      });
      res.on('end', () => {
        const buf = Buffer.concat(chunks);
        let title = '';
        const isUtf8 = !/charset=gb/i.test(String(res.headers['content-type'] || ''));
        const text = isUtf8 ? buf.toString('utf8') : buf.toString('latin1');
        const m = text.match(/<title[^>]*>([\s\S]{0,200}?)<\/title>/i);
        if (m) title = m[1].replace(/\s+/g, ' ').trim();
        const cf = /cloudflare|cf-ray/i.test(JSON.stringify(res.headers)) ||
          /just a moment|checking your browser|cf-browser-verification/i.test(text.slice(0, 4000));
        resolve({
          name, url: urlStr, ok: res.statusCode >= 200 && res.statusCode < 400,
          status: res.statusCode,
          type: String(res.headers['content-type'] || '').split(';')[0],
          len: size, title, cloudflare: cf,
        });
      });
    });
    req.on('timeout', () => { req.destroy(); resolve({ name, url: urlStr, ok: false, stage: 'timeout' }); });
    req.on('error', (e) => resolve({ name, url: urlStr, ok: false, stage: e.code || 'error', detail: String(e.message).slice(0, 80) }));
    req.end();
  });
}

const limit = Number(process.env.PROBE_CONCURRENCY || 8);
const results = [];
let idx = 0;
async function worker() {
  while (idx < CANDIDATES.length) {
    const i = idx++;
    const [name, url] = CANDIDATES[i];
    const r = await probe(name, url);
    results[i] = r;
    const flag = r.ok ? 'OK  ' : (r.cloudflare ? 'CF  ' : 'FAIL');
    console.log(`${flag} ${name.padEnd(16)} ${String(r.status ?? r.stage ?? '').padEnd(7)} ${(r.type || '').padEnd(26)} ${String(r.len ?? '').padEnd(8)} ${r.title ? r.title.slice(0, 40) : (r.detail || '')}`);
  }
}
await Promise.all(Array.from({ length: limit }, worker));

const ok = results.filter((r) => r.ok);
console.log(`\n=== 可达 ${ok.length}/${results.length} ===`);
console.log(ok.map((r) => r.name).join(', '));
const fs = await import('node:fs');
fs.writeFileSync(new URL('./probe-sites.json', import.meta.url), JSON.stringify(results, null, 2));
