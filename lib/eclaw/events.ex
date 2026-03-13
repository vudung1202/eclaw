defmodule Eclaw.Events do
  @moduledoc """
  Event system using Registry pub/sub.

  Allows any process to subscribe and receive events from Agent
  (text deltas, tool calls, errors, etc.) — useful for Phoenix LiveView,
  WebSocket clients, telemetry handlers.

  ## Usage

      # Subscribe
      Eclaw.Events.subscribe()

      # In GenServer/LiveView handle_info:
      def handle_info({:eclaw_event, event}, state) do
        # event is one of {:text_delta, text}, {:tool_call, name, input}, etc.
        ...
      end

      # Publish (typically called by Agent)
      Eclaw.Events.broadcast({:text_delta, "Hello"})
  """

  @registry Eclaw.EventRegistry
  @topic "eclaw:agent"

  # ── Setup ──────────────────────────────────────────────────────────

  @doc "Child spec for the event Registry (added to supervision tree)."
  def child_spec(_opts) do
    Registry.child_spec(keys: :duplicate, name: @registry)
  end

  # ── Public API ─────────────────────────────────────────────────────

  @doc "Subscribe the current process to receive events."
  @spec subscribe() :: {:ok, pid()} | {:error, term()}
  def subscribe do
    Registry.register(@registry, @topic, [])
  end

  @doc "Unsubscribe the current process."
  @spec unsubscribe() :: :ok
  def unsubscribe do
    Registry.unregister(@registry, @topic)
  end

  @doc "Broadcast event to all subscribers."
  @spec broadcast(term()) :: :ok
  def broadcast(event) do
    Registry.dispatch(@registry, @topic, fn entries ->
      for {pid, _} <- entries do
        send(pid, {:eclaw_event, event})
      end
    end)
  end

  @doc """
  Create a lazy stream of events.

  Useful for consuming events in a function:

      Eclaw.Events.stream()
      |> Stream.each(fn event -> IO.inspect(event) end)
      |> Stream.run()
  """
  @spec stream(timeout()) :: Enumerable.t()
  def stream(timeout \\ 60_000) do
    Stream.resource(
      fn -> subscribe(); :ok end,
      fn
        :halt ->
          {:halt, :halt}

        state ->
          receive do
            {:eclaw_event, {:done, _} = event} ->
              {[event], :halt}

            {:eclaw_event, event} ->
              {[event], state}
          after
            timeout ->
              {:halt, state}
          end
      end,
      fn _state -> unsubscribe() end
    )
  end
end
