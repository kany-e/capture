# AI 个人记忆捕获工具：OpenAI Build Week 项目执行计划

> **历史基线：** 本文件保留最初的 Build Week 范围与产品原则，不是当前安装
> 指南。当前实现状态和后续顺序见
> [`roadmap.md`](roadmap.md)，已接受的范围新增与架构决定见
> [`decisions.md`](decisions.md)。

## 0. 给 Work 会话的执行指令

你正在帮助我和一位合作者开发一个参加 OpenAI Build Week 的 macOS 项目。

请把本文视为当前项目的产品规格和执行基线。开始工作后：

1. 先检查当前工作目录、已有仓库和开发环境。
2. 若目录为空，按照本文建议创建项目结构和基础工程。
3. 优先完成一个可以真实运行的端到端闭环，不要先实现所有扩展功能。
4. 每完成一个阶段，实际运行、测试并修复问题。
5. 对架构作必要调整时，应优先保证：
   - 能在截止前演示；
   - 两位开发者可以并行；
   - 核心体验稳定；
   - 项目容易解释；
   - OpenAI 模型的作用清晰且不可替代。
6. 不要把项目过度设计成正式商业产品。当前目标是 Build Week 提交版本。
7. 代码中不得硬编码 API Key。使用环境变量和 `.env.example`。
8. 所有重要决策应记录在 `docs/decisions.md`。
9. 每完成一个可运行的纵向切片，就提交一次清晰的 Git commit。
10. 若本文中的某个技术细节与实际 SDK 或本机环境不兼容，应采用当前官方支持的最简单方案，并在文档中说明调整。

---

# 1. 项目概述

## 1.1 项目名称

项目与仓库统一命名为 `Mema`。

## 1.2 一句话介绍

Mema 是一个 macOS 个人记忆捕获工具。用户可以从网页或任意本地应用中快速保存一段有价值的内容，补充一句自己的备注，随后由 AI 自动理解上下文、生成情境摘要、整理标签，并支持日后的关键词和语义检索。

## 1.3 核心价值

传统收藏工具保存的是“链接”。

传统笔记软件要求用户自己决定：

- 标题写什么；
- 放在哪个文件夹；
- 如何总结；
- 使用哪些标签；
- 未来怎样检索。

Mema 保存的不是孤立文本，而是一次“发现”的完整情境：

- 用户当时看到了什么；
- 内容来自哪里；
- 用户为什么觉得重要；
- 它解决了什么问题；
- 未来在什么情况下可能再次需要它。

产品的核心价值是：

> 极低摩擦捕获 + 自动保留情境 + 智能检索和重新利用。

---

# 2. 目标用户与核心场景

## 2.1 目标用户

第一版主要面向：

- 经常浏览技术资料的开发者；
- 阅读论文、文章和论坛的学生；
- 经常在聊天、网页和文档之间收集信息的人；
- 有大量收藏但很难重新找到内容的人。

## 2.2 核心场景

### 场景 A：Stack Overflow 解决方案

用户在 Stack Overflow 上遇到一条非常有效的回答。

用户：

1. 选中关键回答；
2. 触发 Mema；
3. 输入备注：

   “今天在 VPS 上遇到这个错误，网上常见方法全部失败，只有这个方法有效。部署时还需要注意配置路径。”

Mema 自动保存：

- 页面 URL；
- 页面标题；
- 问题背景；
- 选中的回答；
- 用户备注；
- 来源网站；
- AI 生成的标题；
- AI 生成的情境摘要；
- 标签；
- 搜索别名；
- 语义向量。

未来用户搜索：

- 错误代码；
- VPS；
- Linux；
- 神奇解决方案；
- 那个反直觉的修复方法；

都应有机会找到这条内容。

### 场景 B：任意 macOS 应用

用户在 Word、Preview、微信、iMessage 或其他应用中选中文字。

用户使用全局快捷键，Mema 通过系统选区或剪贴板取得文本，然后保存内容和来源应用。

第一版不要求自动取得整个文档，只要能稳定取得：

- 选中文字；
- 当前应用名称；
- 当前窗口标题；
- 用户备注；

即可完成基本价值。

### 场景 C：回忆和检索

用户打开 Mema，搜索：

> 那个在 VPS 上很神奇的 Linux 修复办法

系统返回相关笔记卡片，并突出显示：

- AI 情境摘要；
- 用户原始备注；
- 原始选区；
- 来源链接；
- 标签。

---

# 3. Build Week 版本的成功标准

本项目不是以功能数量衡量，而是以一个强而完整的演示闭环衡量。

Build Week 官方评审维度包括技术实现、设计和用户体验、潜在影响以及创意质量，并强调对 GPT-5.6 和 Codex 的周全使用。因此项目应优先体现“AI 为什么对这个产品不可替代”，而不是堆叠普通 CRUD 功能。

## 3.1 必须成功的主流程

```text
网页中选中内容
→ 触发保存
→ 可选输入一句备注
→ AI 自动生成结构化情境笔记
→ 笔记出现在 macOS App 中
→ 使用模糊自然语言搜索
→ 找回刚才的笔记
```

## 3.2 可提交版本的最低验收条件

提交版本必须满足：

- macOS App 可以启动；
- 用户可以保存真实文本，而不只是展示硬编码假数据；
- 至少一种捕获方式稳定可用；
- 浏览器捕获能保存 URL 和页面标题；
- 用户可以添加备注；
- OpenAI API 可以生成结构化笔记；
- 数据可以持久化；
- 重新启动后笔记仍然存在；
- 可以搜索笔记；
- 至少支持关键词搜索；
- 最好支持语义搜索；
- AI 失败时不会丢失原始捕获内容；
- Demo 流程可以连续完成，不需要开发者临时修改数据库。

---

# 4. 项目范围

