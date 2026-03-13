# CLAUDE.md — Eclaw Project Guide

## What is Eclaw?

Autonomous AI Agent built with Elixir/OTP. Connects to LLM APIs (Anthropic Claude, OpenAI GPT, Google Gemini), executes tools, manages multi-turn conversations with per-user sessions, persistent memory (DETS + vector search), and a real-time LiveView dashboard.

## Quick Reference

```bash
# Run CLI
mix eclaw

# Run with dashboard
ECLAW_DASHBOARD=true mix eclaw

# IEx console
iex -S mix

# Compile
mix compile

# Run tests
mix test
```

## Tech Stack

- **Language:** Elixir ~> 1.18, Erlang/OTP 27+
- **HTTP:** Req ~> 0.5
- **Web:** Phoenix ~> 1.7, Phoenix LiveView ~> 1.0, Bandit ~> 1.0
- **Serialization:** Jason ~> 1.4
- **Observability:** Telemetry ~> 1.3

## Architecture Overview

OTP supervision tree with `rest_for_one` strategy (children depend on those started before them):

```
Eclaw.Supervisor (rest_for_one)
├── Phoenix.PubSub (Eclaw.PubSub)
├── Registry (unique: Eclaw.Registry)
├── Eclaw.Events (duplicate Registry for pub/sub)
├── Task.Supervisor (Eclaw.TaskSupervisor)
├── Eclaw.Memory (GenServer + DETS)
├── Eclaw.ToolRegistry (GenServer)
├── DynamicSupervisor (Eclaw.SessionSupervisor, max_children: 100)
├── DynamicSupervisor (Eclaw.ChannelSupervisor)
├── Eclaw.ChannelManager (GenServer)
├── Eclaw.Agent (singleton for CLI)
└── EclawWeb.Endpoint (optional, with auth plugs)
```

## Key Patterns

- **Agent dual-mode:** `Eclaw.Agent` runs as singleton (CLI, `name: __MODULE__`) or multi-instance (per-user sessions via Registry `{:agent, session_id}`). Session agents auto-terminate after 30 min idle.
- **Provider abstraction:** `Eclaw.Provider` behaviour → `Providers.Anthropic` / `Providers.OpenAI` / `Providers.Gemini`. OpenAI and Gemini responses normalized to Anthropic format internally.
- **Plugin tools:** Implement `Eclaw.ToolBehaviour` (`name/0`, `description/0`, `input_schema/0`, `execute/1`). Register via `Eclaw.ToolRegistry`. Multi-tool plugins (like `Eclaw.Browser`) expose `tools/0` returning a list.
- **Channel adapters:** Implement `Eclaw.Channel` behaviour. Built-in: Telegram (long polling, user allowlist), Webhook. ChannelManager handles routing async via TaskSupervisor.
- **Session management:** `Eclaw.SessionManager` uses `Eclaw.SessionSupervisor` (DynamicSupervisor, max 100 children) + Registry lookup. `get_or_create/1` with session_id like `"telegram:123456"`. Web chat and webhook use per-session agents (each browser tab gets its own).
- **Context management:** Token estimation (~3.5 chars/token), auto-compaction at 70% of context window, UTF-8 safe tool result truncation (head+tail, 3K char max) using `String.slice`.
- **Security (multi-layer):**
  - Command validation via `Eclaw.Approval`: tiered blocklist (`:blocked` for dangerous commands, `:needs_approval` for risky ones with human-in-the-loop)
  - Path validation via `Eclaw.Security`: forbidden paths regex, symlink resolution (walks every path component), safe prefix allowlist (cwd, ~/.eclaw, /tmp)
  - SSRF protection via `Eclaw.Security.safe_url?/1`: blocks private/internal IPs (RFC1918, loopback, link-local, CGN), IPv6-mapped IPv4, internal hostnames. Used by both `Eclaw.Tools.web_fetch` and `Eclaw.Browser`
  - Redirect validation: auto-redirect disabled, manual single-hop with SSRF re-check
  - Secret redaction in logs: API keys, Bearer tokens, env var secrets
  - Browser: JS injection prevented via Base64 encoding in `browser_evaluate`
