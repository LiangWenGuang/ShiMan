// 第九轮：哔哩哔哩漫画 API（带 cookie 引导）+ 包子漫画前端接口定位。
import { fetchFollow, DEFAULT_UA } from './http.mjs';

// --- 1) 哔哩哔哩漫画：先拿 cookie，再调 twirp 接口 ---
const home = await fetchFollow('https://manga.bilibili.com/', { timeout: 20000 });
const rawCookie = (home.headers?.['set-cookie'] || []).map((c) => c.split(';')[0]).join('; ');
console.log('bili cookie:', rawCookie.slice(0, 120) || '(none)');

async function twirp(path, body) {
  const r = await fetchFollow(`https://manga.bilibili.com/twirp/comic.v1.Comic/${path}?device=pc&platform=web`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Referer': 'https://manga.bilibili.com/',
      'Origin': 'https://manga.bilibili.com',
      'Cookie': rawCookie,
    },
    body: JSON.stringify(body),
    timeout: 20000,
  });
  return { status: r.status, len: r.len, text: (r.text || '').slice(0, 400) };
}

console.log('\n[Search]', JSON.stringify(await twirp('Search', { keyword: '斗破', page_num: 1, page_size: 6 })));
console.log('[Search2]', JSON.stringify(await twirp('Search', { key_word: '斗破', page_num: 1, page_size: 6 })));

// --- 2) 包子漫画前端接口 ---
const js = await fetchFollow('https://baozimh.org/_astro/_mangaslug_.astro_astro_type_script_index_0_lang.Dll3CkV5.js', { timeout: 20000 });
const s = js.text || '';
console.log('\n包子 js len=' + s.length);
const fetches = [...new Set([...s.matchAll(/["'`]([^"'`]{0,120}(?:api|fetch|chapter)[^"'`]{0,80})["'`]/gi)].map((m) => m[1]))];
console.log('候选:', fetches.slice(0, 15).join('\n       '));

for (const p of ['/api/manga/manjiwanjiadedi100cihuigui/chapters', '/api/chapters/manjiwanjiadedi100cihuigui']) {
  const r = await fetchFollow('https://baozimh.org' + p, { timeout: 15000 });
  console.log(`包子 ${p} → ${r.status} ${r.len} ${(r.type || '')} ${(r.text || '').slice(0, 160)}`);
}