## 4.1 P0：必须完成

### macOS App

- SwiftUI 主界面；
- 菜单栏入口；
- 笔记列表；
- 搜索框；
- 笔记详情；
- 快速保存窗口；
- 保存状态显示；
- 打开原始 URL；
- 基本错误提示。

### 捕获

至少完成两种方式：

1. Chrome 扩展捕获网页；
2. 剪贴板或选中文字捕获本地应用。

### Chrome 扩展

- 获取当前页面标题；
- 获取 URL；
- 获取选中文字；
- 获取有限的周围上下文；
- 将捕获内容发送给本地服务。

### AI 整理

- 自动标题；
- 情境摘要；
- 主题标签；
- 关键词或实体；
- 搜索别名；
- Embedding。

### 数据层

- SQLite 持久化；
- Capture 数据模型；
- 处理状态；
- FTS5 全文搜索；
- 向量相似度搜索或最小可用语义搜索。

## 4.2 P1：核心完成后再做

- 单条笔记的 AI 对话；
- 跨笔记问答；
- 全局快捷键直接显示搜索窗口；
- 自动读取 Accessibility 选中文字；
- 保存成功动画；
- 相似笔记；
- 编辑标签和摘要；
- AI 重新生成；
- 删除笔记；
- 搜索结果关键词高亮；
- Demo 专用示例数据导入。

## 4.3 P2：明确不在当前版本实现

- Windows；
- iOS；
- 云同步；
- 多用户账户；
- 团队协作；
- OCR；
- 图片和论文图表理解；
- PDF 区域坐标；
- 完整网页离线快照；
- Safari 扩展；
- 微信聊天历史自动抓取；
- 自动监控屏幕；
- 复杂文件夹体系；
- 多 Agent 编排；
- 长期自主运行的后台 Agent；
- 完整富文本编辑器；
- 本地大模型；
- 正式 Mac App Store 发布；
- 完整生产级沙盒、公证和自动更新系统。

---

# 5. 产品设计原则

## 5.1 捕获必须快

用户在决定保存内容之后，不应被迫填写大量表单。

目标交互：

```text
选中内容
→ 一个操作打开 Mema
→ 可选输入备注
→ Enter 保存
```

保存窗口默认只显示：

- 内容简短预览；
- 来源；
- 备注输入框；
- 保存按钮。

不要在保存时要求用户手动选择：

- 文件夹；
- 多层分类；
- 大量标签；
- 笔记模板；
- 复杂格式。

## 5.2 原始信息永远先保存

用户点击保存后，系统应立即把原始 Capture 写入数据库，再异步调用 AI。

不能采用：

```text
先等待 AI 成功
→ 再保存笔记
```

应采用：

```text
先保存原始内容
→ 状态设为 processing
→ 调用 AI
→ 更新生成字段
→ 状态设为 ready
```

如果 AI 失败：

- 原始笔记仍然存在；
- 状态显示为失败；
- 用户可以重试；
- 用户仍可通过原文关键词找到它。

## 5.3 原文、用户备注和 AI 解释必须分开

界面和数据库都必须明确区分：

### Source

原始内容：

- 选中文字；
- 周围上下文；
- URL；
- 页面标题；
- 应用名称。

### User Note

用户亲自输入的内容：

- 为什么保存；
- 当时遇到了什么；
- 使用时的注意事项。

### AI Interpretation

模型生成内容：

- 标题；
- 摘要；
- 标签；
- 搜索别名；
- 关键概念。

AI 不得覆盖或改写原始内容。

## 5.4 不做传统文件夹优先的笔记系统

所有 Capture 默认进入同一个资料库。

组织方式以以下维度为主：

- 标签；
- 来源；
- 时间；
- 应用；
- 语义关系；
- 搜索。

---

# 6. 用户体验流程

## 6.1 浏览器捕获流程

推荐 Demo 流程：

1. 用户在 Chrome 中打开 Stack Overflow 或技术文章。
2. 用户选中一段回答。
3. 点击扩展图标或使用扩展快捷键。
4. 扩展显示一个非常小的弹窗：
   - 已选内容预览；
   - 备注输入框；
   - Save 按钮。
5. 用户输入备注并保存。
6. 扩展立即显示：
   - Saved；
   - Processing with AI。
7. macOS App 中出现一张 processing 状态的卡片。
8. AI 完成后卡片自动更新标题、摘要和标签。

第一版中，浏览器扩展可直接调用 localhost 服务，不强制通过 macOS App 转发。

## 6.2 任意应用捕获流程

最低实现方案：

1. 用户在任何应用中选中文字；
2. 用户按 `Command+C`；
3. 用户从菜单栏点击 “Capture Clipboard”，或者使用全局快捷键；
4. Mema 读取剪贴板；
5. 弹出备注窗口；
6. 用户保存。

进阶方案：

1. 用户选中文字；
2. 直接按 Mema 全局快捷键；
3. App 暂存当前剪贴板；
4. 模拟复制或通过 Accessibility 读取选区；
5. 恢复用户原剪贴板；
6. 弹出保存窗口。

若 Accessibility 实现消耗时间过多，提交版本可保留 Clipboard Capture，并在 Demo 中清楚表述：

> 当前原型通过浏览器扩展和系统剪贴板工作，未来版本会通过 Accessibility API 将任意应用捕获缩减为单个快捷键。

## 6.3 搜索流程

主窗口顶部只有一个主要搜索框。

用户输入时：

- 空查询：按时间显示最近笔记；
- 精确字符串：使用 FTS；
- 自然语言：同时计算语义相似度；
- 有 URL、错误码或命令：关键词匹配应具有更高权重。

结果卡片展示：

- AI 标题；
- AI 情境摘要；
- 来源；
- 时间；
- 用户备注摘要；
- 标签；
- 处理状态。

