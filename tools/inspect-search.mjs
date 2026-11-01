import fs from 'node:fs';
const ids = process.argv.slice(2);
for (const id of ids) {
  const p = `dumps/all/${id}.html`;
  if (!fs.existsSync(p)) { console.log(`### ${id} 无文件`); continue; }
  const t = fs.readFileSync(p, 'utf8');
  console.log(`\n########## ${id}`);
  // 1) 表单
  for (const m of t.matchAll(/<form\b[^>]*>[\s\S]{0,400}?<\/form>/gi)) {
    if (/search/i.test(m[0])) console.log('[FORM]', m[0].replace(/\s+/g, ' ').slice(0, 300));
  }
  // 2) JS 里拼搜索地址
  let n = 0;
  for (const m of t.matchAll(/(?:location\.href|window\.open|action|url)\s*[=:]\s*["'][^"']*search[^"']*["']/gi)) {
    console.log('[JS]', m[0].replace(/\s+/g, ' ').slice(0, 200)); if (++n >= 5) break;
  }
  // 3) 搜索框附近的 data-*
  n = 0;
  for (const m of t.matchAll(/<input\b[^>]*search[^>]*>/gi)) {
    console.log('[INPUT]', m[0].replace(/\s+/g, ' ').slice(0, 200)); if (++n >= 4) break;
  }
}
