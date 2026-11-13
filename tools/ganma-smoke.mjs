// 验证 GANMA! 网站上允许匿名访问的公开章节，不尝试付费/登录内容。
// 运行：node tools/ganma-smoke.mjs
const base='https://ganma.jp';
const kw1='怪談',kw2='レガシー';
const reader='/web/reader/kaidanloop/936237d0-d2b2-11e9-b339-5e26199913ba/0';
async function get(url,headers={}){
 const ctl=new AbortController(),timer=setTimeout(()=>ctl.abort(),16000);
 try{return await fetch(url,{signal:ctl.signal,headers:{'User-Agent':'Mozilla/5.0',...headers}});}
 finally{clearTimeout(timer);}
}
function validate(ok,name){console.log((ok?'PASS ':'FAIL ')+name);if(!ok)throw Error(name);}
function magazineLinks(html){return [...new Set([...html.matchAll(/href=["'](\/web\/magazine\/[^"'/?]+)["']/g)].map(m=>m[1]))];}
const searchA=await get(base+'/web/search?keyword='+encodeURIComponent(kw1));
const searchB=await get(base+'/web/search?keyword='+encodeURIComponent(kw2));
validate(searchA.ok&&searchB.ok,'两个公开搜索入口 HTTP 2xx');
const [a,b]=await Promise.all([searchA.text(),searchB.text()]);
const la=magazineLinks(a),lb=magazineLinks(b);
validate(la.includes('/web/magazine/kaidanloop')&&lb.includes('/web/magazine/regacy'),'不同关键词分别命中不同漫画');
validate(la.join('|')!==lb.join('|'),'搜索结果非固定推荐');
const detail=await get(base+'/web/magazine/kaidanloop');
validate(detail.ok,'详情页面 HTTP 2xx');
const dh=await detail.text();
const chapterLinks=[...new Set([...dh.matchAll(/href=["'](\/web\/reader\/kaidanloop\/[^"'?#]+)["']/g)].map(m=>m[1]))];
validate(chapterLinks.length>=3,'详情正文包含至少三个公开章节链接');
validate(chapterLinks.includes(reader),'目录包含首话示例');
const page=await get(base+reader);
validate(page.ok,'首话页面 HTTP 2xx');
const html=await page.text();
const pattern=/https:\/\/d1bzi54d5ruxfk\.cloudfront\.net\/story_[a-z0-9-]+_pages_[0-9]+_orig\/[0-9]+\.jpg\?Policy=[^"<> ]+/g;
const matches=[...html.matchAll(pattern)].map(m=>m[0].replace(/\\u0026/gi,'&').replace(/\\+$/g,''));
const images=[...new Set(matches)];
console.log('source details',JSON.stringify({searchA:la.length,searchB:lb.length,chapters:chapterLinks.length,imageMatches:matches.length,uniqueImages:images.length,firstImagePath:images[0]?.split('?')[0]}));
validate(images.length>=5,'正文可解析至少五张独立图片');
validate(images.every(x=>x.includes('&Signature=')&&x.includes('&Key-Pair-Id=')),'图片签名参数完整');
const first=await get(images[0],{'Referer':base+reader,'Range':'bytes=0-1023'});
const type=first.headers.get('content-type')??'';
const bytes=(await first.arrayBuffer()).byteLength;
console.log('image response',JSON.stringify({status:first.status,type,bytes}));
validate(first.ok&&type.startsWith('image/')&&bytes>100,'公开正文首张图片可下载');
