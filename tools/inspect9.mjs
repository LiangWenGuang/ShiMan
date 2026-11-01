import { fetchFollow } from './http.mjs';
import fs from 'node:fs';
const A = await fetchFollow('https://www.mhw1.com/search?key=' + encodeURIComponent('斗破'), { timeout: 20000 });
fs.writeFileSync('dumps/all/yunbei-search.html', A.text || '', 'utf8');
const ta = A.text || '';
const i = ta.indexOf('/index.php/comic/');
console.log('=== 云北搜索结果条目 ===');
console.log(ta.slice(Math.max(0, i - 420), i + 320).replace(/\s+/g, ' '));

const B = await fetchFollow('https://www.m206.com/search?key=' + encodeURIComponent('斗破'), { timeout: 20000 });
fs.writeFileSync('dumps/all/206-search.html', B.text || '', 'utf8');
const tb = B.text || '';
const j = tb.indexOf('comic_70407.html');
console.log('\n=== 206 搜索结果条目 ===');
console.log(tb.slice(Math.max(0, j - 400), j + 260).replace(/\s+/g, ' '));

const d = fs.readFileSync('dumps/all/yunbei-detail.html', 'utf8');
const k = d.indexOf('chapter-item');
console.log('\n=== 云北章节条目 ===');
console.log(d.slice(k, k + 380).replace(/\s+/g, ' '));
