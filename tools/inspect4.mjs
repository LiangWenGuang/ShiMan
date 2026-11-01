import { fetchFollow } from './http.mjs';
const TARGETS = [
  ['1070 如漫画', 'http://rumanhua2.com/index.php/search?keyword=' + encodeURIComponent('斗破')],
  ['1075 漫画客', 'https://yumanhua.com/index.php/search?keyword=' + encodeURIComponent('斗破')],
  ['1073 206漫画', 'https://www.m206.com/search?key=' + encodeURIComponent('斗破')],
  ['1081 云漫画', 'https://www.yunmanhua.com/search?key=' + encodeURIComponent('斗破')],
];
for (const [name, url] of TARGETS) {
  const r = await fetchFollow(url, { timeout: 15000 });
  console.log(`\n##### ${name} ${r.status} ${r.len}`);
  const t = r.text || '';
  const hrefs = [...new Set([...t.matchAll(/href="([^"]+)"/g)].map(m => m[1]))]
    .filter(h => /\d/.test(h) && !/\.(css|js|png|jpg|ico)/.test(h));
  const byPrefix = {};
  for (const h of hrefs) {
    const seg = h.split('/').filter(Boolean).slice(0, 2).join('/');
    byPrefix[seg] = (byPrefix[seg] || 0) + 1;
  }
  console.log('路径前缀分布:', Object.entries(byPrefix).sort((a,b)=>b[1]-a[1]).slice(0,6).map(([k,v])=>`${k}(${v})`).join(' '));
  console.log('样例:', hrefs.filter(h=>!/rank|custom|recom|tag|sort/.test(h)).slice(0,8).join('\n        '));
}
