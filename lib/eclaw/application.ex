defmodule Eclaw.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Attach telemetry handlers before starting children
    Eclaw.Telemetry.attach_default_handlers()

    children = [
      # Phoenix PubSub (used by LiveView)
      {Phoenix.PubSub, name: Eclaw.PubSub},

      # Process discovery
      {Registry, keys: :unique, name: Eclaw.Registry},

      # Event pub/sub
      Eclaw.Events,

      # Async tool execution (crash-isolated)
      {Task.Supervisor, name: Eclaw.TaskSupervisor},

      # Persistent memory (DETS-backed)
      Eclaw.Memory,

      # Conversation history (DETS-backed)
      Eclaw.History,

      # Tool result cache (ETS-backed, TTL expiration)
      Eclaw.Cache,

      # Plugin tool registry
      Eclaw.ToolRegistry,

      # Per-user agent sessions (Telegram, Discord, ...) — capped to prevent DoS
      {DynamicSupervisor, strategy: :one_for_one, name: Eclaw.SessionSupervisor, max_children: 100},

      # Channel adapter supervisor
      {DynamicSupervisor, strategy: :one_for_one, name: Eclaw.ChannelSupervisor},
      Eclaw.ChannelManager,

      # Scheduled task manager (DETS-backed, fires via ChannelManager)
      Eclaw.Scheduler,

      # OpenClaw skill discovery (ETS-backed index)
      Eclaw.Skills.OpenClaw,

      # MCP client — external tool integration
      Eclaw.MCP,

      # Agent GenServer — conversation + agent loop
      {Eclaw.Agent, []}
    ] ++ maybe_start_dashboard()

    opts = [strategy: :rest_for_one, name: Eclaw.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Register channels after supervision tree is ready
        register_channels()
        # Register browser automation plugin
        register_plugins()
        {:ok, pid}

      error ->
        error
    end
  end

  # Register channels via ChannelManager (start adapter + add to routing map)
  defp register_channels do
    token = Eclaw.Config.get(:telegram_token, nil) || System.get_env("TELEGRAM_BOT_TOKEN")

    if token && token != "" do
      Eclaw.ChannelManager.register(Eclaw.Channels.Telegram, token: token)
    end
  end

  defp register_plugins do
    # Browser tools are auto-registered by ToolRegistry.init

    # Register schedule management tool
    Eclaw.ToolRegistry.register(Eclaw.Tools.Schedule)

    # Register MCP management tool
    Eclaw.ToolRegistry.register(Eclaw.Tools.McpManage)

    # Register OpenClaw skill search tool
    Eclaw.ToolRegistry.register(Eclaw.Tools.SkillSearch)

    # Register MCP tools (discovered from connected servers)
    mcp_tools = Eclaw.MCP.tool_definitions()
    if mcp_tools != [] do
      Enum.each(mcp_tools, fn tool_def ->
        Eclaw.ToolRegistry.register_tool_definition(tool_def)
      end)
    end
  end

  defp maybe_start_dashboard do
    if Eclaw.Config.get(:start_dashboard, false) or System.get_env("ECLAW_DASHBOARD") == "true" do
      [EclawWeb.Endpoint]
    else
      []
    end
  end
end
