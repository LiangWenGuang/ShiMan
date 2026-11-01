# MyComic 数据源逆推分析（前置调研）

> 目标：把 MyComic（用户提供的 `MyComic-v1.11.9.apk`）的数据源方式，移植进拾漫 App。
> 状态：调研完成，待 REA MCP 连通后对真实请求做精确适配。

## 1. 来源

- **开源代码**：`github.com/15974577446/MyComic`（安卓漫画/小说/番剧阅读器），已 `git clone --depth 1`
  到 `F:/AI/QoderCN-Data/output/MyComic-src`（与主项目同级，**不污染** harmony-comic-origin 仓库）。
- **用户 APK**：`C:\Users\10245\Downloads\MyComic-v1.11.9.apk`。
  - 内含加密配置 `assets/na.czl`（2094 字节）。**开源代码里完全没有任何对 `na.czl` 的引用**
    → 说明 APK 实际加载的数据源规则，和 GitHub 默认分支的代码**不一致**（可能更新或混淆）。
  - 反编译 APK 需要 jadx，但沙箱下载 github release 二进制被限速到 ~11KB/s（jadx 116MB
    下不完），此路当前不可行。

## 2. 17 个内置漫画源（源自开源 `top.luqichuang.mycomic.source` 包）

根 URL 通过 grep `getIndex()` 提取；沙箱存活为重测结果（跟随重定向，注意沙箱对国内站常有限制，
`000` 不代表用户真机访问不了）。图片获取方式按源码 `getContentList` 初判。

| 源名 | 根 URL | 搜索 URL 模板 | 图片获取(初判) | 沙箱存活 |
|---|---|---|---|---|
| MiTui 米推 | https://www.imitui.com | `m.imitui.com/search/?keywords=` | HTML 内 `chapterImages=[...]` 数组+前缀 | 000 |
| PuFei 扑飞 | http://m.pufei.cc | `/e/search/?...&keyboard=`(GBK) | `cp="..."` base64+`exeJsCode` 解密 | 200 |
| TengXun 腾讯 | https://ac.qq.com | 腾讯搜索 | JS 解密 | 200 |
| BiliBili 哔哩哔哩 | https://manga.bilibili.com | B站搜索 | JSON(初判) | 200 |
| OH | https://www.cocomanga.com | 待读码 | JSON(初判) | 000 |
| ManHuaTai 漫画台 | https://m.manhuatai.com | `/sort/all.html?search_key=` | JSON API `getchapterinfov2` | 000 |
| MH118 | http://m.ccshwy.com | 待读码 | 待读码 | 200 |
| MH118W | http://m.xzcstjx.com | 待读码 | 待读码 | 200 |
| MH1234 | http://www.mh1234.com | 待读码 | 待读码 | 502 |
| Du 独漫画 | https://m.dumanhhua.com | 待读码 | 待读码 | 000 |
| BL | https://www.kanbl.com | 待读码 | 待读码 | 200 |
| AiYouMan 爱优漫 | https://www.iyouman.com | 待读码 | JSON(初判) | 000 |
| BaoZi 包子 | https://cn.baozimh.com | 待读码 | 待读码 | 000 |
| DaShu 大树 | https://www.dashuhuwai.com | 待读码 | JS 解密 | 200 |
| QiMiao 奇妙 | http://www.qimiaomh.com | `/search.html?keyword=` | `z_img='[...]'` 数组+字符串替换 | 200 |
| SiSi 嘶嘶 | https://m.sisimanhua.com | 待读码 | 待读码 | 200 |
| ManHuaFen 漫画粉 | https://m.manhuafen.com | 待读码 | 待读码 | 200 |

## 3. 选择器语法映射（MyComic Java → 拾漫 JSON）

