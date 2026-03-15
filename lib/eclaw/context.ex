defmodule Eclaw.Context do
  @moduledoc """
  Manages conversation context window.

  Features:
  - Estimate token count (heuristic: ~3.5 chars/token)
  - Truncate tool results that are too long
  - Compact (summarize) conversation when exceeding threshold
  - Support input_token_budget for rate-limited accounts
  """

  require Logger

  # Model context windows (tokens)
  @context_limits %{
    # Anthropic
    "claude-sonnet-4-20250514" => 200_000,
    "claude-opus-4-20250514" => 200_000,
    "claude-haiku-4-20250514" => 200_000,
    # OpenAI
    "gpt-4o" => 128_000,
    "gpt-4o-mini" => 128_000,
    "gpt-4-turbo" => 128_000,
    "o1" => 200_000,
    "o3-mini" => 200_000,
    # Google
    "gemini-2.0-flash" => 1_000_000,
    "gemini-2.5-pro" => 1_000_000
  }

  # When total tokens exceed this threshold (% of context window), trigger compaction
  @compaction_threshold 0.70
  # How many recent messages to keep (not compacted)
  @keep_recent 4
  # Max tool result chars before truncation (~2300 tokens)
  @max_tool_result_chars 8_000

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Estimate total token count for a list of messages.

  Uses simple heuristic: character count / 3.5 (average between EN and VI).
  """
  @spec estimate_tokens(list(map())) :: non_neg_integer()
  def estimate_tokens(messages) do
    messages
    |> Enum.map(&message_chars/1)
    |> Enum.sum()
    |> Kernel./(3.5)
    |> ceil()
  end

  @doc """
  Check if messages need compaction.

  Two thresholds:
  - input_token_budget (config, default 8000) — for rate-limited accounts
  - compaction_threshold × context_window — for context window overflow
  """
  @spec needs_compaction?(list(map()), String.t() | nil) :: boolean()
  def needs_compaction?(messages, model \\ nil) do
    tokens = estimate_tokens(messages)

    # Check budget first (rate limit protection)
    budget = Eclaw.Config.get(:input_token_budget, 60_000)
    if tokens > budget do
      true
    else
      # Fallback: check context window
      model = model || Eclaw.Config.model()
      limit = Map.get(@context_limits, model, 200_000)
      threshold = ceil(limit * @compaction_threshold)
      tokens > threshold
    end
  end

  @doc """
  Compact messages: summarize old messages, keep recent ones.

  Calls LLM to generate a concise summary, then replaces old messages with
  a single summary message.
  """
  @spec compact(list(map()), String.t()) :: {:ok, list(map())} | {:error, term()}
  def compact(messages, system) do
    total = length(messages)

    if total <= @keep_recent do
      {:ok, messages}
    else
      split_at = total - @keep_recent
      {old_messages, recent_messages} = Enum.split(messages, split_at)

      Logger.info(
        "[Eclaw.Context] Compacting: #{length(old_messages)} old msgs → summary, keeping #{length(recent_messages)} recent"
      )

      case summarize(old_messages, system) do
        {:ok, summary} ->
          token_before = estimate_tokens(messages)

          summary_message = %{
            "role" => "user",
            "content" =>
              "[CONVERSATION SUMMARY]\n" <>
                "The following is a summary of the earlier conversation:\n\n" <>
                summary <>
                "\n\n[END SUMMARY — conversation continues below]"
          }

          compacted = ensure_alternating_roles([summary_message | recent_messages])
          token_after = estimate_tokens(compacted)

          reduction_pct = if token_before > 0, do: ceil((1 - token_after / token_before) * 100), else: 0

          Logger.info(
            "[Eclaw.Context] Compacted: ~#{token_before} → ~#{token_after} tokens (#{reduction_pct}%)"
          )

          {:ok, compacted}

        {:error, reason} ->
          Logger.warning("[Eclaw.Context] Compaction summarization failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Force compact — used when rate limited due to oversized context.

  Keeps fewer messages than normal (2 instead of 4) to maximize token reduction.
  Does not call LLM to summarize (would also be rate limited) — directly drops old messages.
  """
  @spec force_compact(list(map()), String.t()) :: {:ok, list(map())}
  def force_compact(messages, _system) do
    total = length(messages)

    if total <= 2 do
      {:ok, messages}
    else
      keep = min(2, total - 1)
      recent_messages = Enum.take(messages, -keep)

      Logger.warning(
        "[Eclaw.Context] Force compact: dropping #{total - keep} old messages, keeping #{keep} recent"
      )

      {:ok, ensure_alternating_roles(recent_messages)}
    end
  end

  @doc """
  Truncate tool result if too long.

  Keeps head and tail (head+tail strategy), since errors are often at the end of output.
  """
  @spec truncate_tool_result(String.t()) :: String.t()
  def truncate_tool_result(result) do
    char_count = String.length(result)

    if char_count <= @max_tool_result_chars do
      result
    else
      head_size = div(@max_tool_result_chars, 2)
      tail_size = div(@max_tool_result_chars, 2)
      omitted = char_count - head_size - tail_size

      head = String.slice(result, 0, head_size)
      tail = String.slice(result, -tail_size..-1//1)

      "#{head}\n\n[... #{omitted} chars omitted ...]\n\n#{tail}"
    end
  end

  @doc "Extract text from content blocks (Anthropic message format)."
  @spec extract_text(list(map())) :: String.t()
  def extract_text(blocks) when is_list(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(& &1["text"])
    |> Enum.join("\n")
  end

  def extract_text(_), do: ""

  # ── Private ────────────────────────────────────────────────────────

  defp message_chars(%{"content" => content}) when is_binary(content) do
    String.length(content)
  end

  defp message_chars(%{"content" => blocks}) when is_list(blocks) do
    Enum.reduce(blocks, 0, fn
      %{"text" => text}, acc -> acc + String.length(text)
      %{"content" => text}, acc when is_binary(text) -> acc + String.length(text)
      %{"type" => "tool_use", "input" => input}, acc -> acc + (input |> Jason.encode!() |> String.length())
      _, acc -> acc
    end)
  end

  defp message_chars(_), do: 0

  # Ensure messages alternate between user/assistant roles.
  # After compaction, a "user" summary may precede a "user" recent message.
  # Insert a placeholder assistant message to maintain valid API format.
  defp ensure_alternating_roles([first | rest]) do
    {result, _} =
      Enum.reduce(rest, {[first], first["role"]}, fn msg, {acc, prev_role} ->
        if msg["role"] == prev_role and prev_role == "user" do
          placeholder = %{"role" => "assistant", "content" => [%{"type" => "text", "text" => "(continued)"}]}
          {[msg, placeholder | acc], msg["role"]}
        else
          {[msg | acc], msg["role"]}
        end
      end)

    Enum.reverse(result)
  end

  # Call LLM to summarize old conversation
  defp summarize(old_messages, _system) do
    summary_prompt = %{
      "role" => "user",
      "content" =>
        "Please provide a concise summary of the conversation above. " <>
          "Focus on: key decisions made, important context, file paths mentioned, " <>
          "tools used and their results, and any ongoing tasks. " <>
          "Keep the summary under 200 words."
    }

    messages = old_messages ++ [summary_prompt]

    case Eclaw.LLM.chat(messages, "You are a conversation summarizer. Be concise and factual.") do
      {:ok, %{"content" => blocks}} ->
        {:ok, extract_text(blocks)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
