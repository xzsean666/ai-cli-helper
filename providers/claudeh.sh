# Provider configuration for claudeh alias (Claude Subscription / OAuth)
export AI_PROVIDER_NAME="claudeh"
export AI_AUTH_MODE="oauth"

# 数据共享模式 (支持 shared-team / isolated / 自定义分组):
# - "shared-team" 或 "shared": 共享全部项目会话记录与历史 (默认推荐)
# - "isolated" 或 "private": 完全独立私有空间，不与其他 alias 共享任何对话
# - 自定义分组名 (如 "claude-oauth", "work"): 仅在相同分组名的 alias 之间共享
export AI_HOME_PROFILE="${AI_HOME_PROFILE:-shared-team}"

# Claude OAuth 模式通过官方授权登录（ai claudeh login），
# 凭据独立保存在 ~/.local/share/ai/claude/auth/claudeh/ 中，无需配置 ANTHROPIC_API_KEY。
