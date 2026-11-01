// 验证图片 CDN 是否支持 HTTPS（鸿蒙默认拦截明文 HTTP，需要能升级就升级）
import { fetchFollow } from './http.mjs';

const api = 'https://comic.mkzcdn.com/chapter/content/v1/?chapter_id=1069798&comic_id=217087&quality=1&type=1&format=0';
const r = await fetchFollow(api, { headers: { Referer: 'https://www.mkzhan.com/217087/1069798.html' } });
const body = r.text || '';
const urls = [...body.matchAll(/"image":"([^"]+)"/g)].map((m) => m[1].replace(/\\\//g, '/'));
console.log('图片数:', urls.length);

for (const u of urls.slice(0, 3)) {
  const https = u.replace(/^http:\/\//, 'https://');
  const a = await fetchFollow(u, { headers: { Referer: 'https://www.mkzhan.com/' } });
  const b = await fetchFollow(https, { headers: { Referer: 'https://www.mkzhan.com/' } });
  console.log(`http  ${a.status} ${a.type} ${a.len}`);
  console.log(`https ${b.status} ${b.type} ${b.len}`);
  console.log('   ', u.slice(0, 80));
}
