defmodule Eclaw.MCP.HttpTransport do
  @moduledoc """
  HTTP/SSE transport for MCP servers.

  Connects to MCP servers that expose an HTTP endpoint with Server-Sent Events (SSE)
  for receiving messages and a JSON-RPC POST endpoint for sending requests.

  ## Flow

  1. Connect to the SSE endpoint (GET). The server sends an `endpoint` event
     containing the URL to POST JSON-RPC messages to.
  2. Send JSON-RPC requests via POST to the provided endpoint.
  3. Receive responses via SSE `message` events.
  4. Reconnect with exponential backoff on disconnect.

  ## Usage

      {:ok, pid} = HttpTransport.start_link(%{
        url: "http://localhost:3000/sse",
        headers: [{"Authorization", "Bearer token"}]
      })

      {:ok, result} = HttpTransport.send_request(pid, "tools/list", %{})
  """

  use GenServer
  require Logger

  @default_sse_path "/sse"
  @connect_timeout 15_000
  @request_timeout 30_000
  @max_reconnect_delay 60_000
  @initial_reconnect_delay 1_000

  defstruct [
    :url,
    :post_endpoint,
    :sse_task,
    :headers,
    pending: %{},
    next_id: 1,
    connected: false,
    reconnect_delay: @initial_reconnect_delay,
    reconnect_timer: nil,
    buffer: ""
  ]

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc "Send a JSON-RPC request and wait for the response."
  @spec send_request(pid(), String.t(), map(), timeout()) :: {:ok, map()} | {:error, term()}
  def send_request(pid, method, params, timeout \\ @request_timeout) do
    GenServer.call(pid, {:send_request, method, params}, timeout)
  end

  @doc "Send a JSON-RPC notification (no response expected)."
  @spec send_notification(pid(), String.t(), map()) :: :ok | {:error, term()}
  def send_notification(pid, method, params) do
    GenServer.call(pid, {:send_notification, method, params})
  end

  @doc "Check if the transport is connected."
  @spec connected?(pid()) :: boolean()
  def connected?(pid) do
    GenServer.call(pid, :connected?)
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(config) do
    url = normalize_url(config[:url] || config["url"])
    headers = config[:headers] || config["headers"] || []

    state = %__MODULE__{
      url: url,
      headers: headers
    }

    # Defer connection to handle_continue
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    state = start_sse_connection(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:send_request, method, params}, from, state) do
    if not state.connected do
      {:reply, {:error, :not_connected}, state}
    else
      id = state.next_id

      message = %{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => params
      }

      case post_message(state, message) do
        :ok ->
          # Store pending request to match response
          pending = Map.put(state.pending, id, %{from: from, sent_at: System.monotonic_time(:millisecond)})
          {:noreply, %{state | pending: pending, next_id: id + 1}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:send_notification, method, params}, _from, state) do
    if not state.connected do
      {:reply, {:error, :not_connected}, state}
    else
      message = %{
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params
      }

      result = post_message(state, message)
      {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  # SSE task sends parsed events back to us
  @impl true
  def handle_info({:sse_event, event_type, data}, state) do
    state = handle_sse_event(event_type, data, state)
    {:noreply, state}
  end

  # SSE connection established
  @impl true
  def handle_info(:sse_connected, state) do
    Logger.info("[Eclaw.MCP.HttpTransport] SSE connection established to #{state.url}")
    {:noreply, %{state | reconnect_delay: @initial_reconnect_delay}}
  end

  # SSE task exited
  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, %{sse_task: {pid, ref}} = state) do
    Logger.warning("[Eclaw.MCP.HttpTransport] SSE connection lost: #{inspect(reason)}")

    # Reply to all pending requests with error
    state = fail_pending_requests(state, {:error, :connection_lost})
    state = %{state | connected: false, post_endpoint: nil, sse_task: nil}

    # Schedule reconnect with backoff
    state = schedule_reconnect(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("[Eclaw.MCP.HttpTransport] Attempting reconnect to #{state.url}")
    state = %{state | reconnect_timer: nil}
    state = start_sse_connection(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cancel_reconnect(state)
    stop_sse_task(state)
    :ok
  end

  # ── Private: SSE Connection ────────────────────────────────────────

  defp start_sse_connection(state) do
    state = stop_sse_task(state)
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        run_sse_loop(parent, state.url, state.headers)
      end)

    %{state | sse_task: {pid, ref}}
  end

  defp stop_sse_task(%{sse_task: {pid, ref}} = state) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :shutdown)
    %{state | sse_task: nil}
  end

  defp stop_sse_task(state), do: state

  defp run_sse_loop(parent, url, headers) do
    req_headers = [{"accept", "text/event-stream"} | normalize_headers(headers)]

    # Use Req to make a streaming GET request for SSE
    case Req.get(url,
           headers: req_headers,
           receive_timeout: :infinity,
           connect_options: [timeout: @connect_timeout],
           into: :self,
           retry: false,
           redirect: false
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        send(parent, :sse_connected)
        sse_receive_loop(parent, "")

      {:ok, %Req.Response{status: status}} ->
        Logger.error("[Eclaw.MCP.HttpTransport] SSE connection failed with status #{status}")
        exit({:sse_error, status})

      {:error, reason} ->
        Logger.error("[Eclaw.MCP.HttpTransport] SSE connection failed: #{inspect(reason)}")
        exit({:sse_error, reason})
    end
  end

  defp sse_receive_loop(parent, buffer) do
    receive do
      {_ref, {:data, chunk}} ->
        buffer = buffer <> chunk
        {events, remaining} = parse_sse_events(buffer)

        Enum.each(events, fn {event_type, data} ->
          send(parent, {:sse_event, event_type, data})
        end)

        sse_receive_loop(parent, remaining)

      {_ref, :done} ->
        Logger.info("[Eclaw.MCP.HttpTransport] SSE stream ended")
        exit(:normal)

      {:DOWN, _ref, :process, ^parent, _reason} ->
        exit(:normal)
    end
  end

  # ── Private: SSE Event Parsing ─────────────────────────────────────

  # Parse SSE events from buffer. Returns {[{event_type, data}], remaining_buffer}
  defp parse_sse_events(buffer) do
    # SSE events are separated by double newlines
    case String.split(buffer, "\n\n", parts: 2) do
      [complete_event, rest] ->
        event = parse_single_sse_event(complete_event)
        {more_events, remaining} = parse_sse_events(rest)
        {[event | more_events], remaining}

      [incomplete] ->
        {[], incomplete}
    end
  end

  defp parse_single_sse_event(raw) do
    lines = String.split(raw, "\n")

    {event_type, data_parts} =
      Enum.reduce(lines, {"message", []}, fn line, {evt, data} ->
        cond do
          String.starts_with?(line, "event: ") ->
            {String.replace_prefix(line, "event: ", ""), data}

          String.starts_with?(line, "data: ") ->
            {evt, [String.replace_prefix(line, "data: ", "") | data]}

          String.starts_with?(line, "data:") ->
            {evt, [String.replace_prefix(line, "data:", "") | data]}

          true ->
            {evt, data}
        end
      end)

    data = data_parts |> Enum.reverse() |> Enum.join("\n")
    {event_type, data}
  end

  # ── Private: SSE Event Handling ────────────────────────────────────

  defp handle_sse_event("endpoint", data, state) do
    # Server sends the POST endpoint URL
    post_url = resolve_post_url(state.url, String.trim(data))
    Logger.debug("[Eclaw.MCP.HttpTransport] Got POST endpoint: #{post_url}")
    %{state | post_endpoint: post_url, connected: true}
  end

  defp handle_sse_event("message", data, state) do
    case Jason.decode(data) do
      {:ok, %{"id" => id, "result" => result}} ->
        resolve_pending(state, id, {:ok, result})

      {:ok, %{"id" => id, "error" => error}} ->
        resolve_pending(state, id, {:error, error})

      {:ok, %{"method" => _method}} ->
        # Server-initiated notification — ignore for now
        state

      {:ok, _other} ->
        Logger.debug("[Eclaw.MCP.HttpTransport] Unhandled SSE message: #{data}")
        state

      {:error, _} ->
        Logger.warning("[Eclaw.MCP.HttpTransport] Failed to parse SSE message: #{data}")
        state
    end
  end

  defp handle_sse_event(event_type, _data, state) do
    Logger.debug("[Eclaw.MCP.HttpTransport] Ignoring SSE event type: #{event_type}")
    state
  end

  # ── Private: POST Requests ────────────────────────────────────────

  defp post_message(%{post_endpoint: nil}, _message) do
    {:error, :no_post_endpoint}
  end

  defp post_message(%{post_endpoint: url, headers: headers}, message) do
    json = Jason.encode!(message)

    req_headers = [{"content-type", "application/json"} | normalize_headers(headers)]

    case Req.post(url,
           headers: req_headers,
           body: json,
           connect_options: [timeout: @connect_timeout],
           receive_timeout: @request_timeout,
           retry: false
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("[Eclaw.MCP.HttpTransport] POST failed (#{status}): #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("[Eclaw.MCP.HttpTransport] POST failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── Private: Pending Request Management ────────────────────────────

  defp resolve_pending(state, id, result) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        Logger.debug("[Eclaw.MCP.HttpTransport] Response for unknown request id=#{id}")
        state

      {%{from: from}, pending} ->
        GenServer.reply(from, result)
        %{state | pending: pending}
    end
  end

  defp fail_pending_requests(state, error) do
    Enum.each(state.pending, fn {_id, %{from: from}} ->
      GenServer.reply(from, error)
    end)

    %{state | pending: %{}}
  end

  # ── Private: Reconnection ──────────────────────────────────────────

  defp schedule_reconnect(state) do
    delay = state.reconnect_delay
    # Jitter: +/- 20%
    jitter = trunc(delay * 0.2 * (:rand.uniform() * 2 - 1))
    actual_delay = delay + jitter

    Logger.info("[Eclaw.MCP.HttpTransport] Reconnecting in #{actual_delay}ms")
    timer = Process.send_after(self(), :reconnect, actual_delay)

    # Exponential backoff, capped
    next_delay = min(delay * 2, @max_reconnect_delay)
    %{state | reconnect_timer: timer, reconnect_delay: next_delay}
  end

  defp cancel_reconnect(%{reconnect_timer: nil}), do: :ok

  defp cancel_reconnect(%{reconnect_timer: timer}) do
    Process.cancel_timer(timer)
    :ok
  end

  # ── Private: URL Helpers ───────────────────────────────────────────

  defp normalize_url(url) when is_binary(url) do
    url = String.trim(url)
    path = URI.parse(url).path || ""

    if path == @default_sse_path or String.ends_with?(path, @default_sse_path) do
      url
    else
      String.trim_trailing(url, "/") <> @default_sse_path
    end
  end

  defp resolve_post_url(sse_url, endpoint_path) do
    if String.starts_with?(endpoint_path, "http") do
      endpoint_path
    else
      uri = URI.parse(sse_url)
      "#{uri.scheme}://#{uri.host}:#{uri.port}#{endpoint_path}"
    end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {k, v} -> {to_string(k), to_string(v)}
      other -> other
    end)
  end

  defp normalize_headers(_), do: []
end
