defmodule Eclaw.History do
  @moduledoc """
  Persistent conversation history for Eclaw sessions.

  Stores per-session message history in DETS (~/.eclaw/history.dets).
  Write operations (save, delete) go through GenServer serialization.
  Read operations (load, list_sessions, search) read DETS directly
  since DETS supports concurrent reads.

  Record format in DETS: `{session_id, [%{role: String.t(), content: term(), timestamp: DateTime.t()}]}`
  """

  use GenServer
  require Logger

  @table_name :eclaw_history
  @default_data_dir "~/.eclaw"
  @max_messages 100
  @sync_interval 5_000

  # ── Types ──────────────────────────────────────────────────────────

  @type message :: %{role: String.t(), content: term(), timestamp: DateTime.t()}
  @type session_info :: %{session_id: String.t(), message_count: non_neg_integer(), last_active: DateTime.t()}

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Save/overwrite conversation messages for a session. Trims to last #{@max_messages} entries."
  @spec save(String.t(), [map()]) :: :ok
  def save(session_id, messages) do
    GenServer.cast(__MODULE__, {:save, session_id, messages})
  end

  @doc "Retrieve messages for a session. Returns `[]` if not found."
  @spec load(String.t()) :: [message()]
  def load(session_id) do
    case :dets.lookup(@table_name, session_id) do
      [{^session_id, messages}] -> messages
      [] -> []
    end
  rescue
    _ -> []
  end

  @doc "List all sessions with metadata."
  @spec list_sessions() :: [session_info()]
  def list_sessions do
    :dets.foldl(
      fn {session_id, messages}, acc ->
        last_active =
          messages
          |> List.last()
          |> case do
            %{timestamp: ts} -> ts
            _ -> DateTime.from_unix!(0)
          end

        info = %{
          session_id: session_id,
          message_count: length(messages),
          last_active: last_active
        }

        [info | acc]
      end,
      [],
      @table_name
    )
    |> Enum.sort_by(& &1.last_active, {:desc, DateTime})
  rescue
    _ -> []
  end

  @doc "Delete a session's history."
  @spec delete(String.t()) :: :ok
  def delete(session_id) do
    GenServer.cast(__MODULE__, {:delete, session_id})
  end

  @doc "Simple text search within a session's messages."
  @spec search(String.t(), String.t()) :: [message()]
  def search(session_id, query) do
    query_lower = String.downcase(query)

    load(session_id)
    |> Enum.filter(fn msg ->
      content = stringify_content(msg.content)
      String.contains?(String.downcase(content), query_lower)
    end)
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    data_dir = Path.expand(@default_data_dir)
    File.mkdir_p!(data_dir)
    db_path = Path.join(data_dir, "history.dets") |> String.to_charlist()

    case :dets.open_file(@table_name, file: db_path, type: :set) do
      {:ok, table} ->
        count = :dets.info(table, :size)
        Logger.info("[Eclaw.History] Loaded #{count} sessions from #{db_path}")
        schedule_sync()
        {:ok, %{table: table, dirty: false}}

      {:error, reason} ->
        Logger.error("[Eclaw.History] Failed to open DETS: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:save, session_id, messages}, state) do
    now = DateTime.utc_now()

    # Normalize messages: add timestamp if missing, trim to last @max_messages
    normalized =
      messages
      |> Enum.map(fn msg ->
        %{
          role: msg["role"] || Map.get(msg, :role, "unknown"),
          content: msg["content"] || Map.get(msg, :content, ""),
          timestamp: Map.get(msg, :timestamp) || now
        }
      end)
      |> Enum.take(-@max_messages)

    :dets.insert(state.table, {session_id, normalized})
    Logger.debug("[Eclaw.History] Saved #{length(normalized)} messages for session #{session_id}")

    {:noreply, %{state | dirty: true}}
  end

  @impl true
  def handle_cast({:delete, session_id}, state) do
    :dets.delete(state.table, session_id)
    Logger.debug("[Eclaw.History] Deleted session #{session_id}")
    {:noreply, %{state | dirty: true}}
  end

  # Periodic sync — flush dirty writes to disk
  @impl true
  def handle_info(:sync, state) do
    if state.dirty do
      :dets.sync(state.table)
    end

    schedule_sync()
    {:noreply, %{state | dirty: false}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.dirty, do: :dets.sync(state.table)
    :dets.close(state.table)
    :ok
  end

  # ── Private ────────────────────────────────────────────────────────

  defp schedule_sync, do: Process.send_after(self(), :sync, @sync_interval)

  defp stringify_content(content) when is_binary(content), do: content

  defp stringify_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      %{type: "text", text: text} -> text
      other -> inspect(other)
    end)
    |> Enum.join(" ")
  end

  defp stringify_content(content), do: inspect(content)
end
