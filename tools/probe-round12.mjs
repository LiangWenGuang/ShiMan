// 最后一次侦察：猜测包子/G站 CDN 直连图片路径。
import { fetchFollow } from './http.mjs';

const SLUG = 'manjiwanjiadedi100cihuigui';
const CH = '29437-038792390-1';
const HOSTS = ['https://c-nc-1.6wm.top', 'https://c-nd2-1.6wm.top', 'https://c-nd3-1.6wm.top'];

const PATTERNS = [
  `/manga/${SLUG}/${CH}/1.webp`,
  `/manga/${SLUG}/${CH}/001.webp`,
  `/manga/${SLUG}/${CH}/1.jpg`,
  `/manga/${SLUG}/${CH}/001.jpg`,
  `/manga/${SLUG}/${CH}/1.png`,
  `/manga/${CH}/1.webp`,
  `/manga/${CH}/001.webp`,
];

for (const h of HOSTS.slice(0, 1)) {
  for (const p of PATTERNS) {
    const r = await fetchFollow(h + p, { timeout: 12000 });
    console.log(`${r.status ?? r.stage}`.padEnd(6), String(r.len ?? '').padEnd(8), r.type || '', h + p);
  }
}

// 也试 m.bzmh.org 其它入口
for (const u of [
  `https://m.bzmh.org/go?token=8bbfbfa2bfacd82ccb532b&ms=29437&cs=${CH}&host=${encodeURIComponent('https://v2.apikk.top')}`,
  `https://v2.apikk.top/api/manga/chapter?mid=29437&chapter_slug=${CH}`,
  `https://v2.apikk.top/api/manga/getChapter?mid=29437&cs=${CH}`,
]) {
  const r = await fetchFollow(u, { timeout: 15000 });
  console.log(`${r.status ?? r.stage}`.padEnd(6), String(r.len ?? '').padEnd(8), (r.type || '').padEnd(16), u.slice(0, 80), (r.text || '').slice(0, 80).replace(/\s+/g, ' '));
}
