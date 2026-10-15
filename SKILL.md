---
name: dev-env-upgrade
description: 开发环境升级医生：JDK / Maven / IDEA / Node / Python / Go / Rust / CLI 工具链的版本体检、最新版查询、升级风险评级与安全落地。一键盘查本机台账与最新版对照表，内置各组件权威查询口径与本机实测可用端点（含被策略代理 403 拦截的端点黑名单），升级风险评估矩阵（切 JDK 必查 cacerts 信任库交集、必统计存量项目 JDK 依赖分布、必认 build.txt 而非目录名），批量改动 dry-run + 备份 + 字节级读写三条铁律（2026-10-15 workspace.xml 二次编码事故教训）。触发词：升级JDK、升级Maven、升级工具链、环境体检、版本体检、还有啥能升级、查最新版本、升级IDEA、Node升级、环境盘点、环境升级、dev-env-upgrade、jdk1.8升到最新、Maven最新版、mvninfo、查Maven仓库。
author: 胡志伟
motto: "升级不难，难的是知道哪个能升、哪个升了会炸——先查口径，再评风险，最后才动手。"
---

# dev-env-upgrade — 开发环境升级医生

回答两类问题：

1. **"还有啥能升级？"** —— 一键盘查本机组件版本 vs 各自最新版，出对照清单
2. **"XX 升到最新"** —— 按风险矩阵评估 → 出方案 → 确认词 → 落地 → 实证验收 → 回写台账

本机环境快照与历史升级记录：[references/台账.md](references/台账.md)（**先读它再动手**，台账是"上次长什么样"的唯一真相）。

## 零、铁律（每条都是踩坑换来的）

1. **批量改文件必须字节级读写**：`[IO.File]::ReadAllBytes` → `GetEncoding(28591)` 映射字符串 → 替换 → `GetBytes` → `WriteAllBytes`。禁止 `Get-Content -Raw` 读非本进程编码的文件——PS 5.1 按 GBK 解码 UTF-8，中文必变乱码，个别字还会吃掉 XML 引号（2026-10-15 实锤，17 个 workspace.xml 中招）。
2. **动手前先备份、先 dry-run**：复制原文件到备份目录 → 空跑统计将改动数 → 实改 → 双指标校验（文件数+字节数）。
3. **升级动作逐项走确认词**：一轮对话只确认一个方案，多组件升级逐个出方案。
4. **脚本源码纯 ASCII**：PS 5.1 无 BOM 按 ANSI 解析，中文必炸；要中文输出就用 `[Console]::OutputEncoding=UTF8` + 从 JSON 配置读，或干脆英文标签。
5. **`-File` 传参不拆逗号**：`powershell -File x.ps1 -Only A,B` 里 `A,B` 是**一个** token（外层 pwsh 还会把逗号变空格），脚本内必须自己 `-split '[,;\s]+'`；且拆分结果**不能赋回 `[string]` 类型 param**（会被空格拼回一根字符串），要用独立 `[string[]]` 变量（2026-10-15 实锤）。

## 一、本机环境台账（摘要，详情见 references/台账.md）

| 组件 | 本机现状 | 位置 |
|------|----------|------|
| JDK 8（主力） | Oracle 1.8.0_451（commercial，**8u211 起商用需订阅**） | `F:\Program Files\Java\jdk-1.8` = JAVA_HOME |
| JDK 8（备用） | Temurin 1.8.0_492（装而未用） | `F:\Program Files\Java\jdk-8-tem` |
| JDK 11/17/21 | Temurin 11.0.31 / 17.0.19（另有 MS 17.0.16）/ 21.0.11 | `F:\Program Files\jdk-*-tem`、`C:\Program Files\Eclipse Adoptium\...` |
| Maven | 3.10.0（2026-10-15 刚升） | `MAVEN_HOME`（注册表 Machine）=`F:\maven\apache-maven-3.10.0` |
| IDEA | 目录名 2026.2.1，**实际 build IU-262.10968.63 = 2026.2.3 已最新** | `F:\JetBrains\IntelliJ IDEA 2026.2.1` |
| PyCharm | 2026.2.3（最新） | `C:\Program Files\JetBrains\PyCharm 2026.2.3` |
| Node | v22.20.0 激活（nvm symlink `F:\nodejs`），已装至 v24.21.0 | `NVM_HOME=F:\nvm` |
| Python | 3.13.13（pyenv 当前） | pyenv-win |
| Go / Rust | 1.27.2（g 管理）/ 1.99.0（rustup） | 均为最新 |
| CLI | git 2.55.0 / jq 1.8.2 / tokei 12.1.2 / xh 0.25.3 / gh 2.95.0 | 各有最新版可查 |
| shell | **只有 PowerShell 5.1，无 pwsh 7** | 中文 .ps1 必须 UTF-8 with BOM 或纯 ASCII |