| MyComic (Jsoup) | 拾漫 JSON |
|---|---|
| `node.ownText("a.title")` | `.a.title@text` |
| `node.ownText("p", 2, "dd")` | 多段回退（拾漫用 `A\|B` 备选） |
| `node.href("a")` | `@attr:href` |
| `node.src("img")` | `img@attr:src` |
| `node.attr("div.thumb img","data-src")` | `div.thumb img@attr:data-src` |
| `node.title("a")` | `a@attr:title` |
| `StringUtil.match("re", html)` | 图片 `type:regex` + 模板拼接 |

## 4. 已精读源（完整解析逻辑）

### MiTui 米推
- 搜索：`https://m.imitui.com/search/?keywords={kw}`，列表 `div.itemBox`，
  标题 `a.title@text`，封面 `img@src`，详情 `a.title@href`（相对，拼 `m.imitui.com`）。
- 详情：标题 `div#comicName`、封面 `div#Cover img`、简介 `p#full-des|p#simple-des`。
- 章节：`ul#chapter-list-1 li`，标题 `span@text`，链接 `a@href`（需 `//m.`→`//www.` 处理）。
- **图片**：HTML 内 `chapterImages = [ ... ]` 数组（逗号分隔，带引号）→
  前缀 `chapterImageHost`（默认 `https://resnode.yxtun.com/`）+ `chapterPath`(代码里置空)。
  → 需引擎支持「提取单变量 + 分隔符 split + 前缀拼接」。

### ManHuaTai 漫画台
- 搜索：`/sort/all.html?search_key={kw}`，列表 `li.comic-item`。
- **图片**：详情页含 `window.comicInfo={...}`；`buildRequest` 构造
  `https://m.manhuatai.com/api/getchapterinfov2`（带 `comic_id`/`chapter_newid` 等参数，
  从 `window.comicInfo` 提取）→ 返回 JSON `chapter_img_list` 数组。
  → 需引擎支持「详情页抽变量 → 发 API 请求 → 解析 JSON 图片数组」。

### PuFei 扑飞
- 搜索：`/e/search/?...&keyboard=`（`DecryptUtil.getGBKEncodeStr` 做 GBK 编码）。
- **图片**：`cp="..."` → `decryptBase64` → `exeJsCode`（执行一段 JS 解密）→ 逗号分隔 URL
  + 前缀 `http://res.img.tueqi.com/`。
  → 需执行 JS 解密，纯 HTTP 引擎拿不到；要么无头 WebView 跑那段 JS，要么复刻解密算法。

### QiMiao 奇妙
- 搜索：`/search.html?keyword={kw}`，列表 `div.classification`。
- **图片**：`z_img='[...]'` 数组，且 `lyffny`→`yzrbhb` 字符串替换后 split。
  → 同数组拼接类，需引擎支持。

## 5. 关键结论

1. **图片获取方式分三类**：HTML 数组变量拼接、JSON API、JS 解密——每个源都要定制，
   不是简单复制选择器。
2. **MyComic 在 WebView 中渲染页面后再用 Jsoup 解析**。实测 QiMiao 搜索页返回
   `Redirecting... Loading` + `window.location`（JS 重定向空壳），纯 HTTP 客户端拿不到结果。
   → 直接照搬 GitHub 源码的选择器，在拾漫纯 HTTP 引擎下大概率失效。
3. 因此「把数据源弄进来」对每个源都是定制任务；部分源需**增强引擎**
   （支持无头渲染 / 数组拼接 / API 请求），不是改几个 JSON 字段能解决的。

## 6. REA 连通后的逆推计划

1. 用 REA（浏览器/设备自动化）在运行 MyComic 时**抓真实网络请求**，
   直接拿到每个源当前的真实 URL、参数、接口（绕过站点改版/JS 渲染问题）。
2. 据此把 17 源逐一翻译成拾漫图源 JSON；需扩展引擎的（数组拼接 / API / 无头渲染）单独处理。
3. 真机验证 + 修复，按「探测台失败≠死刑，以真机为准」原则迭代。

## 7. 备选（不等 REA）
若用户不想等 REA，可直接基于开源源码从「纯 HTML / 数组类」源开始逐个定制适配
（先做 MiTui、ManHuaTai 等），先交付几个能用的源真机验证。
