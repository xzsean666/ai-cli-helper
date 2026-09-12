# Provider configuration for agye (Google Antigravity CLI - Account E)
export AI_PROVIDER_NAME="agye"
export AI_AUTH_MODE="google-oauth"

# 数据共享模式 (支持 shared-team / isolated / 自定义分组):
# - "shared-team" 或 "shared": 共享全部对话记录、工作空间、历史会话与记忆 (默认推荐)
# - "isolated" 或 "private": 完全独立私有空间，不与其他 alias 共享任何对话
# - 自定义分组名 (如 "work", "dev"): 仅在相同分组名的 alias 之间共享
export AI_HOME_PROFILE="${AI_HOME_PROFILE:-shared-team}"
