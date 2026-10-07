# AI CLI Helper

> **One Command. Every AI CLI.**

`ai` 是一个统一管理 AI CLI 的 Bash 工具。

项目目标不是提供新的 AI CLI，而是作为所有 AI CLI 的统一入口，负责：

- Provider 管理
- API Key 管理
- Environment 管理
- CLI 启动
- Profile / HOME 隔离
- 多 Provider 切换
- 多 CLI 切换

---

## 🚀 快速开始 (Quick Start)

1. **Clone 项目**:
   ```bash
   git clone <your-repo-url> ai-cli-helper
   cd ai-cli-helper
   ```

2. **运行一键安装 / 更新脚本**:
   ```bash
   ./install.sh
   ```
   *安装会自动将 `~/.config/ai/bin` 加入 PATH，并自动在 `~/.bashrc` (或 `~/.zshrc`) 中引入 `~/.config/ai/env.sh`。*

3. **重新加载终端配置**:
   ```bash
   source ~/.bashrc
   ```

4. **配置 Secret (API Key)**:
   编辑对应的 Secret 文件：
   ```bash
   vim ~/.config/ai/secrets/openai.sh
   ```
   填入你的 `OPENAI_API_KEY` 等参数。

5. **开启使用**:
   ```bash
   ai doctor             # 诊断环境
   ai provider list      # 查看 Provider 列表
   ai provider use myapi # 切换 active Provider
   ai claude             # 启动 Claude Code
   ai codex              # 启动 Codex
   ai gemini             # 启动 Gemini
   ```

### 🧠 OpenAI Codex: API Key 与 ChatGPT OAuth 混合多账号架构

Codex 支持 **API Key 网关** 与 **ChatGPT OAuth 账号登录** 的混合模式，并引入了与 `agy` 相同规格的凭据独立存储 + 全局会话共享架构：

#### 1. 混合认证模式 (Hybrid Auth Mode)
- **API Key 模式** (如 `codexa`, `codexb`, `codexn`, `codexg`):
  配置 `OPENAI_BASE_URL`、`OPENAI_MODEL` 与 `OPENAI_API_KEY`，支持第三方转发与自定义网关。
- **ChatGPT OAuth 模式** (如 `codexh`):
  登录 ChatGPT Plus / Pro / Team / Enterprise 账号，无需配置 Base URL 或 API Key：
  ```bash
  ai codexh login              # 打开浏览器完成 OAuth 授权
  ai codexh login --device-auth# 终端设备码授权 (适合远程服务器 / SSH 纯终端环境)
  ai codexh                    # 启动 ChatGPT OAuth 授权会话
  ```
- **智能模式感知 (Auto Detection)**:
  若未强制指定 `AI_AUTH_MODE`，系统将智能判断当前 alias 是优先使用 API Key 还是已登录的 ChatGPT OAuth 凭据，永不误清或串号。

#### 2. 多账号凭据隔离与防止串号
- 每个别名拥有专属隔离的认证目录 (`~/.local/share/ai/codex/auth/<alias>/auth.json`) 与 `email.txt`。
- 换号、退出或在多个终端并发运行不同账号与 API 网关完全互不干扰。

#### 3. 会话历史与续接 (通过 AI_HOME_PROFILE)
- **全局共享模式 (Shared, 默认推荐)**:
  所有别名在 `shared-team` 下全局共享 `rollouts/`（会话记录与思维转储）、`history.jsonl`（交互历史）与 SQLite 状态数据库。任意别名（即使在 API 模式与 ChatGPT 模式之间切换）均可直接通过 `codex resume --last` 或 `codex resume <id>` 继续此前对话！
- **完全私有隔离模式 (Isolated)**:
  设置 `AI_HOME_PROFILE="isolated"` 时，该别名运行在完全私有的独立环境中。

#### 4. 辅助命令
- `ai codex whoami` / `ai codex status` : 查看当前绑定的 ChatGPT 账号邮箱、API 状态、Profile 与数据共享模式
- `ai codex login [--device-auth]` : 发起登录（支持设备码模式）
- `ai codex logout` : 退出当前别名的登录并清除凭据
- `ai reset codex` : 重置该别名的运行时环境（不影响共享的历史会话）
- `ai env codex` : 查看详细运行环境与认证状态

---

### 🎭 Claude Code: API Key 与 官方 OAuth 订阅模式

系统原生优化 Claude Code CLI，支持第三方 API 与官方订阅授权共存：

#### 1. 双模式支持
- **API Key 模式** (如 `claude`, `claudeb`):
  配置 `ANTHROPIC_BASE_URL` 与 `ANTHROPIC_API_KEY`，内置 HTTPS 校验与 `--dangerously-skip-permissions --no-chrome` 快速启动。
- **官方 OAuth 订阅模式** (如 `claudeh`):
  支持通过官方授权直接使用 Claude Pro / Team 订阅：
  ```bash
  ai claudeh login             # 浏览器完成官方授权登录
  ai claudeh                   # 使用官方订阅启动 Claude Code
  ```

