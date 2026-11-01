import fs from 'node:fs';
const base = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/tools/dumps/szz/';

function show(file, marker, before = 400, after = 400) {
  const t = fs.readFileSync(base + file, 'utf8');
  const i = t.indexOf(marker);
  console.log(`\n===== ${file} @ "${marker}" =====`);
  if (i < 0) { console.log('未找到'); return; }
  console.log(t.slice(Math.max(0, i - before), i + after).replace(/\s+/g, ' '));
}

// 1) 章节页：正文图片容器
show('read.html', '19_1.webp', 500, 300);

// 2) 搜索页：结果条目
const s = fs.readFileSync(base + 'search.html', 'utf8');
const m = s.match(/<a[^>]+href="\/book\/\d+\/"[^>]*>[\s\S]{0,400}?<\/a>/);
console.log('\n===== search.html 首个结果条目 =====');
console.log(m ? m[0].replace(/\s+/g, ' ') : '未匹配');

// 3) 详情页：标题/作者/封面/简介
show('detail.html', 'og:title', 0, 200);
const d = fs.readFileSync(base + 'detail.html', 'utf8');
for (const kw of ['detail-title', 'detail-author', 'detail-cover', 'detail-desc', 'detail-meta']) {
  const i = d.indexOf(kw);
  if (i >= 0) {
    console.log(`\n[${kw}] ` + d.slice(Math.max(0, i - 150), i + 300).replace(/\s+/g, ' '));
  }
}