- **Authentication:**
  - Web UI: HTTP Basic Auth via `EclawWeb.Plugs.WebAuth` (enabled by `ECLAW_WEB_PASSWORD`)
  - API: Bearer token via `EclawWeb.Plugs.ApiAuth` (default-deny, enabled by `ECLAW_API_TOKEN`, or `ECLAW_API_OPEN=true` to skip)
  - Telegram: user allowlist via `TELEGRAM_ALLOWED_USERS` (default-deny)
  - All comparisons use `Plug.Crypto.secure_compare` (timing-safe)
- **Retry:** Exponential backoff with jitter. Retryable: 429 (4x delay), 500, 502, 503, 529. Max 3 retries, max 30s delay.

## Important Files

| File | Role |
|------|------|
| `lib/eclaw.ex` | Public API facade — entry point for all operations |
| `lib/eclaw/agent.ex` | Core agent loop — LLM calls, tool execution, context management |
| `lib/eclaw/llm.ex` | LLM facade — merges builtin + plugin tools, delegates to provider |
| `lib/eclaw/providers/anthropic.ex` | Anthropic API with SSE streaming parser |
| `lib/eclaw/providers/openai.ex` | OpenAI API adapter (normalizes to Anthropic format) |
| `lib/eclaw/providers/gemini.ex` | Google Gemini API adapter |
| `lib/eclaw/tools.ex` | Tool execution with security checks, SSRF-safe web_fetch |
| `lib/eclaw/security.ex` | Path validation, SSRF protection, symlink resolution |
| `lib/eclaw/approval.ex` | Tiered command blocklist (blocked/needs_approval/safe) |
| `lib/eclaw/browser.ex` | Playwright-based browser automation (5 tools) |
| `lib/eclaw/session_manager.ex` | Per-user session lifecycle (get_or_create, stop, list) |
| `lib/eclaw/channel_manager.ex` | Async message routing: channel → session → agent → channel |
| `lib/eclaw/channels/telegram.ex` | Telegram Bot: long polling, user auth, commands, message splitting |
| `lib/eclaw/application.ex` | OTP supervision tree (rest_for_one) |
| `lib/eclaw_web/plugs/api_auth.ex` | Bearer token auth for API endpoints |
| `lib/eclaw_web/plugs/web_auth.ex` | HTTP Basic Auth for web UI |
| `config/config.exs` | Default config + Phoenix endpoint |
| `config/runtime.exs` | Env var overrides (API keys, tokens, auth, security) |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes (for Claude) | Anthropic API key |
| `OPENAI_API_KEY` | Alt | OpenAI API key (auto-switches provider) |
| `GEMINI_API_KEY` | Alt | Google Gemini API key |
| `TELEGRAM_BOT_TOKEN` | For Telegram | Bot token from @BotFather |
| `TELEGRAM_ALLOWED_USERS` | For Telegram | Comma-separated user IDs (default-deny) |
| `ECLAW_PROVIDER` | No | `anthropic` (default), `openai`, or `gemini` |
| `ECLAW_MODEL` | No | Default: `claude-sonnet-4-20250514` |
| `ECLAW_MAX_TOKENS` | No | Default: `8192` |
| `ECLAW_COMMAND_TIMEOUT` | No | Bash timeout ms, default: `30000` |
| `ECLAW_DASHBOARD` | No | `true` to start Phoenix dashboard |
| `ECLAW_API_TOKEN` | No | Bearer token for API auth (default-deny if unset) |
| `ECLAW_API_OPEN` | No | `true` to allow unauthenticated API access |
| `ECLAW_WEB_PASSWORD` | No | HTTP Basic Auth password for web UI |
| `SECRET_KEY_BASE` | Prod | Phoenix secret key base |
| `ECLAW_SESSION_SALT` | No | Cookie session signing salt |
| `ECLAW_SIGNING_SALT` | No | LiveView signing salt |

## Conventions

- All config access goes through `Eclaw.Config` — never read `Application.get_env` directly in modules.
- Tool results are always strings. Tools return `{:ok, string}` or `string`.
- LLM responses use Anthropic's format internally (content blocks with `type` field). OpenAI responses are normalized.
- Events broadcast via `Eclaw.Events` (Registry-based pub/sub). Dashboard subscribes for real-time updates. Web chat uses direct `send/2` to avoid cross-session event leaks.
- All numeric env vars use `Integer.parse` with validation (not `String.to_integer`).
- Vietnamese comments in code are intentional — this is a Vietnamese developer's project.