## 6.4 笔记详情

详情页顺序建议：

1. AI 标题；
2. 情境摘要；
3. 用户备注；
4. 原始选区；
5. 周围上下文；
6. 标签；
7. 来源和时间；
8. 打开原始链接；
9. AI 处理状态；
10. 重试 AI 按钮。

---

# 7. 技术架构

## 7.1 推荐总体架构

```text
┌────────────────────────────┐
│ macOS App                  │
│ SwiftUI + AppKit           │
│                            │
│ - Menu bar                 │
│ - Capture window           │
│ - Notes list               │
│ - Search UI                │
└─────────────┬──────────────┘
              │ HTTP localhost
              ▼
┌────────────────────────────┐
│ Local Backend              │
│ Python + FastAPI           │
│                            │
│ - Capture API              │
│ - SQLite                   │
│ - AI enrichment            │
│ - Embeddings               │
│ - Hybrid search            │
└─────────────▲──────────────┘
              │ HTTP localhost
┌─────────────┴──────────────┐
│ Chrome Extension           │
│ TypeScript / JavaScript    │
│                            │
│ - Selection                │
│ - URL/title                │
│ - Page context             │
│ - User note                │
└────────────────────────────┘
```

## 7.2 为什么采用本地 HTTP 服务

Build Week 阶段使用 localhost FastAPI 的优势：

- Swift 和 Python 可以独立开发；
- Chrome 扩展容易接入；
- OpenAI API 实验速度快；
- SQLite 和检索逻辑容易调试；
- 可以用 curl 独立测试后端；
- 两位开发者代码冲突较少。

当前版本不需要解决正式产品中的所有进程打包问题。

Demo 时可以：

- 通过启动脚本运行后端；
- 再启动 macOS App；
- 扩展连接固定 localhost 端口。

## 7.3 推荐端口

默认：

`127.0.0.1:8765`

必须仅绑定 localhost，不绑定 `0.0.0.0`。

## 7.4 OpenAI 集成方式

后端使用官方 OpenAI SDK 和 Responses API，API Key 从环境变量读取。官方快速入门说明 SDK 可以从环境变量取得 `OPENAI_API_KEY`，并展示了通过 Responses API 发起模型请求的方式。

模型名称不得散落在代码中，使用环境变量：

```text
OPENAI_API_KEY=
OPENAI_MODEL=
OPENAI_EMBEDDING_MODEL=
```

AI 整理结果应使用 JSON Schema Structured Outputs，而不是让模型随意输出 JSON 字符串。官方 API 文档说明 `json_schema` 可以约束模型匹配指定结构，并建议在支持的模型上优先于旧的 JSON mode。

---

# 8. 推荐仓库结构

建议使用单仓库：

```text
Mema/
├── README.md
├── .gitignore
├── .env.example
├── Makefile
├── scripts/
│   ├── dev.sh
│   ├── backend.sh
│   └── seed_demo_data.py
│
├── apps/
│   ├── macos/
│   │   ├── Mema.xcodeproj
│   │   └── Mema/
│   │       ├── App/
│   │       ├── Models/
│   │       ├── Networking/
│   │       ├── Views/
│   │       ├── ViewModels/
│   │       ├── Capture/
│   │       └── Resources/
│   │
│   └── chrome-extension/
│       ├── manifest.json
│       ├── package.json
│       ├── tsconfig.json
│       └── src/
│           ├── popup/
│           ├── content/
│           ├── background/
│           └── api/
│
├── services/
│   └── backend/
│       ├── pyproject.toml
│       ├── requirements.txt
│       ├── app/
│       │   ├── main.py
│       │   ├── config.py
│       │   ├── api/
│       │   ├── db/
│       │   ├── models/
│       │   ├── schemas/
│       │   ├── services/
│       │   │   ├── enrichment.py
│       │   │   ├── embeddings.py
│       │   │   └── search.py
│       │   └── prompts/
│       └── tests/
│
├── contracts/
│   ├── capture.schema.json
│   ├── enriched_capture.schema.json
│   └── api.md
│
└── docs/
    ├── product-plan.md
    ├── architecture.md
    ├── decisions.md
    ├── judge-walkthrough.md
    └── submission-copy.md
```

如果创建 Xcode 工程和单仓库结构产生问题，可以保留同样的逻辑目录，但不必强行完全匹配。

---

# 9. 数据模型

## 9.1 Capture 的核心 JSON 合同

前端提交：

```json
{
  "client_capture_id": "optional-client-generated-uuid",
  "source_type": "web",
  "source_app": "Google Chrome",
  "source_title": "How to fix example error",
  "source_url": "https://example.com/question",
  "selected_text": "The selected answer or passage.",
  "surrounding_context": "Question, nearby paragraphs, or page context.",
  "user_note": "This was the only solution that worked on my VPS.",
  "captured_at": "2026-07-18T12:00:00-07:00"
}
```

## 9.2 后端返回

```json
{
  "id": "server-generated-uuid",
  "status": "processing",
  "created_at": "2026-07-18T19:00:00Z",
  "updated_at": "2026-07-18T19:00:00Z",
  "source_type": "web",
  "source_app": "Google Chrome",
  "source_title": "How to fix example error",
  "source_url": "https://example.com/question",
  "selected_text": "The selected answer or passage.",
  "surrounding_context": "Question, nearby paragraphs, or page context.",
  "user_note": "This was the only solution that worked on my VPS.",
  "ai_title": null,
  "ai_summary": null,
  "problem": null,
  "key_insight": null,
  "why_saved": null,
  "caveats": [],
  "tags": [],
  "entities": [],
  "search_aliases": [],
  "error_message": null
}
```

## 9.3 AI 完成后的对象

