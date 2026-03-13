# 🦀 Eclaw

Autonomous AI Agent built with Elixir/OTP. Inspired by [OpenClaw](https://github.com/openclaw/openclaw).

Eclaw connects to LLM APIs (Anthropic Claude, OpenAI GPT), executes tools on your system, and manages multi-turn conversations — all backed by OTP supervision trees, persistent memory, and a real-time LiveView dashboard.

## Features

- **Agent Loop** — send prompt → LLM responds → calls tools if needed → loops until done
- **6 Built-in Tools** — `execute_bash`, `read_file`, `write_file`, `list_directory`, `search_files`, `web_fetch`
- **Browser Automation** — Playwright-based tools: navigate, screenshot, click, type, evaluate JS
- **Streaming** — real-time text output via SSE (Server-Sent Events)
- **Multi-provider** — Anthropic Claude, OpenAI GPT, and Google Gemini, switchable via env var
- **Per-user Sessions** — each user gets an isolated Agent with idle auto-cleanup (30 min)
- **Telegram Bot** — auto-start with long polling, per-user sessions, user allowlist, message splitting, Markdown
- **Plugin System** — register custom tools at runtime via `Eclaw.ToolBehaviour`
- **Persistent Memory** — DETS-backed storage with vector search (OpenAI embeddings), survives restarts
- **Context Management** — token budget, auto-compaction, rate limit protection, UTF-8 safe truncation
- **Security** — tiered command approval (blocked/needs-approval/safe), SSRF protection, path traversal prevention with symlink resolution, secret redaction in logs
- **Authentication** — HTTP Basic Auth (web UI), Bearer token (API), timing-safe comparison, default-deny
- **Retry & Backoff** — exponential backoff with jitter, smart 429 token limit detection
- **Telemetry** — instrumented LLM calls, tool execution, agent loop duration
- **LiveView Dashboard** — real-time monitoring, web chat, tool activity log
- **Channel Adapters** — behaviour for Discord/Slack/custom platforms, webhook included
- **CLI REPL** — interactive terminal with streaming, slash commands, memory management

## Requirements

- Elixir ~> 1.18
- Erlang/OTP 27+
- An Anthropic, OpenAI, or Google Gemini API key

## Quick Start

```bash
git clone <repo-url> eclaw && cd eclaw
mix deps.get

export ANTHROPIC_API_KEY="sk-ant-..."
mix eclaw
```

```
🦀 Eclaw Agent v0.1

eclaw> List the files in the current directory
  ⚡ list_directory `.`
  → [dir] config [dir] lib [file] mix.exs ...

Here are the files in the current directory...

eclaw> /help
```

## Usage

### CLI

```bash
mix eclaw
```

| Command | Description |
|---------|-------------|
| `/reset` | Reset conversation history |
| `/model` | Show provider, model, max tokens |
| `/memory` | List stored memories |
| `/remember <text>` | Save something to memory |
| `/forget` | Clear all memories |
| `/help` | Show commands |
| `/exit` | Quit |

### IEx

```elixir
iex -S mix

iex> Eclaw.chat("What files are in this project?")
{:ok, "Here are the files..."}

iex> Eclaw.stream("Explain mix.exs", fn
...>   {:text_delta, t} -> IO.write(t)
...>   _ -> :ok
...> end)

iex> Eclaw.remember("User prefers Vietnamese")
iex> Eclaw.memories()
iex> Eclaw.reset()
```

### Telegram Bot

1. Create a bot via [@BotFather](https://t.me/BotFather) on Telegram and copy the token.

2. Start Eclaw — bot auto-connects:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
iex -S mix
# [info] [Telegram] Bot @your_bot (YourBot) ready
```

Each user gets an isolated conversation session (auto-cleanup after 30 min idle).

**Security:** Set `TELEGRAM_ALLOWED_USERS` to restrict access (comma-separated user IDs). If unset, all users are rejected by default.

**Bot commands:**

| Command | Description |
|---------|-------------|
| `/start` | Start a new conversation |
| `/reset` | Reset conversation history |
| `/help` | Show available commands |

Messages longer than 4096 characters are automatically split. Markdown formatting is supported with plain-text fallback.

### Web Dashboard

```bash
ECLAW_DASHBOARD=true iex -S mix
# Open http://localhost:4000
```

Protect the web UI with a password:

```bash
export ECLAW_WEB_PASSWORD="your-password"
```

- `/` — Dashboard: provider info, memory stats, tool activity, event stream
- `/chat` — Web chat interface with per-session streaming (each browser tab gets its own agent)
- `/api/status` — JSON health check
- `/api/webhook` — POST `{"from": "id", "text": "message"}` for integrations

**API Authentication:** Set `ECLAW_API_TOKEN` to require Bearer token authentication for `/api/*` endpoints. If unset, API endpoints are closed by default (set `ECLAW_API_OPEN=true` to allow unauthenticated access).

### OpenAI Provider

```bash
export OPENAI_API_KEY="sk-..."
export ECLAW_PROVIDER=openai
export ECLAW_MODEL=gpt-4o
mix eclaw
```

### Google Gemini Provider

```bash
export GEMINI_API_KEY="AI..."
export ECLAW_PROVIDER=gemini
export ECLAW_MODEL=gemini-2.0-flash
mix eclaw
```

## Configuration

All settings via environment variables:

| Env Variable | Default | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | Anthropic API key (required for Claude) |
| `OPENAI_API_KEY` | — | OpenAI API key (auto-switches provider) |
| `GEMINI_API_KEY` | — | Google Gemini API key |
| `ECLAW_MODEL` | `claude-sonnet-4-20250514` | Model to use |
| `ECLAW_MAX_TOKENS` | `8192` | Max tokens per response |
| `ECLAW_PROVIDER` | `anthropic` | LLM provider (`anthropic`, `openai`, or `gemini`) |
| `ECLAW_COMMAND_TIMEOUT` | `30000` | Bash command timeout in ms |
| `ECLAW_TOKEN_BUDGET` | `60000` | Max input tokens before auto-compaction |
| `ECLAW_DASHBOARD` | `false` | Start Phoenix dashboard |
| `TELEGRAM_BOT_TOKEN` | — | Telegram Bot API token (auto-starts bot) |
| `TELEGRAM_ALLOWED_USERS` | — | Comma-separated Telegram user IDs allowed to use the bot |
| `ECLAW_API_TOKEN` | — | Bearer token for API authentication |
| `ECLAW_API_OPEN` | `false` | Set `true` to allow unauthenticated API access |
| `ECLAW_WEB_PASSWORD` | — | HTTP Basic Auth password for web UI |
| `SECRET_KEY_BASE` | (dev default) | Phoenix secret key base (set in production) |
| `ECLAW_SESSION_SALT` | (dev default) | Cookie session signing salt |
| `ECLAW_SIGNING_SALT` | (dev default) | LiveView signing salt |

## Plugin Tools

Create custom tools by implementing `Eclaw.ToolBehaviour`:

```elixir
defmodule MyApp.Tools.Weather do
  @behaviour Eclaw.ToolBehaviour

  @impl true
  def name, do: "get_weather"

  @impl true
  def description, do: "Get current weather for a city"

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "city" => %{"type" => "string", "description" => "City name"}
      },
      "required" => ["city"]
    }
  end

  @impl true
  def execute(%{"city" => city}) do
    {:ok, "Weather in #{city}: 25°C, sunny"}
  end
end

# Register at runtime
Eclaw.register_tool(MyApp.Tools.Weather)
```

The LLM will automatically discover and use registered tools.

## Channel Adapters

Implement `Eclaw.Channel` to connect messaging platforms:

```elixir
defmodule MyApp.DiscordAdapter do
  @behaviour Eclaw.Channel

  @impl true
  def name, do: :discord

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def send_message(channel_id, text, _opts) do
    # Call Discord API
    {:ok, :sent}
  end

  @impl true
  def handle_incoming(event) do
    {:ok, %{from: event.author.id, text: event.content}}
  end
end

# Register
Eclaw.ChannelManager.register(MyApp.DiscordAdapter, token: "bot-token...")
```

## License

MIT
