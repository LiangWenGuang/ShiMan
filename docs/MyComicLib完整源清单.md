# MyComic 完整数据源清单（MyComicLib 源库逆向）

> 逆推对象：`MyComicLib-v1.50.apk`（从 `https://source.mycomic.xin/file/MyComicLib-v1.50.apk` 服务器实时下发，4.6MB）
> 逆向工具：REA MCP + androguard 4.1.4（dex 解析）
> 结论：MyComic 是「主 APK + 动态源库插件」架构，真正数据源在 MyComicLib 里，**漫画源 75 个 + 小说源 35 个 + 番剧源 15 个**，远多于之前以为的 17 个内置源。

## 一、关键结论

1. **na.czl 不是数据源**。它是「反模拟器/反多开检测」的字符串黑名单（59 条全是 qemu/bluestacks/nox/vbox/droid4x 等模拟器特征路径）。编码方式已破解：
   `00 01 01 00` + 2字节长度 + **[首字节 = XOR key]** + 密文（密文每字节 XOR 首字节 = 明文）。
   与漫画源无关，之前「na.czl 是加密源配置」的判断是错的。

2. **真正的源库 = MyComicLib.apk**（`xin.mycomic.lib.source.comic.*`，75 个漫画源类）。
   源库走 `source.mycomic.xin` 服务器动态下发，持续维护更新，比编译进主 APK 的 17 个旧源更有价值。

3. **源分两类**：
   - **旧式**（约 25 个）：硬编码 Java 逻辑（`getContentList`/`getInfoList`/`setInfoDetail`），与之前逆推的 17 个内置源一致。
   - **新式**（约 50 个）：配置对象声明规则（`getContentListConfig`/`getInfoListConfig` 返回匿名内部类，规则是「正则提取 + 密钥 + 前缀拼接」），更接近拾漫的 JSON DSL，易移植。

## 二、75 个漫画源完整清单（域名 + 风格）

