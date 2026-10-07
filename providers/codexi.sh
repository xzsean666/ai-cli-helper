# Provider configuration for codexi alias (ChatGPT OAuth - Account 2)
export AI_PROVIDER_NAME="codexi"
export AI_AUTH_MODE="chatgpt"

# 数据共享模式 (支持 shared-team / isolated / 自定义分组):
# - "shared-team" 或 "shared": 共享全部会话记录、历史会话与数据库 (默认推荐，与 codex 其它别名无缝续接会话)
# - "isolated" 或 "private": 完全独立私有空间，不与其他 alias 共享任何对话
# - 自定义分组名 (如 "chatgpt-oauth", "work"): 仅在相同分组名的 alias 之间共享
export AI_HOME_PROFILE="${AI_HOME_PROFILE:-shared-team}"

# ChatGPT OAuth 模式通过浏览器或设备码登录（ai codexi login / ai codexi login --device-auth），
# 凭据独立保存在 ~/.local/share/ai/codex/auth/codexi/ 中，无需配置 OPENAI_BASE_URL 或 OPENAI_API_KEY。
