// 只探测公开 HTML。跟踪几个可见列表链接到详情和首章，不绕过付费/鉴权。
const cases=[
 ['dm5-search','https://cnc.dm5.com/search?title=%E7%81%AB%E5%BD%B1','dm5'],
 ['dm5-search-alt','https://cnc.dm5.com/search?title=%E6%B5%B7%E8%B4%BC','dm5'],
 ['dm5-index','https://cnc.dm5.com/comicindex/','dm5'],
 ['manhuagui-list','https://www.manhuagui.com/list/','manhuagui'],
 ['manhuagui-search','https://www.manhuagui.com/s/%E7%81%AB%E5%BD%B1.html','manhuagui'],
 ['ganma-detail','https://ganma.jp/web/magazine/kaidanloop','ganma'],
 ['ganma-reader','https://ganma.jp/web/reader/kaidanloop/936237d0-d2b2-11e9-b339-5e26199913ba/0','ganma'],
 ['ganma-home','https://ganma.jp/web','ganma'],
 ['comicwalker-detail','https://comic-walker.com/detail/KC_003497_S/episodes/KC_0034970000100012_E?episodeType=comics','walker']
];
function clean(s){return s.replace(/\s+/g,' ').slice(0,180);}
function links(html,kind,limit=14){
 const tags=html.match(/<a\b[^>]*>/gi)||[],out=[];
 for(const tag of tags){
  const href=tag.match(/href=["']([^"']+)["']/i)?.[1]??'';
  const match=kind==='dm5'?/(manhua|\/m[0-9]{3,}|\/chapter)/i.test(href):
    kind==='manhuagui'?/\/comic\//i.test(href):
    kind==='ganma'?/\/web\/(magazine|reader)\//i.test(href):
    /\/detail\//i.test(href);
  if(match&&!out.some(x=>x.href===href)){out.push({href,tag:clean(tag)});if(out.length>=limit)break;}
 }
 return out;
}
const results=[];
for(const [name,url,kind] of cases){
 const ctl=new AbortController();const timer=setTimeout(()=>ctl.abort(),13000);
 try{
  const r=await fetch(url,{redirect:'follow',signal:ctl.signal,headers:{'User-Agent':'Mozilla/5.0','Accept':'text/html,application/xhtml+xml'}});
  const html=(await r.text()).slice(0,1200000);
  const relevant=links(html,kind);
  const imgs=(html.match(/<img\b[^>]*>/gi)||[]).slice(0,8).map(clean);
  const titles=(html.match(/<h[1-3]\b[^>]*>[\s\S]{0,160}?<\/h[1-3]>/gi)||[]).slice(0,6).map(clean);
  const forms=(html.match(/<form\b[^>]*>/gi)||[]).slice(0,3).map(clean);
  const formsInputs=(html.match(/<input\b[^>]*>/gi)||[]).filter(x=>/search|keyword|title|query|name/i.test(x)).slice(0,6).map(clean);
  const hosts=[...new Set((html.match(/https?:\\?\/\\?\/[^\s"'<>\\]{6,120}/gi)||[]).slice(0,200))].slice(0,8);
  const dataMarkers=['__NEXT_DATA__','page_content','chapterImages','chapter_id','magazineId','episode','imageUrl','imagePath','data-src','data-original'].filter(x=>html.includes(x));
  const item={name,url,status:r.status,final:r.url,bytes:html.length,links:relevant,images:imgs,titles,forms,formsInputs,hosts,dataMarkers,
    imgCount:(html.match(/<img\b/gi)||[]).length,
    jpegCount:(html.match(/\.jpe?g/gi)||[]).length,
    webpCount:(html.match(/\.webp/gi)||[]).length};
  console.log(JSON.stringify(item));results.push(item);
 }catch(e){console.log(JSON.stringify({name,url,error:String(e)}));}
 finally{clearTimeout(timer);}
}
// 用真实搜索结果的第一条链接再读详情，避免预设无效 URL。
for(const origin of results.filter(x=>x.name==='dm5-search'||x.name==='manhuagui-list')){
 const link=origin.links.find(x=>x.href.startsWith('/'))??origin.links[0];
 if(!link)continue;
 const url=new URL(link.href,origin.final).href;const ctl=new AbortController();const timer=setTimeout(()=>ctl.abort(),12000);
 try{
  const r=await fetch(url,{signal:ctl.signal,headers:{'User-Agent':'Mozilla/5.0'}});
  const html=(await r.text()).slice(0,1000000);
  const all=(html.match(/<a\b[^>]*>/gi)||[]);
  const candidate=all.map(x=>x.match(/href=["']([^"']+)["']/i)?.[1]??'')
    .filter(x=>/(\/m\d+\/|\/comic\/\d+\/\d+|chapter)/i.test(x)).slice(0,18);
  console.log(JSON.stringify({name:origin.name+'-detail-follow',url,status:r.status,bytes:html.length,title:html.match(/<title[^>]*>([^<]+)/i)?.[1],
    chapterLinks:candidate,imgCount:(html.match(/<img\b/gi)||[]).length,imgs:(html.match(/<img\b[^>]*>/gi)||[]).slice(0,4).map(clean)}));
 }catch(e){console.log(JSON.stringify({name:origin.name+'-detail-follow',url,error:String(e)}));}
 finally{clearTimeout(timer);}
}

const more=[
 ['ganma-search-keyword','https://ganma.jp/web/search?keyword=%E6%80%AA%E8%AB%87'],
 ['ganma-search-q','https://ganma.jp/web/search?q=%E6%80%AA%E8%AB%87'],
 ['ganma-search-query','https://ganma.jp/web/search?query=%E6%80%AA%E8%AB%87'],
 ['ganma-search-b','https://ganma.jp/web/search?keyword=%E3%83%AC%E3%82%AC%E3%82%B7%E3%83%BC'],
 ['comicwalker-search','https://comic-walker.com/search?keyword=DOG'],
 ['manhuagui-chapter','https://www.manhuagui.com/comic/62362/923084.html'],
 ['dm5-detail','https://cnc.dm5.com/manhua-huoyingrenzhetedian/'],
 ['dm5-chapter','https://cnc.dm5.com/m794921/']
];
for(const [name,url] of more){
 const ctl=new AbortController();const timer=setTimeout(()=>ctl.abort(),11000);
 try{
  const r=await fetch(url,{signal:ctl.signal,headers:{'User-Agent':'Mozilla/5.0'}});
  const html=(await r.text()).slice(0,900000);
  const anchor=(html.match(/<a\b[^>]*href=["'][^"']+["'][^>]*>/gi)||[]).filter(x=>/web\/magazine|\/comic\/|\/m\d+\/|reader/i.test(x)).slice(0,6).map(x=>x.slice(0,250));
  const markerNames=['imageUrl','imageUrl\\','pageImage','chapterImages','img_data','chapter_data','dm5imagefun','chapterfun','__NEXT_DATA__','__next_f.push','pageCount','imageUrls'];
  const contexts={};
  for(const marker of markerNames){const at=html.indexOf(marker);if(at>=0)contexts[marker]=html.slice(Math.max(0,at-110),at+450);}
  const cdn=(html.match(/https?:\\?\/\\?\/[^\s"'<>{}]{20,230}?\.(?:jpg|jpeg|webp|png)(?:\?[^"'<> ]{0,200})?/gi)||[]).slice(0,6);
  const sample=html.match(/<script[^>]*id=["']__NEXT_DATA__["'][^>]*>[\s\S]{0,500}/i)?.[0]??'';
  console.log(JSON.stringify({name,status:r.status,final:r.url,title:html.match(/<title[^>]*>([^<]+)/i)?.[1],bytes:html.length,
    anchors:anchor,contexts,cdn:cdn.map(x=>x.slice(0,180)),readerPageCount:(html.match(/page_number/gi)||[]).length,
    imageUrlCount:(html.match(/imageUrl/gi)||[]).length,sample:sample.slice(0,300)}));
 }catch(e){console.log(JSON.stringify({name,url,error:String(e)}));}finally{clearTimeout(timer);}
}

async function targeted(name,url,fn){
 const ctl=new AbortController();const timer=setTimeout(()=>ctl.abort(),11000);
 try {const r=await fetch(url,{signal:ctl.signal,headers:{'User-Agent':'Mozilla/5.0'}});const h=(await r.text()).slice(0,1200000);console.log(JSON.stringify({name,status:r.status,...fn(h,r.url)}));}
 catch(e){console.log(JSON.stringify({name,error:String(e)}));}finally{clearTimeout(timer);}
}
await targeted('ganma-structure-search','https://ganma.jp/web/search?keyword=%E6%80%AA%E8%AB%87',(h)=>{
 const k=h.indexOf('href="/web/magazine/kaidanloop"');
 return {card:h.slice(Math.max(0,k-300),k+1500)};
});
await targeted('ganma-structure-detail','https://ganma.jp/web/magazine/kaidanloop',(h)=>{
 const k=h.indexOf('href="/web/reader/kaidanloop/');
 return {header:h.slice(Math.max(0,h.indexOf('<h1')-300),h.indexOf('<h1')+400),chapter:h.slice(Math.max(0,k-270),k+1200)};
});
await targeted('ganma-structure-reader','https://ganma.jp/web/reader/kaidanloop/936237d0-d2b2-11e9-b339-5e26199913ba/0',(h)=>{
 const k=h.indexOf('imageUrl'),m=h.match(/https?:[^"'<> ]{10,400}\.jpe?g/gi)||[];
 return {imageUrlSnippet:h.slice(Math.max(0,k-400),k+1100),jpegSnippets:m.slice(0,4).map(x=>x.slice(0,180)),
   imageTagCount:(h.match(/<img\b/gi)||[]).length,episodeImgLinks:(h.match(/imageUrl/gi)||[]).length};
});
await targeted('walker-structure-search','https://comic-walker.com/search?keyword=DOG',(h)=>{
 const k=h.indexOf('__NEXT_DATA__');const a=h.indexOf('KC_003497_S',k);
 return {nextSnippet:h.slice(a-200,a+1600),searchResultCount:(h.match(/"code":"KC_/g)||[]).length};
});
await targeted('walker-structure-reader','https://comic-walker.com/detail/KC_003497_S/episodes/KC_0034970000100012_E?episodeType=comics',(h)=>{
 const k=h.indexOf('__NEXT_DATA__'); const pics=(h.match(/https:\/\/cdn\.comic-walker\.com\/integration\/cdpf\/resources\/[a-zA-Z0-9\/._-]+\.(?:jpe?g|webp)/g)||[]);
 return {nextSnippet:h.slice(k,k+700),imageCount:pics.length,firstPictures:[...new Set(pics)].slice(0,4)};
});
