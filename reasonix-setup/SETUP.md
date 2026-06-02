# SETUP.md — Reasonix 深度研究环境部署指南

> 给新电脑上的 Claude Code 看：读完本文件后，按步骤执行即可完成全部部署。

## 前置条件

- [ ] 已安装 Claude Code
- [ ] 已安装 Node.js ≥20.10（推荐 fnm 管理版本）
- [ ] 已安装 Git for Windows（bash 环境）

## 一键部署

在新电脑上 clone 本仓库后，进入安装目录执行：

```bash
cd reasonix-setup
bash setup.sh
```

> 或从项目根目录：`bash reasonix-setup/setup.sh`

该脚本自动完成：
1. 环境检查 + 安装 Node.js ≥20（通过 fnm，如缺失）
2. 安装 Reasonix（`npm install -g reasonix`）
3. 安装 Vibe-Trading（`pip install vibe-trading-ai`，可选跳过）
4. 部署 `CLAUDE.md` → `~/.claude/CLAUDE.md`
5. 部署 `reasonix-tracker.sh` → `~/bin/reasonix-tracker.sh`
6. 配置系统 PATH（所有终端通用）
7. 配置 Bash / PowerShell 环境持久化

如果不需要金融分析功能，跳过 Vibe-Trading：

```bash
bash setup.sh --skip-vibe
```

## 安装完成后 — 手动配置

### 1. 重启终端（重要！）

`setup.sh` 修改了系统 PATH，**必须关掉所有旧终端，重新打开新终端**，`node` / `npm` / `reasonix` 才能使用。

### 2. 配置 API Key

`setup.sh` 跑完后，还需你手动完成（需要你的 DeepSeek API Key）：

| # | 操作 | 命令 |
|---|------|------|
| 1 | 配置 Reasonix | `reasonix setup` → 粘贴 API Key |
| 2 | 验证 Reasonix | `reasonix doctor`（确认 api key ✓） |
| 3 | 配置 Vibe-Trading | `vibe-trading init` → 选 DeepSeek → 粘贴 API Key（如需金融分析） |

> **API Key 不会存储在脚本或仓库中**，仅在你本地 `~/.reasonix/config.json` 和 `~/.vibe-trading/.env` 中。本仓库不含任何密钥。

## 验证管线

```bash
# 基础搜索
bash ~/bin/reasonix-tracker.sh research "Python最新版本是多少"

# 元思考框架
bash ~/bin/reasonix-tracker.sh framework "AI芯片行业竞争格局"

# 深度研究（含金融数据）
bash ~/bin/reasonix-tracker.sh research-deep "分析英伟达ROE趋势"
```

## 文件说明

| 文件 | 部署位置 | 用途 |
|------|---------|------|
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 全局搜索规则（Reasonix 100% 走） |
| `reasonix-tracker.sh` | `~/bin/reasonix-tracker.sh` | 搜索包装脚本（research / framework / research-deep） |
| `setup.sh` | `reasonix-setup/` 目录 | 一键部署脚本 |
| `TROUBLESHOOTING.md` | `reasonix-setup/` 目录 | 常见问题与解决方法 |

## 遇到问题？

查看 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)，记录了安装过程中 7 个常见问题及解决方案：

- winget 协议接受失败
- 网络下载错误
- shell 找不到命令
- 新终端 PATH 不生效
- Git Bash 不加载 .bashrc
- PowerShell 执行策略阻止
- API Key 未配置

## 工作原理

```
Claude Code 想搜索
  → CLAUDE.md 规则：必须用 reasonix-tracker.sh
  → reasonix-tracker.sh：
      research      → Reasonix 直接搜索
      framework     → 元思考 → 分析框架 + 子问题
      research-deep → 框架 + 初步搜索 + 逐一子问题 + Vibe-Trading
  → 均失败 exit 2 → 回退 Claude 原生 WebSearch
```