```json
{
  "id": "server-generated-uuid",
  "status": "ready",
  "ai_title": "An unexpected fix for a VPS package error",
  "ai_summary": "While configuring a Linux VPS, the user encountered an error that common fixes did not resolve. The saved answer recommends changing a specific configuration, which worked, but the deployment path should be verified before applying it elsewhere.",
  "problem": "A package or deployment command failed on a Linux VPS.",
  "key_insight": "A short configuration change resolved the issue after common fixes failed.",
  "why_saved": "The solution was unusually simple, surprising, and effective.",
  "caveats": [
    "Verify the configuration path for the target Linux distribution."
  ],
  "tags": [
    "Linux",
    "VPS",
    "Deployment",
    "Troubleshooting"
  ],
  "entities": [
    "Linux",
    "VPS"
  ],
  "search_aliases": [
    "unexpected VPS fix",
    "surprising Linux solution",
    "deployment error workaround"
  ]
}
```

## 9.4 SQLite 表

建议至少建立以下表。

### captures

```sql
CREATE TABLE captures (
    id TEXT PRIMARY KEY,
    client_capture_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    captured_at TEXT,
    status TEXT NOT NULL,
    source_type TEXT NOT NULL,
    source_app TEXT,
    source_title TEXT,
    source_url TEXT,
    selected_text TEXT NOT NULL,
    surrounding_context TEXT,
    user_note TEXT,
    ai_title TEXT,
    ai_summary TEXT,
    problem TEXT,
    key_insight TEXT,
    why_saved TEXT,
    caveats_json TEXT NOT NULL DEFAULT '[]',
    tags_json TEXT NOT NULL DEFAULT '[]',
    entities_json TEXT NOT NULL DEFAULT '[]',
    search_aliases_json TEXT NOT NULL DEFAULT '[]',
    embedding_json TEXT,
    error_message TEXT,
    enrichment_version INTEGER NOT NULL DEFAULT 1
);
```

### FTS 表

```sql
CREATE VIRTUAL TABLE captures_fts USING fts5(
    capture_id UNINDEXED,
    source_title,
    selected_text,
    surrounding_context,
    user_note,
    ai_title,
    ai_summary,
    problem,
    key_insight,
    why_saved,
    tags,
    entities,
    search_aliases
);
```

## 9.5 状态枚举

```text
captured
processing
ready
error
```

可选增加：

```text
deleted
```

但当前版本可直接物理删除。

---

# 10. 后端 API

## 10.1 健康检查

```http
GET /health
```

返回：

```json
{
  "status": "ok",
  "database": "ok",
  "openai_configured": true
}
```

## 10.2 创建 Capture

```http
POST /v1/captures
```

行为：

1. 验证输入；
2. 立即写数据库；
3. 返回 processing 对象；
4. 启动 enrichment；
5. enrichment 完成后更新对象。

对于 Build Week，可使用 FastAPI `BackgroundTasks`。

如果后台任务在 App 关闭后不可靠，不必引入 Celery、Redis 或复杂队列。也可以在请求内同步执行，但 UI 应先表现出正在处理。

更稳妥的折中方式：

- `/captures` 先写入；
- 客户端随后调用 `/captures/{id}/enrich`；
- 或后端使用简单线程池。

## 10.3 列出 Capture

```http
GET /v1/captures?limit=50&offset=0
```

默认按 `created_at DESC`。

## 10.4 查看单条 Capture

```http
GET /v1/captures/{id}
```

## 10.5 重新处理

```http
POST /v1/captures/{id}/enrich
```

## 10.6 搜索

```http
GET /v1/search?q=unexpected+linux+fix&limit=20
```

返回：

```json
{
  "query": "unexpected linux fix",
  "results": [
    {
      "capture": {},
      "score": 0.91,
      "keyword_score": 0.68,
      "semantic_score": 0.93
    }
  ]
}
```

## 10.7 删除

P1：

```http
DELETE /v1/captures/{id}
```

## 10.8 对话

P1：

```http
POST /v1/chat
```

输入：

```json
{
  "message": "What Linux deployment problems have I saved?",
  "capture_id": null
}
```

这项功能只有在主流程完成后再做。

---

# 11. AI 整理管线

## 11.1 管线步骤

```text
Capture
→ normalize text
→ truncate irrelevant context
→ call OpenAI
→ validate structured result
→ generate embedding
→ update database
→ rebuild FTS row
→ mark ready
```

## 11.2 文本限制策略

不要向模型发送整个网页 HTML。

发送内容：

- 页面标题；
- URL 域名；
- 选中文字；
- 附近上下文；
- 用户备注；
- 来源应用。

建议长度优先级：

1. 用户备注必须完整保留；
2. 选中文字必须完整保留；
3. 周围上下文按合理字符数截断；
4. 页面导航、Cookie、页脚等内容应过滤。

第一版可以简单限制：

- 选区最多约 12,000 字符；
- 周围上下文最多约 20,000 字符；
- 超出部分截断并记录 `context_truncated=true`。

具体限制应根据所选模型和实际测试调整。

## 11.3 模型任务

模型一次请求生成：

- title；
- summary；
- problem；
- key_insight；
- why_saved；
- caveats；
- tags；
- entities；
- search_aliases。

不需要为每个字段单独调用模型。

## 11.4 建议 Structured Output Schema

```json
{
  "type": "object",
  "properties": {
    "title": {
      "type": "string"
    },
    "summary": {
      "type": "string"
    },
    "problem": {
      "type": "string"
    },
    "key_insight": {
      "type": "string"
    },
    "why_saved": {
      "type": "string"
    },
    "caveats": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "tags": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "entities": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "search_aliases": {
      "type": "array",
      "items": {
        "type": "string"
      }
    }
  },
  "required": [
    "title",
    "summary",
    "problem",
    "key_insight",
    "why_saved",
    "caveats",
    "tags",
    "entities",
    "search_aliases"
  ],
  "additionalProperties": false
}
```

