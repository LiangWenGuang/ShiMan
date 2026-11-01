// 批量探测 Mycomic 源清单：对每个站点跑 首页 → 详情 → 章节 → 图片 四段，
// 重点判断「章节页正文图片是否在 HTML 里」（这决定了能不能做成纯 HTTP 图源）。
import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

const HOSTS = [
  ['漫蛙', 'https://www.simanhua.com'],
  ['古风漫画', 'https://www.gufengmh.com'],
  ['小爱漫画', 'https://www.xiaoaomanhua.com'],
  ['松子漫画', 'https://www.songzimanhua.com'],
  ['哇哇漫画', 'https://www.lailaimanhua.com'],
  ['雌龙漫画', 'https://www.labmanhua.com'],
  ['漫番团', 'https://www.manhuafan.com'],
  ['漫画屋(gzh)', 'https://www.gaozihumanhua.com'],
  ['网漫', 'https://www.manhuaren8.com'],
  ['206漫画', 'https://www.mc36.com'],
  ['动漫画', 'https://www.dongman.la'],
  ['dmshbh', 'https://www.dmshbh.com'],
  ['爱优漫', 'https://www.kaiman.com'],
  ['SF漫画', 'https://www.sfacg.com'],
  ['包子漫画', 'https://www.baozimh.com'],
  ['书海阁', 'https://www.shubaoge.com'],
  ['古风备用', 'https://www.gufengmh8.com'],
];

const IMG_RE = /(?:https?:)?\/\/[^"'\s\\)]+\.(?:jpg|jpeg|png|webp)[^"'\s\\)]*/gi;

function detailLinks(html, host) {
  const out = [];
  const re = /<a[^>]+href="([^"]{2,120})"[^>]*>([\s\S]{0,40}?)<\/a>/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    const href = m[1];
    if (/login|register|search|tag|author|user|javascript|css|js|#/.test(href)) continue;
    if (!/\d/.test(href)) continue;
    out.push(href);
    if (out.length >= 5) break;
  }
  return out;
}

function chapterLinks(html) {
  const out = [];
  const re = /<a[^>]+href="([^"]{2,120})"/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    const href = m[1];
    if (/chapter|\/ch\d|\/m\d+|\.html?$/i.test(href) && /\d/.test(href)) {
      if (!/login|register|search|tag|author/.test(href)) out.push(href);
    }
    if (out.length >= 8) break;
  }
  return out;
}

function absolute(host, href) {
  if (/^https?:\/\//.test(href)) return href;
  if (href.startsWith('//')) return 'https:' + href;
  if (href.startsWith('/')) return host + href;
  return host + '/' + href;
}

const results = [];
const limit = 4;
let cursor = 0;

async function worker() {
  while (cursor < HOSTS.length) {
    const [name, host] = HOSTS[cursor++];
    const row = { name, host, home: 0, detail: 0, chapter: 0, imgs: 0, inlineArray: '', status: '' };
    try {
      const home = await fetchFollow(host, { timeout: 15000 });
      row.home = home.status || 0;
      if (!home.ok || !home.text) {
        row.status = '不可达 ' + (home.stage || home.status);
        results.push(row);
        console.log(`${name.padEnd(14)} ${row.status}`);
        continue;
      }
      const links = detailLinks(home.text, host);
      if (links.length === 0) {
        row.status = '首页无可识别详情链接';
        results.push(row);
        console.log(`${name.padEnd(14)} ${row.status}  (len=${home.len})`);
        continue;
      }
      const detailUrl = absolute(host, links[0]);
      const detail = await fetchFollow(detailUrl, { timeout: 15000 });
      row.detail = detail.status || 0;
      if (!detail.ok || !detail.text) {
        row.status = '详情失败 ' + (detail.stage || detail.status);
        results.push(row);
        console.log(`${name.padEnd(14)} ${row.status}`);
        continue;
      }
      const chs = chapterLinks(detail.text);
      if (chs.length === 0) {
        row.status = '详情页无章节链接';
        results.push(row);
        console.log(`${name.padEnd(14)} ${row.status}  (len=${detail.len})`);
        continue;
      }
      const chUrl = absolute(detailUrl, chs[Math.min(1, chs.length - 1)]);
      const ch = await fetchFollow(chUrl, { timeout: 15000 });
      row.chapter = ch.status || 0;
      const html = ch.text || '';
      const all = [...new Set(html.match(IMG_RE) || [])];
      const good = all.filter((u) => !/logo|icon|avatar|favicon|banner|placeholder|sprite|loading|ads?/i.test(u));
      row.imgs = good.length;
      if (/chapterImages|chapter_images|var\s+images|IMAGE_ARR|imgData/i.test(html)) row.inlineArray = '有JS数组';
      row.status = good.length >= 3 ? '★ 图片在HTML里' : (row.inlineArray ? 'JS数组（可正则）' : '图片不在HTML');
      results.push(row);
      console.log(`${name.padEnd(14)} home=${row.home} ch=${row.chapter} imgs=${String(row.imgs).padStart(3)}  ${row.inlineArray.padEnd(10)} ${row.status}`);
    } catch (e) {
      row.status = '异常 ' + e.message.slice(0, 40);
      results.push(row);
      console.log(`${name.padEnd(14)} ${row.status}`);
    }
  }
}

await Promise.all(Array.from({ length: limit }, worker));
fs.writeFileSync(new URL('./probe-more.json', import.meta.url), JSON.stringify(results, null, 2));
const good = results.filter((r) => r.status.startsWith('★') || r.inlineArray);
console.log('\n===== 可用/可救 ' + good.length + ' / ' + results.length + ' =====');
for (const g of good) console.log('  ' + g.name + '  ' + g.host + '  ' + g.status);
