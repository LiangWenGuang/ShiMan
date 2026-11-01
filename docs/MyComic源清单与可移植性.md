# MyComic 数据源逆推 · 源清单与可移植性矩阵

> 逆推对象：`MyComic-v1.11.9.apk`（github.com/15974577446/MyComic，开源安卓漫画/小说/番剧阅读器）
> 逆推方式：APK 内 `assets/na.czl` 是服务器下发的加密源配置（非开源、自定义 TLV+异或编码，本仓库未含解码器，跳过）；
> 真正编译进 APK 的内置 17 个图源是 `common/.../mycomic/source/` 下的 17 个 `BaseComicSource` 子类，逻辑即权威解析规则。
> 目标：把它们的「搜索 / 详情 / 目录 / 正文图」解析方式翻译进拾漫（纯 ArkTS，无 JS 引擎，仅有 `images.type="web"` 无头取图兜底）。

## 一、拾漫引擎能力边界（决定哪些能搬）

| 能力 | 字段 | 适用 |
|---|---|---|
| 搜索 | `search.url`({kw}) + 列表选择器 | 纯 HTTP GET |
| 详情/目录 | `detail.*` / `chapters.list` | 纯 HTML 选择器 |
| 正文图·HTML | `images.type=html` | `<img>` 已在 DOM |
| 正文图·JSON | `images.type=json` | 图片来自一个**静态** JSON 接口 |
| 正文图·序号 | `images.type=sequence` | 前缀+序号拼地址 |
| 正文图·无头 | `images.type=web` | 页面脚本把图片写进 `<img>`，渲染后捞 `attr:src` |
| 正文图·正则 | `images.type=regex` | 图片地址在原始 HTML 里可被正则抠出 |
| ❌ 不支持 | — | 需要**执行 JS** 解密 / 调**带签名** twirp 接口 / AES 解密 |

**结论**：能搬的只有「搜索/详情/目录是纯 HTML，且正文图要么在 DOM、要么页面 JS 渲染后会写进 `<img>`（走 web 兜底）」的源。需要 `DecryptUtil.exeJsCode`（执行 JS）、AES、base64+JS、签名 twirp 的源无法搬。

## 二、17 源逐条结论

| # | 源 | 域名 | 搜索 | 详情/目录 | 正文图 | 可移植 | 本轮动作 |
|---|---|---|---|---|---|---|---|
| 1 | MiTui 咪兔 | imitui.com | m.子域 GET | 纯 HTML | `chapterImages=[...]` 数组+host 前缀（页面 JS 拼） | ✅ web | **已搬 mitui.json** |
| 2 | ManHuaTai 漫画台 | manhuatai.com | GET | 纯 HTML | `getchapterinfov2` JSON 接口（需 detail 页 comic_id+chapter_newid） | ⚠️ 需动态 API | 暂缓（见第三节） |
| 3 | AiYouMan 爱优漫 | iyouman.com | GET | 纯 HTML | 同上 `getchapterinfov2` | ⚠️ 需动态 API | 暂缓 |
| 4 | BaoZi 包子 | cn.baozimh.com | GET | 纯 HTML(AMP) | `<amp-img>` 直接在 DOM | ✅ html | **已搬 baozi.json** |
| 5 | Du 漫画堆 | dumanhhua.com | GET | 纯 HTML(MIP) | `chapterImages` 数组+host 前缀 | ✅ web | **已搬 dumanhua.json** |
| 6 | MH118 | ccshwy.com(**http**) | GET | 纯 HTML | `qTcms_S_m_murl_e` base64+`$qingtiandy$` 拆分 | ⚠️ 需 base64 解码 | 暂缓（http 多半已挂） |
| 7 | MH118W | xzcstjx.com(**http**) | GET | 纯 HTML | 同上 | ⚠️ 同上 | 暂缓 |
| 8 | MH1234 | mh1234.com | — | — | — | ❌ `@Deprecated` `isValid=false` | 不搬 |
| 9 | ManHuaFen 漫画粉 | manhuafen.com | — | — | — | ❌ 整文件被注释 + `isValid=false` | 不搬 |
| 10 | BL | kanbl.com | — | — | — | ❌ `@Deprecated` `isValid=false` | 不搬 |
| 11 | OH 可可 | cocomanga.com | GET | 纯 HTML | `C_DATA` AES+base64 解密 | ❌ 需 AES/JS | 不搬 |
| 12 | PuFei  puff | pufei.cc(**http**) | GBK 搜索 | 纯 HTML | `cp="..."` base64 + `exeJsCode` | ❌ 需执行 JS | 不搬 |
| 13 | QiMiao 奇妙 | qimiaomh.com(**http**) | GET | 纯 HTML | `z_img='[...]'` 数组 | ⚠️ 搜索页是 JS 重定向空壳 | 暂缓（搜索大概率失效） |
| 14 | SiSi 丝丝 | sisimanhua.com | GET | 纯 HTML(MIP) | `view/{id}/{n}.webp` 序号（id 在 URL） | ✅ web | **已搬 sisi.json** |
| 15 | TengXun 腾讯 | ac.qq.com | GET | 纯 HTML | `DATA` base64 + nonce JS 解密 | ❌ 需执行 JS | 不搬 |
| 16 | BiliBili | manga.bilibili.com | twirp POST | twirp POST | twirp POST + ImageToken 签名 | ❌ 签名接口 | 不搬 |
| 17 | DaShu 大叔 | dashuhuwai.com | GET | 纯 HTML | `eval(function(){...})` JS 解密 | ❌ 需执行 JS | 不搬 |

