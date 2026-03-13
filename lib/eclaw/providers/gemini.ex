defmodule Eclaw.Providers.Gemini do
  @moduledoc """
  Google Gemini provider.

  Supports Gemini 2.0 Flash, Gemini 2.5 Pro, etc.
  API key from env var `GEMINI_API_KEY`.

  Note: Gemini uses a different API format. This module converts between
  Anthropic's format (used internally by Eclaw) and Gemini's format.
  """

  @behaviour Eclaw.Provider

  require Logger

  @api_base "https://generativelanguage.googleapis.com/v1beta/models"

  @impl true
  def name, do: :gemini

  @impl true
  def chat(messages, system, tools, opts) do
    model = Keyword.get(opts, :model, "gemini-2.0-flash")
    api_key = Keyword.fetch!(opts, :api_key)
    url = "#{@api_base}/#{model}:generateContent"

    body = build_body(messages, system, tools)
    headers = [{"x-goog-api-key", api_key}, {"content-type", "application/json"}]

    case Req.post(url, json: body, headers: headers, receive_timeout: 120_000) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        {:ok, normalize_response(resp)}

      {:ok, %Req.Response{status: status, body: err}} ->
        {:error, {:api_error, status, err}}

      {:error, exception} ->
        {:error, {:http_error, exception}}
    end
  end

  @impl true
  def stream(messages, system, tools, _on_chunk, opts) do
    Logger.warning("[Gemini] Streaming not yet implemented, falling back to non-streaming")
    chat(messages, system, tools, opts)
  end

  # ── Private ────────────────────────────────────────────────────────

  defp build_body(messages, system, tools) do
    contents = convert_messages(messages)

    base = %{
      "contents" => contents,
      "systemInstruction" => %{
        "parts" => [%{"text" => system}]
      }
    }

    if tools != [] do
      Map.put(base, "tools", [%{"functionDeclarations" => convert_tools(tools)}])
    else
      base
    end
  end

  # Convert Anthropic messages → Gemini format
  # Build a tool_use_id → name lookup from all messages first
  defp convert_messages(messages) do
    # Build lookup: tool_use_id → tool name from assistant tool_use blocks
    tool_name_lookup =
      messages
      |> Enum.flat_map(fn
        %{"role" => "assistant", "content" => blocks} when is_list(blocks) ->
          Enum.filter(blocks, &(&1["type"] == "tool_use"))
        _ -> []
      end)
      |> Map.new(fn block -> {block["id"], block["name"]} end)

    Enum.flat_map(messages, fn msg ->
      case msg do
        %{"role" => "user", "content" => content} when is_binary(content) ->
          [%{"role" => "user", "parts" => [%{"text" => content}]}]

        %{"role" => "user", "content" => blocks} when is_list(blocks) ->
          parts =
            Enum.map(blocks, fn
              %{"type" => "tool_result", "tool_use_id" => id, "content" => content} ->
                name = Map.get(tool_name_lookup, id, "unknown_tool")
                %{"functionResponse" => %{"name" => name, "response" => %{"result" => content}}}

              %{"type" => "text", "text" => text} ->
                %{"text" => text}

              other ->
                %{"text" => inspect(other)}
            end)

          [%{"role" => "user", "parts" => parts}]

        %{"role" => "assistant", "content" => blocks} when is_list(blocks) ->
          parts =
            Enum.map(blocks, fn
              %{"type" => "text", "text" => text} ->
                %{"text" => text}

              %{"type" => "tool_use", "name" => name, "input" => input} ->
                %{"functionCall" => %{"name" => name, "args" => input}}

              _ ->
                nil
            end)
            |> Enum.reject(&is_nil/1)

          [%{"role" => "model", "parts" => parts}]

        _ ->
          []
      end
    end)
  end

  # Convert Anthropic tool schema → Gemini function declarations
  defp convert_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        "name" => tool["name"],
        "description" => tool["description"],
        "parameters" => tool["input_schema"]
      }
    end)
  end

  # Convert Gemini response → Anthropic format
  defp normalize_response(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]} = resp) do
    content_blocks =
      Enum.flat_map(parts, fn
        %{"text" => text} ->
          [%{"type" => "text", "text" => text}]

        %{"functionCall" => %{"name" => name, "args" => args}} ->
          [%{
            "type" => "tool_use",
            "id" => "gemini_#{:erlang.unique_integer([:positive])}",
            "name" => name,
            "input" => args || %{}
          }]

        _ ->
          []
      end)

    has_tool_calls = Enum.any?(content_blocks, &(&1["type"] == "tool_use"))
    stop_reason = if has_tool_calls, do: "tool_use", else: "end_turn"

    # Extract usage
    usage =
      case resp do
        %{"usageMetadata" => %{"promptTokenCount" => input, "candidatesTokenCount" => output}} ->
          %{"input_tokens" => input, "output_tokens" => output}
        _ ->
          %{"input_tokens" => 0, "output_tokens" => 0}
      end

    %{
      "content" => content_blocks,
      "stop_reason" => stop_reason,
      "usage" => usage
    }
  end

  defp normalize_response(other) do
    Logger.warning("[Gemini] Unexpected response: #{inspect(other)}")
    %{"content" => [], "stop_reason" => "end_turn", "usage" => %{"input_tokens" => 0, "output_tokens" => 0}}
  end
end
