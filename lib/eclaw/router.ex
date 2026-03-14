defmodule Eclaw.Router do
  @moduledoc """
  Multi-model routing — classifies prompts and selects the optimal model.

  Classification logic:
  - **Haiku-eligible**: short prompts (< 200 chars) matching simple patterns
    (greetings, translations, formatting, lookups, single-step questions)
  - **Sonnet-default**: everything else, including prompts with complexity signals

  Respects explicit model overrides and avoids mid-loop model switches.
  """

  require Logger

  alias Eclaw.Config

  @haiku_model "claude-haiku-4-5-20251001"

  # Patterns that indicate a simple, haiku-eligible prompt
  @simple_patterns [
    ~r/^(hi|hello|hey|chào|xin chào|good (morning|afternoon|evening))\b/i,
    ~r/^(thanks|thank you|cảm ơn|ok|okay|sure|got it|bye|goodbye)\b/i,
    ~r/^(translate|dịch)\b/i,
    ~r/^(format|reformat)\b/i,
    ~r/^(what is|what's|who is|who's|when is|when was|where is|how old)\b/i,
    ~r/^(define|meaning of|definition of)\b/i,
    ~r/^(convert|calculate|how many|how much)\b/i,
    ~r/^(list|name|give me)\b/i,
    ~r/^(yes|no|yep|nope|đúng|không)\s*[.!?]?\s*$/i,
  ]

  # Keywords that signal complexity — always route to Sonnet
  @complexity_signals [
    ~r/\banalyze\b/i,
    ~r/\bdebug\b/i,
    ~r/\brefactor\b/i,
    ~r/\bwrite code\b/i,
    ~r/\bexplain\b/i,
    ~r/\bimplement\b/i,
    ~r/\bfix\b/i,
    ~r/\barchitect\b/i,
    ~r/\bdesign\b/i,
    ~r/\breview\b/i,
    ~r/\boptimize\b/i,
    ~r/\bmigrate\b/i,
  ]

  @doc """
  Select the optimal model for the given prompt.

  Options:
  - `:model` — explicit model override (returned as-is)
  - `:iteration` — current loop iteration (> 0 preserves current model)
  - `:current_model` — model used in current loop (returned when iteration > 0)
  """
  @spec select_model(String.t(), keyword()) :: String.t()
  def select_model(prompt, opts \\ []) do
    cond do
      # Never override an explicit user choice
      opts[:model] ->
        opts[:model]

      # Mid-loop: preserve current model to avoid switching mid-conversation
      is_integer(opts[:iteration]) and opts[:iteration] > 0 ->
        opts[:current_model] || Config.model()

      # Classify the prompt
      true ->
        classify(prompt)
    end
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp classify(prompt) do
    cond do
      has_complexity_signal?(prompt) ->
        Config.model()

      haiku_eligible?(prompt) ->
        Logger.info("[Eclaw.Router] Routed to Haiku: prompt is simple (#{String.length(prompt)} chars)")
        @haiku_model

      true ->
        Config.model()
    end
  end

  defp haiku_eligible?(prompt) do
    String.length(prompt) < 200 and matches_simple_pattern?(prompt)
  end

  defp matches_simple_pattern?(prompt) do
    trimmed = String.trim(prompt)
    Enum.any?(@simple_patterns, &Regex.match?(&1, trimmed))
  end

  defp has_complexity_signal?(prompt) do
    Enum.any?(@complexity_signals, &Regex.match?(&1, prompt))
  end
end