## 11.5 建议系统 Prompt

```text
You transform captured source material into a compact personal memory record.

Your output is not a generic article summary. Its purpose is to help the same user remember, months later:

1. what they were doing,
2. what problem or idea they encountered,
3. what the saved content contributed,
4. why they personally saved it,
5. what cautions matter when applying it again.

Strictly distinguish among:
- facts stated by the source,
- context explicitly provided by the user,
- cautious inferences.

Do not invent technical details.
Do not claim the saved method worked unless the user's note says it worked.
Preserve exact error codes, commands, product names, APIs, libraries, and technical entities when present.

Generate:
- a concise, specific title;
- a contextual memory summary;
- the underlying problem or subject;
- the key insight;
- why the user likely saved it, primarily grounded in the user note;
- practical caveats;
- a small set of reusable tags;
- named entities;
- natural-language search aliases, including memorable or emotional descriptions used by the user.

Use the language most appropriate to the user's note and captured content.
```

## 11.6 建议用户 Prompt 模板

```text
SOURCE TYPE:
{source_type}

SOURCE APPLICATION:
{source_app}

SOURCE TITLE:
{source_title}

SOURCE URL:
{source_url}

SELECTED CONTENT:
{selected_text}

SURROUNDING CONTEXT:
{surrounding_context}

USER NOTE:
{user_note}
```

## 11.7 AI 质量要求

标题不能是：

- “Interesting Note”
- “Linux Information”
- “A Useful Solution”

标题应该具体，例如：

- “VPS 上 apt 依赖错误的反直觉修复方式”
- “为什么 SwiftUI 菜单栏窗口失去焦点后立即关闭”
- “塑料包装如何在战后美国被正常化”

摘要不能只是原文总结，必须体现用户情境。

---

# 12. Embedding 与混合搜索

## 12.1 Embedding 输入

生成 embedding 时，应把最有检索价值的内容拼成一个稳定字符串：

```text
TITLE:
{ai_title}

SUMMARY:
{ai_summary}

USER NOTE:
{user_note}

SELECTED CONTENT:
{selected_text}

PROBLEM:
{problem}

KEY INSIGHT:
{key_insight}

TAGS:
{tags}

SEARCH ALIASES:
{search_aliases}
```

## 12.2 MVP 向量存储

预计 Demo 数据不多，不需要引入外部向量数据库。

做法：

- embedding 作为 JSON 数组存在 SQLite；
- 搜索时读取所有 ready Capture；
- 在 Python 内计算余弦相似度；
- 返回 Top K。

数百或几千条记录内足够用于原型。

不要在截止前引入：

- Pinecone；
- Weaviate；
- Milvus；
- Redis Vector；
- 复杂 SQLite 向量扩展。

## 12.3 混合得分

建议：

```text
final_score =
    0.55 × semantic_score
  + 0.35 × normalized_keyword_score
  + 0.10 × metadata_bonus
```

metadata bonus 可以包括：

- URL 域名匹配；
- 应用名称匹配；
- 标签精确匹配；
- 错误代码精确匹配。

对于包含以下模式的查询，应提高关键词权重：

- 错误代码；
- 命令；
- 文件路径；
- 函数名称；
- 软件版本；
- URL；
- 带数字的技术标识。

简单实现可以检测查询是否包含：

- 数字；
- `/`；
- `-`；
- `_`；
- `0x`；
- 大小写混合技术标识。

如果存在，则使用：

```text
0.45 semantic + 0.50 keyword + 0.05 metadata
```

## 12.4 没有 Embedding 时的降级

如果 OpenAI embedding 调用失败：

- 仍写入 Capture；
- FTS 搜索仍正常工作；
- `embedding_json` 保持空；
- 搜索时跳过 semantic score；
- UI 不应报致命错误。

---

# 13. Chrome 扩展设计

## 13.1 Manifest

使用 Manifest V3。

需要的最低权限：

- `activeTab`
- `scripting`
- `storage`

只申请真正需要的权限。

localhost 请求可能需要：

```json
{
  "host_permissions": [
    "http://127.0.0.1:8765/*"
  ]
}
```

## 13.2 页面捕获数据

Content script 获取：

```javascript
const selection = window.getSelection();
const selectedText = selection?.toString().trim() ?? "";
```

周围上下文的最低方案：

1. 找到选区的 `commonAncestorContainer`；
2. 找到最近的段落、文章、回答或内容容器；
3. 获取容器 `innerText`；
4. 限制长度；
5. 若无法定位，则使用页面正文的部分内容。

优先容器：

- `article`
- `[role="main"]`
- `.answer`
- `.post-text`
- `main`
- 最近的 `p`、`div` 或 `section`

第一版不需要为每个网站写专属解析器。

## 13.3 Popup

Popup 包含：

- 页面标题；
- 选区预览；
- 备注输入；
- Save；
- 状态信息。

如果没有选中文字：

- 可以保存当前页面标题和少量正文；
- 但 UI 应提示 “No text selected; saving page context”。

## 13.4 CORS

FastAPI 仅允许：

- Chrome Extension origin；
- localhost 开发 origin。

开发阶段可放宽，但提交前不要无条件允许所有公网来源。

## 13.5 Extension API 错误

如果后端没启动：

```text
Mema’s backend is not running.
Start the local Mema backend and try again.
```

不能静默失败。

---

# 14. macOS App 设计

## 14.1 技术栈

- Swift；
- SwiftUI；
- 必要处使用 AppKit；
- `URLSession` 调用本地 API；
- `ObservableObject` 或 Observation 框架管理状态。

不要引入大型第三方 UI 框架。

## 14.2 主窗口

