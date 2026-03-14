defmodule Eclaw.Tools.Schedule do
  @moduledoc """
  Tool for managing scheduled tasks via the LLM.

  Allows the AI agent to create, list, delete, enable, and disable
  recurring or one-time scheduled tasks (e.g., "every morning at 8am
  send wife a greeting via Telegram").
  """

  @behaviour Eclaw.ToolBehaviour

  require Logger

  @impl true
  def name, do: "manage_schedule"

  @impl true
  def description do
    "Manage scheduled tasks — create recurring or one-time tasks that send messages via channels (Telegram, etc.). " <>
      "Schedule formats: 'daily HH:MM', 'weekday HH:MM', 'every Nm' (minutes), 'every Nh' (hours), 'once YYYY-MM-DD HH:MM'. " <>
      "All times are in Vietnam timezone (UTC+7)."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["create", "list", "delete", "enable", "disable"],
          "description" => "Action to perform"
        },
        "name" => %{
          "type" => "string",
          "description" => "Human-readable task name (required for create)"
        },
        "schedule" => %{
          "type" => "string",
          "description" => "Schedule string: 'daily HH:MM', 'weekday HH:MM', 'every Nm', 'every Nh', 'once YYYY-MM-DD HH:MM' (required for create)"
        },
        "prompt" => %{
          "type" => "string",
          "description" => "The message/prompt to send when the task fires (required for create)"
        },
        "channel" => %{
          "type" => "string",
          "description" => "Channel to send via (default: 'telegram')"
        },
        "target" => %{
          "type" => "string",
          "description" => "Target user/chat ID on the channel (required for create)"
        },
        "task_id" => %{
          "type" => "string",
          "description" => "Task ID (required for delete/enable/disable)"
        }
      },
      "required" => ["action"]
    }
  end

  @impl true
  def execute(%{"action" => "create"} = input) do
    name = Map.get(input, "name", "Unnamed task")
    schedule = Map.get(input, "schedule")
    prompt = Map.get(input, "prompt")
    channel = Map.get(input, "channel", "telegram")
    target = Map.get(input, "target")

    cond do
      is_nil(schedule) or schedule == "" ->
        {:error, "Missing required field: schedule"}

      is_nil(prompt) or prompt == "" ->
        {:error, "Missing required field: prompt"}

      is_nil(target) or target == "" ->
        {:error, "Missing required field: target (the user/chat ID to send to)"}

      true ->
        action = %{
          type: :chat,
          channel: String.to_atom(channel),
          target: target,
          prompt: prompt
        }

        case Eclaw.Scheduler.create(name, schedule, action) do
          {:ok, task} ->
            next_run = Eclaw.Scheduler.format_vietnam_time(task.next_run)

            {:ok,
              "Created scheduled task:\n" <>
              "  ID: #{task.id}\n" <>
              "  Name: #{task.name}\n" <>
              "  Schedule: #{task.schedule}\n" <>
              "  Channel: #{channel} -> #{target}\n" <>
              "  Next run: #{next_run}"}

          {:error, reason} ->
            {:error, "Failed to create task: #{reason}"}
        end
    end
  end

  def execute(%{"action" => "list"}) do
    tasks = Eclaw.Scheduler.list()

    if tasks == [] do
      {:ok, "No scheduled tasks."}
    else
      lines =
        tasks
        |> Enum.map(fn task ->
          status = if task.enabled, do: "enabled", else: "disabled"
          next_run = Eclaw.Scheduler.format_vietnam_time(task.next_run)
          channel = task.action[:channel] || task.action.channel
          target = task.action[:target] || task.action.target
          prompt = task.action[:prompt] || task.action.prompt

          "- [#{status}] #{task.name} (#{task.id})\n" <>
          "  Schedule: #{task.schedule}\n" <>
          "  Channel: #{channel} -> #{target}\n" <>
          "  Prompt: #{String.slice(prompt, 0, 100)}\n" <>
          "  Next run: #{next_run}"
        end)

      {:ok, "Scheduled tasks (#{length(tasks)}):\n\n#{Enum.join(lines, "\n\n")}"}
    end
  end

  def execute(%{"action" => "delete", "task_id" => task_id}) when is_binary(task_id) do
    case Eclaw.Scheduler.delete(task_id) do
      :ok -> {:ok, "Task #{task_id} deleted."}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(%{"action" => "delete"}) do
    {:error, "Missing required field: task_id"}
  end

  def execute(%{"action" => "enable", "task_id" => task_id}) when is_binary(task_id) do
    case Eclaw.Scheduler.enable(task_id) do
      :ok -> {:ok, "Task #{task_id} enabled."}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(%{"action" => "enable"}) do
    {:error, "Missing required field: task_id"}
  end

  def execute(%{"action" => "disable", "task_id" => task_id}) when is_binary(task_id) do
    case Eclaw.Scheduler.disable(task_id) do
      :ok -> {:ok, "Task #{task_id} disabled."}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(%{"action" => "disable"}) do
    {:error, "Missing required field: task_id"}
  end

  def execute(%{"action" => action}) do
    {:error, "Unknown action: #{action}. Supported: create, list, delete, enable, disable"}
  end

  def execute(_input) do
    {:error, "Missing required field: action"}
  end
end
