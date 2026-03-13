---
name: scheduler
description: Task scheduling, cron jobs, periodic tasks, background jobs
triggers: [schedule, cron, periodic, timer, interval, background job, queue, worker, oban, quantum, recurring]
---

## Scheduler & Background Jobs

### Cron (system level)
```bash
# Edit crontab
crontab -e

# List current jobs
crontab -l

# Syntax: min hour day month weekday command
# Every 5 minutes
*/5 * * * * /path/to/script.sh

# Daily at 2am
0 2 * * * /path/to/backup.sh

# Every Monday at 9am
0 9 * * 1 /path/to/report.sh

# Redirect output
*/10 * * * * /path/to/job.sh >> /var/log/job.log 2>&1
```

### Elixir — Oban (recommended)
```elixir
# In mix.exs
{:oban, "~> 2.18"}

# Worker
defmodule MyApp.Workers.EmailWorker do
  use Oban.Worker, queue: :mailers, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email}}) do
    MyApp.Mailer.send(email)
    :ok
  end
end

# Enqueue
%{email: "user@example.com"}
|> MyApp.Workers.EmailWorker.new()
|> Oban.insert()

# Schedule (run in 1 hour)
%{email: "user@example.com"}
|> MyApp.Workers.EmailWorker.new(scheduled_at: DateTime.add(DateTime.utc_now(), 3600))
|> Oban.insert()

# Recurring (cron plugin)
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"0 2 * * *", MyApp.Workers.DailyReport},
      {"*/15 * * * *", MyApp.Workers.HealthCheck}
    ]}
  ]
```

### Elixir — Simple periodic with Process.send_after
```elixir
defmodule MyApp.Poller do
  use GenServer

  def init(state) do
    schedule_poll()
    {:ok, state}
  end

  def handle_info(:poll, state) do
    do_work()
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, :timer.minutes(5))
end
```

### Rules
- Use Oban for persistent, reliable job queues (survives restarts)
- Use GenServer + `Process.send_after` for simple in-memory periodic tasks
- Always set `max_attempts` to avoid infinite retries
- Log job failures for monitoring