建议使用简洁双栏布局：

```text
┌─────────────────────────────────────────────┐
│ Search your memories...                     │
├───────────────────┬─────────────────────────┤
│ Capture list      │ Capture detail          │
│                   │                         │
│ Title             │ AI summary              │
│ Summary           │ User note               │
│ Tags              │ Original selection      │
│ Source            │ Context                 │
└───────────────────┴─────────────────────────┘
```

窗口较小时可使用列表和详情导航。

## 14.3 菜单栏

菜单项：

- Open Mema；
- Capture Clipboard；
- Search；
- Quit。

P1：

- Capture Selection；
- Preferences。

## 14.4 Clipboard Capture

最低实现：

1. 读取 `NSPasteboard.general.string(forType: .string)`；
2. 取得当前前台应用名称；
3. 显示 Capture Sheet；
4. 用户添加备注；
5. POST 到后端。

当前应用名称可通过：

```swift
NSWorkspace.shared.frontmostApplication
```

窗口标题获取失败时可以为空。

## 14.5 快速保存窗口

字段：

- 文本预览，只读；
- 来源 App；
- 备注；
- Save；
- Cancel。

键盘：

- Enter：保存；
- Escape：取消；
- Command+Enter：保存并打开详情，属于 P1。

## 14.6 网络层

定义统一的 API Client：

```swift
protocol MemaAPIClient {
    func health() async throws -> HealthResponse
    func createCapture(_ request: CreateCaptureRequest) async throws -> Capture
    func listCaptures() async throws -> [Capture]
    func getCapture(id: String) async throws -> Capture
    func search(query: String) async throws -> SearchResponse
    func enrich(id: String) async throws -> Capture
}
```

提供：

- `LiveMemaAPIClient`
- `MockMemaAPIClient`

这样 macOS UI 可在后端未完成时使用 Mock 数据开发。

## 14.7 状态刷新

第一版可使用简单轮询：

- 创建 Capture 后立即展示 processing；
- 每 1–2 秒请求单条 Capture；
- 状态变为 ready 或 error 后停止；
- 最多轮询约 30–60 秒。

不需要 WebSocket。

---

# 15. 两位开发者分工

## 15.1 开发者 A：Capture & Experience Owner

主要负责：

- macOS App；
- SwiftUI；
- 菜单栏；
- Clipboard Capture；
- 快速保存窗口；
- 笔记列表；
- 搜索 UI；
- 详情页；
- Demo 交互；
- 视觉一致性。

代码所有权：

```text
apps/macos/
docs/judge-walkthrough.md
```

## 15.2 开发者 B：Intelligence & Data Owner

主要负责：

- FastAPI；
- SQLite；
- API Contract；
- OpenAI API；
- Structured Output；
- Embedding；
- FTS；
- 混合搜索；
- Chrome 扩展；
- AI 失败和重试。

代码所有权：

```text
services/backend/
apps/chrome-extension/
contracts/
```

## 15.3 共同负责

- Capture Schema；
- Prompt 质量；
- 每日端到端集成；
- 测试样例；
- README；
- Demo 视频；
- Devpost 描述；
- 最终代码清理。

## 15.4 Git 协作原则

建议分支：

```text
main
feature/macos-client
feature/backend-ai
feature/chrome-extension
feature/demo-polish
```

规则：

- `main` 必须保持可运行；
- 小批量合并；
- 不要两个人同时大改同一份 Contract；
- Contract 变化必须双方确认；
- 每天至少两次端到端合并测试；
- 截止前最后半天冻结大功能。

---

# 16. 三天冲刺计划

## 当前时间背景

官方 Build Week 页面列出的提交截止日期为 2026 年 7 月 21 日，并要求提交项目说明、Demo 视频和代码仓库等材料。

以下按 7 月 18 日至 7 月 21 日安排。

---

## Day 0：7 月 18 日——合同与纵向骨架

### 共同任务

- 创建 Git 仓库；
- 确定项目名称；
- 写入本计划；
- 创建目录结构；
- 确定 Capture JSON；
- 确定 API 路径；
- 创建 `.env.example`；
- 建立 README 骨架；
- 创建 Git 分支。

### 开发者 A

完成：

- Xcode macOS App 工程；
- 主窗口能启动；
- Mock Capture 列表；
- Capture 详情 Mock UI；
- 本地 API Client 骨架；
- 菜单栏入口；
- Clipboard 读取实验。

### 开发者 B

完成：

- FastAPI 工程；
- `/health`；
- SQLite 初始化；
- `POST /v1/captures`；
- `GET /v1/captures`；
- `GET /v1/captures/{id}`；
- curl 测试；
- 测试 JSON。

### 当日结束验收

必须可以：

```text
curl 创建一条 Capture
→ SQLite 中保存
→ GET 返回
→ macOS Mock 或真实 API 显示列表
```

当日不要求 AI。

---

## Day 1：7 月 19 日——真实捕获与 AI 整理

### 开发者 A

完成：

- Clipboard Capture；
- Capture 输入窗口；
- 输入备注；
- POST 后端；
- processing 卡片；
- 笔记列表刷新；
- 详情展示原始内容和备注。

### 开发者 B

完成：

- OpenAI SDK；
- Enrichment Structured Output；
- Prompt；
- 状态更新；
- AI 错误处理；
- FTS5；
- 基本 `/search`；
- Chrome 扩展骨架；
- 扩展取得 URL、标题和选区。

### 共同测试样例

至少测试五类：

1. Stack Overflow 技术答案；
2. 普通文章观点；
3. 带错误代码的内容；
4. 中文用户备注和英文原文；
5. 没有备注的内容。

### 当日结束验收

必须可以：

```text
macOS Clipboard
→ 输入备注
→ 保存
→ AI 生成标题和摘要
→ App 自动更新
→ 关键词搜索找回
```