| 源类 | 域名 | 风格 | 备注 |
|---|---|---|---|
| AiGuoMan | https://www.guoman.net | 新式 | 爱国漫（国漫网） |
| AiYouMan | https://www.kanman.com | 旧式 | 爱优漫→已迁移看漫画 |
| BL | https://www.kanbl.com | 旧式 | 已废弃 isValid=false |
| BaiManWu | https://www.ql1.net | 旧式 | 白漫屋 |
| BaoZi | https://www.baozimh.com | 新式 | 包子漫画（拾漫已接入） |
| BiliBili | https://manga.bilibili.com | 旧式 | B站（签名接口） |
| BoDong | https://ymcdnyfqdapp.ikmmh.com | 新式 | 波动 |
| CiYuan | https://2cycomic.com | 新式 | 次元 |
| Copy | https://www.mangacopy.com | 新式 | 拷贝漫画（头部大站） |
| Cui | https://www.cuiman.com | 旧式 | 催漫 |
| DM5 | https://www.dm5.cn | 新式 | 动漫屋（老牌） |
| DaMoTu | http://www.damotu.com | 新式 | 大磨图 |
| DaShu | https://www.dashumanhua.com | 旧式 | 大树（大叔） |
| DiDi | http://www.didimh.com | 新式 | 滴滴漫画 |
| Digital | https://source.mycomic.xin | 新式 | 动态配置源（非真站） |
| Ding | https://www.dingmanhua.com | 新式 | 顶漫画（拾漫已接入） |
| Ding2 | https://www.dingmanhua.com | 新式 | 顶漫画备用 |
| DmLa | https://www.dongman.la | 新式 | 动漫啦 |
| Du | https://m.tianshimanhua.com | 新式 | 天使漫画（原漫画堆已改名） |
| DuManWu | http://dumanwu1.com | 新式 | 独漫屋 |
| DuShi | https://m.dushimh.com | 旧式 | 都市漫画 |
| FeiChangAi | http://shouji.veryim.com | 新式 | 非常爱 |
| GMH | https://m.g-mh.org | 新式 | |
| GoDa | https://godamanga.site | 旧式 | 高达漫画 |
| Gou | https://www.manhuagou.com | 新式 | 漫画购 |
| GuFeng | https://www.gufengmh9.com | 新式 | 古风漫画 |
| GuoMan | https://www.guomanwang.com | 新式 | 国漫网 |
| HMKanKan | https://hmlook.xyz | 新式 | 韩漫看看 |
| HaoGuoMan | https://www.haoguoman.net | 新式 | 好国漫 |
| HaoMan6 | https://www.haoman6.com | 旧式 | 好漫画6 |
| JmComic | https://jm18c-qwq.org | 新式 | 禁漫（成人站，必须排除） |
| KaiXin | https://yydscomic.com | 旧式 | 开心（yyds） |
| KuManWu | http://www.kumwu2.com | 旧式 | 酷漫屋 |
| KuaiKan | https://www.kuaikanmanhua.com | 新式 | 快看漫画（头部大站，需 JSON 构造） |
| Kuang | https://www.cartoonmad.com | 旧式 | 狂漫画（GBK） |
| Lai | https://www.laimanhua8.com | 旧式 | 来漫画（GBK） |
| LengYue | http://www.9000w.com | 新式 | 冷月 |
| MH100 | https://www.100mhl.com | 旧式 | |
| MH118 | http://m.ccshwy.com | 旧式 | http 已挂 |
| MH118W | http://m.xzcstjx.com | 旧式 | http 已挂 |
| MH1234 | http://www.gmh1234.com | 新式 | 漫画1234 |
| MH160 | https://www.mh160.cc | 旧式 | |
| MH166 | https://www.manhua166.com | 旧式 | |
| MH178 | https://cc178.cn | 新式 | |
| MH18 | https://m.18mhx.com | 新式 | 成人站，排除 |
| MH4499 | https://www.m4499.com | 新式 | |
| MH6 | http://www.sixmanhua.com | 旧式 | 六漫画 |
| MHOl | https://www.manhuaol.com | 新式 | 漫画OL |
| MHYu | https://www.manhuayu8.com | 新式 | 漫画语 |
| MHZhan | https://www.manhuazhan.com | 新式 | 漫画栈 |
| MHZhan2 | https://www.manhuamh.com | 新式 | 漫画栈备用 |
| ManHua | https://www.manhua3.com | 新式 | 漫画3 |
| ManHuaFen | https://m.manhuafen.com | 旧式 | 漫画粉 |
| ManHuaTai | https://m.manhuatai.com | 旧式 | 漫画台（已迁移看漫画） |
| ManHuaWu | https://www.mhw1.com | 新式 | 漫画屋（拾漫已接入 mhw1） |
| ManWa | https://manwawang.com | 新式 | 漫蛙 |
| MaoMi | https://www.sisimanhua.com | 新式 | 猫咪（丝丝） |
| MiTui | https://m.imitui.com | 旧式 | 咪兔（拾漫已接入） |
| OH | https://www.cocomanga.com | 旧式 | 可可（AES 解密） |
| PinYue | https://www.pinmh.com | 旧式 | 品阅 |
| PuFei | http://m.pufei.cc | 旧式 | 扑飞（GBK+JS 解密） |
| QiMiao | http://www.qimiaomh.com | 旧式 | 奇妙（http） |
| QiXi | http://www.qiximh4.com | 旧式 | 七夕漫画 |
| QianWei | https://m1.qianwee.com | 旧式 | 千维 |
| Ru | https://www.rumanhua.com | 新式 | 汝漫画 |
| Ru2 | http://rumanhua1.com | 新式 | 汝漫画备用 |
| SFAcg | https://www.sfacg.com | 新式 | SF轻小说漫画 |
| SiSi | https://m.sisimanhua.com | 旧式 | 丝丝（拾漫已接入） |
| TengXun | https://ac.qq.com | 旧式 | 腾讯动漫（JS 解密） |
| WuQian | https://comic.mkzcdn.com | 新式 | 五千（漫客栈 CDN） |
| XL | https://www.xlshc.com | 新式 | |
| XianMan | https://www.gaonaojin.com | 新式 | 闲漫（高脑筋） |
| XinXin | https://www.77mh.nl | 新式 | 心心（77漫画） |
| YanShi | http://111.180.202.218:1314 | 新式 | 岩石（裸 IP，已挂） |
| ZhuZhu | https://www.zhuzhumh.com | 新式 | 猪猪漫画 |