已知陷阱：
- **IDEA 版本只认 `build.txt` / `product-info.json`**，目录名与注册表 DisplayName 都是安装时的旧值（自动补丁升级不改名）。
- **`MAVEN_HOME` 老进程看不到**：脚本必须注册表兜底读 `HKLM:\...\Session Manager\Environment`。
- `mvn` 在**当次会话**常解析不到（进程 PATH 是环境变量生效前继承的旧值）；**新开终端可直敲 `mvn`**（注册表 Machine PATH 含 `%MAVEN_HOME%\bin`，类型 ExpandString）。拿不准就显式调 `$MAVEN_HOME\bin\mvn.cmd`。
- `where node` 第一条是 DSH 自带运行时 `...\dsh-tauri\runtime\node.exe`，不是 nvm 的。
- `nvm list` 非交互无输出；读 `F:\nvm` 目录 + `F:\nodejs` 链接目标即可。

## 二、版本查询口径表（本机实测，2026-10-15）

### 网络通道（策略代理 127.0.0.1:2816 白名单制）

DSH 会话 shell 经本地策略代理出网：`HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY = http://127.0.0.1:2816`。三条铁律：

1. **IWR 不吃环境变量代理**——.NET 默认代理是 10808（死的），必报"无法连接到远程服务器"。必须显式 `-Proxy http://127.0.0.1:2816`。
2. **curl.exe 必须 `--proxy http://127.0.0.1:2816`**（否则 HTTP 000）。
3. **白名单制**（实测 2026-10-15）：

| 通道 | 结果 |
|------|------|
| `registry.npmmirror.com`、`mirrors.aliyun.com`、`registry.npmjs.org` | ✅ 通 |
| `mirrors.cloud.tencent.com`（部分路径） | ✅ 通（maven-metadata OK；go/adoptium/rust 子路径 404） |
| `api.github.com`（**gh api 全可用**） | ✅ 通 |
| github.com 网页 | ⏱ 超时 |
| `api.adoptium.net`、`dlcdn.apache.org`、`data.services.jetbrains.com`、`repo1.maven.org`、`search.maven.org`、`maven.aliyun.com`、tuna/ustc/bfsu、`goproxy.cn`、huaweicloud、jetbrains.com、`golang.google.cn` | ❌ 403（策略拦截） |

4. **兜底通道**：被 403 的端点，AI 会话里用 `web_fetch` 工具实测可通（adoptium 200）——脚本查不到时 AI 用 web_fetch 补，别死磕脚本。

### 各组件口径（主 = 本机实测可用；备 = 需兜底）

| 组件 | 本机版本 | 最新版查询主口径 | 备注/坑 |
|------|----------|------------------|---------|
| JDK | `JAVA_HOME\release` 读 `JAVA_VERSION`/`BUILD_TYPE` | `gh api repos/adoptium/temurin{N}-binaries/releases/latest --jq .tag_name`（8→`jdk8u504-b01`） | 兜底：web_fetch `api.adoptium.net/v3/assets/latest/{N}/hotspot?os=windows&architecture=x64&image_type=jdk`；`/v3/info/release_names` **永远 404 别试**；阿里云/腾讯无 Adoptium 镜像（404）；tuna 有镜像但被 403；Oracle 8u502+ 需订阅 |
| Maven | `mvn.cmd -version` 解析 "Apache Maven x.y.z" | 腾讯云 `.../maven-public/org/apache/maven/apache-maven/maven-metadata.xml` 正则抽 `<version>` | dlcdn / repo1 / search.maven.org 全 403；注意 4.x 要 JDK17，本机 JDK8 只认 3.x 最新 |
| IDEA | `<install>\product-info.json` → `version`+`buildNumber`（**不认目录名/注册表**） | 无可用主口径（data.services 403）→ AI 用 web_fetch 或让用户看 IDEA 内更新提示 | JetBrains 端点全被拦；目录名滞后实证：`2026.2.1` 目录 = build IU-262.10968.63 = 2026.2.3 |
| Node | `node -v`（注意 DSH node 抢 first）+ nvm 目录列表 | `registry.npmmirror.com/-/binary/node/index.json`（首条=latest current，首条 `lts!=false`=最新 LTS） | aliyun nodejs-release 目录列表 872 项按**字符串序**排（v9.x 排最后），不能取"最后 N 个"当最新，必须版本号数值比较 |
| Python | `pyenv version` | `mirrors.aliyun.com/python-release/windows/` 解析 `python-(\d+\.\d+\.\d+)-amd64.exe` | 列表也按字符串序，同样要数值比较 |
| Go | `go version` | `mirrors.aliyun.com/golang/` 目录页正则 `go(\d+\.\d+(?:\.\d+)?)[\.-]windows-amd64` 取版本最大者 | `?mode=json` **已失效**（2026-10-15 实测返回 HTML 页面，3.6MB，`ConvertFrom-Json` 必炸）；goproxy.cn / golang.google.cn / tencent /go 全 403 或 404；`gh api repos/golang/go/tags` 返回 2012 年老标签，**不可用** |
| Rust | `rustc --version` | `gh api repos/rust-lang/rust/releases/latest --jq .tag_name` | static.rust-lang.org、tuna 全 403；`rustup check` 因 RUSTUP_DIST_SERVER=tuna 被拦必失败；gh release 可能滞后于 stable channel，重要场合 web_fetch `static.rust-lang.org` 兜底 |
| CLI 工具 | 各自 `--version`（jq/tokei/xh/gh/git/officecli） | `gh api repos/{owner}/{repo}/releases/latest --jq .tag_name` | 对应仓库：jqlang/jq、XAMPPRocky/tokei、ducaale/xh、git-for-windows/git、cli/cli；officecli 无 GitHub 发布（跳过） |
| winget/scoop | 存在但不可靠 | `winget show` 对 Temurin/Maven/Node 输出空 | 别依赖 |

