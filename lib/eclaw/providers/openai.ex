defmodule Eclaw.Providers.OpenAI do
  @moduledoc """
  OpenAI ChatGPT provider.

  Supports GPT-4o, GPT-4, GPT-3.5-turbo.
  API key from env var `OPENAI_API_KEY`.

  Note: OpenAI uses a different tool/function calling format than Anthropic.
  This module converts between the two formats.
  """

  @behaviour Eclaw.Provider

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"

  @impl true
  def name, do: :openai

  @impl true
  def chat(messages, system, tools, opts) do
    body = build_body(messages, system, tools, opts, false)
    headers = build_headers(opts)

    case Req.post(api_url(opts), json: body, headers: headers, receive_timeout: 120_000) do
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
    # TODO: implement SSE streaming for OpenAI
    # Currently falls back to non-streaming
    Logger.warning("[OpenAI] Streaming not yet implemented, falling back to non-streaming")
    chat(messages, system, tools, opts)
  end

  # ── Private ────────────────────────────────────────────────────────

  defp api_url(opts), do: Keyword.get(opts, :api_url, @api_url)

  defp build_body(messages, system, tools, opts, _stream?) do
    model = Keyword.get(opts, :model, "gpt-4o")
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    # Convert messages from Anthropic format to OpenAI format
    oai_messages = [%{"role" => "system", "content" => system} | convert_messages(messages)]

    base = %{
      "model" => model,
      "max_tokens" => max_tokens,
      "messages" => oai_messages
    }

    # Convert tools from Anthropic format to OpenAI function calling format
    if tools != [] do
      Map.put(base, "tools", convert_tools(tools))
    else
      base
    end
  end

  defp build_headers(opts) do
    api_key = Keyword.fetch!(opts, :api_key)

    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end

  # Convert Anthropic messages → OpenAI messages
  defp convert_messages(messages) do
    Enum.map(messages, fn msg ->
      case msg do
        # Simple user message
        %{"role" => "user", "content" => content} when is_binary(content) ->
          %{"role" => "user", "content" => content}

        # User message containing tool results
        %{"role" => "user", "content" => blocks} when is_list(blocks) ->
          Enum.map(blocks, fn
            %{"type" => "tool_result", "tool_use_id" => id, "content" => content} ->
              %{"role" => "tool", "tool_call_id" => id, "content" => content}

            other ->
              %{"role" => "user", "content" => inspect(other)}
          end)

        # Assistant text
        %{"role" => "assistant", "content" => blocks} when is_list(blocks) ->
          text_parts =
            blocks
            |> Enum.filter(&(&1["type"] == "text"))
            |> Enum.map(& &1["text"])
            |> Enum.join("\n")

          tool_calls =
            blocks
            |> Enum.filter(&(&1["type"] == "tool_use"))
            |> Enum.map(fn tc ->
              %{
                "id" => tc["id"],
                "type" => "function",
                "function" => %{
                  "name" => tc["name"],
                  "arguments" => Jason.encode!(tc["input"])
                }
              }
            end)

          msg = %{"role" => "assistant", "content" => text_parts}
          if tool_calls != [], do: Map.put(msg, "tool_calls", tool_calls), else: msg

        other ->
          other
      end
    end)
    |> List.flatten()
  end

  # Convert Anthropic tool schema → OpenAI function format
  defp convert_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        "type" => "function",
        "function" => %{
          "name" => tool["name"],
          "description" => tool["description"],
          "parameters" => tool["input_schema"]
        }
      }
    end)
  end

  # Convert OpenAI response → Anthropic format (so Agent processes uniformly)
  defp normalize_response(%{"choices" => [%{"message" => message, "finish_reason" => finish_reason} | _]} = resp) do
    content_blocks = []

    # Text content
    content_blocks =
      case message do
        %{"content" => text} when is_binary(text) and text != "" ->
          content_blocks ++ [%{"type" => "text", "text" => text}]

        _ ->
          content_blocks
      end

    # Tool calls
    content_blocks =
      case message do
        %{"tool_calls" => tool_calls} when is_list(tool_calls) ->
          tool_blocks =
            Enum.map(tool_calls, fn tc ->
              input =
                case Jason.decode(tc["function"]["arguments"]) do
                  {:ok, parsed} -> parsed
                  _ -> %{}
                end

              %{
                "type" => "tool_use",
                "id" => tc["id"],
                "name" => tc["function"]["name"],
                "input" => input
              }
            end)

          content_blocks ++ tool_blocks

        _ ->
          content_blocks
      end

    # Normalize stop_reason
    stop_reason =
      case finish_reason do
        "stop" -> "end_turn"
        "tool_calls" -> "tool_use"
        other -> other
      end

    # Extract usage (OpenAI format → Anthropic format)
    usage =
      case resp do
        %{"usage" => %{"prompt_tokens" => input, "completion_tokens" => output}} ->
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
    Logger.warning("[OpenAI] Unexpected response: #{inspect(other)}")
    %{"content" => [], "stop_reason" => "end_turn", "usage" => %{"input_tokens" => 0, "output_tokens" => 0}}
  end
end
