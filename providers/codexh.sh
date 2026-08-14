# Provider configuration for codexh alias (ChatGPT OAuth)
export AI_PROVIDER_NAME="codexh"
export AI_AUTH_MODE="chatgpt"

# Keep OAuth credentials separate from API-key providers. Codex stores its
# login state under this profile's .codex directory after HOME is isolated.
export AI_HOME_PROFILE="chatgpt-oauth"

# Do not set OPENAI_BASE_URL, OPENAI_API_KEY, or OPENAI_MODEL here. The Codex
# wrapper will then use its native ChatGPT/OAuth authentication path.