## 三、新式源规则结构（可移植性关键）

新式源的正文图规则 = 匿名内部类的 `addUrlList` 方法，本质是「**正则提取 + 密钥 + 前缀拼接**」，示例：

- **GuoMan（国漫网）**：正则 `params = '(.*?)';` 提取变量 → 密钥 `9S8$vJnU2ANeSRoF` → 正则 `"images":\[(.*?)\]` 提取数组 → 按 `"`/`\`/`,` split → 前缀 `https://img1.baipiaoguai.org`。
- **HaoGuoMan（好国漫）**：密钥 `YxUpqGrs5$3wYg` → 正则 `"chapter_images":"(.*?)"` → split `\`/`###` → 前缀 `https://res.xiaoqinre.com/`。

这些规则**可直接翻译成拾漫 `images.type="regex"` + 新增的 `splitUrls()` 能力**（密钥若只是字符串替换而非真解密，则纯 HTTP 可解；若密钥参与 XOR/AES 则需要引擎支持解密）。

## 四、对拾漫的移植优先级（待真机探活后确定）

### ❌ 必须排除（成人内容，合规红线，绝不接入）
| 源类 | 域名 | 原因 |
|---|---|---|
| JmComic | jm18c-qwq.org | 禁漫天堂（成人站） |
| MH18 | m.18mhx.com | 18禁成人站 |
| （清单中其他含 18+ 属性的站逐一甄别） | | |

### ⚠️ 已挂/失效（不浪费探活）
| 源类 | 域名 | 原因 |
|---|---|---|
| MH118 | http://m.ccshwy.com | http 死链 |
| MH118W | http://m.xzcstjx.com | http 死链 |
| YanShi | http://111.180.202.218:1314 | 裸 IP，已失效 |
| AiYouMan | www.kanman.com | 已迁移（拾漫已接看漫画） |
| ManHuaTai | m.manhuatai.com | 已迁移看漫画 |
| Digital | source.mycomic.xin | 动态配置源，非真站 |

### ✅ 高价值、大概率纯 HTTP 可搬（新式，规则简单，重点探活）
- 拷贝漫画 Copy、动漫屋 DM5、催漫 Cui、漫画栈 MHZhan、古风 GuFeng、国漫 GuoMan、好国漫 HaoGuoMan、漫画语 MHYu、漫画OL MHOl、77漫画 XinXin、猪猪 ZhuZhu、SF轻小说 SFAcg、品阅 PinYue、漫画3 ManHua、漫画购 Gou、滴滴 DiDi、动漫啦 DmLa 等

### 🔶 头部大站（需额外能力，暂缓）
- 快看漫画 KuaiKan（需构造 JSON 请求 + 可能签名）
- 腾讯动漫 TengXun（JS 解密）
- B站 BiliBili（twirp 签名）
- 可可 OH（AES 解密）

## 五、探活结果（2026-11-02 首轮，本机 HTTP 探测）

> ⚠️ HTTP 000 可能是本机 TLS 指纹拦截，不代表站点真挂——最终以手机自检为准。

