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

2. **运行一键初始化脚本**:
   ```bash
   ./ai-init.sh
   ```
   *初始化会自动将 `~/.config/ai/bin` 加入 PATH，并自动在 `~/.bashrc` (或 `~/.zshrc`) 中写入初始化代码。*

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

### ChatGPT OAuth 登录

初始化后可以使用内置的 `codexh` 示例，通过浏览器登录 ChatGPT。它使用独立的
`chatgpt-oauth` profile，不会覆盖 API key provider 的登录状态：

```bash
ai codexh login       # 打开浏览器完成 ChatGPT OAuth 登录
ai codexh              # 使用 ChatGPT OAuth 启动 Codex
```

官方 Codex CLI 支持 `codex login` 的 ChatGPT 登录方式；OAuth 模式不需要配置
`OPENAI_BASE_URL` 或 `OPENAI_API_KEY`。

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
