defmodule Eclaw.Cache do
  @moduledoc """
  ETS-backed cache with TTL-based expiration for tool results.

  Uses an ETS `:set` table for concurrent reads and a GenServer
  for stats tracking and periodic cleanup of expired entries.

  Keys can be any term — the caller is responsible for choosing
  a meaningful key (e.g. `{:web_fetch, url}`).

  Values are stored as `{result, expires_at_monotonic}`.
  """

  use GenServer
  require Logger

  @table_name :eclaw_cache
  @cleanup_interval_ms 60_000

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Return cached value for `key` if present and not expired,
  otherwise call `compute_fn.()`, cache the result for `ttl_ms`
  milliseconds, and return it.
  """
  @spec get_or_compute(term(), pos_integer(), (-> term())) :: term()
  def get_or_compute(key, ttl_ms, compute_fn) when is_function(compute_fn, 0) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table_name, key) do
      [{^key, {result, expires_at}}] when expires_at > now ->
        GenServer.cast(__MODULE__, :hit)
        result

      _ ->
        GenServer.cast(__MODULE__, :miss)
        result = compute_fn.()
        expires_at = System.monotonic_time(:millisecond) + ttl_ms
        :ets.insert(@table_name, {key, {result, expires_at}})
        result
    end
  end

  @doc "Remove a specific entry from the cache."
  @spec invalidate(term()) :: :ok
  def invalidate(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc "Remove all entries from the cache."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table_name)
    GenServer.call(__MODULE__, :reset_stats)
    :ok
  end

  @doc "Return hit/miss statistics."
  @spec stats() :: %{hits: non_neg_integer(), misses: non_neg_integer()}
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    Logger.info("[Eclaw.Cache] Started ETS cache table")
    schedule_cleanup()
    {:ok, %{table: table, hits: 0, misses: 0}}
  end

  @impl true
  def handle_cast(:hit, state) do
    {:noreply, %{state | hits: state.hits + 1}}
  end

  @impl true
  def handle_cast(:miss, state) do
    {:noreply, %{state | misses: state.misses + 1}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, %{hits: state.hits, misses: state.misses}, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    {:reply, :ok, %{state | hits: 0, misses: 0}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    swept = sweep_expired()
    if swept > 0, do: Logger.debug("[Eclaw.Cache] Swept #{swept} expired entries")
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ────────────────────────────────────────────────────────

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp sweep_expired do
    now = System.monotonic_time(:millisecond)

    :ets.foldl(
      fn {key, {_result, expires_at}}, count ->
        if expires_at <= now do
          :ets.delete(@table_name, key)
          count + 1
        else
          count
        end
      end,
      0,
      @table_name
    )
  end
end
