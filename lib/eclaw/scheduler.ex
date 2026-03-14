defmodule Eclaw.Scheduler do
  @moduledoc """
  Scheduled task manager with DETS persistence.

  Supports recurring and one-time tasks that execute actions via channels
  (e.g., sending messages via Telegram at specific times).

  ## Schedule formats

  - `"daily HH:MM"` — every day at the specified time
  - `"weekday HH:MM"` — Monday through Friday at the specified time
  - `"every Nm"` — every N minutes
  - `"every Nh"` — every N hours
  - `"once YYYY-MM-DD HH:MM"` — one-time at the specified date/time

  All times are in UTC+7 (Asia/Ho_Chi_Minh). Internally stored and
  calculated as UTC, offset +7 hours for display and scheduling.
  """

  use GenServer
  require Logger

  @table_name :eclaw_scheduler
  @default_data_dir "~/.eclaw"

  # UTC offset for Asia/Ho_Chi_Minh (Vietnam)
  @vietnam_offset_seconds 7 * 3600

  # ── Types ──────────────────────────────────────────────────────────

  @type action :: %{
          type: :chat,
          channel: atom(),
          target: String.t(),
          prompt: String.t()
        }

  @type task :: %{
          id: String.t(),
          name: String.t(),
          schedule: String.t(),
          action: action(),
          next_run: DateTime.t(),
          enabled: boolean(),
          created_at: DateTime.t()
        }

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Create and persist a scheduled task, then schedule its timer."
  @spec create(String.t(), String.t(), action()) :: {:ok, task()} | {:error, String.t()}
  def create(name, schedule, action) do
    GenServer.call(__MODULE__, {:create, name, schedule, action})
  end

  @doc "Delete a task by ID and cancel its timer."
  @spec delete(String.t()) :: :ok | {:error, String.t()}
  def delete(task_id) do
    GenServer.call(__MODULE__, {:delete, task_id})
  end

  @doc "List all scheduled tasks."
  @spec list() :: [task()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc "Enable a disabled task."
  @spec enable(String.t()) :: :ok | {:error, String.t()}
  def enable(task_id) do
    GenServer.call(__MODULE__, {:enable, task_id})
  end

  @doc "Disable a task (cancel its timer but keep it)."
  @spec disable(String.t()) :: :ok | {:error, String.t()}
  def disable(task_id) do
    GenServer.call(__MODULE__, {:disable, task_id})
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    data_dir = Path.expand(@default_data_dir)
    File.mkdir_p!(data_dir)
    db_path = Path.join(data_dir, "scheduler.dets") |> String.to_charlist()

    case :dets.open_file(@table_name, file: db_path, type: :set) do
      {:ok, table} ->
        count = :dets.info(table, :size)
        Logger.info("[Eclaw.Scheduler] Loaded #{count} tasks from #{db_path}")

        # Schedule all enabled tasks on startup
        timer_refs = schedule_all_tasks(table)

        {:ok, %{table: table, timer_refs: timer_refs}}

      {:error, reason} ->
        Logger.error("[Eclaw.Scheduler] Failed to open DETS: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:create, name, schedule, action}, _from, state) do
    case parse_schedule(schedule) do
      {:ok, _} ->
        now_utc = DateTime.utc_now()

        case calculate_next_run(schedule, now_utc) do
          {:ok, next_run} ->
            task_id = generate_id()

            task = %{
              id: task_id,
              name: name,
              schedule: schedule,
              action: action,
              next_run: next_run,
              enabled: true,
              created_at: now_utc
            }

            :dets.insert(state.table, {task_id, task})
            :dets.sync(state.table)

            timer_ref = schedule_timer(task_id, next_run)
            timer_refs = Map.put(state.timer_refs, task_id, timer_ref)

            Logger.info("[Eclaw.Scheduler] Created task '#{name}' (#{task_id}), schedule: #{schedule}, next run: #{format_vietnam_time(next_run)}")
            {:reply, {:ok, task}, %{state | timer_refs: timer_refs}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:delete, task_id}, _from, state) do
    case :dets.lookup(state.table, task_id) do
      [{^task_id, task}] ->
        cancel_timer(state.timer_refs, task_id)
        :dets.delete(state.table, task_id)
        :dets.sync(state.table)

        timer_refs = Map.delete(state.timer_refs, task_id)
        Logger.info("[Eclaw.Scheduler] Deleted task '#{task.name}' (#{task_id})")
        {:reply, :ok, %{state | timer_refs: timer_refs}}

      [] ->
        {:reply, {:error, "Task not found: #{task_id}"}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    tasks =
      :dets.foldl(fn {_id, task}, acc -> [task | acc] end, [], state.table)
      |> Enum.sort_by(& &1.created_at, {:asc, DateTime})

    {:reply, tasks, state}
  end

  @impl true
  def handle_call({:enable, task_id}, _from, state) do
    case :dets.lookup(state.table, task_id) do
      [{^task_id, task}] ->
        now_utc = DateTime.utc_now()

        case calculate_next_run(task.schedule, now_utc) do
          {:ok, next_run} ->
            updated = %{task | enabled: true, next_run: next_run}
            :dets.insert(state.table, {task_id, updated})
            :dets.sync(state.table)

            cancel_timer(state.timer_refs, task_id)
            timer_ref = schedule_timer(task_id, next_run)
            timer_refs = Map.put(state.timer_refs, task_id, timer_ref)

            Logger.info("[Eclaw.Scheduler] Enabled task '#{task.name}' (#{task_id})")
            {:reply, :ok, %{state | timer_refs: timer_refs}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      [] ->
        {:reply, {:error, "Task not found: #{task_id}"}, state}
    end
  end

  @impl true
  def handle_call({:disable, task_id}, _from, state) do
    case :dets.lookup(state.table, task_id) do
      [{^task_id, task}] ->
        updated = %{task | enabled: false}
        :dets.insert(state.table, {task_id, updated})
        :dets.sync(state.table)

        cancel_timer(state.timer_refs, task_id)
        timer_refs = Map.delete(state.timer_refs, task_id)

        Logger.info("[Eclaw.Scheduler] Disabled task '#{task.name}' (#{task_id})")
        {:reply, :ok, %{state | timer_refs: timer_refs}}

      [] ->
        {:reply, {:error, "Task not found: #{task_id}"}, state}
    end
  end

  @impl true
  def handle_info({:fire, task_id}, state) do
    case :dets.lookup(state.table, task_id) do
      [{^task_id, %{enabled: true} = task}] ->
        Logger.info("[Eclaw.Scheduler] Firing task '#{task.name}' (#{task_id})")

        # Execute action async via TaskSupervisor
        Task.Supervisor.start_child(Eclaw.TaskSupervisor, fn ->
          execute_action(task)
        end)

        # Schedule next run (or remove if one-time)
        state = schedule_next(task, state)
        {:noreply, state}

      [{^task_id, %{enabled: false}}] ->
        # Task was disabled between scheduling and firing
        Logger.debug("[Eclaw.Scheduler] Skipping disabled task #{task_id}")
        {:noreply, state}

      [] ->
        # Task was deleted
        Logger.debug("[Eclaw.Scheduler] Task #{task_id} no longer exists, skipping")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    :dets.sync(state.table)
    :dets.close(state.table)
    :ok
  end

  # ── Private: Scheduling ────────────────────────────────────────────

  defp schedule_all_tasks(table) do
    now_utc = DateTime.utc_now()

    :dets.foldl(
      fn {task_id, task}, acc ->
        if task.enabled do
          case calculate_next_run(task.schedule, now_utc) do
            {:ok, next_run} ->
              # Update next_run in DETS
              :dets.insert(table, {task_id, %{task | next_run: next_run}})
              timer_ref = schedule_timer(task_id, next_run)
              Logger.debug("[Eclaw.Scheduler] Scheduled '#{task.name}' for #{format_vietnam_time(next_run)}")
              Map.put(acc, task_id, timer_ref)

            {:error, reason} ->
              # One-time task in the past — disable it
              Logger.info("[Eclaw.Scheduler] Task '#{task.name}' expired: #{reason}")
              :dets.insert(table, {task_id, %{task | enabled: false}})
              acc
          end
        else
          acc
        end
      end,
      %{},
      table
    )
  end

  defp schedule_timer(task_id, next_run_utc) do
    now_utc = DateTime.utc_now()
    delay_ms = max(DateTime.diff(next_run_utc, now_utc, :millisecond), 1000)
    Process.send_after(self(), {:fire, task_id}, delay_ms)
  end

  defp cancel_timer(timer_refs, task_id) do
    case Map.get(timer_refs, task_id) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end
  end

  defp schedule_next(task, state) do
    if String.starts_with?(task.schedule, "once") do
      # One-time task — disable after execution
      updated = %{task | enabled: false}
      :dets.insert(state.table, {task.id, updated})
      :dets.sync(state.table)

      timer_refs = Map.delete(state.timer_refs, task.id)
      Logger.info("[Eclaw.Scheduler] One-time task '#{task.name}' completed, disabled")
      %{state | timer_refs: timer_refs}
    else
      # Recurring — calculate and schedule next run
      now_utc = DateTime.utc_now()

      case calculate_next_run(task.schedule, now_utc) do
        {:ok, next_run} ->
          updated = %{task | next_run: next_run}
          :dets.insert(state.table, {task.id, updated})
          :dets.sync(state.table)

          timer_ref = schedule_timer(task.id, next_run)
          timer_refs = Map.put(state.timer_refs, task.id, timer_ref)
          Logger.debug("[Eclaw.Scheduler] Next run for '#{task.name}': #{format_vietnam_time(next_run)}")
          %{state | timer_refs: timer_refs}

        {:error, reason} ->
          Logger.error("[Eclaw.Scheduler] Cannot schedule next run for '#{task.name}': #{reason}")
          state
      end
    end
  end

  # ── Private: Action Execution ──────────────────────────────────────

  defp execute_action(%{action: %{type: :chat, channel: channel, target: target, prompt: prompt}}) do
    channel_name = if is_binary(channel), do: String.to_existing_atom(channel), else: channel
    Logger.info("[Eclaw.Scheduler] Executing chat action → #{channel_name}:#{target}")
    Eclaw.ChannelManager.handle_message(channel_name, target, prompt)
  end

  defp execute_action(%{action: action}) do
    Logger.warning("[Eclaw.Scheduler] Unknown action type: #{inspect(action)}")
  end

  # ── Private: Schedule Parsing ──────────────────────────────────────

  @doc false
  def parse_schedule("daily " <> time), do: parse_time(time)
  def parse_schedule("weekday " <> time), do: parse_time(time)

  def parse_schedule("every " <> interval) do
    cond do
      String.ends_with?(interval, "m") ->
        case Integer.parse(String.trim_trailing(interval, "m")) do
          {n, ""} when n > 0 -> {:ok, {:interval_minutes, n}}
          _ -> {:error, "Invalid minute interval: #{interval}"}
        end

      String.ends_with?(interval, "h") ->
        case Integer.parse(String.trim_trailing(interval, "h")) do
          {n, ""} when n > 0 -> {:ok, {:interval_hours, n}}
          _ -> {:error, "Invalid hour interval: #{interval}"}
        end

      true ->
        {:error, "Invalid interval format: #{interval}. Use 'Nm' for minutes or 'Nh' for hours"}
    end
  end

  def parse_schedule("once " <> datetime) do
    case parse_datetime(datetime) do
      {:ok, _dt} -> {:ok, :once}
      error -> error
    end
  end

  def parse_schedule(schedule) do
    {:error, "Unknown schedule format: '#{schedule}'. Supported: 'daily HH:MM', 'weekday HH:MM', 'every Nm', 'every Nh', 'once YYYY-MM-DD HH:MM'"}
  end

  defp parse_time(time_str) do
    case String.split(time_str, ":") do
      [h_str, m_str] ->
        with {hour, ""} <- Integer.parse(h_str),
             {minute, ""} <- Integer.parse(m_str),
             true <- hour >= 0 and hour <= 23,
             true <- minute >= 0 and minute <= 59 do
          {:ok, {hour, minute}}
        else
          _ -> {:error, "Invalid time format: #{time_str}. Use HH:MM (00:00-23:59)"}
        end

      _ ->
        {:error, "Invalid time format: #{time_str}. Use HH:MM"}
    end
  end

  defp parse_datetime(datetime_str) do
    case String.split(datetime_str, " ") do
      [date_str, time_str] ->
        with [y_str, mo_str, d_str] <- String.split(date_str, "-"),
             {year, ""} <- Integer.parse(y_str),
             {month, ""} <- Integer.parse(mo_str),
             {day, ""} <- Integer.parse(d_str),
             {:ok, {hour, minute}} <- parse_time(time_str),
             {:ok, naive} <- NaiveDateTime.new(year, month, day, hour, minute, 0),
             {:ok, dt} <- DateTime.from_naive(naive, "Etc/UTC") do
          {:ok, dt}
        else
          _ -> {:error, "Invalid datetime format: #{datetime_str}. Use YYYY-MM-DD HH:MM"}
        end

      _ ->
        {:error, "Invalid datetime format: #{datetime_str}. Use YYYY-MM-DD HH:MM"}
    end
  end

  # ── Private: Next Run Calculation ──────────────────────────────────

  @doc false
  def calculate_next_run("daily " <> time_str, now_utc) do
    with {:ok, {hour, minute}} <- parse_time(time_str) do
      # hour/minute are in Vietnam time (UTC+7), convert target to UTC
      target_utc_hour = rem(hour - 7 + 24, 24)
      next = next_daily(now_utc, target_utc_hour, minute)
      {:ok, next}
    end
  end

  def calculate_next_run("weekday " <> time_str, now_utc) do
    with {:ok, {hour, minute}} <- parse_time(time_str) do
      target_utc_hour = rem(hour - 7 + 24, 24)
      next = next_weekday(now_utc, target_utc_hour, minute)
      {:ok, next}
    end
  end

  def calculate_next_run("every " <> interval, now_utc) do
    cond do
      String.ends_with?(interval, "m") ->
        case Integer.parse(String.trim_trailing(interval, "m")) do
          {n, ""} when n > 0 ->
            {:ok, DateTime.add(now_utc, n * 60, :second)}

          _ ->
            {:error, "Invalid minute interval"}
        end

      String.ends_with?(interval, "h") ->
        case Integer.parse(String.trim_trailing(interval, "h")) do
          {n, ""} when n > 0 ->
            {:ok, DateTime.add(now_utc, n * 3600, :second)}

          _ ->
            {:error, "Invalid hour interval"}
        end

      true ->
        {:error, "Invalid interval format"}
    end
  end

  def calculate_next_run("once " <> datetime_str, _now_utc) do
    with {:ok, vietnam_dt} <- parse_datetime(datetime_str) do
      # The user-provided datetime is in Vietnam time — convert to UTC
      utc_dt = DateTime.add(vietnam_dt, -@vietnam_offset_seconds, :second)
      now_utc = DateTime.utc_now()

      if DateTime.compare(utc_dt, now_utc) == :gt do
        {:ok, utc_dt}
      else
        {:error, "Scheduled time is in the past"}
      end
    end
  end

  def calculate_next_run(schedule, _now_utc) do
    {:error, "Cannot calculate next run for: #{schedule}"}
  end

  # Find the next occurrence of a daily HH:MM (in UTC)
  defp next_daily(now_utc, target_hour, target_minute) do
    today = DateTime.to_date(now_utc)
    {:ok, naive} = NaiveDateTime.new(today, Time.new!(target_hour, target_minute, 0))
    {:ok, candidate} = DateTime.from_naive(naive, "Etc/UTC")

    if DateTime.compare(candidate, now_utc) == :gt do
      candidate
    else
      # Tomorrow
      tomorrow = Date.add(today, 1)
      {:ok, naive_tomorrow} = NaiveDateTime.new(tomorrow, Time.new!(target_hour, target_minute, 0))
      {:ok, dt} = DateTime.from_naive(naive_tomorrow, "Etc/UTC")
      dt
    end
  end

  # Find the next weekday occurrence of HH:MM (in UTC)
  defp next_weekday(now_utc, target_hour, target_minute) do
    # In Vietnam time, the day may differ from UTC day when hour crosses midnight
    # We compute in UTC and check the Vietnam-time day of week
    today = DateTime.to_date(now_utc)
    {:ok, naive} = NaiveDateTime.new(today, Time.new!(target_hour, target_minute, 0))
    {:ok, candidate} = DateTime.from_naive(naive, "Etc/UTC")

    # Check if candidate is in the future and falls on a weekday (in Vietnam time)
    candidate =
      if DateTime.compare(candidate, now_utc) == :gt and weekday_in_vietnam?(candidate) do
        candidate
      else
        find_next_weekday(today, target_hour, target_minute, 1)
      end

    candidate
  end

  defp find_next_weekday(from_date, target_hour, target_minute, days_ahead) when days_ahead <= 7 do
    next_date = Date.add(from_date, days_ahead)
    {:ok, naive} = NaiveDateTime.new(next_date, Time.new!(target_hour, target_minute, 0))
    {:ok, candidate} = DateTime.from_naive(naive, "Etc/UTC")

    if weekday_in_vietnam?(candidate) do
      candidate
    else
      find_next_weekday(from_date, target_hour, target_minute, days_ahead + 1)
    end
  end

  defp find_next_weekday(from_date, target_hour, target_minute, _days_ahead) do
    # Fallback — should not happen (7 days always includes a weekday)
    next_date = Date.add(from_date, 1)
    {:ok, naive} = NaiveDateTime.new(next_date, Time.new!(target_hour, target_minute, 0))
    {:ok, candidate} = DateTime.from_naive(naive, "Etc/UTC")
    candidate
  end

  # Check if a UTC datetime falls on a weekday in Vietnam time (UTC+7)
  defp weekday_in_vietnam?(utc_dt) do
    vietnam_dt = DateTime.add(utc_dt, @vietnam_offset_seconds, :second)
    day_of_week = Date.day_of_week(DateTime.to_date(vietnam_dt))
    day_of_week >= 1 and day_of_week <= 5
  end

  # ── Private: Helpers ───────────────────────────────────────────────

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  @doc false
  def format_vietnam_time(utc_dt) do
    vietnam_dt = DateTime.add(utc_dt, @vietnam_offset_seconds, :second)
    Calendar.strftime(vietnam_dt, "%Y-%m-%d %H:%M (UTC+7)")
  end
end
