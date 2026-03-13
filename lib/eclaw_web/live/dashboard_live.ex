defmodule EclawWeb.DashboardLive do
  use Phoenix.LiveView, layout: {EclawWeb.Layouts, :app}

  @refresh_interval 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Eclaw.Events.subscribe()
      {:ok, timer_ref} = :timer.send_interval(@refresh_interval, self(), :refresh)
      {:ok, assign(socket, stats: collect_stats(), events: [], tool_log: [], timer_ref: timer_ref)}
    else
      {:ok, assign(socket, stats: collect_stats(), events: [], tool_log: [], timer_ref: nil)}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, stats: collect_stats())}
  end

  def handle_info({:eclaw_event, {:tool_call, name, input}}, socket) do
    entry = %{time: DateTime.utc_now(), tool: name, input: inspect(input, limit: 50), status: :running}
    tool_log = [entry | Enum.take(socket.assigns.tool_log, 49)]
    {:noreply, assign(socket, tool_log: tool_log)}
  end

  def handle_info({:eclaw_event, {:tool_result, name, result}}, socket) do
    # Update the latest entry with matching tool name
    tool_log =
      socket.assigns.tool_log
      |> update_latest_tool(name, String.slice(result, 0, 100))

    {:noreply, assign(socket, tool_log: tool_log)}
  end

  def handle_info({:eclaw_event, {:text_delta, text}}, socket) do
    event = %{time: DateTime.utc_now(), type: :text, content: String.slice(text, 0, 80)}
    events = [event | Enum.take(socket.assigns.events, 99)]
    {:noreply, assign(socket, events: events)}
  end

  def handle_info({:eclaw_event, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("reset", _, socket) do
    Eclaw.Agent.reset()
    {:noreply, put_flash(socket, :info, "Conversation reset")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-cyan-400">🦀 Eclaw Dashboard</h1>
        <div class="flex gap-3">
          <button phx-click="reset" class="px-3 py-1 bg-yellow-600 hover:bg-yellow-500 rounded text-sm">
            Reset Chat
          </button>
          <a href="/chat" class="px-3 py-1 bg-cyan-600 hover:bg-cyan-500 rounded text-sm">
            Web Chat →
          </a>
        </div>
      </div>

      <%!-- Stats cards --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <.stat_card label="Provider" value={@stats.provider} />
        <.stat_card label="Model" value={@stats.model} />
        <.stat_card label="Memory" value={"#{@stats.memory_count} entries"} />
        <.stat_card label="Plugins" value={"#{@stats.plugin_count} tools"} />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%!-- Tool execution log --%>
        <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
          <h2 class="text-lg font-semibold text-gray-300 mb-3">⚡ Tool Activity</h2>
          <div class="space-y-2 max-h-80 overflow-y-auto">
            <div :for={entry <- @tool_log} class="flex items-start gap-2 text-sm">
              <span class={[
                "px-1.5 py-0.5 rounded text-xs font-mono",
                if(entry.status == :running, do: "bg-yellow-900 text-yellow-300 animate-pulse-fast", else: "bg-green-900 text-green-300")
              ]}>
                {entry.tool}
              </span>
              <span class="text-gray-400 truncate">{entry.input}</span>
            </div>
            <p :if={@tool_log == []} class="text-gray-600 text-sm">No tool activity yet</p>
          </div>
        </div>

        <%!-- Event stream --%>
        <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
          <h2 class="text-lg font-semibold text-gray-300 mb-3">📡 Event Stream</h2>
          <div class="space-y-1 max-h-80 overflow-y-auto font-mono text-xs">
            <div :for={event <- @events} class="flex gap-2 text-gray-400">
              <span class="text-gray-600">{Calendar.strftime(event.time, "%H:%M:%S")}</span>
              <span class="text-cyan-400">[{event.type}]</span>
              <span class="truncate">{event.content}</span>
            </div>
            <p :if={@events == []} class="text-gray-600">Waiting for events...</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def terminate(_reason, socket) do
    if timer_ref = socket.assigns[:timer_ref] do
      :timer.cancel(timer_ref)
    end

    :ok
  end

  # ── Components ────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
      <p class="text-xs text-gray-500 uppercase tracking-wider">{@label}</p>
      <p class="text-lg font-semibold text-gray-200 mt-1 truncate">{@value}</p>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────

  defp collect_stats do
    %{
      provider: to_string(Eclaw.Config.provider()),
      model: Eclaw.Config.model(),
      memory_count: safe_call(fn -> Eclaw.Memory.count() end, 0),
      plugin_count: safe_call(fn -> length(Eclaw.ToolRegistry.list()) end, 0)
    }
  end

  defp safe_call(fun, default) do
    fun.()
  catch
    :exit, _ -> default
  end

  defp update_latest_tool(log, name, result) do
    case Enum.split_while(log, fn e -> e.tool != name or e.status != :running end) do
      {before, [entry | rest]} ->
        before ++ [%{entry | status: :done, input: result} | rest]

      _ ->
        log
    end
  end
end
