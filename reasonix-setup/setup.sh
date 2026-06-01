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
        if ! command -v fnm &>/dev/null; then
            echo "  安装 fnm（Fast Node Manager）..."
            if is_windows && command -v winget &>/dev/null; then
                winget install Schniz.fnm --accept-package-agreements 2>&1 | tail -3
            elif is_macos && command -v brew &>/dev/null; then
                brew install fnm
            elif command -v curl &>/dev/null; then
                curl -fsSL https://fnm.vercel.app/install | bash
                # shellcheck disable=SC1090
                export PATH="$HOME/.local/share/fnm:$PATH"
            else
                return 1
            fi
            ok "fnm 安装完成"
        else
            ok "fnm 已安装"
        fi

        # 配置 fnm 环境（当前会话）
        if command -v fnm &>/dev/null; then
            eval "$(fnm env --shell bash)" 2>/dev/null || true
        fi

        # 安装 Node LTS
        echo "  安装 Node.js LTS..."
        fnm install --lts 2>&1 | tail -5
        fnm default lts-latest 2>/dev/null || true
        eval "$(fnm env --shell bash)" 2>/dev/null || true

        # 配置 PowerShell profile（Windows）
        if is_windows && command -v powershell &>/dev/null; then
            local ps_profile
            ps_profile=$(powershell.exe -Command 'Write-Host $PROFILE' 2>/dev/null || echo "")
            if [ -n "$ps_profile" ]; then
                local ps_dir
                ps_dir=$(dirname "$ps_profile" | sed 's|\\|/|g')
                mkdir -p "$ps_dir"
                fnm env --use-on-cd --shell powershell | Out-String | Out-File -FilePath "$ps_profile" -Encoding utf8 2>/dev/null || true
            fi
        elif is_macos || is_linux; then
            # 追加到 bashrc/zshrc
            local rc_file=""
            [ -f "$HOME/.bashrc" ] && rc_file="$HOME/.bashrc"
            [ -f "$HOME/.zshrc" ] && rc_file="$HOME/.zshrc"
            if [ -n "$rc_file" ] && ! grep -q "fnm env" "$rc_file" 2>/dev/null; then
                echo 'eval "$(fnm env --use-on-cd)"' >> "$rc_file"
            fi
        fi
    }

    # 尝试 fnm 安装
    if install_via_fnm; then
        eval "$(fnm env --shell bash)" 2>/dev/null || true
    else
        fail "fnm 不可用，无法自动安装 Node.js"
        cat <<HELP >&2

  请手动安装:
  1. 安装 fnm:      https://github.com/Schniz/fnm （推荐，管理多版本）
  2. 安装 Node LTS:  fnm install --lts
  3. 配置 shell:     fnm env --use-on-cd >> 你的 shell 配置文件
  4. 重新运行:       bash setup.sh

HELP
        return 1
    fi

    # 验证
    if command -v node &>/dev/null; then
        ok "Node.js 就绪: $(node --version)"
        ok "npm 就绪: $(npm --version)"
        return 0
    fi
    fail "Node.js 安装后仍不可用，请检查"
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
step "5/5  验证"
# ============================================================

echo ""
echo "  --- 版本信息 ---"
echo "  Node.js   : $(node --version)"
echo "  npm       : $(npm --version)"
echo "  Reasonix  : $(reasonix --version 2>/dev/null || echo '需手动配置')"
if [ "$SKIP_VIBE" = false ]; then
    echo "  Vibe-Trade: $(vibe-trading --version 2>/dev/null || echo '已安装')"
fi
echo ""

# 快速功能测试
echo "  测试 reasonix-tracker..."
bash "$BIN_DIR/reasonix-tracker.sh" research "1+1等于几" 2>/dev/null | head -3 > /dev/null && \
    ok "reasonix-tracker.sh 工作正常" || \
    warn "reasonix-tracker.sh 需要配置 API Key"

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
│  API Key 不会存储在脚本或仓库中，仅在你本地配置。         │
│                                                          │
└──────────────────────────────────────────────────────────┘
EOF
