defmodule Eclaw.Telemetry do
  @moduledoc """
  Telemetry instrumentation for Eclaw.

  Emits events:
  - `[:eclaw, :llm, :request]` — LLM API call (duration, model, token count)
  - `[:eclaw, :tool, :execute]` — Tool execution (duration, tool name, success/error)
  - `[:eclaw, :agent, :loop]` — Agent loop iteration (iteration count, compaction)
  - `[:eclaw, :agent, :chat]` — Full chat round-trip (total duration, iterations)

  ## Usage

      # Attach handler (e.g. log to console)
      Eclaw.Telemetry.attach_default_handlers()

      # Or attach manually
      :telemetry.attach("my-handler", [:eclaw, :llm, :request, :stop], &handler/4, nil)
  """

  require Logger

  # ── Emit helpers (called from other modules) ─────────────────────────

  @doc "Measure function execution time and emit a telemetry event."
  @spec span(list(atom()), map(), function()) :: term()
  def span(event_name, metadata, fun) do
    start_time = System.monotonic_time()

    try do
      result = fun.()

      duration = System.monotonic_time() - start_time

      result_meta =
        case result do
          {:error, reason} -> %{result: :error, error: inspect(reason)}
          {:ok, _, _, %{requests: n}} -> %{result: :ok, iterations: n}
          _ -> %{result: :ok}
        end

      :telemetry.execute(
        event_name ++ [:stop],
        %{duration: duration},
        Map.merge(metadata, result_meta)
      )

      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          event_name ++ [:exception],
          %{duration: duration},
          Map.merge(metadata, %{error: Exception.message(e)})
        )

        reraise e, __STACKTRACE__
    end
  end

  @doc "Emit a counter event (no duration)."
  @spec emit(list(atom()), map(), map()) :: :ok
  def emit(event_name, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(event_name, measurements, metadata)
  end

  # ── Default console handlers ──────────────────────────────────────

  @doc "Attach default log handlers for development."
  def attach_default_handlers do
    handler_id = "eclaw-default-logger"

    events = [
      [:eclaw, :llm, :request, :stop],
      [:eclaw, :llm, :request, :exception],
      [:eclaw, :tool, :execute, :stop],
      [:eclaw, :agent, :chat, :stop]
    ]

    # Detach first to make idempotent (safe on app restart / re-attach)
    :telemetry.detach(handler_id)

    :telemetry.attach_many(
      handler_id,
      events,
      &handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event([:eclaw, :llm, :request, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("[Telemetry] LLM request: #{metadata[:model]} — #{duration_ms}ms")
  end

  def handle_event([:eclaw, :llm, :request, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.error("[Telemetry] LLM error: #{metadata[:error]} — #{duration_ms}ms")
  end

  def handle_event([:eclaw, :tool, :execute, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("[Telemetry] Tool #{metadata[:tool]}: #{duration_ms}ms")
  end

  def handle_event([:eclaw, :agent, :chat, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info(
      "[Telemetry] Chat complete: #{metadata[:iterations]} iterations, #{duration_ms}ms total"
    )
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok
end
