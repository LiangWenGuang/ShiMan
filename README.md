# 拾漫 · 鸿蒙原生多源漫画阅读器

纯 ArkTS 实现的 HarmonyOS NEXT 漫画聚合阅读器。**无广告、无登录、无数据上传**，只做两件事：把多个图源的漫画聚合到一起看，以及在任何时候自由换源。

功能一览：多源发现 / 跨源聚合搜索 / 阅读中换源 / **星标收藏** / 书架与阅读进度 / 图源管理与自检。

- 包名：`com.manyu.reader`
- 目标平台：HarmonyOS NEXT（编译目标 API 22 / 6.0.2，向下兼容可在 5.x、7.0 上运行）
- 产物：`hap/manyu-1.0.0-unsigned-20261101.hap`（660 KB）

---

## 1. 先说清楚验证边界

这是最重要的部分，避免你拿到手后有落差。

| 项目 | 状态 | 依据 |
|---|---|---|
| ArkTS 编译 | ✅ 已验证 | `hvigor BUILD SUCCESSFUL`，产出签名 HAP |
| 图源解析引擎（离线） | ✅ 已验证 | 真实页面回归 19/19 + JSON 健壮性 4/4 |
| 图源解析引擎（真实网络） | ✅ 已验证 | 漫客栈全链路 11/11；分类页 4/4；腾讯动漫 7/7 |
| 漫客栈：搜索/分类/详情/阅读 | ✅ **真机验证** | 装到 PLR-AL00（HarmonyOS 7.0）实测：三列封面、73 话目录、正文 41 页正常出图 |
| 腾讯动漫：搜索/详情/目录 | ✅ **真机验证** | 聚合搜索合并出 9 条；详情 1378 话；目录可点 |
| 腾讯动漫：**正文图片** | ❌ **未攻克** | 无头取图只能拿到 1 张分享图，正文图不在 DOM 里 |
| **松子漫画：全链路** | ✅ **真机验证** | 搜索 5 条、详情 673 话、**正文 29 页真实出图**（正则取图 + 带 Referer 下载） |
| **云北漫画：全链路** | ✅ **真机验证** | 搜索 8 条、详情 670 话、**正文 36 页真实出图**（首页推荐 8 部） |
| **206 漫画：全链路** | ✅ **真机验证** | 搜索 8 条、详情 58 话、**正文 82 页真实出图**（3 个分类入口） |
| 换源 | ✅ **真机验证** | 候选卡片、匹配度、章节对齐、一键跳转均正常 |
| 真机安装与交互 | ✅ **真机验证** | PLR-AL00 / HarmonyOS 7.0.0.111 / API 26 实装运行 |

当前内置 **5 个图源，其中 4 个可完整阅读**：漫客栈、松子漫画、云北漫画、206 漫画；
腾讯动漫只能搜索和看目录。

> 用户提供的「数据源配置」清单里一共 32 个漫画源，逐条探测结论见
> **[docs/图源探测报告.md](docs/图源探测报告.md)**。真正能用的只有上面 4 个，
> 其余大半是站点已挂、搜索/正文走 JS、或需要客户端签名。

也就是说：**主图源（漫客栈）全链路在真机上跑通了**；腾讯动漫可搜索、可看目录，但正文图片还没解决。遇到时阅读器会给明确提示 + 一键换源，不会白屏也不会崩。

> 真机验证过程中修掉两个致命问题，记录在这里免得重犯：
> 1. **JSON 解析器死循环**：`readNumber` 遇到非数字字符时不前进，`runJavaScript` 返回的双重编码字符串（`"[...]"`）正好触发，导致内存爆满硬崩溃。已加字符吞掉 + 循环上限 + 双重编码解包。
> 2. **Web 取图并发**：章节页会跳转，`onPageEnd` 多次触发，并发 `runJavaScript` 打崩控制器。已加会话令牌 + 看门狗。

---

## 2. 和原方案的关键差异

你没有沿用上一版（VenHM 魔改），这一版是**从零写的**：

| 维度 | 旧方案 | 本工程 |
|---|---|---|
| JS 运行时 | 内嵌 QuickJS（C++ NAPI）+ 上游 `init.js` | **无**。零 C++、零 JS 引擎 |
| 图源规则 | Legado 书源转换 | **自研 JSON DSL**（见第 4 节） |
| HTML 解析 | JS 侧实现 | **ArkTS 自研分词器 + DOM 轻量树** |
| 包体积 | 10.28 MB | 660 KB |
| 图源数量 | 141（转换而来） | 2（手写原创）+ 可持续新增 |

