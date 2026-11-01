// 第八轮：桌面 UA 下章节页是否直出图片；并尝试常见图片接口。
import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

const DESKTOP = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const IMG_RE = /(?:https?:)?\/\/[^"'\s\\)]+\.(?:jpg|jpeg|png|webp)[^"'\s\\)]*/gi;

fs.mkdirSync(new URL('./dumps/r8/', import.meta.url), { recursive: true });

const T = [
  ['dm5桌面', 'https://www.dm5.com/m1722522/', DESKTOP],
  ['1kkk桌面', 'https://www.1kkk.com/ch1-6-1722522/', DESKTOP],
  ['腾讯桌面', 'https://ac.qq.com/ComicView/chapter/id/531040/cid/1', DESKTOP],
  ['腾讯API', 'https://m.ac.qq.com/chapter/get_chapter_info?id=531040&cid=1', DESKTOP],
  ['腾讯API2', 'https://ac.qq.com/ComicView/chapter/id/531040/cid/1?from=pc', DESKTOP],
];

for (const [name, url, ua] of T) {
  const r = await fetchFollow(url, { ua, timeout: 20000 });
  const html = r.text || '';
  const all = [...new Set(html.match(IMG_RE) || [])];
  const good = all.filter((u) => !/logo|icon|avatar|favicon|banner|placeholder|sprite|css99tel|apple-touch/i.test(u));
  console.log(`\n##### ${name} ${r.status ?? r.stage} ${r.len ?? ''}  uniq=${all.length} good=${good.length}`);
  if (r.finalUrl && r.finalUrl !== url) console.log('  → ' + r.finalUrl);
  if (good.length) {
    console.log('  ' + good.slice(0, 8).join('\n  '));
    fs.writeFileSync(new URL(`./dumps/r8/${name}.html`, import.meta.url), html, 'utf8');
  }
  // 桌面页常见变量
  const v = html.match(/(?:var\s+)?(?:CHAPTER_IMAGES|chapterImages|arrImages|imgData|page_list|pages)\s*=\s*([\[{][\s\S]{0,600})/);
  if (v) console.log('  变量: ' + v[1].replace(/\s+/g, ' ').slice(0, 320));
}
