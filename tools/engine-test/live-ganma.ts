// 使用真正的 app/*.ets 解析器镜像测试 GANMA! 当前公开站点；无浏览器/付费绕过。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const here=path.resolve(import.meta.dirname);
const repo=path.resolve(here,'..','..');
const appRoot=path.join(repo,'app','entry','src','main','ets');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'shiman-live-ganma-'));
function mirror(relative:string,output:string):void{
 let source=fs.readFileSync(path.join(appRoot,relative),'utf8');
 source=source.replaceAll("'../parse/Html'","'./Html.ts'")
   .replaceAll("'../parse/Selector'","'./Selector.ts'")
   .replaceAll("'../parse/Json'","'./Json.ts'")
   .replaceAll("'../util/Text'","'./Text.ts'")
   .replaceAll("'../model/Models'","'./Models.ts'")
   .replaceAll("'./Rules'","'./Rules.ts'")
   .replaceAll("'./Html'","'./Html.ts'")
   .replaceAll("'./Text'","'./Text.ts'")
   .replaceAll("'@kit.CryptoArchitectureKit'","'./kitshim.ts'")
   .replaceAll("'@kit.ArkTS'","'./kitshim.ts'");
 fs.writeFileSync(path.join(temp,output),source,'utf8');
}
function assert(ok:boolean,name:string):void{console.log((ok?'PASS ':'FAIL ')+name);if(!ok)throw Error(name);}
async function page(url:string):Promise<string>{
 const ctl=new AbortController();const timer=setTimeout(()=>ctl.abort(),16000);
 try{
  const r=await fetch(url,{signal:ctl.signal,headers:{'User-Agent':'Mozilla/5.0'}});
  assert(r.ok,'HTTP '+r.status+' '+new URL(url).pathname);
  return await r.text();
 }finally{clearTimeout(timer);}
}
try{
 mirror('parse/Html.ets','Html.ts');mirror('parse/Selector.ets','Selector.ts');
 mirror('parse/Json.ets','Json.ts');mirror('util/Text.ets','Text.ts');
 mirror('model/Models.ets','Models.ts');mirror('rule/Rules.ets','Rules.ts');
 mirror('rule/Engine.ets','Engine.ts');
 fs.copyFileSync(path.join(here,'kitshim.ts'),path.join(temp,'kitshim.ts'));
 const html=await import(pathToFileURL(path.join(temp,'Html.ts')).href);
 const json=await import(pathToFileURL(path.join(temp,'Json.ts')).href);
 const rules=await import(pathToFileURL(path.join(temp,'Rules.ts')).href);
 const engine=await import(pathToFileURL(path.join(temp,'Engine.ts')).href);
 const sourcePath=path.join(repo,'app','entry','src','main','resources','rawfile','sources','ganma.json');
 const rule=rules.ruleFromJson(json.parseJson(fs.readFileSync(sourcePath,'utf8')));
 function search(text:string):any[]{
  return engine.parseListItems(text,rule.search.listSelector,rule.id,rule.baseUrl,
    rule.search.title,rule.search.cover,rule.search.link,rule.search.id,rule.search.author,rule.search.latest);
 }
 const a=search(await page('https://ganma.jp/web/search?keyword='+encodeURIComponent('怪談')));
 const b=search(await page('https://ganma.jp/web/search?keyword='+encodeURIComponent('レガシー')));
 console.log('parsed search items',a.map(x=>x.title).slice(0,5),b.map(x=>x.title).slice(0,5));
 assert(a.some(x=>x.url.endsWith('/web/magazine/kaidanloop')),'真实搜索 A 命中怪談ルゥプ');
 assert(b.some(x=>x.url.endsWith('/web/magazine/regacy')),'真实搜索 B 命中レガシー');
 const detailUrl='https://ganma.jp/web/magazine/kaidanloop';
 const detail=html.parseHtml(await page(detailUrl));
 const fields=engine.parseDetailFields(detail,rule,detailUrl);
 assert(fields.title.includes('怪談'),'真实详情页标题解析');
 const chapters=engine.parseChapters(detail,rule,detailUrl,false);
 console.log('parsed chapters',chapters.length,chapters.slice(0,3).map(x=>x.url));
 assert(chapters.length>=3&&chapters[0].url.includes('/web/reader/'),'真实公开章节目录解析');
 const chapterUrl='https://ganma.jp/web/reader/kaidanloop/936237d0-d2b2-11e9-b339-5e26199913ba/0';
 const pics=engine.parseImagesFromRegex(await page(chapterUrl),rule,chapterUrl);
 console.log('parsed images',pics.length,pics.slice(0,2).map(x=>x.url.split('?')[0]));
 assert(pics.length>=30&&pics.length<=40,'真实正文图片去重后页数');
 assert(pics[0].url.includes('&Signature=')&&pics[0].url.includes('&Key-Pair-Id='),'解析图片签名参数完整');
 const ctl=new AbortController();const timer=setTimeout(()=>ctl.abort(),15000);
 try{
  const response=await fetch(pics[0].url,{signal:ctl.signal,headers:{'Referer':chapterUrl,'Range':'bytes=0-1023'}});
  assert(response.ok&&(response.headers.get('content-type')??'').startsWith('image/'),'实际解析的图片 URL 可以下载');
  console.log('image bytes',(await response.arrayBuffer()).byteLength);
 }finally{clearTimeout(timer);}
 console.log('GANMA actual ArkTS parsing chain: ALL PASS');
}finally{
 fs.rmSync(temp,{recursive:true,force:true});
}