代价必须讲明白：**旧方案 141 个源里，绝大多数章节图片是通过页面 JS 动态注入的，纯 HTTP 拿不到。** 我用 11 轮探测验证过这一点，详见 `docs/00-交付全案.md` 的「图源生态现状」。本工程用两种手段解决：接口直连（漫客栈）和无头取图（腾讯）。

---

## 3. 目录结构

```
harmony-comic-origin/
├── app/
│   ├── AppScope/                    应用级配置与图标
│   └── entry/src/main/
│       ├── ets/
│       │   ├── entryability/        Ability 入口（初始化图源与本地库）
│       │   ├── model/               数据模型、路由参数
│       │   ├── util/                字符串/URL 工具
│       │   ├── parse/               ★ 自研 HTML 解析、CSS 选择器、JSON 解析
│       │   ├── rule/                ★ 自研规则模型与执行引擎
│       │   ├── net/                 HTTP 客户端（幂等重试、编码探测）
│       │   ├── source/              图源注册表与调用门面
│       │   ├── store/               书架 / 进度 / 历史
│       │   ├── view/                通用组件
│       │   └── pages/               6 个页面
│       └── resources/rawfile/sources/   内置图源规则（JSON）
├── tools/                           探测与回归脚本（不参与打包）
├── hap/                             构建产物
├── docs/                            交付文档
└── 一键构建.ps1
```

带 ★ 的两个目录是本项目的核心资产，全部原创。

---

## 4. 图源规则 DSL

一个 JSON 文件描述一个站点。新增图源不需要改一行代码。

```json
{
  "id": "mkzhan",
  "name": "漫客栈",
  "baseUrl": "https://www.mkzhan.com",
  "charset": "utf-8",
  "headers": [{ "name": "Referer", "value": "https://www.mkzhan.com/" }],

  "search": {
    "url": "/search/?keyword={kw}",
    "list": ".search-comic-list .common-comic-item",
    "id": "@attr:data-cid",
    "title": ".comic__title a@text",
    "cover": "img.lazy@attr:data-src",
    "link": "a.cover@attr:href",
    "latest": ".comic-update a@text"
  },

  "detail": {
    "title": "p.comic-title@text",
    "cover": ".de-info__cover img@attr:data-src",
    "author": ".comic-author .name@text",
    "desc": ".comic-intro@text"
  },

  "chapters": {
    "list": "a.j-chapter-link",
    "id": "@attr:data-chapterid",
    "title": "@text",
    "link": "@attr:data-hreflink",
    "reverse": true
  },

  "images": {
    "type": "json",
    "url": "https://comic.mkzcdn.com/chapter/content/v1/?chapter_id={chapterId}&comic_id={comicId}&quality=1&type=1&format=0",
    "list": "$.data.page",
    "field": "image"
  },

  "browse": [
    { "name": "最近更新", "url": "/update/" },
    { "name": "热血", "url": "/category/?theme_id=8" }
  ]
}
```

### 取值表达式（FieldExpr）

| 写法 | 含义 |
|---|---|
| `.title@text` | 取后代 `.title` 的文本 |
| `img@attr:data-src` | 取后代 `img` 的 `data-src` |
| `@text` | 取作用域自身文本（用于章节项就是 `<a>` 的情况） |
| `@attr:data-cid` | 取作用域自身属性 |
| `A \|\| B` | 备选链，A 取不到再试 B |
| `...~s\|正则\|替换\|` | 末尾正则替换（`g` 全局、`i` 忽略大小写） |

### 三种图片取法（`images.type`）

| `type` | 适用 | 说明 |
|---|---|---|
| `json` | 站点有接口 | 直接按 JSON Path 取值，最快（漫客栈） |
| `html` | 图片写在 HTML 的 `<img>` 里 | CSS 选择器取值 |
| `regex` | **图片藏在 JSON-LD / 内联 JS 数组里** | 对原始 HTML 跑正则抠地址（松子漫画） |
| `web` | 图片由页面 JS 动态注入 | 系统 Web 组件后台渲染后取图（腾讯） |

### 防盗链

部分图源 CDN 会校验 `Referer`（实测松子漫画不带直接 403）。因此封面与正文都走
`net/ImageLoader`：自带 `Referer` 下载字节再解成 PixelMap，而不是直接用 `Image(url)`。

`web` 模式不引入任何第三方 JS 引擎，用的是鸿蒙自带 `Web` 组件：

```json
"images": {
  "type": "web",
  "url": "{chapterUrl}",
  "readySelector": "img[src*='acimg']",
  "extract": "attr:src",
  "settleMs": 1500
}
```

