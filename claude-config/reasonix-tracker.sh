#!/usr/bin/env bash
# ============================================================
# reasonix-tracker.sh — Reasonix 搜索包装脚本
# 用法:
#   bash reasonix-tracker.sh research       "你的查询"   ← 直接搜索
#   bash reasonix-tracker.sh framework      "你的问题"   ← 元思考+分析框架
#   bash reasonix-tracker.sh research-deep  "你的问题"   ← 深度研究（含金融数据）
# ============================================================
# 1. 调用 DeepSeek API（通过 Reasonix）搜索和总结
# 2. 失败自动重试 1 次
# 3. Reasonix 不可用时 exit 2，回退 Claude 原生处理
# 4. research-deep 模式自动检测金融关键词，集成 Vibe-Trading
# ============================================================

set -euo pipefail

MODE="${1:-}"
QUERY="${2:-}"
CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
log_info()  { echo -e "${CYAN}[reasonix-tracker]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[reasonix-tracker WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[reasonix-tracker ERROR]${NC} $*" >&2; }
log_ok()    { echo -e "${GREEN}[reasonix-tracker]${NC} $*" >&2; }

# --- 验证参数 ---
case "$MODE" in
    research|framework|research-deep) ;;
    *) echo "用法: bash reasonix-tracker.sh research|framework|research-deep \"查询内容\"" >&2; exit 1;;
esac
[ -z "$QUERY" ] && { echo "用法: bash reasonix-tracker.sh $MODE \"查询内容\"" >&2; exit 1; }

# --- 定位 reasonix CLI ---
find_reasonix() {
    local found
    found=$(command -v reasonix 2>/dev/null) && { echo "$found"; return 0; }
    local fnm_dir="$HOME/AppData/Roaming/fnm/node-versions"
    if [ -d "$fnm_dir" ]; then
        found=$(ls -dt "$fnm_dir"/v*/installation/reasonix.cmd 2>/dev/null | head -1)
        [ -n "$found" ] && { echo "${found%.cmd}"; return 0; }
    fi
    return 1
}

# --- 确保 Node 在 PATH（reasonix 依赖）---
setup_node_path() {
    local fnm_dir="$HOME/AppData/Roaming/fnm/node-versions"
    if [ -d "$fnm_dir" ]; then
        local node_dir=$(ls -dt "$fnm_dir"/v*/installation 2>/dev/null | head -1)
        [ -n "$node_dir" ] && export PATH="$node_dir:$PATH"
    fi
}

# --- 金融关键词检测 ---
FINANCE_KEYWORDS=(
    投资 股票 ROE 供应链 行业 经济 财务 资产 负债 利润 营收 现金流
    估值 分红 股息 市盈率 市净率 资本开支 毛利率 净利率 资产负债率
    杜邦分析 宏观 货币政策 利率 通胀 GDP 基本面 技术面 回测 量化
    IPO ETF 基金 期货 外汇 比特币 加密货币 股指 纳斯达克 标普
    stake stock ROE supply-chain industry economy finance
    asset liability profit revenue cash-flow valuation dividend
    PE PB capex margin macro monetary fiscal inflation
)

detect_finance_keywords() {
    local query_lower
    query_lower=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')
    local count=0
    local matched=""

    for kw in "${FINANCE_KEYWORDS[@]}"; do
        local kw_lower
        kw_lower=$(echo "$kw" | tr '[:upper:]' '[:lower:]')
        if echo "$query_lower" | grep -qi "$kw_lower"; then
            count=$((count + 1))
            matched="$matched, $kw"
        fi
    done

    # 至少匹配 2 个关键词才触发金融分析
    if [ "$count" -ge 2 ]; then
        log_info "检测到金融关键词 ($count 个: ${matched#, })"
        return 0
    fi
    return 1
}

# --- 调用 Vibe-Trading ---
call_vibe_trading() {
    log_info "调用 Vibe-Trading 金融研究..."

    if ! command -v vibe-trading &>/dev/null; then
        log_warn "Vibe-Trading 未安装，跳过金融数据分析"
        return 1
    fi

    local output
    if output=$(vibe-trading run -p "$QUERY" 2>&1); then
        echo "---"
        echo "## 📊 Vibe-Trading 金融研究"
        echo ""
        echo "$output"
        return 0
    fi
    log_warn "Vibe-Trading 执行失败，继续常规研究"
    return 1
}

