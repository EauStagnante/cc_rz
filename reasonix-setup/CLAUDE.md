# CLAUDE.md — 全局规则（所有项目加载）

## 项目概况

当未指定项目时，使用中文回复，技术讨论中英文术语不翻译。

## 搜索规则（硬约束）

所有搜索研究类任务 **100% 走 Reasonix，绝对禁止绕过**。

Claude Code 自身需要查外部信息时，**必须先用 Reasonix，禁止直接调 WebSearch/WebFetch**：

```
Claude 想调 WebSearch/WebFetch → 停下 → 改用:
  bash reasonix-tracker.sh research "想查的内容"
```

**回退条件（唯一允许用 WebSearch 的情况）：**
- Reasonix 被禁用或 reasonix-tracker.sh 返回 exit code 2（脚本内部已重试）
- 回退时必须以 "⚠️ Reasonix 不可用，已回退到 Claude 原生搜索" 告知用户

**禁止的行为：**
- 第一步就调 WebSearch/WebFetch
- "快速搜一下"的想法 —— 不存在快速，只能走 Reasonix
- Reasonix 和 WebSearch 并发调用

**回答格式：**

```
---
🔍 搜索来源: Reasonix (DeepSeek API)
```

### 复杂问题的元思考流程（framework 模式）

遇到以下类型问题时，**先做元思考再搜索**：
- 行业/竞争/市场分析、财务评估、趋势预测、战略评价、技术路线比较、宏观政策影响

**三步流程：**

```
第一步: bash reasonix-tracker.sh framework "问题"
       → 输出结构化框架：问题类型、分析框架、分析维度、子问题、注意事项

第二步: 对每个子问题执行 bash reasonix-tracker.sh research "子问题"
       → 收集各维度答案

第三步: 按框架综合所有结果，给出结构化分析报告
```

**示例：**
```
bash reasonix-tracker.sh framework "拼多多供应链投资会不会导致模式越来越重资产"
→ 返回：问题类型=公司战略评价+财务健康，框架=杜邦分析+商业模式分析
→ 子问题：①资产结构趋势对比 ②ROE历史趋势 ③投资性质 ④Temu海外仓 ⑤沃尔玛亚马逊历史
→ 对每个子问题调用 research，最后综合
```

### 金融/投资类问题的深度研究（research-deep 模式）

当用户问题涉及 **投资、股票、财务、经济、供应链** 等金融领域时，使用 `research-deep` 一键完成完整研究管线：

```
bash reasonix-tracker.sh research-deep "问题"
```

**脚本自动完成三步：**
1. 元思考 → 输出分析框架
2. Reasonix 深度研究 → 网络搜索+分析
3. 金融关键词检测 → 自动调用 Vibe-Trading 获取财务数据/杜邦拆解/回测（研究结果以 "📊 Vibe-Trading 金融研究" 区块呈现）

**触发条件：** 查询中匹配 ≥2 个金融关键词（如"ROE"+"资产结构"），脚本自动激活金融通道。

**示例：**
```
bash reasonix-tracker.sh research-deep "分析拼多多供应链投资对ROE的影响"
→ 自动检测：财务+供应链+ROE ≥2 关键词
→ 输出：分析框架 + 网络研究 + Vibe-Trading 财务数据
```

## 约定

- 回答前先查代码和 git 状态，不凭空猜测
- 文件路径引用使用相对路径的 markdown 链接：`[file.ts](src/file.ts)`
- 修改文件前先读文件内容，不假设文件内容
- 涉及多文件/架构级修改时，先用 EnterPlanMode 制定方案再执行
- 代码风格匹配上下文，不引入项目未使用的模式

## 硬约束

- 不修改 `.git/`、`.claude/` 下的配置文件（除非明确要求）
- 删除/覆盖文件前先确认（`Bash` 的 `rm` 等破坏性操作）
- Commit/Push 只在用户明确要求时执行

## 常见错误（Gotchas）

- Windows 系统但 bash 环境用 Unix 路径语法（`/c/Users/...`，不是 `C:\Users\...`）
- 不要重复读刚编辑过的文件验证更改 —— Edit/Write 失败会报错
- 不要同时运行独立的 `find`/`grep`/`cat`/`echo` 命令，用 Glob/Grep/Read 工具
- 独立的任务可以并行发起多个 tool call，提高效率
