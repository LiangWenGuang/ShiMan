import fs from 'node:fs';
const t = fs.readFileSync('F:/AI/QoderCN-Data/output/harmony-comic-origin/tools/dumps/detail/腾讯-斗破.html', 'utf8');

const acimg = [...t.matchAll(/https:\/\/manhua\.acimg\.cn\/[^"'\s\\)]+/g)];
console.log('acimg 出现次数:', acimg.length);
for (const m of acimg.slice(0, 5)) {
  console.log('\n>>> ' + m[0].slice(0, 90));
  console.log('    ' + t.slice(Math.max(0, m.index - 300), m.index + 80).replace(/\s+/g, ' '));
}

const bg = [...t.matchAll(/background-image\s*:\s*url\(([^)]+)\)/g)];
console.log('\nbackground-image 次数:', bg.length);
for (const m of bg.slice(0, 4)) {
  console.log('  ' + m[1].slice(0, 90));
}
