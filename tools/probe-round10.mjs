// 第十轮：包子/G站 后端接口全链路验证（章节列表 + 章节图片）。
import { fetchFollow } from './http.mjs';

const SLUG = 'manjiwanjiadedi100cihuigui';

const ch = await fetchFollow(`https://v2.apikk.top/api/manga/get?mid=${SLUG}&mode=all`, {
  headers: { Referer: 'https://baozimh.org/', Origin: 'https://baozimh.org' },
  timeout: 20000,
});
console.log(`[章节列表] ${ch.status} ${ch.len} ${ch.type}`);
console.log((ch.text || '').slice(0, 700));

let firstChapterId = null;
try {
  const j = JSON.parse(ch.text);
  const arr = j?.data?.chapters ?? j?.data?.allchapters ?? j?.data ?? j?.chapters;
  const list = Array.isArray(arr) ? arr : (arr?.chapters ?? []);
  if (Array.isArray(list) && list.length) {
    firstChapterId = list[0]?.id ?? list[0]?.chapter_id ?? list[0]?.cid;
    console.log('\n章节样例:', JSON.stringify(list[0]).slice(0, 300));
    console.log('章节数:', list.length, ' firstId:', firstChapterId);
  } else {
    console.log('\nJSON 结构:', Object.keys(j || {}), 'data keys:', Object.keys(j?.data || {}));
  }
} catch (e) {
  console.log('解析失败', e.message);
}

// 找章节图片接口
const g = await fetchFollow('https://baozimh.org/_astro/getChapter.BfDB3pMV.js', { timeout: 20000 });
const s = g.text || '';
console.log('\n[getChapter.js] len=' + s.length);
const urls = [...new Set([...s.matchAll(/https?:\/\/[^"'`\s]+/g)].map((m) => m[0]))];
console.log('URL:', urls.slice(0, 12).join('\n     '));

if (firstChapterId) {
  for (const u of [
    `https://v2.apikk.top/api/manga/chapter?chapter_id=${firstChapterId}`,
    `https://v2.apikk.top/api/chapter/get?chapter_id=${firstChapterId}`,
    `https://v2.apikk.top/api/manga/chapter?id=${firstChapterId}`,
  ]) {
    const r = await fetchFollow(u, { headers: { Referer: 'https://baozimh.org/' }, timeout: 15000 });
    console.log(`\n${u}\n  → ${r.status} ${r.len} ${(r.text || '').slice(0, 300)}`);
  }
}
