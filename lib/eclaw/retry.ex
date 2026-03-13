defmodule Eclaw.Retry do
  @moduledoc """
  Retry logic with exponential backoff for API calls.

  Error classification:
  - Retryable: 429 (rate limit), 500, 502, 503, 529 (overloaded)
  - Non-retryable: 400, 401, 403, 404 → returns error immediately
  - 429 token limit: returns special error so agent can compact context
  """

  require Logger

  @max_retries 3
  @base_delay_ms 1_000
  @max_delay_ms 60_000

  @doc """
  Execute function with retry logic.

  `fun` is a 0-arity function returning `{:ok, result}` or `{:error, reason}`.

  ## Example

      Eclaw.Retry.with_retry(fn -> Eclaw.LLM.chat(messages, system) end)
  """
  @spec with_retry(function(), keyword()) :: {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, @max_retries)
    attempt(fun, 0, max_retries)
  end

  # ── Private ────────────────────────────────────────────────────────

  defp attempt(fun, retry_count, max_retries) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, {:api_error, 429, body}} = error ->
        if token_limit_error?(body) do
          # Token per minute limit — retry won't help, need to compact context
          Logger.warning("[Eclaw.Retry] 429 token limit — signaling for context compaction")
          {:error, :token_rate_limited}
        else
          # Request rate limit — wait and retry
          retry_or_fail(fun, error, retry_count, max_retries, 429)
        end

      {:error, {:api_error, status, _body}} = error when status in [500, 502, 503, 529] ->
        retry_or_fail(fun, error, retry_count, max_retries, status)

      {:error, {:http_error, _reason}} = error ->
        retry_or_fail(fun, error, retry_count, max_retries, :network)

      # Non-retryable errors (400, 401, 403, etc.) — return immediately
      error ->
        error
    end
  end

  defp retry_or_fail(fun, error, retry_count, max_retries, status) do
    if retry_count < max_retries do
      delay = calculate_delay(retry_count, status)

      Logger.warning(
        "[Eclaw.Retry] #{status_label(status)}, retry #{retry_count + 1}/#{max_retries} in #{delay}ms"
      )

      Process.sleep(delay)
      attempt(fun, retry_count + 1, max_retries)
    else
      Logger.error("[Eclaw.Retry] Max retries exceeded for #{status_label(status)}")
      error
    end
  end

  # Check if 429 is caused by exceeding input tokens per minute
  defp token_limit_error?(%{"error" => %{"message" => msg}}) when is_binary(msg) do
    String.contains?(msg, "input tokens per minute") or
      (String.contains?(msg, "token") and String.contains?(msg, "rate limit"))
  end

  defp token_limit_error?(_), do: false

  # Exponential backoff with jitter
  defp calculate_delay(retry_count, status) do
    base =
      case status do
        429 -> @base_delay_ms * 8
        _ -> @base_delay_ms
      end

    # 2^retry * base + random jitter
    delay = min(base * Integer.pow(2, retry_count), @max_delay_ms)
    jitter = :rand.uniform(1_000)
    delay + jitter
  end

  defp status_label(:network), do: "Network error"
  defp status_label(status), do: "API #{status}"
end
