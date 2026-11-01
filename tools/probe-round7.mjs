// 第七轮：包子漫画 / G站 章节与图片链路；漫客栈 httpApi 接口常量。
import { fetchFollow } from './http.mjs';
import fs from 'node:fs';

fs.mkdirSync(new URL('./dumps/r7/', import.meta.url), { recursive: true });
const IMG_RE = /(?:https?:)?\/\/[^"'\s\\)]+\.(?:jpg|jpeg|png|webp)[^"'\s\\)]*/gi;

function showImgs(tag, html) {
  const all = [...new Set(html.match(IMG_RE) || [])];
  const good = all.filter((u) => !/logo|icon|avatar|favicon|banner|placeholder|sprite|apple-touch/i.test(u));
  console.log(`  ${tag}: img uniq=${all.length} good=${good.length}`);
  console.log('    ' + good.slice(0, 6).join('\n    '));
}

// 1) 包子漫画章节列表
const cl = await fetchFollow('https://baozimh.org/chapterlist/manjiwanjiadedi100cihuigui', { timeout: 20000 });
console.log(`\n##### 包子-chapterlist ${cl.status} ${cl.len}`);
if (cl.text) {
  fs.writeFileSync(new URL('./dumps/r7/baozimh-chapterlist.html', import.meta.url), cl.text, 'utf8');
  const links = [...new Set([...cl.text.matchAll(/href="([^"]{2,120})"/g)].map((m) => m[1]))];
  console.log('  chapter links: ' + links.filter((h) => /chapter|view|\/c\//i.test(h)).slice(0, 8).join(' | '));
  showImgs('imgs', cl.text);
}

// 2) G站 取首页一个漫画，进详情
const home = await fetchFollow('https://godamh.com/', { timeout: 20000 });
if (home.text) {
  const hrefs = [...new Set([...home.text.matchAll(/href="(\/manga\/[^"]+)"/g)].map((m) => m[1]))];
  console.log('\n##### G站 manga href 样例: ' + hrefs.slice(0, 5).join(' | '));
  if (hrefs.length) {
    const d = await fetchFollow('https://godamh.com' + hrefs[0], { timeout: 20000 });
    console.log(`  detail ${d.status} ${d.len}`);
    if (d.text) {
      fs.writeFileSync(new URL('./dumps/r7/godamh-detail.html', import.meta.url), d.text, 'utf8');
      const ls = [...new Set([...d.text.matchAll(/href="([^"]{2,120})"/g)].map((m) => m[1]))];
      console.log('  章节链接: ' + ls.filter((h) => /chapter|view/i.test(h)).slice(0, 8).join(' | '));
      showImgs('detail imgs', d.text);
    }
  }
}

// 3) 漫客栈 httpApi 常量
const api = await fetchFollow('https://static.mkzcdn.com/home/assets/script/modules/httpApi/httpApi.js?v=d8dabac6');
const s = api.text || '';
console.log('\n##### mkzhan httpApi.js len=' + s.length);
const paths = [...new Set([...s.matchAll(/["']([\/][a-zA-Z0-9_\/{}$:-]{3,60})["']/g)].map((m) => m[1]))];
console.log('  接口路径: ' + paths.slice(0, 30).join(' | '));
