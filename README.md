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

### Google Antigravity (AGY) OAuth 多账号与并发隔离支持

系统原生支持 Google Antigravity CLI (`agy`)，通过独立 Profile 隔离与独立 Auth Storage，彻底解决多终端并发运行或切换账号时的凭据冲突与串号问题：

#### 1. 多账号完全独立隔离
- **`ai agya`**：绑定 Google 账号 A。首次运行提示 Google OAuth 授权链接，浏览器登录账号 A 完成认证。
- **`ai agyb`**：绑定 Google 账号 B。首次运行提示 Google OAuth 授权链接，浏览器登录账号 B 完成认证。
- **`ai agyc`** / **`ai agyd`**：分别绑定 Google 账号 C、D。
- 每个别名拥有专属隔离的运行时 HOME 目录 (`~/.local/share/ai/agy/<alias>/`)，**不同终端同时并发运行多个 AI 互不干扰，换号/退出永不串号！**

#### 2. 全局配置与技能自动共享
虽然各账号的 OAuth 凭据与运行时会话严格隔离，系统会自动打通并共享：
- 全局 MCP 配置与 Skills/Workflows (`~/.gemini/config` 自动软链接到集中共享目录)。
- 用户常用开发工具链（如 `cargo`, `rustup`, `npm` 等直接复用）。
- 既享有团队共享配置的高效，又拥有多账号 100% 的凭据隔离安全。

#### 3. 辅助命令
- `ai agya whoami` : 查看 `agya` 当前绑定的 Google 账号邮箱与 HOME 状态
- `ai agya login` : 重新发起 Google OAuth 认证
- `ai agya logout` : 退出登录并清除当前别名的凭据
- `ai reset agya` : 重置 `agya` 的 HOME 空间及凭据

---

## 🛠️ 命令说明

### Provider
- `ai provider list` : 查看可用 Provider
- `ai provider use <name>` : 切换当前 active Provider
- `ai provider add [name]` : 创建新的 Provider 模板
- `ai provider remove <name>` : 删除 Provider 配置

### CLI 启动
- `ai agy` (Google Antigravity CLI)
- `ai agya` (Google OAuth 账号 A)
- `ai agyb` (Google OAuth 账号 B)
- `ai agyc` (Google OAuth 账号 C)
- `ai agyd` (Google OAuth 账号 D)
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
