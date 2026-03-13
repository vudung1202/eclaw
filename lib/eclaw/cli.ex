defmodule Eclaw.CLI do
  @moduledoc """
  REPL (Read-Eval-Print Loop) with streaming output.

  Run via: `mix eclaw`

  Commands:
  - /reset            — Reset conversation
  - /model [name]     — Show or switch model (e.g. /model gpt-4o)
  - /usage            — Show token usage and cost
  - /compact          — Force context compaction
  - /status           — Show system status
  - /memory           — View memory entries
  - /remember <text>  — Save to memory
  - /forget           — Clear all memory
  - /help             — Show help
  - /exit             — Exit
  """

  @doc "Entry point for CLI REPL."
  def main do
    print_banner()
    loop()
  end

  # ── REPL Loop ─────────────────────────────────────────────────────

  defp loop do
    case IO.gets("\n\e[36meclaw>\e[0m ") do
      :eof -> bye()
      {:error, _} -> bye()
      input ->
        input |> String.trim() |> handle_input()
    end
  end

  defp handle_input(""), do: loop()

  defp handle_input(input) do
    lower = String.downcase(input)

    cond do
      lower == "/exit" or lower == "/quit" -> bye()
      lower == "/reset" -> do_reset()
      lower == "/model" -> do_model()
      String.starts_with?(lower, "/model ") -> do_switch_model(String.slice(input, 7..-1//1) |> String.trim())
      lower == "/usage" -> do_usage()
      lower == "/compact" -> do_compact()
      lower == "/status" -> do_status()
      lower == "/memory" -> do_memory()
      lower == "/forget" -> do_forget()
      lower == "/help" -> do_help()
      String.starts_with?(lower, "/remember ") ->
        text = String.slice(input, 10..-1//1) |> String.trim()
        do_remember(text)
      true ->
        do_chat(input)
    end
  end

  # ── Chat with streaming output ─────────────────────────────────────

  defp do_chat(prompt) do
    IO.write("\n")

    on_chunk = fn
      {:text_delta, text} ->
        IO.write("\e[32m#{text}\e[0m")

      {:tool_call, name, input} ->
        summary = tool_summary(name, input)
        IO.write("\n\e[33m  ⚡ #{name}\e[0m\e[90m #{summary}\e[0m\n")

      {:tool_result, _name, result} ->
        truncated = result |> String.trim() |> String.slice(0, 300)
        IO.write("\e[90m  → #{truncated}\e[0m\n\n")

      {:status, message} ->
        IO.write("\e[33m  ⏳ #{message}\e[0m\n")

      {:done, _response} ->
        IO.write("\n")

      _ ->
        :ok
    end

    case Eclaw.Agent.stream(prompt, on_chunk) do
      {:ok, _text} -> :ok
      {:error, reason} -> IO.puts("\n\e[31mError: #{inspect(reason)}\e[0m")
    end

    loop()
  end

  defp tool_summary("execute_bash", %{"command" => cmd}), do: "`#{cmd}`"
  defp tool_summary("read_file", %{"path" => path}), do: path
  defp tool_summary("write_file", %{"path" => path}), do: path
  defp tool_summary("list_directory", %{"path" => path}), do: path
  defp tool_summary("search_files", %{"pattern" => p, "path" => d}), do: "'#{p}' in #{d}"
  defp tool_summary(_name, input), do: inspect(input)

  # ── Slash commands ────────────────────────────────────────────────

  defp do_reset do
    Eclaw.Agent.reset()
    IO.puts("\e[33mConversation reset.\e[0m")
    loop()
  end

  defp do_model do
    model = Eclaw.Agent.get_model()
    provider = Eclaw.LLM.detect_provider(model) || Eclaw.Config.provider()

    IO.puts("\e[33mProvider: #{provider}\e[0m")
    IO.puts("\e[33mModel: #{model}\e[0m")
    IO.puts("\e[33mMax tokens: #{Eclaw.Config.max_tokens()}\e[0m")

    pricing = Eclaw.LLM.pricing_for(model)
    IO.puts("\e[33mPricing: $#{pricing.input}/1M input, $#{pricing.output}/1M output\e[0m")

    plugins = Eclaw.ToolRegistry.list()

    if plugins != [] do
      IO.puts("\e[33mPlugins: #{Enum.join(plugins, ", ")}\e[0m")
    end

    loop()
  end

  defp do_switch_model(model_name) do
    provider = Eclaw.LLM.detect_provider(model_name)

    if provider do
      case Eclaw.Agent.set_model(model_name) do
        :ok ->
          IO.puts("\e[33mSwitched to #{model_name} (#{provider})\e[0m")
        {:error, reason} ->
          IO.puts("\e[31mCannot switch to #{model_name}: #{reason}\e[0m")
      end
    else
      IO.puts("\e[31mUnknown model: #{model_name}\e[0m")
      IO.puts("\e[90mSupported prefixes: claude-*, gpt-*, gemini-*\e[0m")
    end

    loop()
  end

  defp do_usage do
    usage = Eclaw.Agent.get_usage()

    IO.puts("\e[33m  Session Usage:\e[0m")
    IO.puts("\e[33m    Requests:      #{usage.requests}\e[0m")
    IO.puts("\e[33m    Input tokens:  #{format_number(usage.input_tokens)}\e[0m")
    IO.puts("\e[33m    Output tokens: #{format_number(usage.output_tokens)}\e[0m")
    IO.puts("\e[33m    Total tokens:  #{format_number(usage.input_tokens + usage.output_tokens)}\e[0m")
    IO.puts("\e[33m    Est. cost:     $#{Float.round(usage.cost, 4)}\e[0m")

    loop()
  end

  defp do_compact do
    IO.write("\e[33m  Compacting...")
    case Eclaw.Agent.compact() do
      :ok -> IO.puts(" done.\e[0m")
      {:error, reason} -> IO.puts(" failed: #{inspect(reason)}\e[0m")
    end

    loop()
  end

  defp do_status do
    status = Eclaw.Agent.status()

    IO.puts("\e[33m  Agent Status:\e[0m")
    IO.puts("\e[33m    Model:        #{status.model}\e[0m")
    IO.puts("\e[33m    Provider:     #{status.provider}\e[0m")
    IO.puts("\e[33m    Session:      #{status.session_id || "singleton"}\e[0m")
    IO.puts("\e[33m    Messages:     #{status.messages}\e[0m")
    IO.puts("\e[33m    Est. tokens:  #{format_number(status.estimated_tokens)}\e[0m")
    IO.puts("\e[33m    Total cost:   $#{Float.round(status.usage.cost, 4)}\e[0m")

    loop()
  end

  defp do_memory do
    entries = Eclaw.Memory.list_all()

    if entries == [] do
      IO.puts("\e[90m  (no memories stored)\e[0m")
    else
      IO.puts("\e[33m  Memory (#{length(entries)} entries):\e[0m")

      Enum.each(entries, fn entry ->
        IO.puts("\e[90m  [#{entry.type}] #{entry.key}: #{String.slice(entry.content, 0, 80)}\e[0m")
      end)
    end

    loop()
  end

  defp do_remember(text) when text == "" do
    IO.puts("\e[31mUsage: /remember <something to remember>\e[0m")
    loop()
  end

  defp do_remember(text) do
    key = "user_#{System.system_time(:millisecond)}"
    Eclaw.Memory.store(key, text, :fact)
    IO.puts("\e[33mRemembered: #{text}\e[0m")
    loop()
  end

  defp do_forget do
    Eclaw.Memory.clear()
    IO.puts("\e[33mAll memories cleared.\e[0m")
    loop()
  end

  defp do_help do
    IO.puts("""
    \e[33m
    Commands:
      /model [name]    — Show or switch model (e.g. /model gpt-4o)
      /usage           — Show token usage and cost for this session
      /compact         — Force conversation history compaction
      /status          — Show agent status (model, tokens, cost)
      /reset           — Reset conversation history
      /memory          — List stored memories
      /remember <text> — Store something in memory
      /forget          — Clear all memories
      /help            — Show this help
      /exit            — Exit Eclaw
    \e[0m\
    """)

    loop()
  end

  defp print_banner do
    model = Eclaw.Config.model()
    provider = Eclaw.LLM.detect_provider(model) || Eclaw.Config.provider()

    IO.puts("""
    \e[36m
    ╔═══════════════════════════════════════╗
    ║          🦀 Eclaw Agent v0.2          ║
    ║   AI Assistant • Multi-model          ║
    ╚═══════════════════════════════════════╝
    \e[0m\e[90m  Provider: #{provider} | Model: #{model}
      Type /help for commands, /model <name> to switch.\e[0m
    """)
  end

  defp bye do
    IO.puts("\n\e[36mGoodbye! 👋\e[0m")
    :ok
  end

  defp format_number(n) when is_number(n) and n >= 1_000_000, do: "#{Float.round(n * 1.0 / 1_000_000, 1)}M"
  defp format_number(n) when is_number(n) and n >= 1_000, do: "#{Float.round(n * 1.0 / 1_000, 1)}K"
  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(n) when is_float(n), do: Float.to_string(Float.round(n, 1))
end
