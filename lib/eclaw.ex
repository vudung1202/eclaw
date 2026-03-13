defmodule Eclaw do
  @moduledoc """
  Eclaw — Autonomous AI Agent powered by LLM with Tool Use.

  ## CLI

      $ mix eclaw

  ## IEx

      iex> Eclaw.chat("List all files")
      {:ok, "Here are the files..."}

  ## Streaming

      iex> Eclaw.stream("Hello", fn {:text_delta, t} -> IO.write(t); _ -> :ok end)

  ## Memory

      iex> Eclaw.remember("User prefers Vietnamese")
      iex> Eclaw.memories()

  ## Plugin tools

      iex> Eclaw.register_tool(MyApp.WeatherTool)

  ## Telegram

      iex> Eclaw.start_telegram()
  """

  # ── Chat (Singleton — CLI) ───────────────────────────────────────

  @spec chat(String.t()) :: {:ok, String.t()} | {:error, term()}
  def chat(prompt), do: Eclaw.Agent.chat(prompt)

  @spec stream(String.t(), function()) :: {:ok, String.t()} | {:error, term()}
  def stream(prompt, on_chunk), do: Eclaw.Agent.stream(prompt, on_chunk)

  @spec reset() :: :ok
  def reset, do: Eclaw.Agent.reset()

  # ── Session-aware Chat ──────────────────────────────────────────

  @spec session_chat(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def session_chat(session_id, prompt) do
    case Eclaw.SessionManager.get_or_create(session_id) do
      {:ok, pid} -> Eclaw.Agent.chat(pid, prompt)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec session_reset(String.t()) :: :ok
  def session_reset(session_id), do: Eclaw.SessionManager.stop(session_id)

  @spec sessions() :: [map()]
  def sessions, do: Eclaw.SessionManager.list_sessions()

  # ── Memory ─────────────────────────────────────────────────────────

  @spec remember(String.t(), atom(), keyword()) :: :ok
  def remember(content, type \\ :fact, opts \\ []) do
    key = Keyword.get(opts, :key, "user_#{System.system_time(:millisecond)}")
    Eclaw.Memory.store(key, content, type, opts)
  end

  @spec memories() :: [map()]
  def memories, do: Eclaw.Memory.list_all()

  @spec search_memory(String.t()) :: [map()]
  def search_memory(query), do: Eclaw.Memory.search(query)

  @spec forget_all() :: :ok
  def forget_all, do: Eclaw.Memory.clear()

  # ── Model switching ──────────────────────────────────────────────

  @spec set_model(String.t()) :: :ok
  def set_model(model), do: Eclaw.Agent.set_model(model)

  @spec model() :: String.t()
  def model, do: Eclaw.Agent.get_model()

  # ── Usage tracking ──────────────────────────────────────────────

  @spec usage() :: map()
  def usage, do: Eclaw.Agent.get_usage()

  @spec status() :: map()
  def status, do: Eclaw.Agent.status()

  # ── Plugin Tools ──────────────────────────────────────────────────

  @spec register_tool(module()) :: :ok | {:error, term()}
  def register_tool(module), do: Eclaw.ToolRegistry.register(module)

  # ── Skills ──────────────────────────────────────────────────────

  @spec skills() :: [map()]
  def skills, do: Eclaw.Skills.load_all()

  # ── Events ────────────────────────────────────────────────────────

  @spec subscribe() :: {:ok, pid()} | {:error, term()}
  def subscribe, do: Eclaw.Events.subscribe()

  # ── MCP ─────────────────────────────────────────────────────────

  @spec mcp_tools() :: [map()]
  def mcp_tools, do: Eclaw.MCP.list_tools()

  @spec mcp_connect(map()) :: :ok | {:error, term()}
  def mcp_connect(config), do: Eclaw.MCP.connect(config)

  # ── Telegram ──────────────────────────────────────────────────────

  @doc "Start Telegram bot adapter."
  @spec start_telegram(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_telegram(opts \\ []) do
    token = Keyword.get(opts, :token) || Application.get_env(:eclaw, :telegram_token)

    if token do
      Eclaw.ChannelManager.register(Eclaw.Channels.Telegram, token: token)
    else
      {:error, :missing_telegram_token}
    end
  end
end