---

## Day 2：7 月 20 日——浏览器深度捕获与语义检索

### 开发者 A

完成：

- 搜索结果 UI；
- 详情页优化；
- 打开原始 URL；
- processing、ready、error 状态；
- 空状态；
- 加载状态；
- Demo 视觉整理。

### 开发者 B

完成：

- Chrome 扩展调用后端；
- 选区周围上下文；
- 扩展备注输入；
- Embedding；
- 余弦相似度；
- 混合搜索；
- 重试接口；
- Seed Demo Data 脚本。

### 共同

完成完整主 Demo：

```text
Chrome 选中回答
→ 扩展保存并备注
→ App 出现
→ AI 整理
→ 模糊自然语言搜索找回
```

录制第一次测试视频，即使界面还不完美。

### 当日结束验收

Demo 主流程必须在干净启动后连续成功三次。

---

## Day 3：7 月 21 日——只修复、打磨和提交

### 禁止事项

除非主流程无法工作，否则不要：

- 加新平台；
- 换技术栈；
- 重写数据库；
- 加复杂 Agent；
- 做 Safari 扩展；
- 做 OCR；
- 引入新的基础设施；
- 大改 UI 导航。

### 上午

- 修复阻塞 Bug；
- 清理错误提示；
- 写 README；
- 添加安装步骤；
- 添加架构图；
- 添加截图；
- 确认无 API Key；
- 确认 `.env` 被忽略；
- 添加开源许可证；
- 运行测试。

### 中段

- 准备 Demo 数据；
- 清空无关数据；
- 录制最终 Demo；
- 录制备用 Demo；
- 导出高质量视频；
- 准备封面图。

### 提交前

- 完成 Devpost 描述；
- 填写使用的 OpenAI 能力；
- 填写 Codex 如何帮助开发；
- 提交 Git 仓库；
- 确认仓库权限；
- 验证视频链接；
- 验证所有材料；
- 以 Devpost 显示的准确时区和截止时间为准提前提交。

---

# 17. 端到端验收测试

## 17.1 后端测试

### 创建

- 正常选区；
- 空备注；
- 长备注；
- 中文；
- 英文；
- 中英混合；
- 缺失 URL；
- 无页面标题；
- 超长上下文。

### AI

- 正常响应；
- API Key 缺失；
- 模型超时；
- Structured Output 验证失败；
- Embedding 失败；
- 重试成功。

### 搜索

- 标题精确词；
- 错误代码；
- 用户备注；
- 标签；
- 模糊描述；
- 无结果；
- 空查询。

## 17.2 Chrome 测试

至少测试：

- Stack Overflow；
- GitHub Issue；
- 普通博客；
- OpenAI 文档；
- 选中代码块；
- 无选区；
- 后端未启动。

## 17.3 macOS 测试

至少测试：

- Chrome；
- Preview 文本；
- Word 或 TextEdit；
- 微信或聊天应用；
- 空剪贴板；
- 超长剪贴板；
- 后端关闭；
- API 处理失败；
- App 重启后数据仍存在。

---

# 18. Demo 方案

## 18.1 Demo 核心叙事

不要先解释所有技术架构。

先展示问题：

> We save links, screenshots, and fragments everywhere, but months later we no longer remember why they mattered.

然后展示产品：

> Mema captures not only the content, but the context of why you saved it.

## 18.2 推荐 90–120 秒 Demo 脚本

### 0–15 秒：问题

画面展示浏览器中很多标签或一个普通收藏夹。

旁白：

> I constantly find useful solutions in articles, forums, documents, and chats. Saving the link is easy, but finding it later—and remembering why I saved it—is not.

### 15–40 秒：捕获

打开一个 Stack Overflow 风格的页面。

- 选中关键回答；
- 打开 Mema 扩展；
- 输入备注：
  “Every common fix failed. This one-line change finally worked on my VPS.”
- 点击 Save。

旁白：

> With Mema, I select the useful part and add the context only I know.

### 40–65 秒：AI 整理

切到 macOS App。

显示：

- processing；
- 自动标题出现；
- 摘要出现；
- 标签出现。

旁白：

> Mema combines the source, surrounding page context, and my note to create a compact memory—not just a generic summary.

### 65–90 秒：找回

搜索：

> that surprising VPS fix after all common methods failed

显示目标笔记。

旁白：

> Later, I do not need to remember the exact wording. Hybrid search finds it through both keywords and meaning.

### 90–110 秒：跨应用

从 Preview、Word 或聊天中复制一句话，使用菜单栏 Capture Clipboard 保存。

旁白：

> And because Mema is a macOS app rather than only a browser bookmark, the same workflow can capture information from local apps.

### 110–120 秒：结束

旁白：

> Mema turns scattered fragments into searchable personal context.

## 18.3 Demo 可靠性策略

- 使用确定可访问的网页；
- 准备本地备用 HTML 页面；
- 准备已有处理完成的同类笔记；
- AI 处理过慢时，剪辑等待部分；
- 同时准备一版连续实时演示和一版剪辑演示；
- 不在录制前更新依赖；
- 关闭无关通知；
- 确认 API 额度；
- 提前测试网络；
- 保留原始录屏文件。

---

# 19. README 结构

```text
# Mema

One-line description

## Problem

## Solution

## Demo

## Key Features

## How It Works

## Architecture

## OpenAI Usage

## Repository Structure

## Setup

### Backend

### macOS App

### Chrome Extension

## Environment Variables

## Development

## Known Limitations

## Future Work

## Team

## License
```

## 19.1 OpenAI Usage 部分应说明

