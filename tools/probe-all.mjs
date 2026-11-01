// 逐个探测「数据源配置」里的 32 个漫画源。
// 判定四段链路：首页 → 搜索 → 详情 → 章节页图片。
// 只做只读 GET，不登录、不写任何东西。
import { fetchFollow } from './http.mjs';

// [编号, 名称, 首页]
const SITES = [
  ['1004', '腾讯动漫', 'https://ac.qq.com'],
  ['1005', '哔哩哔哩', 'https://manga.bilibili.com'],
  ['1056', '快看漫画', 'https://www.kuaikanmanhua.com'],
  ['1052', 'SF漫画', 'https://www.sfacg.com'],
  ['1011', '爱优漫', 'https://www.kanman.com'],
  ['1017', '包子漫画', 'https://www.baozimh.com'],
  ['1040', '动漫啦', 'https://www.dongman.la'],
  ['1041', '滴滴漫画', 'http://www.didimh.com'],
  ['1042', '顶漫画', 'https://www.dingmanhua.com'],
  ['1043', '猫咪漫画', 'https://www.sisimanhua.com'],
  ['1046', '云北漫画', 'https://www.mhw1.com'],
  ['1051', '武芊漫画', 'https://comic.mkzcdn.com'],
  ['1053', 'G站漫画', 'https://m.g-mh.org'],
  ['1054', '读漫屋', 'http://dumanwu1.com'],
  ['1069', '晴天漫画', 'https://m.sisimanhua.com'],
  ['1070', '如漫画', 'http://rumanhua2.com'],
  ['1071', '漫画100', 'https://www.manhua100.com'],
  ['1072', '漫画鱼', 'https://www.manhuayu88.com'],
  ['1073', '206漫画', 'https://www.m206.com'],
  ['1075', '漫画客', 'https://yumanhua.com'],
  ['1076', '咚漫', 'https://www.dongmanmanhua.cn'],
  ['1077', '知音漫客', 'https://m.zymk.cn'],
  ['1078', '漫网', 'https://www.manwang.net'],
  ['1079', '豆包漫画', 'https://www.doubaomanhua.com'],
  ['1080', '瓜子漫画', 'https://www.guazimanhua.com'],
  ['1081', '云漫画', 'https://www.yunmanhua.com'],
  ['1082', '小爱漫画', 'https://www.xiaoaimanhua.com'],
  ['1083', '松子漫画', 'https://songzimanhua.com'],
  ['1084', '来漫画吧', 'https://www.laimanhuaba.com'],
  ['1085', '飞翔漫画', 'https://ffppt.com'],
  ['1086', '蜡笔漫画', 'https://www.labimanhua.com'],
  ['1087', '漫画团', 'https://www.manhuatuan.com']
];

const KW = ['keyword', 'q', 'key', 'searchkey', 'k', 'wd', 'word', 'search_key', 'kw'];

function abs(base, href) {
  try {
    return new URL(href, base).toString();
  } catch {
    return '';
  }
}

/** 从首页找搜索表单：action + 参数名 */
function findSearchForm(html, base) {
  const forms = [...html.matchAll(/<form\b[^>]*>/gi)];
  for (const f of forms) {
    const head = f[0];
    const action = (/action\s*=\s*["']([^"']*)["']/i.exec(head) || [])[1] || '';
    const rest = html.slice(f.index + head.length, f.index + head.length + 600);
    const nameMatch = [...rest.matchAll(/<input\b[^>]*name\s*=\s*["']([^"']+)["']/gi)]
      .map((m) => m[1])
      .find((n) => KW.includes(n.toLowerCase()));
    if (nameMatch !== undefined) {
      return { action: abs(base, action || ''), param: nameMatch };
    }
  }
  // 兜底：页面里出现常见猜法路径
  for (const p of ['/search/', '/search', '/s/', '/index.php/search']) {
    if (html.includes(`action="${p}`) || html.includes(`"${p}?"`)) {
      return { action: abs(base, p), param: 'keyword' };
    }
  }
  return null;
}

