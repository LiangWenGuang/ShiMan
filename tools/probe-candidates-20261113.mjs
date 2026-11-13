// 候选公开图源的轻量可达性/静态 HTML 检查（不下载正文图、不调用私人接口）。
// 仅输出摘录，探测结果不能单独证明一个站点已经实现完整的漫画阅读。
const cases = [
  ['dm5-home','https://cnc.dm5.com/comicindex/'],
  ['dm5-search','https://cnc.dm5.com/search?title=%E7%81%AB%E5%BD%B1'],
  ['dmzj-home','https://www.dmzj.com/'],
  ['manhuagui-home','https://www.manhuagui.com/'],
  ['ganma-home','https://ganma.jp/'],
  ['ganma-reader','https://ganma.jp/web/reader/kaidanloop/936237d0-d2b2-11e9-b339-5e26199913ba/0'],
  ['comicwalker-home','https://comic-walker.com/'],
  ['comicwalker-detail','https://comic-walker.com/detail/KC_003497_S/episodes/KC_0034970000100012_E?episodeType=comics'],
  ['comicdays-home','https://comicdays.com/'],
  ['webtoons-home','https://www.webtoons.com/zh-hans/'],
  ['mangaplus-home','https://mangaplus.shueisha.co.jp/'],
  ['baseline-mkzhan','https://www.mkzhan.com/']
];
function samples(html, pattern, limit=5) {
  const out=[]; const r=new RegExp(pattern,'ig'); let m;
  while((m=r.exec(html))!==null&&out.length<limit){out.push(m[0].replace(/\s+/g,' ').slice(0,380));if(r.lastIndex===m.index)r.lastIndex++;}
  return out;
}
for(const [name,url] of cases) {
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),11000);
  try {
    const response=await fetch(url,{
      signal:controller.signal,
      headers:{'User-Agent':'Mozilla/5.0 (compatible; ShiManSourceVerifier/1.0; +https://github.com/LiangWenGuang/ShiMan)','Accept':'text/html,application/xhtml+xml'},
      redirect:'follow'
    });
    const type=response.headers.get('content-type')??'';
    const body=(await response.text()).slice(0,1_000_000);
    const title=/<title[^>]*>([\s\S]*?)<\/title>/i.exec(body)?.[1]?.replace(/<[^>]+>/g,'').trim().slice(0,100)??'';
    const links=samples(body,'<a\b[^>]*href=["\'][^"\']+["\'][^>]*>',5);
    const images=samples(body,'<img\b[^>]*>',5);
    const forms=samples(body,'<form\b[^>]*>',3);
    const state=samples(body,'(__NEXT_DATA__|__NUXT__|__INITIAL_STATE__|reader|chapter|episode|manga)',7);
    console.log(JSON.stringify({name,status:response.status,url:response.url,type,length:body.length,title,
      anchorTags:links,imageTags:images,formTags:forms,markers:state,bodyStart:body.slice(0,100)},null,0));
  } catch(error){console.log(JSON.stringify({name,url,error:String(error)}));}
  finally{clearTimeout(timer);}
}