#### 2. 多账号凭据隔离与项目会话共享
- 凭据隔离存储于 `~/.local/share/ai/claude/auth/<alias>/`，多账号并发互不串号。
- 全局共享模式 (`AI_HOME_PROFILE="shared-team"`) 下自动共享 `projects/`、`sessions/`、`todos/` 与 `history.jsonl`，任意别名均可 `claude --resume` 无缝恢复项目会话。
- 自动桥接开发工具链（`cargo`, `rustup`, `npm`, `.gitconfig`, `.ssh`, `.config/gh`）。

#### 3. 辅助命令
- `ai claude whoami` / `ai claude status` : 查看当前账号邮箱、认证方式与环境配置
- `ai claude login` : 发起官方授权登录
- `ai claude logout` : 退出登录
- `ai reset claude` : 重置该别名运行环境
- `ai env claude` : 查看当前环境变量

---

### Google Antigravity (AGY) OAuth 多账号、凭据隔离与工作空间共享

系统原生支持 Google Antigravity CLI (`agy`)，通过凭据独立存储 + 全局持久化工作空间共享架构，彻底解决多账号并发运行、凭据串号，以及换号会话丢失的问题：

#### 1. 多账号凭据完全独立隔离
- **`ai agya` ~ `ai agyg`**：支持绑定多个不同 Google 账号（如 A ~ G 账号）。首次运行分别提示对应 OAuth 授权链接，在浏览器登录对应账号即可完成绑定。
- 每个别名拥有专属隔离的运行时认证目录 (`~/.local/share/ai/agy/auth/<alias>/`) 与独立的 `antigravity-oauth-token`，**不同终端同时并发运行不同账号互不干扰，换号/退出永不串号！**

#### 2. 对话历史与工作空间模式（通过 AI_HOME_PROFILE 自由指定）
系统支持通过 `export AI_HOME_PROFILE=...` 精细控制数据共享与隔离策略。无论选用哪种数据模式，各别名的 Google OAuth 登录凭据始终严格隔离：

- **全局共享模式 (Shared, 默认推荐)**:
  ```bash
  export AI_HOME_PROFILE="shared-team"   # 或 "shared"
  ```
  所有别名全局共享 `brain/`（对话记录、思维链与生成的产物）、`conversations/`（会话状态）、`conversation_summaries.db`（工作空间项目索引）、`history.jsonl`、`knowledge/`（智能体记忆库）与 `annotations/`。任意别名均可无缝继续此前会话（`agy -c` 或 `/resume`）。
- **完全私有隔离模式 (Isolated)**:
  ```bash
  export AI_HOME_PROFILE="isolated"      # 或 "private"
  ```
  该别名运行在完全私有的独立环境中，不与其他任何别名共享会话、历史记录与工作空间记忆，适合独立项目或私密开发。
- **分组共享模式 (Group Sharing)**:
  ```bash
  export AI_HOME_PROFILE="work"          # 自定义分组名，例如 work, dev, projectA
  ```
  系统会自动创建并接入对应的分组池 (`~/.local/share/ai/agy/pools/<name>`)，仅具有相同分组名的别名之间共享对话与记忆。

> [!TIP]
> - **持久配置**：直接在 `~/.config/ai/providers/<alias>.sh` 中修改 `export AI_HOME_PROFILE=...`。
> - **临时生效**：在终端执行 `export AI_HOME_PROFILE=isolated` 或在启动指令前直接指定 `AI_HOME_PROFILE=isolated ai agya`。
> - **全局工具链与环境**：无论处于哪种共享模式，系统均自动桥接全局 MCP / Skills (`~/.gemini/config`) 及开发工具链（`cargo`, `rustup`, `npm`, `.gitconfig`, `.ssh`, `.config/gh`）。

#### 3. 辅助命令
- `ai agya whoami` : 查看 `agya` 当前绑定的 Google 账号邮箱、HOME 路径与数据共享状态
- `ai agya login` : 重新发起 Google OAuth 认证
- `ai agya logout` : 退出登录并清除当前别名的凭据
- `ai reset agya` : 重置 `agya` 的凭据与运行时环境（不会误删共享池中的持久化对话记录）
- `ai env agya` : 查看 `agya` 的详细运行环境与 Data Sharing 状态

---

## 🛠️ 命令说明

### Provider
- `ai provider list` : 查看可用 Provider
- `ai provider use <name>` : 切换当前 active Provider
- `ai provider add [name]` : 创建新的 Provider 模板
- `ai provider remove <name>` : 删除 Provider 配置

### CLI 启动
- `ai agy` (Google Antigravity CLI)
- `ai agya` ~ `ai agyg` (Google OAuth 账号 A ~ G)
- `ai codex`
- `ai codexh` (ChatGPT OAuth)
- `ai claude`
- `ai gemini`
- `ai aider`
- `ai qwen`
- `ai openai`

### Environment & Doctor
- `ai env` : 查看当前 active Provider 的环境变量
- `ai doctor` : 检查 CLI 安装、Provider 配置与 Secret 状态
- `ai update` : Git pull 自动更新
- `ai init` : 重新初始化配置