`ReaderPage` 会把这个页面放进 1×1 的隐藏 Web 里加载，`onPageEnd` 后注入脚本把图址捞回来。代价是首次打开多等 1~2 秒。

> **2026-11-01 修正：松子漫画的搜索参数是 `q`，不是 `keyword`。**
> 写错时站点不会报错，而是把「热门推荐」当结果吐回来——用任意关键词都得到同样 12 条，
> 看上去像「搜到了」，实际是假的。已改正并补上 `emptyMarker`（`暂时没有找到`）与分类页
> `/genre/all/`。教训：**验证搜索必须换两个差异极大的关键词比对结果集**，
> 只测一个词会把静态推荐位误判成搜索成功。

---

## 5. 界面与版式

设计令牌集中在 `ets/theme/Theme.ets`：颜色、字号、间距、圆角都从这里取，
页面里不再各写各的常量（改版前 6 个页面各自复制了一份 `BG`/`SURFACE`/`TEXT_SUB`）。

**字号只有七级（vp）**

| 令牌 | 值 | 用途 |
|---|---|---|
| `fsDisplay` | 26 | 首页主标题 |
| `fsTitle` | 20 | 详情页作品名 |
| `fsHeadline` | 17 | 分区标题 |
| `fsBody` | 15 | 正文、列表主文字、按钮 |
| `fsLabel` | 13 | 章节名、次级标签 |
| `fsCaption` | 12 | 辅助说明 |
| `fsMicro` | 11 | 封面角标、页码 |

改版前后对比：正文 11–13 → 13–15，标题 15–17 → 17–26，章节条目 11 → 13，
列表行高 44 → 52，底部导航 56 → 62 并加了图标。

**版式约定**

- 分区标题统一为「左侧 3vp 强调色竖条 + 标题 + 右侧计数」
- 圆角：封面 12、分组卡 18、按钮 12、胶囊 999
- 网格：单元格内边距 4（相邻封面间距 8），行距 18；卡片标题固定两行高度，
  否则单行标题会让整排高低不齐
- 详情页章节改两列 44vp 高（原三列 11 号字太难点），当前阅读章用强调色描出
- 阅读器底栏必须有实底色：阅读页是沉浸式的，不铺底色漫画会透上来把图标糊掉

**踩过的坑**

ArkUI 的 `Scroll` 在内容比一屏短时会把子组件**垂直居中**，表现是设置页顶部凭空多出
一大块空白。给滚动内容加 `.constraintSize({ minHeight: '100%' })` 钉回顶部即可。

底部导航用系统符号（`sys.symbol.house` / `book_pages` / `person`，共 3778 个可选）
配文字：符号在个别系统版本上可能取不到，文字是兜底。

---

## 6. 构建与装机

```powershell
# 编译（产出 unsigned HAP，不需要账号）
powershell -ExecutionPolicy Bypass -File 一键构建.ps1

# 编译 + 跑引擎回归（真实网络）
powershell -ExecutionPolicy Bypass -File 一键构建.ps1 -EngineTest
```

装机需要一次签名，见 **[装机与签名指引.md](装机与签名指引.md)**。

### 克隆后第一步

仓库里**没有** `app/build-profile.json5`——它含证书路径与签名口令，已被 `.gitignore` 排除。
克隆后先复制模板，再在 DevEco 里点一次「自动签名」：

    copy app\build-profile.example.json5 app\build-profile.json5

之后 `File → Project Structure → Signing Configs → 勾选自动签名`，
DevEco 会把 `signingConfigs` 写回这个文件，构建就能出签名包了。

---

## 7. 已知限制

1. **腾讯动漫正文图片取不到。** 搜索、详情、1378 话目录都正常，但正文图不在页面 DOM 里（只暴露 1 张分享图），无头取图这条路对它无效，需要逆向它的章节接口。阅读时会提示「可尝试换源」。
2. **阅读器只有竖向连续模式。** 横向翻页、双页、卷轴模式未实现。
3. **无离线下载。** 图片靠系统 Image 组件缓存，没有主动下载队列。
4. **章节对齐是启发式的。** 换源时按章节号匹配，两个源编号体系不同会退回按索引夹取。
5. **签名有效期 365 天**（到 2027-11-01）。到期后 App 会打不开，需要重新签名重装；届时证书也会一起换掉，覆盖安装不了，得先卸载。
6. **没有源健康统计。** 只做了「连通性自检」按钮。

## 8. 版权声明

本工程不存储、不分发任何漫画内容，只做页面解析与展示。所有漫画版权归原作者与发布平台所有，请支持正版。图源规则的可用性取决于目标站点的实际状态，站点改版后规则会失效。
