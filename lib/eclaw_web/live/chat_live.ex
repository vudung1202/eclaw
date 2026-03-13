defmodule EclawWeb.ChatLive do
  @moduledoc "Web chat interface — send prompts and view streaming responses."
  use Phoenix.LiveView, layout: {EclawWeb.Layouts, :app}

  @impl true
  def mount(_params, session, socket) do
    # Use dedicated session ID (not CSRF token) for agent session continuity
    session_token = session["eclaw_session_id"] || Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    session_id = "web:#{session_token}"

    {:ok,
     assign(socket,
       session_id: session_id,
       messages: [],
       input: "",
       streaming: false,
       current_response: "",
       task_ref: nil
     )}
  end

  @impl true
  def handle_event("submit", %{"prompt" => prompt}, socket) when prompt != "" do
    messages = socket.assigns.messages ++ [%{role: :user, content: prompt}]
    session_id = socket.assigns.session_id
    pid = self()

    task =
      Task.Supervisor.async_nolink(Eclaw.TaskSupervisor, fn ->
        agent = get_or_start_agent(session_id)

        on_chunk = fn
          {:text_delta, text} -> send(pid, {:stream_delta, text})
          {:tool_call, name, _input} -> send(pid, {:stream_tool, name})
          _ -> :ok
        end

        result = Eclaw.Agent.stream(agent, prompt, on_chunk)
        send(pid, {:chat_done, result})
      end)

    {:noreply, assign(socket, messages: messages, input: "", streaming: true, current_response: "", task_ref: task.ref)}
  end

  def handle_event("submit", _, socket), do: {:noreply, socket}

  def handle_event("reset", _, socket) do
    agent = get_or_start_agent(socket.assigns.session_id)
    Eclaw.Agent.reset(agent)
    {:noreply, assign(socket, messages: [], current_response: "", streaming: false)}
  end

  @impl true
  def handle_info({:stream_delta, text}, socket) do
    current = socket.assigns.current_response <> text
    {:noreply, assign(socket, current_response: current)}
  end

  def handle_info({:stream_tool, name}, socket) do
    current = socket.assigns.current_response <> "\n⚡ Using #{name}...\n"
    {:noreply, assign(socket, current_response: current)}
  end

  def handle_info({:chat_done, result}, socket) do
    text =
      case result do
        {:ok, text} -> text
        {:error, reason} -> "Error: #{inspect(reason)}"
      end

    messages = socket.assigns.messages ++ [%{role: :assistant, content: text}]
    {:noreply, assign(socket, messages: messages, streaming: false, current_response: "")}
  end

  # Task completed normally — flush the monitor
  def handle_info({ref, _result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  # Task crashed — stop streaming
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{task_ref: ref}} = socket) do
    {:noreply, assign(socket, streaming: false)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-3rem)]">
      <%!-- Header --%>
      <div class="flex items-center justify-between pb-4 border-b border-gray-800">
        <div class="flex items-center gap-3">
          <a href="/" class="text-gray-500 hover:text-gray-300">← Dashboard</a>
          <h1 class="text-xl font-bold text-cyan-400">🦀 Eclaw Chat</h1>
        </div>
        <button phx-click="reset" class="px-3 py-1 bg-gray-700 hover:bg-gray-600 rounded text-sm">
          Clear
        </button>
      </div>

      <%!-- Messages --%>
      <div class="flex-1 overflow-y-auto py-4 space-y-4" id="messages" phx-hook="ScrollBottom">
        <div :for={msg <- @messages} class={[
          "max-w-3xl p-3 rounded-lg",
          if(msg.role == :user, do: "ml-auto bg-cyan-900/40 border border-cyan-800", else: "bg-gray-800/60 border border-gray-700")
        ]}>
          <p class="text-xs text-gray-500 mb-1">{msg.role}</p>
          <p class="whitespace-pre-wrap text-sm">{msg.content}</p>
        </div>

        <%!-- Streaming response --%>
        <div :if={@streaming} class="max-w-3xl p-3 rounded-lg bg-gray-800/60 border border-gray-700">
          <p class="text-xs text-gray-500 mb-1">assistant</p>
          <p class="whitespace-pre-wrap text-sm">{@current_response}<span class="animate-pulse-fast text-cyan-400">▊</span></p>
        </div>
      </div>

      <%!-- Input --%>
      <form phx-submit="submit" class="pt-4 border-t border-gray-800">
        <div class="flex gap-3">
          <input
            type="text"
            name="prompt"
            value={@input}
            placeholder="Type a message..."
            autocomplete="off"
            disabled={@streaming}
            class="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-cyan-500 disabled:opacity-50"
          />
          <button
            type="submit"
            disabled={@streaming}
            class="px-4 py-2 bg-cyan-600 hover:bg-cyan-500 disabled:bg-gray-700 rounded-lg text-sm font-medium"
          >
            Send
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp get_or_start_agent(session_id) do
    Eclaw.SessionManager.get_or_start!(session_id)
  end
end
