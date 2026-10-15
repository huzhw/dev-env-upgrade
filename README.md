# dev-env-upgrade — 开发环境升级医生

> **适用平台：** 覆盖 DSH 消费端（`~/.dsh/skills`），同时兼容挂载到 Claude Code / Codex / ZCode 技能目录。

JDK / Maven / IDEA / Node / Python / Go / Rust / CLI 工具链的版本体检、最新版查询、升级风险评级与安全落地：一键盘查对照表、实测可用查询口径（含 403 端点黑名单）、风险矩阵、字节级批量改动铁律。

## 相关技能

- [agent-config-sync-check](https://github.com/huzhw/agent-config-sync-check)：八端同步守卫：链接/硬链接/README 同步检查与修复
- [git-commit](https://github.com/huzhw/git-commit-skill)：Git 提交规范
- [daily-record-gitlab-md](https://github.com/huzhw/daily-record-gitlab-md-skill)：日报记录（第一步）
- [daily-merge-gitlab-excel](https://github.com/huzhw/daily-merge-gitlab-excel-skill)：日报合并（手动兜底，已由日报管家接管，不推荐）
- [code-check](https://github.com/huzhw/code-check-skill)：增量代码隐患检查
- [deepseek-harness-plugin-doctor](https://github.com/huzhw/deepseek-harness-plugin-doctor)：DeepSeek Harness 插件与升级体检医生
- [deepseek-harness-settings-curator](https://github.com/huzhw/deepseek-harness-settings-curator)：DeepSeek Harness 模型配置梳理
- [reread-rules](https://github.com/huzhw/reread-rules-skill)：重载 CLAUDE.md / AGENTS.md 规则
- [coding-rules](https://github.com/huzhw/coding-rules)：编码规则库（独立仓库，非 skill）
- [daily-report-panel](https://github.com/huzhw/daily-report-panel)：日报管家（关联仓库，非 skill，自动合并/导出/发件）

---

## 解决了什么问题

开发环境升级最贵的不是下载安装，而是**三样摸不着的东西**：

- 哪个端点能查到真版本？——Adoptium 的 `release_names` 永远 404、阿里云无 Adoptium 镜像、JetBrains 数据端点被本机策略代理拦、`golang/go` 的 tags 返回 2012 年老标签……每个坑都要现场踩一遍
- 升了会不会炸？——切 JDK 有 cacerts 信任库差异和弱算法收紧、Maven 升级有 46 个存量项目 workspace.xml 的路径散落、IDEA 目录名滞后会造成"要不要升级"的误判
- 怎么改才不毁现场？——PS 5.1 下 `Get-Content -Raw` 读 UTF-8 中文必乱码，2026-10-15 的 workspace.xml 二次编码事故就是教训

这个技能把**查询口径（含黑名单）+ 风险矩阵 + 字节级铁律 + 本机台账**固化下来，下次一句"还有啥能升级"直接出全表。

## 使用

触发词（任选）：`升级JDK`、`升级Maven`、`环境体检`、`版本体检`、`还有啥能升级`、`查最新版本`、`升级IDEA`、`环境盘点`、`dev-env-upgrade`、`jdk1.8升到最新`、`mvninfo`。

一键盘查（**当前用户**任意终端；垫片在 User PATH 而非 Machine PATH，换账户敲不到）：

```powershell
envcheck        # 全量：本机版本 vs 最新版对照表
mvninfo         # 单行输出 Maven 本地仓库路径（含生效 settings.xml 判定）
mvninfo -Json   # 同上，结构化输出：repo / source / conf / exists
```

## 文件结构

```
dev-env-upgrade/
├── SKILL.md                     ← 技能定义（台账/口径表/风险矩阵/流程/铁律）
├── README.md                    ← 本文档
├── JUNCTION说明.md              ← Junction 挂接说明
├── .gitignore
├── scripts/
│   ├── check-versions.ps1       ← 一键体检脚本（纯 ASCII，单点失败不中断）
│   ├── versions-config.json     ← 查询端点与标签（中文外置，UTF-8）
│   ├── mvninfo.cmd              ← 垫片源（转发 -Repo）
│   └── envcheck.cmd             ← 垫片源（转发全量体检）
└── references/
    └── 台账.md                  ← 本机环境台账 + 历史升级记录 + 踩坑
```

## 安装

五端已在消费端目录建好 Junction（CodeBuddy 经 `.claude` 复用，无独立链接；本仓库为唯一数据源）：

```bash
C:\Users\Administrator\.claude\skills\dev-env-upgrade
C:\Users\Administrator\.dsh\skills\dev-env-upgrade
C:\Users\Administrator\.codex\skills\dev-env-upgrade
C:\Users\Administrator\.zcode\skills\dev-env-upgrade
C:\Users\Administrator\.qoder-cn\skills\dev-env-upgrade
```

## 许可

MIT
