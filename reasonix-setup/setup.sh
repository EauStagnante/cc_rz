#!/usr/bin/env bash
# ============================================================
# setup.sh — Reasonix 深度研究环境一键部署
# 用法: bash setup.sh
# 或:   bash setup.sh --skip-vibe   跳过 Vibe-Trading（非金融用途）
# ============================================================
set -euo pipefail

SKIP_VIBE=false
[[ "${1:-}" == "--skip-vibe" ]] && SKIP_VIBE=true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
step() { echo -e "\n${CYAN}== ${*} ==${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/bin"
CLAUDE_DIR="$HOME/.claude"
NODE_MIN_VERSION=20

# --- 判断操作系统 ---
is_windows() { [[ "$(uname -s)" == *"MINGW"* || "$(uname -s)" == *"MSYS"* || "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; }
is_macos()   { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux()   { [[ "$(uname -s)" == "Linux" ]]; }

# ============================================================
# 辅助函数：查找 fnm.exe（Windows 下 winget 安装后需手动定位）
# ============================================================
find_fnm_exe() {
    local found

    # 1) 直接 PATH 中查找
    found=$(command -v fnm 2>/dev/null) && { echo "$found"; return 0; }

    # 2) winget Links 目录
    found="$HOME/AppData/Local/Microsoft/WinGet/Links/fnm.exe"
    [ -f "$found" ] && { echo "$found"; return 0; }

    # 3) winget Packages 目录（安装但未被 Links 链接时）
    if [ -d "$HOME/AppData/Local/Microsoft/WinGet/Packages" ]; then
        found=$(find "$HOME/AppData/Local/Microsoft/WinGet/Packages" -name "fnm.exe" -type f 2>/dev/null | head -1)
        [ -n "$found" ] && { echo "$found"; return 0; }
    fi

    return 1
}

# ============================================================
# 辅助函数：确保 fnm 在当前 shell 可用
# ============================================================
ensure_fnm_in_path() {
    local fnm_exe
    fnm_exe=$(find_fnm_exe) || return 1
    local fnm_dir
    fnm_dir=$(dirname "$fnm_exe")
    # 转为 Unix 路径
    fnm_dir=$(echo "$fnm_dir" | sed 's|\\|/|g')
    case ":$PATH:" in
        *":$fnm_dir:"*) ;;
        *) export PATH="$fnm_dir:$PATH" ;;
    esac
}

# ============================================================
step "0/5  安装 Node.js（如缺失）"
# ============================================================

ensure_nodejs() {
    # 已有足够版本
    if command -v node &>/dev/null; then
        local v
        v=$(node --version | sed 's/v//' | cut -d. -f1)
        if [ "$v" -ge "$NODE_MIN_VERSION" ]; then
            ok "Node.js $(node --version)（≥ v${NODE_MIN_VERSION}）"
            return 0
        fi
    fi

    warn "未检测到 Node.js ≥ v${NODE_MIN_VERSION}，尝试安装..."

    # --- fnm 方式（首选，跨平台，支持版本管理）---
    install_via_fnm() {
        # 先装 fnm
        if ! find_fnm_exe &>/dev/null; then
            echo "  安装 fnm（Fast Node Manager）..."
            if is_windows && command -v winget &>/dev/null; then
                # --accept-source-agreements 是必须的！首次运行 winget 需要接受源协议
                # 参考: TROUBLESHOOTING.md #1
                winget install Schniz.fnm \
                    --accept-source-agreements \
                    --accept-package-agreements \
                    --silent 2>&1 | tail -5
            elif is_macos && command -v brew &>/dev/null; then
                brew install fnm
            elif command -v curl &>/dev/null; then
                curl -fsSL https://fnm.vercel.app/install | bash
                export PATH="$HOME/.local/share/fnm:$PATH"
            else
                return 1
            fi

            # 将 fnm 加入当前 PATH（winget 的 PATH 修改不会立即生效）
            ensure_fnm_in_path || {
                fail "fnm 安装后无法定位，请检查 TROUBLESHOOTING.md"
                return 1
            }
            ok "fnm 安装完成: $(fnm --version 2>/dev/null || echo 'ok')"
        else
            ensure_fnm_in_path
            ok "fnm 已安装: $(fnm --version 2>/dev/null || echo 'ok')"
        fi

        # 安装 Node LTS
        echo "  安装 Node.js LTS..."
        fnm install --lts 2>&1 | tail -5
        fnm default lts-latest 2>/dev/null || true
        eval "$(fnm env --shell bash)" 2>/dev/null || true

        # 记录 Node 安装目录（后续要加入系统 PATH）
        NODE_INSTALL_DIR=$(fnm exec --using default node -e "console.log(process.execPath)" 2>/dev/null | xargs dirname 2>/dev/null || echo "")
        if [ -z "$NODE_INSTALL_DIR" ]; then
            # fallback: 根据 fnm 默认版本拼接路径
            local default_ver
            default_ver=$(fnm default 2>/dev/null || fnm list 2>/dev/null | grep default | awk '{print $2}')
            NODE_INSTALL_DIR="$HOME/AppData/Roaming/fnm/node-versions/${default_ver:-v24.16.0}/installation"
        fi
        # 转 Unix 路径
        NODE_INSTALL_DIR=$(echo "$NODE_INSTALL_DIR" | sed 's|\\|/|g')
        export NODE_INSTALL_DIR
    }

    # 尝试 fnm 安装
    if install_via_fnm; then
        eval "$(fnm env --shell bash)" 2>/dev/null || true
    else
        fail "fnm 不可用，无法自动安装 Node.js"
        cat <<HELP >&2

  请手动安装:
  1. 安装 fnm:      https://github.com/Schniz/fnm （推荐用 winget）
  2. 安装 Node LTS:  fnm install --lts
  3. 重新运行:       bash setup.sh

HELP
        return 1
    fi

    # 验证
    if command -v node &>/dev/null; then
        ok "Node.js 就绪: $(node --version)"
        ok "npm 就绪: $(npm --version)"
        return 0
    fi
    fail "Node.js 安装后仍不可用，请检查 TROUBLESHOOTING.md"
    return 1
}

ensure_nodejs || exit 1

# ============================================================
step "1/5  环境检查（其余依赖）"
# ============================================================

# npm（Node 自带，二次确认）
if command -v npm &>/dev/null; then
    ok "npm $(npm --version)"
else
    fail "npm 不可用"
    exit 1
fi

# Python (Vibe-Trading 需要)
if command -v python3 &>/dev/null || command -v python &>/dev/null; then
    ok "Python 可用"
else
    if [ "$SKIP_VIBE" = false ]; then
        warn "Python 未安装，将跳过 Vibe-Trading（金融数据分析）"
        SKIP_VIBE=true
    fi
fi

# pip
if command -v pip &>/dev/null || command -v pip3 &>/dev/null; then
    ok "pip 可用"
else
    if [ "$SKIP_VIBE" = false ]; then
        warn "pip 未安装，将跳过 Vibe-Trading"
        SKIP_VIBE=true
    fi
fi

# ============================================================
step "2/5  安装 Reasonix（npm 全局包）"
# ============================================================

if command -v reasonix &>/dev/null; then
    ok "Reasonix 已安装: $(reasonix --version 2>/dev/null || echo 'ok')"
else
    echo "  安装中..."
    npm install -g reasonix && ok "Reasonix 安装完成" || fail "Reasonix 安装失败"
fi

# ============================================================
step "3/5  安装 Vibe-Trading"
# ============================================================

if [ "$SKIP_VIBE" = false ]; then
    if command -v vibe-trading &>/dev/null; then
        ok "Vibe-Trading 已安装"
    else
        echo "  安装中..."
        pip install vibe-trading-ai 2>&1 | tail -3 && ok "Vibe-Trading 安装完成" || {
            warn "Vibe-Trading 安装失败，跳过（不影响核心搜索功能）"
            SKIP_VIBE=true
        }
    fi
else
    warn "已跳过 Vibe-Trading（金融分析需要时再装: pip install vibe-trading-ai）"
fi

# ============================================================
step "4/5  部署文件"
# ============================================================

# 创建目录
mkdir -p "$BIN_DIR"
mkdir -p "$CLAUDE_DIR"

# reasonix-tracker.sh → ~/bin/
cp "$SCRIPT_DIR/reasonix-tracker.sh" "$BIN_DIR/reasonix-tracker.sh"
chmod +x "$BIN_DIR/reasonix-tracker.sh"
ok "reasonix-tracker.sh → $BIN_DIR/"

# CLAUDE.md → ~/.claude/
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    warn "~/.claude/CLAUDE.md 已存在，备份为 CLAUDE.md.bak"
    cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.bak"
fi
cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
ok "CLAUDE.md → $CLAUDE_DIR/"

# ============================================================
step "5/5  系统级配置 + 验证"
# ============================================================

# --- 5a. 将 Node 安装目录加入 Windows 用户 PATH（所有终端通用）---
if is_windows; then
    echo "  配置系统 PATH..."
    # 确认安装目录
    if [ -z "${NODE_INSTALL_DIR:-}" ]; then
        NODE_INSTALL_DIR=$(dirname "$(which node 2>/dev/null)" 2>/dev/null || echo "")
    fi
    # 转 Windows 路径格式
    node_path_win=""
    node_path_win=$(echo "$NODE_INSTALL_DIR" | sed 's|^/c/|C:\\|' | sed 's|/|\\|g')

    if [ -n "$node_path_win" ] && [ -d "$NODE_INSTALL_DIR" ]; then
        # 用 PowerShell 添加到用户 PATH（避免 setx 1024 字符截断）
        powershell.exe -Command "
\$installPath = '$node_path_win'
\$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (\$currentPath -notlike \"*\$installPath*\") {
    \$newPath = \"\$installPath;\$currentPath\"
    [Environment]::SetEnvironmentVariable('PATH', \$newPath, 'User')
    Write-Host '  ✓ 已添加 ' \$installPath ' 到用户 PATH'
} else {
    Write-Host '  ✓ 该路径已在用户 PATH 中'
}
" 2>&1 | tail -1
        ok "Windows 用户 PATH 已更新"
    else
        warn "无法确定 Node 安装目录，跳过系统 PATH 配置"
        warn "请手动将 Node 安装目录添加到系统 PATH（参考 TROUBLESHOOTING.md #4）"
    fi
fi

# --- 5b. Bash 配置（fnm 持久化）---
if is_windows; then
    # Git Bash 不自动加载 .bashrc，需要通过 .bash_profile 引入
    if [ ! -f "$HOME/.bash_profile" ]; then
        cat > "$HOME/.bash_profile" <<'BASHPROFILE'
# Source .bashrc if it exists (Git Bash doesn't do this by default)
if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi
BASHPROFILE
        ok "已创建 ~/.bash_profile（Git Bash 启动时自动加载 .bashrc）"
    elif ! grep -q ".bashrc" "$HOME/.bash_profile" 2>/dev/null; then
        echo '
# Source .bashrc
if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi' >> "$HOME/.bash_profile"
        ok "已更新 ~/.bash_profile"
    fi

    # 配置 .bashrc 加载 fnm 环境
    if ! grep -q "fnm" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" <<'BASHRC'

# === fnm (Fast Node Manager) ===
# 查找 fnm
if [ -f "$HOME/AppData/Local/Microsoft/WinGet/Links/fnm.exe" ]; then
    export PATH="$HOME/AppData/Local/Microsoft/WinGet/Links:$PATH"
elif [ -d "$HOME/AppData/Local/Microsoft/WinGet/Packages" ]; then
    FNM_DIR=$(find "$HOME/AppData/Local/Microsoft/WinGet/Packages" -name "fnm.exe" -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
    [ -n "$FNM_DIR" ] && export PATH="$FNM_DIR:$PATH"
fi
# 加载 fnm 环境
eval "$(fnm env --shell bash)" 2>/dev/null || true
BASHRC
        ok "fnm 已添加到 ~/.bashrc"
    fi
fi

# --- 5c. PowerShell 执行策略（解决 reasonix.ps1 无法运行）---
if is_windows && command -v powershell &>/dev/null; then
    echo "  配置 PowerShell 执行策略..."
    current_policy=""
    current_policy=$(powershell.exe -Command "Get-ExecutionPolicy -Scope CurrentUser" 2>/dev/null | tr -d '\r\n')
    if [ "$current_policy" = "Restricted" ] || [ "$current_policy" = "Undefined" ]; then
        powershell.exe -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>&1 | tail -1
        ok "PowerShell 执行策略已设为 RemoteSigned（允许运行 reasonix.ps1）"
    else
        ok "PowerShell 执行策略已是 $current_policy"
    fi
fi

# --- 验证 ---
echo ""
echo "  --- 版本信息 ---"
echo "  Node.js   : $(node --version 2>/dev/null || echo '需重启终端')"
echo "  npm       : $(npm --version 2>/dev/null || echo '需重启终端')"
echo "  Reasonix  : $(reasonix --version 2>/dev/null || echo '需重启终端')"
if [ "$SKIP_VIBE" = false ]; then
    echo "  Vibe-Trade: $(vibe-trading --version 2>/dev/null || echo '已安装')"
fi
echo ""

# 快速功能测试
echo "  测试 reasonix-tracker..."
bash "$BIN_DIR/reasonix-tracker.sh" research "1+1等于几" 2>/dev/null | head -3 > /dev/null && \
    ok "reasonix-tracker.sh 工作正常" || \
    warn "reasonix-tracker.sh 需要配置 API Key（运行 reasonix setup）"

# ============================================================
# 安装完成 — 请手动完成以下配置
# ============================================================

cat <<EOF

┌──────────────────────────────────────────────────────────┐
│                                                          │
│  环境安装完成！请手动完成以下配置（需要你的 API Key）：    │
│                                                          │
│  □ 配置 Reasonix                                        │
│     reasonix setup                                       │
│     → 粘贴你的 DeepSeek API Key                          │
│     → 验证: reasonix doctor                              │
│                                                          │
EOF

if [ "$SKIP_VIBE" = false ]; then
    cat <<EOF
│  □ 配置 Vibe-Trading（如需金融分析）                     │
│     vibe-trading init                                    │
│     → 选 DeepSeek → 粘贴 API Key                        │
│                                                          │
EOF
fi

cat <<EOF
│  □ 验证管线                                             │
│     bash ~/bin/reasonix-tracker.sh research "测试查询"    │
│     bash ~/bin/reasonix-tracker.sh research-deep "ROE分析"│
│                                                          │
│  □ 新开终端验证（重要！）                                 │
│     关掉所有旧终端 → 重新打开 → 运行:                     │
│       node --version                                     │
│       reasonix --version                                 │
│                                                          │
│  ⚠ 如果仍不可用，查看 TROUBLESHOOTING.md                 │
│                                                          │
│  API Key 不会存储在脚本或仓库中，仅在你本地配置。         │
│                                                          │
└──────────────────────────────────────────────────────────┘
EOF
