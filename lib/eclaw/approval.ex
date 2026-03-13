defmodule Eclaw.Approval do
  @moduledoc """
  Human-in-the-loop approval workflow for potentially dangerous commands.

  Instead of hard-blocking all dangerous commands, this module separates them into:
  - `:blocked` — Always blocked, no approval possible (rm -rf /, fork bombs, etc.)
  - `:needs_approval` — Requires user confirmation before execution

  The approval mechanism is channel-aware:
  - CLI: prompts via IO.gets
  - Telegram/other channels: uses callback function
  """

  require Logger

  # Commands that are ALWAYS blocked — too dangerous even with approval
  @always_blocked [
    ~r/\brm\s+.*-[a-zA-Z]*r[a-zA-Z]*f|rm\s+.*-[a-zA-Z]*f[a-zA-Z]*r|rm\s+.*--recursive.*--force|rm\s+.*--force.*--recursive/,
    ~r/\brm\s+(-[a-zA-Z]*f|-[a-zA-Z]*r|--force|--recursive)\s+\/\s*$/,
    ~r/\bmkfs\b/,
    ~r/\bdd\s+.*of=\/dev\//,
    ~r/:\(\)\s*\{\s*:\|:&\s*\}\s*;?\s*:/,
    ~r/\bchmod\s+(-[a-zA-Z]*R)?\s*(777|666)\s+\/\s*$/,
    ~r/\bchown\s+.*\s+\/\s*$/,
    ~r/\b\/boot\//,
    ~r/\b\/dev\/sda\b/,
    # Block common encoding bypass patterns
    ~r/\bbase64\s+(-d|--decode).*\|\s*(ba)?sh/,
    ~r/\bpython[23]?\s+-c\s+.*\b(exec|eval|system|popen|subprocess)\b/,
    ~r/\bperl\s+-e\s+.*\b(system|exec)\b/,
    ~r/\bruby\s+-e\s+.*\b(system|exec|`)\b/,
    ~r/\bfind\s+\/\s+.*-delete\b/,
    ~r/\bfind\s+\/\s+.*-exec\s+rm\b/,
    # Block reverse shells
    ~r/\b(bash|sh)\s+-i\s+.*\/dev\/tcp/,
    ~r/\bnc\s+.*-e\s+(\/bin\/)?(ba)?sh/,
    # Block shell evaluation/obfuscation patterns (narrowed to avoid blocking legitimate use)
    ~r/(^|[;&|]\s*)eval\s+/,
    ~r/\$\(.*\)\s*\|\s*(ba)?sh/,
    # Block reading sensitive paths via bash
    ~r/\bcat\s+.*\.ssh\/(id_|authorized_keys|known_hosts)/,
    ~r/\bcat\s+.*\/etc\/(shadow|sudoers)/,
    ~r/\bcat\s+.*\.env\b/,
    ~r/\bcat\s+.*\.aws\/(credentials|config)/,
    ~r/\bcat\s+.*\.gnupg\//,
    # Block environment variable exfiltration
    ~r/\b(printenv|env)\b.*\|/,
    ~r/\bps\s+.*eww\b/,
  ]

  # Commands that need human approval before execution
  @needs_approval [
    {~r/\bshutdown\b/, "system shutdown"},
    {~r/\breboot\b/, "system reboot"},
    {~r/\binit\s+0\b/, "system halt"},
    {~r/curl\s+.*\|\s*(ba)?sh/, "pipe remote script to shell"},
    {~r/wget\s+.*\|\s*(ba)?sh/, "pipe remote script to shell"},
    {~r/\bgit\s+push\s+(-f|--force)/, "force push to remote"},
    {~r/\bgit\s+reset\s+--hard/, "hard reset (destroys uncommitted changes)"},
    {~r/\bdrop\s+database\b/i, "drop database"},
    {~r/\bdrop\s+table\b/i, "drop table"},
    {~r/\btruncate\s+table\b/i, "truncate table"},
    {~r/\bgit\s+init\b/, "git init (create new repository)"},
    {~r/\brm\s+-rf\s+/, "recursive force delete"},
    {~r/\bsudo\s+/, "sudo command"},
    {~r/\bcurl\s+.*-o\s+/, "download file via curl"},
    {~r/\bwget\s+/, "download file via wget"},
    {~r/\bchmod\s+/, "change file permissions"},
    {~r/\bchown\s+/, "change file ownership"},
    {~r/\bkill\s+/, "kill process"},
    {~r/\bpkill\s+/, "kill process by name"},
    {~r/\bcat\s+.*\.(pem|key|crt)\b/, "read certificate/key file"},
    {~r/\bscp\s+/, "secure copy (file transfer)"},
    {~r/\brsync\s+/, "rsync (file sync)"},
  ]

  @type check_result :: :ok | {:blocked, String.t()} | {:needs_approval, String.t()}

  @doc """
  Check if a command needs approval, is blocked, or is safe.

  Returns:
  - `:ok` — safe to execute
  - `{:blocked, reason}` — always blocked
  - `{:needs_approval, reason}` — needs human confirmation
  """
  @spec check_command(String.t()) :: check_result()
  def check_command(command) do
    cond do
      always_blocked?(command) ->
        {:blocked, "Command permanently blocked by security policy"}

      reason = needs_approval?(command) ->
        {:needs_approval, reason}

      true ->
        :ok
    end
  end

  @doc """
  Request approval via CLI (IO.gets prompt).
  """
  @spec request_cli_approval(String.t(), String.t()) :: boolean()
  def request_cli_approval(command, reason) do
    IO.puts("\n\e[33m  ⚠️  Dangerous command detected: #{reason}\e[0m")
    IO.puts("\e[90m  Command: #{String.slice(command, 0, 200)}\e[0m")
    response = IO.gets("\e[33m  Approve? [y/N] \e[0m")

    case response do
      nil -> false
      text -> String.trim(text) |> String.downcase() |> String.starts_with?("y")
    end
  end

  @doc """
  Request approval via a callback function (for channels like Telegram).

  The callback receives `{command, reason}` and should return a boolean.
  """
  @spec request_approval(String.t(), String.t(), function() | nil) :: boolean()
  def request_approval(_command, _reason, nil), do: false
  def request_approval(command, reason, callback) when is_function(callback, 2) do
    callback.(command, reason)
  end

  # ── Private ────────────────────────────────────────────────────────

  defp always_blocked?(command) do
    Enum.any?(@always_blocked, &Regex.match?(&1, command))
  end

  defp needs_approval?(command) do
    Enum.find_value(@needs_approval, fn {pattern, reason} ->
      if Regex.match?(pattern, command), do: reason
    end)
  end
end
