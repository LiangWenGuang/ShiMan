# 把「拾漫」上传到 GitHub

Git 已经装好：`D:\Git`（Git for Windows 2.56.0，PortableGit 发行版），
`D:\Git\cmd` 已加入用户 PATH，凭据管理器 Git Credential Manager 2.9.1 也配好了，
推送时会自动弹浏览器登录，不用手敲 token。

> 为什么是 PortableGit 而不是那个 `Git-2.56.0.4-64-bit.exe` 安装程序：
> 官方安装包要求管理员权限，会弹 UAC；当前会话不是管理员，也不该替你点确认。
> PortableGit 是官方同款发行包，功能一致、免提权。
> 想换成带右键菜单和开始菜单的标准安装，右键以管理员运行
> `D:\Temp\Git-2.56.0.4-64-bit.exe`，安装路径填 `D:\Git` 即可（先删掉现有目录）。

---

## 1. 先建一个空仓库

打开 https://github.com/new

- Repository name：`shiman`（或你喜欢的名字）
- 可见性：Public / Private 都行
- **不要**勾 "Add a README file"、不要加 .gitignore、不要加 license
  （本地已经有提交了，空仓库才不会冲突）

建完复制页面上的仓库地址，形如：
`https://github.com/你的用户名/shiman.git`

## 2. 本地推送

**新开一个 PowerShell 窗口**（老窗口读不到新 PATH），然后：

```powershell
cd F:\AI\QoderCN-Data\output\harmony-comic-origin

# 本地仓库已经初始化并提交过了，只需要挂远端
git remote add origin https://github.com/你的用户名/shiman.git
git push -u origin main
```

第一次 push 会弹出一个浏览器窗口要求登录 GitHub：

1. 选 **Sign in with your browser**
2. 浏览器里登录并点 **Authorize**
3. 回到终端，看到 `branch 'main' -> 'main'` 就成功了

## 3. 之后再改代码

```powershell
git add -A
git commit -m "改了什么"
git push
```

---

## 仓库里有什么 / 没有什么

`git ls-files | wc -l` 目前是 108 个文件，主要是：

- `app/` 全部 ArkTS 源码与图源规则 JSON
- `tools/` 图源探测、引擎回归脚本
- `docs/` 交付全案与图源探测报告
- `README.md`、`装机与签名指引.md`、`一键构建.ps1`

**被 .gitignore 排除的东西（重要）**

| 排除项 | 原因 |
|---|---|
| `app/build-profile.json5` | 含你的证书路径与签名口令 |
| `signwork/`、`*.p7b`、`*.p12`、`*.cer` | 调试证书材料 |
| `app/entry/build/`、`app/.hvigor/` | 构建产物，7.7 MB + 5.4 MB |
| `hap/`、`*.hap` | 签名绑定设备 UDID，别人装了也跑不了 |
| `tools/dumps/` | 探测时抓的 HTML 缓存，6.5 MB |
| 根目录 `*.jpeg` | 调试截图 |

克隆这个仓库的人要先执行
`copy app\build-profile.example.json5 app\build-profile.json5`，
再在 DevEco 里点一次自动签名，才能出签名包。README 里写了。

## 常见问题

**push 报 `failed to push some refs`**
远端仓库建的时候勾了 README，先 `git pull --rebase origin main` 再 push。

**换机器 / 令牌失效**
删掉旧凭据：控制面板 → 凭据管理器 → Windows 凭据 → 删掉 `git:https://github.com`。

**想用 SSH 而不是 HTTPS**
```powershell
ssh-keygen -t ed25519 -C "你的邮箱"
# 把 ~/.ssh/id_ed25519.pub 的内容贴到 GitHub → Settings → SSH keys
git remote set-url origin git@github.com:你的用户名/shiman.git
```