### 本机命令输出格式实测（解析用）

```
jq       -> jq-1.8.2                       （连字符，无空格）
tokei    -> tokei 12.1.2 compiled with...  （取第一段）
xh       -> xh 0.25.3\n+native-tls...      （两行，取第一行）
gh       -> gh version 2.95.0 (2026-06-17)
git      -> git version 2.55.0.windows.2
go       -> go version go1.27.2 windows/amd64
rustc    -> rustc 1.99.0 (b940084d7 2026-09-28)
node     -> v22.22.0
officecli-> 1.0.143
pyenv    -> 3.13.13 (set by C:\...\version)
```

## 三、升级风险矩阵

| 动作 | 风险面 | 必查项 | 防法 |
|------|--------|--------|------|
| JDK 小版本升级（8u451→8u504） | ①`jdk.tls.disabledAlgorithms` 收紧弱算法，老数据库/老 HTTPS 接口可能连不上 ②根证书库差异 ③license 变化 | **cacerts 交集**（keytool -list 两边各导出，按指纹比对；实测 Oracle 113 条 vs Temurin 144 条，一次性别名）＋**存量项目 JDK 依赖分布**（扫 .idea 的 project-jdk-name / .iml LANGUAGE_LEVEL / pom java.version） | Oracle 目录保留不删可回切；先切一个项目试跑；IDEA 里改 `jdk.table.xml` 该 `name` 的 homePath 可全量无感切换（20 处引用免改） |
| Maven 3.x 内升级 | ①settings.xml/localRepository 路径引用散落各处 ②存量项目 IDEA 配置指向旧版 | 全盘扫 workspace.xml 的 mavenHome/userSettingsFile/localRepository 三键 | 新仓库全量复制（robocopy 双指标校验）；批量替换**字节级**＋哨兵保护公司定制副本（`- xiehui`、`-lisichen` 不动） |
| IDEA 升级 | 目录名滞后造成误判；插件兼容 | `build.txt`/`product-info.json` 定位真实版本 | 补丁升级优先于重装 |
| Node/Python/Go/Rust | **必须走 nvm/pyenv/g/rustup**（AGENTS.md 红线） | 版本管理器是否在 PATH | 禁止直接覆盖系统级安装 |
| pnpm/npm 大版本 | 依赖生态 break | lockfile 兼容性 | 慎升，单独立项 |
| 批量改项目配置文件 | **编码二次转换毁中文**（已实锤） | 文件编码、BOM | 铁律 1/2：字节级 + 备份 + 双指标校验 |

## 四、标准流程

1. **盘查**：`scripts\check-versions.ps1`（或 skill 会话里让 AI 直接跑），输出本机 vs 最新对照表。
2. **出清单**：逐组件标注「已最新 ✅ / 可升级（含风险等级）/ 不建议升（理由）」。
3. **用户勾选** → **逐个组件**出方案（写明改动面、备份位置、回滚方法）＋确认词，回一个动一个。
4. **实证验收**：升级完跑真实命令验证（如 `mvn -version`、`java -version`、`mvn dependency:get` 落盘新仓库），不认"应该好了"。
5. **回写台账**：更新 `references/台账.md`（版本、日期、踩坑），涉及规则的改 coding-rules 走 F 源→commit→`sync-rules.ps1 -Push` 红线。

## 五、脚本用法

```powershell
# 全量体检（本机 vs 最新对照表）
powershell -File F:\idea-workspase-skills\dev-env-upgrade\scripts\check-versions.ps1

# 只看某几类
... -Only Jdk,Maven

# 只输出 Maven 本地仓库路径（单行；垫片 mvninfo 在当前用户任意终端可敲）
... -Repo

# JSON 输出 / 只查本机不联网 / 调超时
... -Json / -Offline / -TimeoutSec 30
```

垫片（`C:\Users\Administrator\.local\bin`，已在用户 PATH）：`mvninfo.cmd` → `-Repo`；`envcheck.cmd` → 全量体检。