### ✅ 存活（HTTP 200，可继续深挖结构）
| 源 | 域名 | 首页体积 | 备注 |
|---|---|---|---|
| DM5 动漫屋 | dm5.cn | 445KB | 搜索页结构已摸清（`/search?title={kw}&language=1`，`div.mh-item`） |
| KuaiKan 快看 | kuaikanmanhua.com | 232KB | 头部站，需 JSON 构造 |
| SFAcg SF轻小说 | sfacg.com | 124KB | |
| ManHua 漫画3 | manhua3.com | 98KB | |
| AiGuoMan 爱国漫 | guoman.net | 78KB | |
| Gou 漫画购 | manhuagou.com | 63KB | |
| GuFeng 古风 | gufengmh9.com | 62KB | |
| DmLa 动漫啦 | dongman.la | 42KB | |
| GuoMan 国漫网 | guomanwang.com | 34KB | 苹果CMS模板，搜索参数待确认 |
| XinXin 77漫画 | 77mh.nl | 5.8KB | |
| BaiManWu 白漫屋 | ql1.net | 5.6KB | |
| HaoGuoMan 好国漫 | haoguoman.net | 1.4KB | 偏小，可能反爬 |
| ZhuZhu 猪猪 | zhuzhumh.com | 1.7KB | 偏小 |

### ⚠️ 重定向（可能换域名，需跟跳转）
- PinYue 品阅 pinmh.com → 301
- DiDi 滴滴 didimh.com → 301

### ❓ HTTP 000（本机拦截，需真机复核，不判死刑）
- Copy 拷贝漫画、Cui 催漫、MHZhan 漫画栈、MHYu 漫画语、MHOl 漫画OL

## 六、下一步

1. 批量真机探活 75 个源（`tools/probe-sources.mjs --catalog` 或手机自检），筛出「还活着 + 纯 HTTP 可取」的。
2. 对可搬的新式源，逐个反编译 `addUrlList` 拿到精确正则/密钥/前缀，翻译成拾漫 JSON。
3. 需要解密（密钥参与运算）的源，评估是「字符串替换」还是「真加密」，决定走 regex 还是需引擎加解密能力。

## 七、C 阶段成果 + A 阶段探测（2026-11-02）

### ✅ 已接入：动漫啦 dmla（第 13 源，全链路纯 HTTP 验证通过）
- 搜索 `/manhua/so/{kw}/`，详情 `/manhua/detail/{id}/`，章节 `/manhua/chapter/{id}/{chid}/`，
  正文图 `img.lazy-image.reader-img` 的 `@attr:data-src`（15 张明文）。
- **教训：反编译类名过时**（cy_list_mh → Tailwind ul.divide-y），必须「反编译 + 真实网页」两步。

### A 阶段批量探测结果（搜索页存活 + 正文图可取性）
| 源 | 搜索 | 正文图 | 结论 |
|---|---|---|---|
| Gou 漫画购 | 200 | `div#img-content img` | 包子马甲站（CDN=static-tw.baozimh.com），与 mhw1 内容重复，低价值 |
| ManHua 漫画3 | 200 | 待确认 | MacCMS，搜索页结构需深挖 |
| AiGuoMan 爱国漫 | 200 | 带密钥 9S8$vJnU2ANeSRoF | ⚠️ 需确认密钥是否真解密 |
| SFAcg | 200 | 动态接口 ajax/Common.ashx | ⚠️ 需引擎动态 API |
| BaiManWu 白漫屋 | 200 | 待确认 | |
| XinXin 77漫画 | 404 | — | 搜索路径过时 |
| ZhuZhu 猪猪 | 404 | — | 搜索路径过时 |
| MHYu 漫画语 | 000 | 带密钥 | 本机拦截，需真机 |
| MHZhan 漫画栈 | 000 | 带密钥 | 本机拦截，需真机 |

**核心结论**：MyComicLib 75 源中，大量站点已改版/转型/失效，真正「纯 HTTP 可搬且内容不重复」的增量有限。
最终可用性以**真机自检**为准（拾漫 SourceSelfTest）。
