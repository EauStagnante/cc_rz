# TROUBLESHOOTING.md — 安装常见问题与解决方法

> 本文档记录了 Reasonix 环境部署过程中遇到的实际问题及修复方案。
> 每个问题已在新版 `setup.sh` 中修复；如果你手动安装遇到类似情况，可参考对应条目。

## 目录

| # | 问题 | 状态 |
|---|------|------|
| 1 | [winget 安装 fnm 时报 "在提示中读取输入时出错"](#1-winget-安装-fnm-时报错) | ✅ 已修复 |
| 2 | [winget 下载 GitHub 包时网络错误 0x80072efd](#2-winget-下载-网络错误) | ✅ 已处理 |
| 3 | [fnm 安装后当前 shell 找不到 fnm 命令](#3-fnm-安装后-shell-找不到命令) | ✅ 已修复 |
| 4 | [新终端找不到 node / npm / reasonix](#4-新终端找不到-node--npm--reasonix) | ✅ 已修复 |
| 5 | [Git Bash 启动时不加载 .bashrc](#5-git-bash-不加载-bashrc) | ✅ 已修复 |
| 6 | [PowerShell 中 reasonix 报错 "禁止运行脚本"](#6-powershell-中-reasonix-报错) | ✅ 已修复 |
| 7 | [reasonix-tracker.sh 报 "未设置 DEEPSEEK_API_KEY"](#7-未设置-api-key) | ⚠️ 需手动配置 |

---

## 1. winget 安装 fnm 时报错

**现象**：运行 `winget install Schniz.fnm` 时报错：

```
执行此命令时发生意外错误：
0x8a150042 : 在提示中读取输入时出错
```

**原因**：winget 首次运行时需要接受**两类协议**：

- `--accept-source-agreements` — 软件源协议条款
- `--accept-package-agreements` — 包许可协议

旧版 `setup.sh` 只传了 `--accept-package-agreements`，缺少源协议参数。在非交互式终端中，winget 无法弹出 Y/N 确认框，导致输入读取失败。

**修复**：winget 命令加上两个参数：

```bash
winget install Schniz.fnm \
    --accept-source-agreements \
    --accept-package-agreements \
    --silent
```

**手动解决**：如果你在交互式 PowerShell 中安装，可以先接受协议：

```powershell
winget source update --accept-source-agreements
winget install Schniz.fnm --accept-package-agreements
```

---

## 2. winget 下载网络错误

**现象**：winget 下载安装包时报错：

```
InternetOpenUrl() failed.
0x80072efd : unknown error
```

**原因**：winget 使用 WinINet 下载，受系统代理/网络环境影响。`0x80072efd` 通常表示无法连接目标服务器（GitHub 被墙或网络不稳定）。

**解决**：

- **检查网络**：确认 GitHub 是否可达：`curl -sI https://github.com`
- **使用代理**：如使用 VPN/Clash 等，确认系统代理已开启
- **备用方案**：如果 winget 始终不可用，可手动下载 fnm：

```bash
# 从 GitHub Releases 下载 fnm（在浏览器中打开）
# https://github.com/Schniz/fnm/releases/latest
# 下载 fnm-windows.zip → 解压 → 将 fnm.exe 放入 PATH
```

---

## 3. fnm 安装后 shell 找不到命令

**现象**：winget 显示安装成功，但 `fnm --version` 提示 `command not found`。

**原因**：winget 修改了系统 PATH 环境变量，但**不会刷新当前 shell 的 PATH**。只有新启动的进程才能看到变更。

**修复**（新版 `setup.sh` 已自动处理）：

```bash
# 手动定位 fnm.exe 并加入当前 PATH
export PATH="$HOME/AppData/Local/Microsoft/WinGet/Packages/Schniz.fnm_Microsoft.Winget.Source_8wekyb3d8bbwe:$PATH"
```

setup.sh 现在包含 `find_fnm_exe()` 函数，自动在以下位置搜索 fnm：

1. 系统 PATH（`command -v fnm`）
2. winget Links 目录
3. winget Packages 目录（遍历搜索 `fnm.exe`）

---

## 4. 新终端找不到 node / npm / reasonix

**现象**：安装完成后，打开新终端执行 `node --version`、`reasonix --version` 提示找不到命令。

**原因**：Node.js 由 fnm 管理，全局包安装在 `~/AppData/Roaming/fnm/node-versions/v<版本>/installation/` 下，该目录未添加到 Windows 系统 PATH。只有通过 `fnm env` 激活的 shell 才能找到它们。

**修复**（新版 `setup.sh` 已自动处理）：

将 Node 安装目录直接加入 Windows **用户 PATH**：

```powershell
# PowerShell（管理员不需要）
$installPath = "$env:APPDATA\fnm\node-versions\v24.16.0\installation"
$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($currentPath -notlike "*$installPath*") {
    [Environment]::SetEnvironmentVariable('PATH', "$installPath;$currentPath", 'User')
}
```

> **注意**：PATH 修改后需**重新打开终端**才能生效。

**验证**：

```bash
# 新终端中执行：
node --version      # 应输出 v24.16.0
npm --version       # 应输出 11.x.x
reasonix --version  # 应输出 0.x.x
```

---

## 5. Git Bash 不加载 .bashrc

**现象**：在 Git Bash 中每次都要手动运行 `fnm env` 才能找到 node。

**原因**：Git Bash 以**登录 shell** 方式启动时只加载 `.bash_profile`，不加载 `.bashrc`。

**修复**（新版 `setup.sh` 已自动处理）：

创建 `~/.bash_profile`，在其中 source `.bashrc`：

```bash
cat > ~/.bash_profile << 'EOF'
# Source .bashrc if it exists (Git Bash doesn't do this by default)
if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi
EOF
```

**验证**：重新打开 Git Bash，直接运行 `node --version` 应正常输出。

---

## 6. PowerShell 中 reasonix 报错

**现象**：在 PowerShell 中运行 `reasonix --version` 时报错：

```
reasonix : 无法加载文件 C:\Users\...\reasonix.ps1，因为在此系统上禁止运行脚本。
+ CategoryInfo          : SecurityError: (:) []，PSSecurityException
+ FullyQualifiedErrorId : UnauthorizedAccess
```

**原因**：PowerShell 默认执行策略是 `Restricted`，禁止运行任何 `.ps1` 脚本。`reasonix` 在 PowerShell 中被解析为 `reasonix.ps1`。

**修复**（新版 `setup.sh` 已自动处理）：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**替代方案**（不需要改策略）：

- 使用 `.cmd` 后缀：`reasonix.cmd --version`
- 切换到 Git Bash：直接运行 `reasonix`（不受 PowerShell 策略限制）

---

## 7. 未设置 API Key

**现象**：运行 `reasonix-tracker.sh` 时报错：

```
未设置 DEEPSEEK_API_KEY 且标准输入不是 TTY（无法交互式输入）。
```

**原因**：Reasonix 需要 DeepSeek API Key 才能调用搜索服务。这是设计行为——API Key 不会存储在仓库或脚本中。

**解决**（需手动操作）：

```bash
# 1. 交互式配置 API Key
reasonix setup
# → 粘贴你的 DeepSeek API Key

# 2. 验证配置
reasonix doctor
# → 确认 "api key ✓"
```

配置后 API Key 存储在 `~/.reasonix/config.json`，不会上传到仓库。

---

## 快速诊断清单

遇到问题时，按以下顺序检查：

```
□ 终端是否是新开的？（PATH 修改后必须重启终端）
□ node --version 是否正常？
□ reasonix --version 是否正常？
□ Windows 环境变量 → 用户变量 → Path 中是否有 fnm 安装目录？
□ PowerShell 执行策略是否为 RemoteSigned？
□ reasonix doctor 是否显示 "api key ✓"？
□ ~/.bash_profile 是否存在并 source 了 ~/.bashrc？
```

如果以上都无法解决，请查看项目 [SETUP.md](SETUP.md) 了解完整部署流程。
