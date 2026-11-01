// 第二轮：对「没识别出搜索表单」的站点，用候选地址矩阵逐个试。
// 命中判据：页面含关键词 + 至少 1 条疑似详情链接。命中后继续跑详情→章节→图片。
import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

const SITES = [
  ['1004', '腾讯动漫', 'https://ac.qq.com'],
  ['1005', '哔哩哔哩', 'https://manga.bilibili.com'],
  ['1056', '快看漫画', 'https://www.kuaikanmanhua.com'],
  ['1052', 'SF漫画', 'https://www.sfacg.com'],
  ['1011', '爱优漫', 'https://www.kanman.com'],
  ['1041', '滴滴漫画', 'http://www.didimh.com'],
  ['1046', '云北漫画', 'https://www.mhw1.com'],
  ['1051', '武芊漫画', 'https://comic.mkzcdn.com'],
  ['1054', '读漫屋', 'http://dumanwu1.com'],
  ['1070', '如漫画', 'http://rumanhua2.com'],
  ['1073', '206漫画', 'https://www.m206.com'],
  ['1075', '漫画客', 'https://yumanhua.com'],
  ['1076', '咚漫', 'https://www.dongmanmanhua.cn'],
  ['1077', '知音漫客', 'https://m.zymk.cn'],
  ['1081', '云漫画', 'https://www.yunmanhua.com'],
  ['1084', '来漫画吧', 'https://www.laimanhuaba.com'],
  ['1085', '飞翔漫画', 'https://ffppt.com']
];

const KW = '斗破';

/** 候选搜索地址模板，按可能性排序 */
function candidates(base) {
  const b = base.replace(/\/$/, '');
  const k = encodeURIComponent(KW);
  return [
    `${b}/search?keyword=${k}`,
    `${b}/search/?keyword=${k}`,
    `${b}/search?key=${k}`,
    `${b}/search/?key=${k}`,
    `${b}/search?q=${k}`,
    `${b}/search/?q=${k}`,
    `${b}/search?searchkey=${k}`,
    `${b}/search?word=${k}`,
    `${b}/search/${k}`,
    `${b}/search/${k}/`,
    `${b}/s?q=${k}`,
    `${b}/search?k=${k}`,
    `${b}/index.php/search?keyword=${k}`,
    `${b}/e/search/index.php?keyboard=${k}&show=title`,
    // 腾讯动漫自己的一套
    `${b}/Comic/searchList/search/${k}`,
    // 快看
    `${b}/search?word=${k}`
  ];
}