## 三、本轮已落地（4 个新源）

拾漫图源目录 `app/entry/src/main/resources/rawfile/sources/`，并在 `index.json` 注册：

- **baozi.json** — 包子漫画：搜索/详情/目录/正文全纯 HTML（AMP），`images.type=html` 直接抠 `<amp-img src>`。
- **sisi.json** — 丝丝漫画：搜索/详情/目录纯 HTML，`images.type=web` 无头兜底（正文是 `view/{id}/{n}.webp` 序号，但 id 在 URL 中段，sequence 模板只支持 `{base}{i}`，故走 web）。
- **mitui.json** — 咪兔漫画：搜索在 `m.` 子域（搜索 URL 写绝对地址），详情/目录在 `www.`，`images.type=web`。
- **dumanhua.json** — 漫画堆：MIP 页面，`images.type=web`。

> 注：MiTui/Du/SiSi 正文图依赖「页面脚本把图片写进 `<img>`」，web 模式在隐藏 Web 组件里渲染后捞 `attr:src`。若站点 AMP/MIP 框架的 JS 被 HarmonyOS Web 拦截导致不渲染，`images` 会取空——**以真机自检为准**（拾漫本来就用手机自检判定源健康）。

## 四、暂缓项（下一轮，需要引擎小扩展）

1. **ManHuaTai / AiYouMan（漫画台 / 爱优漫）**：最大价值的两个源（目录全、更新快）。正文图走 `getchapterinfov2` JSON 接口，参数 `comic_id`+`chapter_newid` 要从**详情页** `window.comicInfo={...}` 抠出再拼请求。
   → 需要给 `images` 增加「从详情页抽变量 + 动态 JSON 接口」能力（参考已有的 `chapters.json` 设计）。引擎改动小、收益高，建议优先。
2. **MH118 / MH118W / QiMiao**：base64/数组，但都在 `http://` 子域，2024 年的 APK 当时可能已挂；即便搬了也可能连不上，建议真机先探活再决定。

## 五、关键坑（与之前结论一致）

- **取值链第一段是「在作用域的后代里找」**：`div.comics-chapters` 本身即是「一章」，title 写 `span@text`、link 写 `a@attr:href`，不要多套一层作用域。
- **`amp-img` / `mip-img` 是真实标签**，选择器直接写 `amp-img@attr:src`，引擎按标签名匹配。
- **`html` 图模式 field 写 `@attr:src`**（整段即表达式，空选择器取自身属性），不是裸 `src`。
- **搜索用 `m.` 子域、其余用 `www.`**：MiTui 搜索 URL 直接写绝对地址，`resolveUrl` 对绝对地址透传。
- **避免 `:eq(n)`**：拾漫选择器引擎不保证支持 Jsoup 的 `:eq()`，作者/状态等非关键字段用简单选择器兜底即可。
