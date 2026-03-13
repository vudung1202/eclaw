defmodule Eclaw.Memory do
  @moduledoc """
  Persistent memory system for Eclaw.

  Stored as DETS files (Disk-based ETS) — built-in Erlang,
  no additional database dependency needed.

  Each memory entry contains:
  - `key`: unique identifier (auto-generated or user-defined)
  - `content`: the content to remember
  - `type`: memory type (:fact, :summary, :preference, :context)
  - `timestamp`: creation time
  - `relevance`: float 0.0-1.0 (used for search ranking)

  Memory persists across sessions — data survives IEx restarts.
  """

  use GenServer
  require Logger

  @table_name :eclaw_memory
  @default_data_dir "~/.eclaw"

  # ── Types ──────────────────────────────────────────────────────────

  @type memory_type :: :fact | :summary | :preference | :context
  @type entry :: %{
          key: String.t(),
          content: String.t(),
          type: memory_type(),
          tags: [String.t()],
          timestamp: DateTime.t(),
          relevance: float(),
          embedding: [float()] | nil
        }

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Store an entry in memory."
  @spec store(String.t(), String.t(), memory_type(), keyword()) :: :ok
  def store(key, content, type \\ :fact, opts \\ []) do
    GenServer.call(__MODULE__, {:store, key, content, type, opts})
  end

  @doc "Search memory by query (simple text matching + tag filtering)."
  @spec search(String.t(), keyword()) :: [entry()]
  def search(query, opts \\ []) do
    use_vector = Keyword.get(opts, :vector, true)

    # Generate embedding OUTSIDE the GenServer to avoid blocking it
    query_embedding = if use_vector, do: generate_embedding(query)
    GenServer.call(__MODULE__, {:search, query, opts, query_embedding})
  end

  @doc "Get all entries."
  @spec list_all() :: [entry()]
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc "Delete entry by key."
  @spec delete(String.t()) :: :ok
  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
  end

  @doc "Clear all memory."
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc "Count entries without loading the entire table."
  @spec count() :: non_neg_integer()
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Format memory entries as context string to inject into system prompt.

  Only takes top N most relevant entries to avoid consuming too much context.
  """
  @spec to_context(String.t(), non_neg_integer()) :: String.t()
  def to_context(query \\ "", max_entries \\ 10) do
    entries =
      if query == "" do
        list_all() |> Enum.take(max_entries)
      else
        search(query, limit: max_entries)
      end

    if entries == [] do
      ""
    else
      header = "[MEMORY — #{length(entries)} relevant entries]\n"

      body =
        entries
        |> Enum.map(fn entry ->
          "- [#{entry.type}] #{entry.content}"
        end)
        |> Enum.join("\n")

      header <> body <> "\n[END MEMORY]"
    end
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    data_dir = Path.expand(@default_data_dir)
    File.mkdir_p!(data_dir)
    db_path = Path.join(data_dir, "memory.dets") |> String.to_charlist()

    case :dets.open_file(@table_name, file: db_path, type: :set) do
      {:ok, table} ->
        count = :dets.info(table, :size)
        Logger.info("[Eclaw.Memory] Loaded #{count} entries from #{db_path}")
        # Schedule periodic sync instead of syncing on every write
        schedule_sync()
        {:ok, %{table: table, dirty: false}}

      {:error, reason} ->
        Logger.error("[Eclaw.Memory] Failed to open DETS: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:store, key, content, type, opts}, _from, state) do
    tags = Keyword.get(opts, :tags, [])

    # Store entry immediately without embedding
    entry = %{
      key: key,
      content: content,
      type: type,
      tags: tags,
      timestamp: DateTime.utc_now(),
      relevance: 1.0,
      embedding: nil
    }

    :dets.insert(state.table, {key, entry})

    # Generate embedding asynchronously — sends result back to GenServer
    Task.Supervisor.start_child(Eclaw.TaskSupervisor, fn ->
      case generate_embedding(content) do
        nil -> :ok
        embedding ->
          GenServer.cast(__MODULE__, {:update_embedding, key, nil, embedding})
      end
    end)

    Logger.debug("[Eclaw.Memory] Stored: #{key} (#{type})")
    {:reply, :ok, %{state | dirty: true}}
  end

  @impl true
  def handle_call({:search, query, opts, query_embedding}, _from, state) do
    limit = Keyword.get(opts, :limit, 20)
    type_filter = Keyword.get(opts, :type, nil)

    entries =
      state.table
      |> dets_to_list()
      |> maybe_filter_type(type_filter)

    # Use pre-computed embedding (generated outside GenServer to avoid blocking)
    has_embeddings = query_embedding != nil && Enum.any?(entries, &(&1[:embedding] != nil))

    results =
      if has_embeddings do
        # Vector similarity search (cosine similarity)
        entries
        |> Enum.map(fn entry ->
          vector_score =
            if entry[:embedding] do
              cosine_similarity(query_embedding, entry.embedding)
            else
              0.0
            end

          # Blend vector score with keyword score
          keyword_score = calculate_relevance(entry, String.downcase(query), String.split(String.downcase(query)))
          blended = vector_score * 0.7 + keyword_score * 0.3

          %{entry | relevance: blended}
        end)
      else
        # Fallback to keyword search
        query_lower = String.downcase(query)
        query_words = String.split(query_lower)

        Enum.map(entries, fn entry ->
          score = calculate_relevance(entry, query_lower, query_words)
          %{entry | relevance: score}
        end)
      end

    results =
      results
      |> Enum.filter(fn entry -> entry.relevance > 0.0 end)
      |> Enum.sort_by(& &1.relevance, :desc)
      |> Enum.take(limit)

    {:reply, results, state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    entries =
      state.table
      |> dets_to_list()
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

    {:reply, entries, state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    :dets.delete(state.table, key)
    {:reply, :ok, %{state | dirty: true}}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :dets.delete_all_objects(state.table)
    :dets.sync(state.table)
    Logger.info("[Eclaw.Memory] Cleared all entries")
    {:reply, :ok, %{state | dirty: false}}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, :dets.info(state.table, :size), state}
  end

  @impl true
  def handle_cast({:update_embedding, key, _entry, embedding}, state) do
    # Re-read current entry from DETS to avoid overwriting with stale data
    case :dets.lookup(state.table, key) do
      [{^key, current_entry}] ->
        updated = %{current_entry | embedding: embedding}
        :dets.insert(state.table, {key, updated})
        Logger.debug("[Eclaw.Memory] Embedding generated for: #{key}")

      [] ->
        Logger.debug("[Eclaw.Memory] Entry #{key} deleted before embedding arrived, skipping")
    end

    {:noreply, %{state | dirty: true}}
  end

  # Periodic sync — flush dirty writes to disk every 5 seconds
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

  defp schedule_sync, do: Process.send_after(self(), :sync, 5_000)

  defp dets_to_list(table) do
    :dets.foldl(fn {_key, entry}, acc -> [entry | acc] end, [], table)
  end

  defp maybe_filter_type(entries, nil), do: entries
  defp maybe_filter_type(entries, type), do: Enum.filter(entries, &(&1.type == type))

  # ── Vector search helpers ──────────────────────────────────────────

  # Generate embedding via OpenAI API (small, fast, cheap).
  # Public so it can be called outside the GenServer (e.g., before search).
  @doc false
  def generate_embedding(text) do
    api_key = System.get_env("OPENAI_API_KEY")

    if api_key do
      body = %{
        "model" => "text-embedding-3-small",
        "input" => String.slice(text, 0, 8000)
      }

      headers = [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      case Req.post("https://api.openai.com/v1/embeddings", json: body, headers: headers, receive_timeout: 10_000) do
        {:ok, %{status: 200, body: %{"data" => [%{"embedding" => embedding} | _]}}} ->
          embedding

        {:ok, %{status: status}} ->
          Logger.debug("[Eclaw.Memory] Embedding API error: HTTP #{status}")
          nil

        {:error, reason} ->
          Logger.debug("[Eclaw.Memory] Embedding request failed: #{inspect(reason)}")
          nil
      end
    else
      nil
    end
  end

  # Cosine similarity between two vectors
  defp cosine_similarity(a, b) when is_list(a) and is_list(b) do
    dot = Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
    norm_a = :math.sqrt(Enum.reduce(a, 0.0, fn x, acc -> acc + x * x end))
    norm_b = :math.sqrt(Enum.reduce(b, 0.0, fn x, acc -> acc + x * x end))

    if norm_a == 0.0 or norm_b == 0.0 do
      0.0
    else
      dot / (norm_a * norm_b)
    end
  end

  defp cosine_similarity(_, _), do: 0.0

  # Simple relevance scoring: word overlap + tag match + recency boost
  defp calculate_relevance(entry, query_lower, query_words) do
    content_lower = String.downcase(entry.content)
    tags_lower = Enum.map(entry.tags, &String.downcase/1)

    # Word match score (0.0 - 1.0)
    word_hits = Enum.count(query_words, &String.contains?(content_lower, &1))

    word_score =
      if length(query_words) > 0,
        do: word_hits / length(query_words),
        else: 0.0

    # Exact substring bonus
    exact_bonus = if String.contains?(content_lower, query_lower), do: 0.3, else: 0.0

    # Tag match bonus
    tag_bonus =
      if Enum.any?(tags_lower, fn tag ->
           Enum.any?(query_words, &String.contains?(tag, &1))
         end),
         do: 0.2,
         else: 0.0

    # Recency boost (entries < 24h get +0.1)
    age_hours = DateTime.diff(DateTime.utc_now(), entry.timestamp, :hour)
    recency_bonus = if age_hours < 24, do: 0.1, else: 0.0

    word_score + exact_bonus + tag_bonus + recency_bonus
  end
end
