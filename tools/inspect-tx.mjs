import fs from 'node:fs';
process.chdir(new URL('./dumps/chapter/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));

const t = fs.readFileSync('腾讯.html', 'utf8');
const re = /https:\/\/manhua\.acimg\.cn\/[^"'\s\\)]+/g;
const all = t.match(re) || [];
const uniq = [...new Set(all)];
console.log('acimg 出现次数:', all.length, ' 去重:', uniq.length);
console.log(uniq.slice(0, 8).join('\n'));

const i = t.indexOf('manhua.acimg.cn');
console.log('\n--- 上下文 ---');
console.log(t.slice(Math.max(0, i - 700), i + 400));
