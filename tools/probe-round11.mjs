// 第十一轮（最后一轮侦察）：包子/G站 用数字 mid 打通章节与图片。
import { fetchFollow } from './http.mjs';

const MID = 29437;

const ch = await fetchFollow(`https://v2.apikk.top/api/manga/get?mid=${MID}&mode=all`, {
  headers: { Referer: 'https://baozimh.org/' }, timeout: 20000,
});
console.log(`[章节] ${ch.status} ${ch.len}`);
console.log((ch.text || '').slice(0, 500));

let first = null;
try {
  const j = JSON.parse(ch.text);
  const d = j?.data ?? j;
  const arr = d?.chapters ?? d?.allchapters ?? d?.groups?.[0]?.chapters ?? [];
  console.log('\ndata keys:', Object.keys(d || {}));
  if (Array.isArray(arr) && arr.length) {
    first = arr[0];
    console.log('章节样例:', JSON.stringify(first));
    console.log('章节数:', arr.length);
  }
} catch (e) { console.log('parse fail', e.message); }

const g = await fetchFollow('https://baozimh.org/_astro/getChapter.BfDB3pMV.js', { timeout: 20000 });
const s = g.text || '';
const tpl = s.slice(Math.max(0, s.indexOf('m.bzmh.org') - 900), s.indexOf('m.bzmh.org') + 500);
console.log('\n[图片URL构造]\n' + tpl);

// 搜索页形态
for (const u of ['https://baozimh.org/search?keyword=%E6%96%97%E7%A0%B4', 'https://baozimh.org/search?q=%E6%96%97%E7%A0%B4', 'https://baozimh.org/manga?q=%E6%96%97%E7%A0%B4']) {
  const r = await fetchFollow(u, { timeout: 15000 });
  console.log(`\n${u} → ${r.status} ${r.len} final=${r.finalUrl}`);
  if (r.text) {
    const hits = (r.text.match(/\/manga\/[a-z0-9-]+/g) || []).length;
    console.log('  /manga/ 链接数:', new Set(r.text.match(/\/manga\/[a-z0-9-]+/g) || []).size);
  }
}
