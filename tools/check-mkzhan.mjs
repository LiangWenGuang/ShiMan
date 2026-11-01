import fs from 'node:fs';
import path from 'node:path';

const base = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/tools/dumps';
const s = fs.readFileSync(path.join(base, '漫客栈-斗破.txt'), 'utf8');
const d = fs.readFileSync(path.join(base, 'detail/漫客栈-217087.html'), 'utf8');

const checks = [
  ['搜索容器 .search-comic-list', /class="[^"]*search-comic-list/.test(s)],
  ['条目 .common-comic-item 数量', (s.match(/common-comic-item/g) || []).length],
  ['条目内 .comic__title a', /class="comic__title">\s*<a href="[^"]+">[^<]+<\/a>/.test(s)],
  ['条目内 a.cover[href]', /<a class="cover" href="\/\d+\/"/.test(s)],
  ['封面 img.lazy[data-src]', /class="lazy" data-src="https:\/\/oss\.mkzcdn\.com/.test(s)],
  ['详情 p.comic-title', /<p class="comic-title j-comic-title">[^<]+<\/p>/.test(d)],
  ['详情 .de-info__cover img[data-src]', /class="de-info__cover"><img class="lazy"[^>]*data-src="([^"]+)"/.test(d)],
  ['详情 .comic-author .name', /class="comic-author">[\s\S]{0,400}?class="name"/.test(d)],
  ['详情 .comic-intro', /class="comic-intro"/.test(d)],
  ['详情 .comic-status', /class="comic-status"/.test(d)],
  ['章节 a.j-chapter-link 数量', (d.match(/class="j-chapter-link"/g) || []).length]
];

for (const [name, value] of checks) {
  console.log(String(value).padEnd(6), name);
}

const m = d.match(/class="j-chapter-link" data-hreflink="([^"]+)" data-chapterid="(\d+)"/);
console.log('样例章节:', m ? [m[1], m[2]] : 'NOT FOUND');
