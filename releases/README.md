# 拾漫 · 安装包

这里放的是每个版本的已签名 HAP，直接下载就能装。

## 当前版本

| 版本 | 文件 | 说明 |
|---|---|---|
| **V1.0.3** | `ShiMan-1.0.3-signed.hap` | 19 个图源、首页双模式、章节更新时间、排行榜页 |

> 上一版 V1.0.2 的安装包在 git 历史里（`git log --all -- releases/`）。

## 怎么装

**方式一：手机直连电脑（推荐）**

```powershell
hdc install -r ShiMan-1.0.3-signed.hap
```

**方式二：把 HAP 传到手机**

用文件管理器点开 HAP 即可安装（需要允许「安装未知来源应用」）。

## ⚠️ 重要：这个包只在我自己的机器上能装

工程用的是 **调试证书 + 调试 Profile**，Profile 里写死了允许安装的设备 UDID。
所以这个 HAP **换一台手机装会报「签名校验失败」**，不是包坏了。

别人要用自己在 DevEco Studio 里重新签名：

1. DevEco Studio 打开 `app/` 工程
2. `File → Project Structure → Signing Configs`
3. 勾上 `Automatically generate signature`（登录华为账号）
4. `Build → Build Hap(s)`，产物在 `app/entry/build/default/outputs/default/`

## 版本历史

### V1.0.3
- 图源精简到 19 个（移除包子漫画 / 漫画堆 / 漫画语 / 漫蛙）
- 首页改成双模式：**当前图源（默认）** / 全部图源聚合
- 详情页章节格子显示更新时间（顶漫画、滴滴已接）
- 新增排行榜页（左类型 + 右列表），分类少时自动改用顶部胶囊
- 修复选择器引擎 `标签:伪类` 全部失效的 bug
- 丝丝 / 爱国漫 / 国漫网 的分类入口修复

### V1.0.2
- 16 个图源、AES 解密引擎、搜索历史
