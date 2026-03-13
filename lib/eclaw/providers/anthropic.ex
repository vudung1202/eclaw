defmodule Eclaw.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude provider — primary implementation.

  Separates HTTP/SSE logic from `Eclaw.LLM` to use via Provider behaviour.
  """

  @behaviour Eclaw.Provider

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"

  @impl true
  def name, do: :anthropic

  @impl true
  def chat(messages, system, tools, opts) do
    body = build_body(messages, system, tools, opts, false)
    headers = build_headers(opts)

    case Req.post(api_url(opts), json: body, headers: headers, receive_timeout: 120_000) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        {:ok, resp}

      {:ok, %Req.Response{status: status, body: err}} ->
        {:error, {:api_error, status, err}}

      {:error, exception} ->
        {:error, {:http_error, exception}}
    end
  end

  @impl true
  def stream(messages, system, tools, on_chunk, opts) do
    body = build_body(messages, system, tools, opts, true)
    headers = build_headers(opts)

    acc = %{
      content_blocks: %{},
      current_index: nil,
      stop_reason: nil,
      buffer: "",
      usage: %{input_tokens: 0, output_tokens: 0}
    }

    req_opts = [
      json: body,
      headers: headers,
      receive_timeout: 120_000,
      into: build_stream_collector(on_chunk, acc)
    ]

    case Req.post(api_url(opts), req_opts) do
      {:ok, %Req.Response{status: 200}} ->
        response = assemble_response(acc)
        on_chunk.({:done, response})
        {:ok, response}

      {:ok, %Req.Response{status: status, body: err}} ->
        Process.delete(:eclaw_stream_acc)
        {:error, {:api_error, status, err}}

      {:error, exception} ->
        Process.delete(:eclaw_stream_acc)
        {:error, {:http_error, exception}}
    end
  end

  # ── Private ────────────────────────────────────────────────────────

  defp api_url(opts), do: Keyword.get(opts, :api_url, @api_url)

  defp build_body(messages, system, tools, opts, stream?) do
    model = Keyword.get(opts, :model, "claude-sonnet-4-20250514")
    max_tokens = Keyword.get(opts, :max_tokens, 8192)

    base = %{
      "model" => model,
      "max_tokens" => max_tokens,
      "system" => system,
      "messages" => messages,
      "tools" => tools
    }

    if stream?, do: Map.put(base, "stream", true), else: base
  end

  defp build_headers(opts) do
    api_key = Keyword.fetch!(opts, :api_key)

    [
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_version},
      {"content-type", "application/json"}
    ]
  end

  defp build_stream_collector(on_chunk, initial_acc) do
    fn {:data, raw_data}, {req, resp} ->
      prev_acc = Process.get(:eclaw_stream_acc, initial_acc)

      combined = prev_acc.buffer <> raw_data
      {events, remaining} = parse_sse_events(combined)

      new_acc =
        Enum.reduce(events, %{prev_acc | buffer: remaining}, fn event, acc ->
          process_sse_event(event, acc, on_chunk)
        end)

      Process.put(:eclaw_stream_acc, new_acc)
      {:cont, {req, resp}}
    end
  end

  # ── SSE parsing (shared with Eclaw.LLM) ──────────────────────────

  defp parse_sse_events(text) do
    parts = String.split(text, "\n\n")

    {complete, remaining} =
      case parts do
        [] -> {[], ""}
        _ -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
      end

    events =
      complete
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.map(&parse_single_event/1)
      |> Enum.reject(&is_nil/1)

    {events, remaining}
  end

  defp parse_single_event(raw) do
    {event_type, data} =
      raw
      |> String.split("\n")
      |> Enum.reduce({nil, nil}, fn line, {evt, dat} ->
        case String.split(line, ": ", parts: 2) do
          ["event", t] -> {String.trim(t), dat}
          ["data", d] -> {evt, String.trim(d)}
          _ -> {evt, dat}
        end
      end)

    if event_type && data do
      case Jason.decode(data) do
        {:ok, parsed} -> {event_type, parsed}
        _ -> nil
      end
    end
  end

  defp process_sse_event({"content_block_start", %{"index" => idx, "content_block" => block}}, acc, on_chunk) do
    case block do
      %{"type" => "text", "text" => text} ->
        if text != "", do: on_chunk.({:text_delta, text})
        put_in(acc, [:content_blocks, Access.key(idx, %{})], %{"type" => "text", "text" => text})

      %{"type" => "tool_use", "id" => id, "name" => name} ->
        on_chunk.({:tool_use_start, %{id: id, name: name}})
        put_in(acc, [:content_blocks, Access.key(idx, %{})], %{
          "type" => "tool_use", "id" => id, "name" => name, "input_json" => ""
        })

      _ ->
        acc
    end
    |> Map.put(:current_index, idx)
  end

  defp process_sse_event({"content_block_delta", %{"index" => idx, "delta" => delta}}, acc, on_chunk) do
    case delta do
      %{"type" => "text_delta", "text" => text} ->
        on_chunk.({:text_delta, text})
        update_in(acc, [:content_blocks, idx, "text"], &((&1 || "") <> text))

      %{"type" => "input_json_delta", "partial_json" => fragment} ->
        on_chunk.({:tool_input_delta, fragment})
        update_in(acc, [:content_blocks, idx, "input_json"], &((&1 || "") <> fragment))

      _ ->
        acc
    end
  end

  defp process_sse_event({"message_start", %{"message" => %{"usage" => usage}}}, acc, _on_chunk) do
    put_in(acc, [:usage, :input_tokens], usage["input_tokens"] || 0)
  end

  defp process_sse_event({"message_delta", %{"delta" => %{"stop_reason" => reason}} = data}, acc, _on_chunk) do
    acc = %{acc | stop_reason: reason}
    case data do
      %{"usage" => usage} -> put_in(acc, [:usage, :output_tokens], usage["output_tokens"] || 0)
      _ -> acc
    end
  end

  defp process_sse_event(_event, acc, _on_chunk), do: acc

  defp assemble_response(_initial_acc) do
    acc = Process.get(:eclaw_stream_acc, %{content_blocks: %{}, stop_reason: nil, usage: %{input_tokens: 0, output_tokens: 0}})
    Process.delete(:eclaw_stream_acc)

    blocks =
      acc.content_blocks
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.map(fn {_idx, block} ->
        case block do
          %{"type" => "tool_use", "input_json" => json} = tb ->
            input = case Jason.decode(json) do
              {:ok, parsed} -> parsed
              _ -> %{}
            end
            %{"type" => "tool_use", "id" => tb["id"], "name" => tb["name"], "input" => input}

          other ->
            other
        end
      end)

    %{
      "content" => blocks,
      "stop_reason" => acc.stop_reason,
      "usage" => %{
        "input_tokens" => acc.usage.input_tokens,
        "output_tokens" => acc.usage.output_tokens
      }
    }
  end
end
