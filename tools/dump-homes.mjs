import { fetchFollow } from './http.mjs';
import fs from 'node:fs';
const SITES = [
  ['1004','腾讯动漫','https://ac.qq.com'],['1005','哔哩哔哩','https://manga.bilibili.com'],
  ['1056','快看漫画','https://www.kuaikanmanhua.com'],['1052','SF漫画','https://www.sfacg.com'],
  ['1011','爱优漫','https://www.kanman.com'],['1041','滴滴漫画','http://www.didimh.com'],
  ['1046','云北漫画','https://www.mhw1.com'],['1051','武芊漫画','https://comic.mkzcdn.com'],
  ['1054','读漫屋','http://dumanwu1.com'],['1070','如漫画','http://rumanhua2.com'],
  ['1073','206漫画','https://www.m206.com'],['1075','漫画客','https://yumanhua.com'],
  ['1076','咚漫','https://www.dongmanmanhua.cn'],['1077','知音漫客','https://m.zymk.cn'],
  ['1081','云漫画','https://www.yunmanhua.com'],['1084','来漫画吧','https://www.laimanhuaba.com'],
  ['1085','飞翔漫画','https://ffppt.com']
];
fs.mkdirSync('dumps/all', { recursive: true });
for (const [id, name, base] of SITES) {
  const r = await fetchFollow(base, { timeout: 12000 });
  if (r.ok && r.text) {
    fs.writeFileSync(`dumps/all/${id}.html`, r.text, 'utf8');
    const hits = [...new Set([...r.text.matchAll(/["'(\s](\/?[a-zA-Z0-9_\-\/]*search[a-zA-Z0-9_\-\/]*)["')\s]/g)].map(m=>m[1]))].slice(0,6);
    const forms = [...r.text.matchAll(/<form\b[^>]*>/gi)].map(m=>m[0].replace(/\s+/g,' ')).slice(0,3);
    console.log(`${id} ${name} | ${r.status} | ${Math.round(r.len/1024)}K`);
    console.log('   search命中:', hits.join(' , ') || '(无)');
    if (forms.length) console.log('   form:', forms.join(' || ').slice(0,220));
  } else {
    console.log(`${id} ${name} | FAIL ${r.status||''} ${r.detail||''}`);
  }
}