- 使用模型读取来源上下文与用户备注；
- 使用 Structured Outputs 生成结构化 Memory；
- 使用 Embeddings 实现自然语言语义搜索；
- 保留原始内容，避免 AI 输出成为唯一事实来源；
- AI 失败时可降级到全文搜索；
- Codex 用于规划、搭建、调试和完成项目。

---

# 20. Devpost 项目说明草稿结构

## Inspiration

人们会保存很多链接、截图和文本，但真正丢失的是保存时的情境。

## What it does

Mema 从浏览器和 macOS 应用捕获文本，结合来源上下文和用户备注，自动生成可检索的个人记忆。

## How we built it

- SwiftUI macOS App；
- Chrome Extension；
- FastAPI；
- SQLite FTS5；
- OpenAI Responses API；
- Structured Outputs；
- Embeddings；
- 混合搜索。

## Challenges

- 跨应用捕获；
- 区分原文、用户备注和 AI 推断；
- 精确搜索与模糊搜索结合；
- 保证 AI 失败不丢失数据；
- 在短时间内完成稳定 Demo。

## Accomplishments

- 从真实网页捕获上下文；
- 自动生成情境记忆，而非普通摘要；
- 支持模糊自然语言找回；
- 支持浏览器和本地 App 两类来源；
- 实现完整 macOS 原型。

## What we learned

- 捕获摩擦比笔记编辑功能更重要；
- 用户备注提供了模型无法从网页获得的个人情境；
- 混合搜索比只使用关键词或只使用向量更可靠；
- AI 管线应与原始数据分离。

## What is next

- Accessibility 直接选区读取；
- 图片和 PDF 区域捕获；
- iOS；
- 云同步；
- 用户可控隐私策略；
- 主动浮现相关记忆；
- 跨笔记研究和对话。

---

# 21. 风险与降级方案

## 风险 1：Accessibility 太难

降级：

- Demo 使用 Chrome 扩展；
- 本地 App 使用 Clipboard Capture；
- 不阻塞主流程。

## 风险 2：Chrome Extension 上下文提取不稳定

降级：

- 保存选区；
- 保存标题；
- 保存 URL；
- 保存 `document.body.innerText` 的截断版本；
- 不做网站专属解析。

## 风险 3：AI 调用慢

降级：

- 原始卡片立即出现；
- processing 状态；
- 后台更新；
- Demo 视频剪辑等待过程。

## 风险 4：Embedding 搜索来不及

降级：

- 先完成 FTS5；
- AI 生成 search aliases；
- 搜索别名本身已能增强关键词检索；
- Embedding 作为最后添加的功能。

## 风险 5：Swift 与后端集成问题

降级：

- 保持 HTTP JSON 简单；
- 使用 curl 记录已验证请求；
- Mac App 暂时轮询；
- 不使用 WebSocket；
- 不使用复杂认证。

## 风险 6：后端无法随 App 自动启动

降级：

- Demo 使用 `scripts/dev.sh`；
- README 明确先启动后端；
- 菜单栏显示 Backend Connected / Disconnected。

## 风险 7：提交前主流程损坏

措施：

- Day 2 结束冻结主架构；
- 最后一天只修复；
- 保留最后一个可用 commit；
- 打 tag：`demo-stable`；
- 录制备用视频。

---

# 22. 开发优先级决策规则

每遇到新想法时，按以下顺序判断：

1. 它是否直接增强主 Demo？
2. 没有它，评委是否看不懂产品价值？
3. 它是否可以在一两个小时内稳定完成？
4. 它是否会破坏现有主流程？
5. 是否已有简单降级方案？

优先级：

```text
稳定的真实捕获
> AI 情境理解
> 可靠找回
> 清晰 Demo
> 视觉打磨
> 附加功能
```

绝对不要反过来。

---

# 23. Definition of Done

只有同时满足以下条件，项目才算完成：

## 功能

- Chrome 可以捕获真实网页选区；
- 用户可以添加备注；
- 数据写入 SQLite；
- AI 自动整理；
- App 显示结果；
- 关键词搜索有效；
- 模糊查询可以找到相关内容；
- 原始来源可以打开；
- AI 失败不丢失原文。

## 工程

- API Key 未提交；
- `.env.example` 存在；
- README 可使另一台机器启动项目；
- 后端至少有核心测试；
- 主分支可运行；
- 有稳定 Demo tag；
- 已记录已知限制。

## 展示

- 最终 Demo 视频完成；
- 备用视频完成；
- 截图完成；
- 项目描述完成；
- 仓库可访问；
- 提交材料已验证。

---

# 24. Work 会话的第一阶段具体任务

开始开发后，请按以下顺序执行，不要先询问大量开放性问题：

1. 检查工作目录和可用开发工具。
2. 若仓库不存在，初始化 Git。
3. 创建上述单仓库目录。
4. 将本计划保存为 `docs/product-plan.md`。
5. 创建 `contracts/capture.schema.json`。
6. 创建 `contracts/enriched_capture.schema.json`。
7. 创建 `contracts/api.md`。
8. 创建 FastAPI 最小服务和 `/health`。
9. 创建 SQLite migration 或初始化脚本。
10. 实现 Capture 创建、列表和单条读取。
11. 使用 curl 完成一次真实写入和读取。
12. 创建 Xcode macOS App 工程。
13. 建立 Swift API Model 和 Client。
14. 让 macOS App 显示来自真实后端的 Capture 列表。
15. 再开始实现 OpenAI enrichment。
16. 最后接入 Chrome Extension。

第一条纵向成果应该是：

```text
curl POST Capture
→ SQLite
→ macOS App 显示 Capture
```

第二条纵向成果：

```text
macOS Clipboard Capture
→ API
→ AI
→ App 更新
```

第三条纵向成果：

```text
Chrome Selection
→ API
→ AI
→ Hybrid Search
→ 找回
```

在前三条纵向成果完成之前，不开发 P1 或 P2 功能。
