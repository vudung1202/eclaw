import Config

# ── Runtime config — override qua environment variables ────────────

if api_key = System.get_env("ANTHROPIC_API_KEY") do
  config :eclaw, anthropic_api_key: api_key
end

if api_key = System.get_env("OPENAI_API_KEY") do
  config :eclaw, openai_api_key: api_key
  # Auto-switch provider to OpenAI if no explicit provider is set
  unless System.get_env("ECLAW_PROVIDER"), do: config(:eclaw, provider: :openai)
end

if api_key = System.get_env("GEMINI_API_KEY") do
  config :eclaw, gemini_api_key: api_key
  unless System.get_env("ECLAW_PROVIDER"), do: config(:eclaw, provider: :gemini)
end

if model = System.get_env("ECLAW_MODEL") do
  config :eclaw, model: model
end

if max_tokens = System.get_env("ECLAW_MAX_TOKENS") do
  case Integer.parse(max_tokens) do
    {val, ""} -> config :eclaw, max_tokens: val
    _ -> IO.puts(:stderr, "[Eclaw] Warning: ECLAW_MAX_TOKENS='#{max_tokens}' is not a valid integer, ignoring")
  end
end

if timeout = System.get_env("ECLAW_COMMAND_TIMEOUT") do
  case Integer.parse(timeout) do
    {val, ""} -> config :eclaw, command_timeout: val
    _ -> IO.puts(:stderr, "[Eclaw] Warning: ECLAW_COMMAND_TIMEOUT='#{timeout}' is not a valid integer, ignoring")
  end
end

if provider = System.get_env("ECLAW_PROVIDER") do
  provider_atom = case provider do
    "anthropic" -> :anthropic
    "openai" -> :openai
    "gemini" -> :gemini
    other -> raise "Unknown ECLAW_PROVIDER: #{other}. Must be one of: anthropic, openai, gemini"
  end
  config :eclaw, provider: provider_atom
end

if budget = System.get_env("ECLAW_TOKEN_BUDGET") do
  case Integer.parse(budget) do
    {val, ""} -> config :eclaw, input_token_budget: val
    _ -> IO.puts(:stderr, "[Eclaw] Warning: ECLAW_TOKEN_BUDGET='#{budget}' is not a valid integer, ignoring")
  end
end

# ── Telegram ──────────────────────────────────────────────────────

if token = System.get_env("TELEGRAM_BOT_TOKEN") do
  config :eclaw, telegram_token: token
end

if allowed = System.get_env("TELEGRAM_ALLOWED_USERS") do
  user_ids = allowed |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  config :eclaw, telegram_allowed_users: user_ids
end

# ── Phoenix / Security ───────────────────────────────────────────

if secret = System.get_env("SECRET_KEY_BASE") do
  config :eclaw, EclawWeb.Endpoint, secret_key_base: secret
end

if signing_salt = System.get_env("ECLAW_SIGNING_SALT") do
  config :eclaw, EclawWeb.Endpoint, live_view: [signing_salt: signing_salt]
end

if session_salt = System.get_env("ECLAW_SESSION_SALT") do
  config :eclaw, session_signing_salt: session_salt
end

# Auth tokens — read once at startup, not per-request
if api_token = System.get_env("ECLAW_API_TOKEN") do
  config :eclaw, api_token: api_token
end

if web_password = System.get_env("ECLAW_WEB_PASSWORD") do
  config :eclaw, web_password: web_password
end

if System.get_env("ECLAW_API_OPEN") == "true" do
  config :eclaw, api_open: true
end