const NOISE = /logo|icon|avatar|banner|advert|\/ads?\/|qrcode|placeholder|loading|blank\.|\.(css|js)(\?|$)/i;
const CHAPTER_RE = /href\s*=\s*["']([^"']*(?:\/(?:chapter|read|ch|episode)[^"'#]*\d[^"'#]*))["']/gi;
const IMG_RE = /<img\b[^>]*?(?:data-src|data-original|data-echo|src)\s*=\s*["']([^"']+\.(?:jpg|jpeg|png|webp|avif)[^"']*)["']/gi;

function abs(base, href) {
  try { return new URL(href, base).toString(); } catch { return ''; }
}
function uniq(a) { return [...new Set(a)]; }

/** 从结果页里挑详情链接：同一站内、带数字、非资源、非首页 */
function pickDetailLinks(html, pageUrl) {
  const origin = new URL(pageUrl).origin;
  const hrefs = uniq([...html.matchAll(/href\s*=\s*["']([^"']+)["']/gi)].map((m) => abs(pageUrl, m[1])));
  const good = hrefs.filter((u) => {
    if (!u.startsWith(origin)) return false;
    if (NOISE.test(u)) return false;
    if (!/\d/.test(u)) return false;
    if (u.replace(origin, '') === '' || u.replace(origin, '') === '/') return false;
    return true;
  });
  // 按路径深度归类，取数量最多的那一类的前几条
  const byPrefix = {};
  for (const u of good) {
    const seg = u.replace(origin, '').split('/').filter(Boolean)[0] || '';
    byPrefix[seg] = (byPrefix[seg] || 0) + 1;
  }
  const best = Object.entries(byPrefix).sort((a, b) => b[1] - a[1])[0];
  if (!best) return [];
  return good.filter((u) => (u.replace(origin, '').split('/').filter(Boolean)[0] || '') === best[0]);
}

async function probe(site) {
  const [id, name, base] = site;
  const out = { id, name, base, tried: [] };
  for (const url of candidates(base)) {
    const r = await fetchFollow(url, { timeout: 10000 });
    if (!r.ok || !r.text) { out.tried.push(`${url.slice(base.length)}:${r.status || 0}`); continue; }
    const hasKw = r.text.includes(KW);
    const links = hasKw ? pickDetailLinks(r.text, url) : [];
    out.tried.push(`${url.slice(base.length)}:${r.status}${hasKw ? '+' : '-'}${links.length}`);
    if (!hasKw || links.length === 0) continue;

    out.searchUrl = url;
    out.searchHits = links.length;
    const durl = links[0];
    out.sampleDetail = durl;
    const dr = await fetchFollow(durl, { timeout: 12000, headers: { Referer: url } });
    out.detailStatus = dr.status || 0;
    if (!dr.ok || !dr.text) { out.stage = 'detail-fail'; return out; }
    const chapters = uniq([...dr.text.matchAll(CHAPTER_RE)].map((m) => abs(durl, m[1])));
    out.chapters = chapters.length;
    if (chapters.length === 0) { out.stage = 'no-chapters'; return out; }

    const cr = await fetchFollow(chapters[0], { timeout: 12000, headers: { Referer: durl } });
    out.chapterStatus = cr.status || 0;
    if (!cr.ok || !cr.text) { out.stage = 'chapter-fail'; return out; }
    const imgs = uniq([...cr.text.matchAll(IMG_RE)].map((m) => m[1]).filter((u) => !NOISE.test(u)));
    const raw = uniq([...cr.text.matchAll(/https?:\/\/[^"'\s\\<>()]+\.(?:jpg|jpeg|png|webp)/gi)].map((m) => m[0]))
      .filter((u) => !NOISE.test(u));
    out.imgs = imgs.length;
    out.rawImgs = raw.length;
    out.sampleChapter = chapters[0];
    out.sampleImg = (imgs[0] || raw[0] || '').slice(0, 100);
    out.stage = imgs.length >= 3 ? 'OK-html' : (raw.length >= 3 ? 'js-only' : 'no-image');
    return out;
  }
  out.stage = 'search-not-found';
  return out;
}

async function pool(items, limit, worker) {
  const out = [];
  let cursor = 0;
  await Promise.all(new Array(Math.min(limit, items.length)).fill(0).map(async () => {
    while (cursor < items.length) {
      const i = cursor++;
      try { out[i] = await worker(items[i]); } catch (e) {
        out[i] = { id: items[i][0], name: items[i][1], base: items[i][2], stage: 'error', tried: [String(e).slice(0, 60)] };
      }
    }
  }));
  return out;
}

const rows = await pool(SITES, 4, probe);
for (const r of rows) {
  console.log(`\n${r.id} ${r.name} → ${r.stage}`);
  console.log('  试过:', r.tried.join(' | ').slice(0, 400));
  if (r.searchUrl) console.log('  命中:', r.searchUrl, '条数', r.searchHits, '章节', r.chapters, '图', r.imgs, '/', r.rawImgs);
  if (r.sampleImg) console.log('  样图:', r.sampleImg);
  if (r.sampleDetail) console.log('  样例:', r.sampleDetail);
}
fs.writeFileSync('probe-search2.json', JSON.stringify(rows, null, 2));
console.log('\n写入 probe-search2.json');
