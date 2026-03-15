import Config

config :eclaw,
  # Provider: :anthropic | :openai
  provider: :anthropic,

  # LLM settings
  model: "claude-sonnet-4-20250514",
  max_tokens: 8192,
  api_url: "https://api.anthropic.com/v1/messages",
  anthropic_version: "2023-06-01",

  # Agent settings
  max_iterations: 25,

  # Tool settings
  command_timeout: 30_000,

  # Context management
  # Token budget per request (compacts if exceeded). Lower this if account has low rate limits.
  input_token_budget: 20_000,

  # Retry settings
  max_retries: 3,

  # Browser automation
  chrome_cdp_port: 9222,

  # MCP servers (auto-connected on startup)
  mcp_servers: [],

  # Dashboard
  start_dashboard: false

# Phoenix endpoint
config :eclaw, EclawWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: String.duplicate("eclaw_dev_secret_", 4),
  live_view: [signing_salt: "eclaw_lv"],
  render_errors: [formats: [html: EclawWeb.Layouts], layout: false],
  pubsub_server: Eclaw.PubSub,
  server: true