# --- 构建 framework 模式的专用 prompt ---
build_framework_prompt() {
    cat <<PROMPT
你是资深分析顾问。在搜索之前，先对问题做"元思考"——确定分析框架而非直接给答案。

请按以下结构输出，每项 1-3 行，总字数控制在 300 字以内：

**问题类型**（选一）：行业竞争分析 / 财务健康评估 / 趋势预测 / 政策影响 / 技术路线比较 / 公司战略评价 / 宏观经济分析

**分析框架**（选一）：波特五力 / SWOT / 杜邦分析 / PEST / 价值链 / 商业飞轮 / 第一性原理

**分析维度**（3-5 个关键维度，每维度一行）

**子问题**（按维度分解的 3-5 个可搜索子问题。每行以 <<<SUBQ>>> 开头，格式如：<<<SUBQ>>>子问题内容）

**注意事项**（1-2 个潜在陷阱或误区）

问题：${QUERY}
PROMPT
}

# --- 构建 decomposed research prompt（子问题逐一搜索）---
build_decompose_prompt() {
    local subqs="$1"
    cat <<PROMPT
请针对以下子问题逐一进行深度研究，每个子问题给出 150-300 字的核心发现：

${subqs}

输出格式：每个子问题以 "## 子问题N: xxx" 开头，然后给出研究发现。
PROMPT
}

# --- 从 framework 输出中提取子问题 ---
extract_sub_questions() {
    local framework_output="$1"
    echo "$framework_output" | grep '<<<SUBQ>>>' | sed 's/<<<SUBQ>>>//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# --- 逐一搜索每个子问题 ---
search_sub_questions() {
    local sub_count=0
    local results=""

    while IFS= read -r subq; do
        [ -z "$subq" ] && continue
        sub_count=$((sub_count + 1))
        log_ok "搜索子问题 $sub_count: ${subq:0:60}..."

        echo ""
        echo "## 子问题${sub_count}: ${subq}"
        echo ""

        setup_node_path
        local reasonix_bin
        reasonix_bin=$(find_reasonix) || { log_warn "未找到 reasonix CLI"; continue; }
        "$reasonix_bin" run "research: ${subq}" 2>&1

    done <<< "$1"

    log_info "完成 $sub_count 个子问题的搜索"
}

# --- 调用 reasonix run ---
call_reasonix() {
    log_info "调用 Reasonix | 模式: ${MODE}..."

    setup_node_path
    local reasonix_bin
    reasonix_bin=$(find_reasonix) || { log_warn "未找到 reasonix CLI"; return 1; }
    log_info "定位: $reasonix_bin"

    case "$MODE" in
        framework)
            local prompt
            prompt=$(build_framework_prompt)
            "$reasonix_bin" run "$prompt" 2>&1
            ;;
        research)
            "$reasonix_bin" run "research: ${QUERY}" 2>&1
            ;;
        research-deep)
            # 1. 先做框架分析（捕获输出用于后续提取子问题）
            log_ok "第一步：元思考 → 分析框架..."
            local framework_prompt framework_output
            framework_prompt=$(build_framework_prompt)
            echo "## 📐 分析框架"
            framework_output=$("$reasonix_bin" run "$framework_prompt" 2>&1)
            echo "$framework_output"
            echo ""

            # 2. 初步搜索
            log_ok "第二步：初步研究搜索..."
            echo "## 🔍 初步研究"
            "$reasonix_bin" run "research: ${QUERY}" 2>&1
            echo ""

            # 3. 提取子问题 → 逐一搜索
            local sub_questions
            sub_questions=$(extract_sub_questions "$framework_output")
            if [ -n "$sub_questions" ]; then
                log_ok "第三步：按框架逐一搜索子问题..."
                echo "## 📋 子问题深度研究"
                search_sub_questions "$sub_questions"
            else
                log_warn "未提取到子问题，跳过逐一搜索"
            fi
            echo ""

            # 4. 检测金融关键词 → 调用 Vibe-Trading（可选，失败不影响整体）
            if detect_finance_keywords; then
                log_ok "第四步：金融数据获取..."
                call_vibe_trading || log_warn "Vibe-Trading 不可用（跳过），需运行 vibe-trading init 配置"
            fi
            return 0
            ;;
    esac
}

# ============================================================
# 主流程
# ============================================================
log_info "开始 | 模式: ${MODE} | 查询: ${QUERY}"

# 尝试 1
call_reasonix && exit 0

# 重试 1 次
log_warn "失败，重试..."
sleep 2
call_reasonix && exit 0

# 回退：提示 Claude 使用原生搜索
log_error "Reasonix 不可用，回退到 Claude 原生 WebSearch"
cat <<EOF
[REASONIX_FALLBACK]
Reasonix 不可用。
请使用 Claude Code 原生 WebSearch 完成搜索，并告知用户回退方案。
搜索内容: ${QUERY}
EOF
exit 2