const DETAIL_RE = /href\s*=\s*["'](\/(?:book|comic|manhua|mh|cartoon|detail|info)\/?[^"'#?]*\d[^"'#?]*\/?)["']/gi;
const CHAPTER_RE = /href\s*=\s*["']([^"']*(?:\/(?:chapter|read|ch)\/?[^"'#]*\d[^"'#]*))["']/gi;
const IMG_RE = /<img\b[^>]*?(?:data-src|data-original|data-echo|src)\s*=\s*["']([^"']+\.(?:jpg|jpeg|png|webp|avif)[^"']*)["']/gi;
const NOISE = /logo|icon|avatar|banner|advert|\/ads?\/|qrcode|loading|placeholder|blank\./i;

function uniq(arr) {
  return [...new Set(arr)];
}

async function probe(site) {
  const [id, name, base] = site;
  const r = { id, name, base };
  const home = await fetchFollow(base, { timeout: 12000 });
  r.homeStatus = home.status || 0;
  r.homeLen = home.len || 0;
  if (!home.ok || !home.text) {
    r.stage = 'home-fail';
    r.detail = home.detail || home.stage || '';
    return r;
  }
  const title = (/<title[^>]*>([\s\S]{0,60}?)<\/title>/i.exec(home.text) || [])[1] || '';
  r.title = title.replace(/\s+/g, ' ').trim();
  r.finalUrl = home.finalUrl || base;

  // 详情链接（首页未必有，先看搜索页）
  const form = findSearchForm(home.text, r.finalUrl);
  r.searchForm = form === null ? '' : `${form.param}`;
  if (form === null) {
    r.stage = 'no-search-form';
    return r;
  }

  const sep = form.action.includes('?') ? '&' : '?';
  const kw = '斗破';
  const searchUrl = `${form.action}${sep}${encodeURIComponent(form.param)}=${encodeURIComponent(kw)}`;
  r.searchUrl = searchUrl;
  const sr = await fetchFollow(searchUrl, { timeout: 15000, headers: { Referer: r.finalUrl } });
  r.searchStatus = sr.status || 0;
  r.searchLen = sr.len || 0;
  if (!sr.ok || !sr.text) {
    r.stage = 'search-fail';
    r.detail = sr.detail || sr.stage || '';
    return r;
  }
  const links = uniq([...sr.text.matchAll(DETAIL_RE)].map((m) => abs(searchUrl, m[1])).filter(Boolean));
  r.searchHits = links.length;
  r.searchHasKw = sr.text.includes(kw);

  if (links.length === 0) {
    r.stage = 'search-empty';
    return r;
  }

  const durl = links[0];
  const dr = await fetchFollow(durl, { timeout: 15000, headers: { Referer: searchUrl } });
  r.detailStatus = dr.status || 0;
  if (!dr.ok || !dr.text) {
    r.stage = 'detail-fail';
    return r;
  }
  const chapters = uniq([...dr.text.matchAll(CHAPTER_RE)].map((m) => abs(durl, m[1])).filter(Boolean));
  r.chapters = chapters.length;
  r.sampleDetail = durl;
  if (chapters.length === 0) {
    r.stage = 'no-chapters';
    return r;
  }

  const curl = chapters[0];
  const cr = await fetchFollow(curl, { timeout: 15000, headers: { Referer: durl } });
  r.chapterStatus = cr.status || 0;
  if (!cr.ok || !cr.text) {
    r.stage = 'chapter-fail';
    return r;
  }
  const imgs = uniq([...cr.text.matchAll(IMG_RE)].map((m) => m[1]).filter((u) => !NOISE.test(u)));
  r.imgs = imgs.length;
  // 图片可能藏在 JS / JSON-LD 里，这里另外统计裸地址出现次数
  const raw = uniq([...cr.text.matchAll(/https?:\/\/[^"'\s\\<>()]+\.(?:jpg|jpeg|png|webp)/gi)].map((m) => m[0]));
  r.rawImgs = raw.filter((u) => !NOISE.test(u)).length;
  r.sampleChapter = curl;
  r.sampleImg = (imgs[0] || raw[0] || '').slice(0, 90);
  r.stage = imgs.length >= 3 ? 'OK-html' : (r.rawImgs >= 3 ? 'js-only' : 'no-image');
  return r;
}

async function pool(items, limit, worker) {
  const out = [];
  let cursor = 0;
  const runners = new Array(Math.min(limit, items.length)).fill(0).map(async () => {
    while (cursor < items.length) {
      const i = cursor++;
      try {
        out[i] = await worker(items[i]);
      } catch (e) {
        out[i] = { id: items[i][0], name: items[i][1], base: items[i][2], stage: 'error', detail: String(e).slice(0, 80) };
      }
    }
  });
  await Promise.all(runners);
  return out;
}

const rows = await pool(SITES, 5, probe);
rows.sort((a, b) => String(a.id).localeCompare(String(b.id)));

console.log('编号 | 名称 | 首页 | 搜索 | 详情 | 章节 | 图片 | 结论');
console.log('---|---|---|---|---|---|---|---');
for (const r of rows) {
  const cell = (v) => (v === undefined || v === null ? '-' : String(v));
  console.log([
    r.id, r.name,
    `${cell(r.homeStatus)}/${Math.round((r.homeLen || 0) / 1024)}K`,
    r.searchForm ? `${r.searchForm}:${cell(r.searchHits)}` : '-',
    cell(r.chapters),
    cell(r.chapterStatus),
    `${cell(r.imgs)}/${cell(r.rawImgs)}`,
    r.stage
  ].join(' | '));
}

const ok = rows.filter((r) => r.stage === 'OK-html');
const js = rows.filter((r) => r.stage === 'js-only');
console.log('\n=== 汇总 ===');
console.log('可直接出图:', ok.map((r) => `${r.name}(${r.id})`).join(', ') || '无');
console.log('图在 JS 里:', js.map((r) => `${r.name}(${r.id})`).join(', ') || '无');
console.log('失败原因分布:');
const byStage = {};
for (const r of rows) byStage[r.stage] = (byStage[r.stage] || 0) + 1;
console.log(byStage);

await import('node:fs').then((fs) => fs.writeFileSync('probe-all.json', JSON.stringify(rows, null, 2)));
console.log('\n详细结果写入 tools/probe-all.json');
