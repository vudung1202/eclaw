defmodule Eclaw.Agent do
  @moduledoc """
  GenServer managing conversation state and orchestrating the Agent Loop.

  Supports 2 modes:
  - Singleton (CLI): `Eclaw.Agent.chat(prompt)` — uses name: __MODULE__
  - Multi-instance (sessions): `Eclaw.Agent.chat(pid, prompt)` — per-user via SessionManager

  Features:
  - Context compaction: auto-summarize when conversation gets too long
  - Retry with backoff: auto-retry on transient API errors
  - Streaming + non-streaming modes
  - Idle timeout: auto-shutdown session after inactivity
  """

  use GenServer
  require Logger

  alias Eclaw.{Config, Context, Events, History, Memory, Retry, Router, Skills, Telemetry}

  @idle_timeout :timer.minutes(30)

  # ── State ──────────────────────────────────────────────────────────

  defstruct [
    :system,
    :session_id,
    :agent_task_ref,
    :agent_from,
    model: nil,
    messages: [],
    busy: false,
    usage: %{input_tokens: 0, output_tokens: 0, requests: 0, cost: 0.0}
  ]

  # ── Public API (Singleton — backward compatible for CLI) ──────────

  def start_link(opts \\ []) do
    session_id = Keyword.get(opts, :session_id)

    name =
      if session_id do
        {:via, Registry, {Eclaw.Registry, {:agent, session_id}}}
      else
        __MODULE__
      end

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Non-streaming: send prompt and wait for full response (singleton)."
  @spec chat(String.t() | list()) :: {:ok, String.t()} | {:error, term()}
  def chat(prompt), do: chat(__MODULE__, prompt)

  @doc "Non-streaming: send prompt and wait for full response (pid/name)."
  @spec chat(pid() | atom() | GenServer.name(), String.t() | list()) :: {:ok, String.t()} | {:error, term()}
  def chat(server, prompt) do
    GenServer.call(server, {:chat, prompt}, :infinity)
  end

  @doc "Streaming: send prompt with on_chunk callback (singleton)."
  @spec stream(String.t(), function()) :: {:ok, String.t()} | {:error, term()}
  def stream(prompt, on_chunk), do: stream(__MODULE__, prompt, on_chunk)

  @doc "Streaming: send prompt with on_chunk callback (pid/name)."
  @spec stream(pid() | atom() | GenServer.name(), String.t(), function()) :: {:ok, String.t()} | {:error, term()}
  def stream(server, prompt, on_chunk) do
    GenServer.call(server, {:stream, prompt, on_chunk}, :infinity)
  end

  @doc "Reset conversation history (singleton)."
  @spec reset() :: :ok
  def reset, do: reset(__MODULE__)

  @doc "Reset conversation history (pid/name)."
  @spec reset(pid() | atom() | GenServer.name()) :: :ok
  def reset(server) do
    GenServer.cast(server, :reset)
  end

  @doc "Switch model at runtime (singleton)."
  @spec set_model(String.t()) :: :ok
  def set_model(model), do: set_model(__MODULE__, model)

  @doc "Switch model at runtime (pid/name)."
  @spec set_model(pid() | atom() | GenServer.name(), String.t()) :: :ok
  def set_model(server, model) do
    GenServer.call(server, {:set_model, model})
  end

  @doc "Get current model (singleton)."
  @spec get_model() :: String.t()
  def get_model, do: get_model(__MODULE__)

  @doc "Get current model (pid/name)."
  def get_model(server), do: GenServer.call(server, :get_model)

  @doc "Get usage stats (singleton)."
  @spec get_usage() :: map()
  def get_usage, do: get_usage(__MODULE__)

  @doc "Get usage stats (pid/name)."
  def get_usage(server), do: GenServer.call(server, :get_usage)

  @doc "Force context compaction (singleton)."
  @spec compact() :: :ok | {:error, term()}
  def compact, do: compact(__MODULE__)

  @doc "Force context compaction (pid/name)."
  def compact(server), do: GenServer.call(server, :compact, :infinity)

  @doc "Get agent status (singleton)."
  @spec status() :: map()
  def status, do: status(__MODULE__)

  @doc "Get agent status (pid/name)."
  def status(server), do: GenServer.call(server, :status)

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id)

    if session_id do
      Logger.info("[Eclaw.Agent] Session #{session_id} initialized")
    else
      Logger.info("[Eclaw.Agent] Singleton initialized successfully")
    end

    {:ok, %__MODULE__{system: Config.system_prompt(), session_id: session_id}, idle_timeout(session_id)}
  end

  @impl true
  def handle_call({:chat, _prompt}, _from, %{busy: true} = state) do
    {:reply, {:error, :busy}, state, idle_timeout(state.session_id)}
  end

  @impl true
  def handle_call({:chat, prompt}, from, state) do
    new_state = run_agent_async(prompt, state, :no_stream, from)
    {:noreply, new_state, idle_timeout(state.session_id)}
  end

  @impl true
  def handle_call({:stream, _prompt, _on_chunk}, _from, %{busy: true} = state) do
    {:reply, {:error, :busy}, state, idle_timeout(state.session_id)}
  end

  @impl true
  def handle_call({:stream, prompt, on_chunk}, from, state) do
    new_state = run_agent_async(prompt, state, {:stream, on_chunk}, from)
    {:noreply, new_state, idle_timeout(state.session_id)}
  end

  @impl true
  def handle_call({:set_model, model}, _from, state) do
    provider = Eclaw.LLM.detect_provider(model)

    # Validate that an API key exists for this provider before switching
    case Eclaw.LLM.validate_api_key(provider) do
      :ok ->
        Logger.info("[Eclaw.Agent] Model switched to #{model} (provider: #{provider || "auto"})")
        {:reply, :ok, %{state | model: model}, idle_timeout(state.session_id)}

      {:error, reason} ->
        {:reply, {:error, reason}, state, idle_timeout(state.session_id)}
    end
  end

  @impl true
  def handle_call(:get_model, _from, state) do
    model = state.model || Config.model()
    {:reply, model, state, idle_timeout(state.session_id)}
  end

  @impl true
  def handle_call(:get_usage, _from, state) do
    {:reply, state.usage, state, idle_timeout(state.session_id)}
  end

  @impl true
  def handle_call(:compact, _from, state) do
    case Context.compact(state.messages, state.system) do
      {:ok, compacted} ->
        {:reply, :ok, %{state | messages: compacted}, idle_timeout(state.session_id)}

      {:error, reason} ->
        Logger.warning("[Eclaw.Agent] Compaction failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state, idle_timeout(state.session_id)}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    model = state.model || Config.model()
    provider = Eclaw.LLM.detect_provider(model) || Config.get(:provider, :anthropic)

    status = %{
      model: model,
      provider: provider,
      session_id: state.session_id,
      messages: length(state.messages),
      estimated_tokens: Context.estimate_tokens(state.messages),
      usage: state.usage
    }

    {:reply, status, state, idle_timeout(state.session_id)}
  end

  @impl true
  def handle_cast(:reset, state) do
    Logger.info("[Eclaw.Agent] Reset conversation #{state.session_id || "singleton"}")
    {:noreply, %{state | messages: [], usage: %{input_tokens: 0, output_tokens: 0, requests: 0, cost: 0.0}}, idle_timeout(state.session_id)}
  end

  # Handle agent Task completion — reply to original caller
  @impl true
  def handle_info({ref, {:agent_done, from, result, messages, usage_delta}}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    GenServer.reply(from, result)

    new_usage = %{
      input_tokens: state.usage.input_tokens + usage_delta.input_tokens,
      output_tokens: state.usage.output_tokens + usage_delta.output_tokens,
      requests: state.usage.requests + usage_delta.requests,
      cost: state.usage.cost + usage_delta.cost
    }

    # Save conversation history asynchronously (skip for singleton CLI agent)
    if state.session_id do
      Task.Supervisor.start_child(Eclaw.TaskSupervisor, fn ->
        History.save(state.session_id, messages)
      end)
    end

    {:noreply, %{state | messages: messages, usage: new_usage, busy: false, agent_task_ref: nil, agent_from: nil}, idle_timeout(state.session_id)}
  end

  # Handle agent Task crash — reply with error to the waiting caller
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{agent_task_ref: ref, agent_from: from} = state) when ref != nil do
    Logger.error("[Eclaw.Agent] Agent task crashed: #{inspect(reason)}")
    if from, do: GenServer.reply(from, {:error, :agent_crashed})
    {:noreply, %{state | busy: false, agent_task_ref: nil, agent_from: nil}, idle_timeout(state.session_id)}
  end

  @impl true
  def handle_info(:timeout, %{session_id: nil} = state) do
    # Singleton never auto-shuts down
    {:noreply, state}
  end

  @impl true
  def handle_info(:timeout, %{session_id: session_id} = state) do
    Logger.info("[Eclaw.Agent] Session #{session_id} idle timeout — shutting down")
    {:stop, :normal, state}
  end

  # Catch-all for orphaned messages (e.g., late task results after timeout)
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state, idle_timeout(state.session_id)}
  end

  # ── Core: prepare messages + run loop ─────────────────────────────

  defp run_agent_async(prompt, state, mode, from) do
    # Demonitor any stale task ref from a previous (timed-out/cancelled) task
    if state.agent_task_ref, do: Process.demonitor(state.agent_task_ref, [:flush])

    task =
      Task.Supervisor.async_nolink(Eclaw.TaskSupervisor, fn ->
        {result, messages, usage_delta} = run_agent(prompt, state, mode)
        {:agent_done, from, result, messages, usage_delta}
      end)

    # Store from + ref so handle_info can reply on both success and crash
    %{state | agent_task_ref: task.ref, agent_from: from, busy: true}
  end

  defp run_agent(prompt, state, mode) do
    # Accept both plain string prompts and structured content blocks (e.g. vision)
    user_message = %{"role" => "user", "content" => prompt}
    messages = state.messages ++ [user_message]

    # Extract text for memory/routing — use raw string or extract from content blocks
    prompt_text = extract_prompt_text(prompt)

    # Inject memory + skills context into system prompt
    memory_context = Memory.to_context(prompt_text, 5)
    skill_context = Skills.build_context(prompt_text)

    system = state.system <> memory_context <> skill_context

    # Build LLM opts (model override if set)
    llm_opts = if state.model, do: [model: state.model], else: []

    # Multi-model routing: select optimal model at iteration 0
    llm_opts = maybe_route_model(prompt_text, llm_opts)

    # Check context window before calling LLM
    messages = maybe_compact(messages, system, mode, state.model)

    # Wrap the agent loop in a telemetry span — return the inner result
    # so telemetry can correctly detect {:ok, _} vs {:error, _}
    prompt_length = if is_binary(prompt), do: String.length(prompt), else: String.length(prompt_text)

    loop_result =
      Telemetry.span([:eclaw, :agent, :chat], %{prompt_length: prompt_length, session_id: state.session_id, iterations: 0}, fn ->
        agent_loop(messages, system, 0, mode, llm_opts)
      end)

    case loop_result do
      {:ok, final_text, updated_messages, loop_usage} ->
        model = state.model || Config.model()
        cost = Eclaw.LLM.calculate_cost(loop_usage.input_tokens, loop_usage.output_tokens, model)

        usage_delta = %{
          input_tokens: loop_usage.input_tokens,
          output_tokens: loop_usage.output_tokens,
          requests: loop_usage.requests,
          cost: cost
        }

        {{:ok, final_text}, updated_messages, usage_delta}

      {:error, reason} ->
        {{:error, reason}, state.messages, %{input_tokens: 0, output_tokens: 0, requests: 0, cost: 0.0}}
    end
  end

  # ── Context compaction ────────────────────────────────────────────

  defp maybe_compact(messages, system, mode, model) do
    if Context.needs_compaction?(messages, model) do
      notify(mode, {:status, "Compacting conversation history..."})

      case Context.compact(messages, system) do
        {:ok, compacted} -> compacted
        {:error, reason} ->
          Logger.warning("[Eclaw.Agent] Auto-compaction failed: #{inspect(reason)}, keeping original messages")
          messages
      end
    else
      messages
    end
  end

  # ── Model routing ─────────────────────────────────────────────────

  defp maybe_route_model(prompt, llm_opts) do
    if Config.routing_enabled() do
      routed_model = Router.select_model(prompt, llm_opts)
      default_model = Config.model()

      if routed_model != default_model do
        Logger.info("[Eclaw.Agent] Router selected model: #{routed_model} (default: #{default_model})")
      end

      Keyword.put(llm_opts, :model, routed_model)
    else
      llm_opts
    end
  end

  # ── Agent Loop ────────────────────────────────────────────────────

  @empty_usage %{input_tokens: 0, output_tokens: 0, requests: 0}

  defp agent_loop(messages, system, iteration, mode, llm_opts, usage_acc \\ @empty_usage, rate_limit_retries \\ 0) do
    max = Config.max_iterations()

    if iteration >= max do
      {:error, :max_iterations_exceeded}
    else
      Logger.debug("[Eclaw.Agent] Loop iteration #{iteration + 1}")

      # Proactive throttle: if we hit rate limit before, wait before next LLM call
      # to avoid immediately exhausting per-minute token quota again
      if rate_limit_retries > 0 do
        cooldown = min(rate_limit_retries * 5_000, 15_000)
        Logger.debug("[Eclaw.Agent] Rate limit cooldown: #{div(cooldown, 1000)}s")
        Process.sleep(cooldown)
      end

      result =
        Retry.with_retry(fn ->
          case mode do
            :no_stream -> Eclaw.LLM.chat(messages, system, llm_opts)
            {:stream, on_chunk} -> Eclaw.LLM.stream(messages, system, on_chunk, llm_opts)
          end
        end)

      case result do
        {:ok, response} ->
          # Extract and accumulate usage from this LLM call
          call_usage = extract_usage(response)
          new_usage = merge_usage(usage_acc, call_usage)

          handle_response(response, messages, system, iteration, mode, llm_opts, new_usage, rate_limit_retries)

        {:error, :token_rate_limited} ->
          Logger.warning("[Eclaw.Agent] Token rate limited (retry #{rate_limit_retries})")

          if rate_limit_retries >= 3 do
            {:error, :context_too_large}
          else
            # Escalating backoff aligned with per-minute rate limit window
            delay = Enum.at([10_000, 30_000, 60_000], rate_limit_retries, 60_000)

            case Context.force_compact(messages, system) do
              {:ok, compacted} when compacted == messages ->
                # Already minimal — wait for rate limit window to reset
                notify(mode, {:status, "Rate limited. Waiting #{div(delay, 1000)}s..."})
                Process.sleep(delay)
                agent_loop(compacted, system, iteration, mode, llm_opts, usage_acc, rate_limit_retries + 1)

              {:ok, compacted} ->
                notify(mode, {:status, "Rate limited. Compacting and retrying in #{div(delay, 1000)}s..."})
                Process.sleep(delay)
                agent_loop(compacted, system, iteration + 1, mode, llm_opts, usage_acc, rate_limit_retries + 1)
            end
          end

        {:error, reason} ->
          Logger.error("[Eclaw.Agent] LLM error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # ── Response handling ─────────────────────────────────────────────

  defp handle_response(%{"content" => content_blocks, "stop_reason" => stop_reason}, messages, system, iteration, mode, llm_opts, usage_acc, rate_limit_retries) do
    assistant_message = %{"role" => "assistant", "content" => content_blocks}
    messages = messages ++ [assistant_message]

    # Extract model from llm_opts for compaction threshold calculation
    model = Keyword.get(llm_opts, :model)

    case stop_reason do
      "tool_use" ->
        tool_results = execute_tool_calls(content_blocks, mode)
        tool_result_message = %{"role" => "user", "content" => tool_results}
        messages = messages ++ [tool_result_message]

        # Compact if needed after each tool round
        messages = maybe_compact(messages, system, mode, model)

        # Decay rate_limit_retries instead of resetting to 0 — prevents
        # immediately hitting rate limit again on the next iteration
        agent_loop(messages, system, iteration + 1, mode, llm_opts, usage_acc, max(0, rate_limit_retries - 1))

      "end_turn" ->
        {:ok, extract_text(content_blocks), messages, usage_acc}

      other ->
        Logger.warning("[Eclaw.Agent] Unexpected stop_reason: #{other}")
        {:ok, extract_text(content_blocks), messages, usage_acc}
    end
  end

  defp handle_response(unexpected, _messages, _system, _iteration, _mode, _llm_opts, _usage_acc, _rate_limit_retries) do
    Logger.error("[Eclaw.Agent] Unexpected response: #{inspect(unexpected)}")
    {:error, :unexpected_response}
  end

  # ── Tool execution ────────────────────────────────────────────────

  defp execute_tool_calls(content_blocks, mode) do
    tool_calls =
      content_blocks
      |> Enum.filter(fn block -> block["type"] == "tool_use" end)

    case tool_calls do
      # 1 tool → execute directly
      [single] ->
        [execute_single_tool(single, mode)]

      # Multiple tools → execute in parallel (capped at 10), notify sequentially
      multiple ->
        # Cap concurrency to avoid resource exhaustion
        capped = Enum.take(multiple, 10)
        if length(multiple) > 10, do: Logger.warning("[Eclaw.Agent] Capping parallel tools from #{length(multiple)} to 10")
        Logger.info("[Eclaw.Agent] Parallel execution: #{length(capped)} tools")

        # Execute tools in parallel (notifications suppressed — use :no_stream)
        results =
          capped
          |> Enum.map(fn tool ->
            {tool["id"], tool["name"], Task.Supervisor.async_nolink(Eclaw.TaskSupervisor, fn ->
              execute_single_tool(tool, :no_stream)
            end)}
          end)
          |> Enum.map(fn {tool_id, _tool_name, task} ->
            case Task.yield(task, 60_000) || Task.shutdown(task) do
              {:ok, result} -> result
              _ -> %{"type" => "tool_result", "tool_use_id" => tool_id, "content" => "Error: Tool execution timed out or crashed"}
            end
          end)

        # Notify sequentially from the agent process
        Enum.each(results, fn %{"tool_use_id" => id, "content" => content} ->
          tool_name = Enum.find_value(multiple, fn t -> if t["id"] == id, do: t["name"] end) || "unknown"
          notify(mode, {:tool_result, tool_name, content})
        end)

        results
    end
  end

  defp execute_single_tool(%{"id" => id, "name" => name} = block, mode) do
    input = Map.get(block, "input", %{})
    notify(mode, {:tool_call, name, input})
    Logger.info("[Eclaw.Agent] Tool: #{name} #{inspect(input, limit: 300)}")

    # Check if this domain was already blocked (bot protection, etc.)
    result =
      case check_domain_skip(name, input) do
        {:skip, reason} ->
          Logger.info("[Eclaw.Agent] Skipping blocked domain: #{reason}")
          reason

        :ok ->
          # Build execution context with channel-aware approval callback
          tool_context = build_tool_context(mode)

          tool_result =
            try do
              Telemetry.span([:eclaw, :tool, :execute], %{tool: name}, fn ->
                Eclaw.Tools.execute(name, input, tool_context)
              end)
            rescue
              e ->
                Logger.error("[Eclaw.Agent] Tool #{name} crashed: #{Exception.message(e)}")
                "Error: Tool crashed — #{Exception.message(e)}"
            end

          # Track domains that return bot protection errors
          maybe_block_domain(name, input, tool_result)
          tool_result
      end

    Logger.info("[Eclaw.Agent] Result: #{String.slice(result, 0, 200)}")
    notify(mode, {:tool_result, name, result})

    %{
      "type" => "tool_result",
      "tool_use_id" => id,
      "content" => result
    }
  end

  # Check if a domain has been blocked during this session (bot protection, etc.)
  defp check_domain_skip(name, input) when name in ["browser_navigate", "web_fetch"] do
    url = input["url"]

    if url do
      domain = URI.parse(url).host
      blocked = Process.get(:blocked_domains, MapSet.new())

      if domain && MapSet.member?(blocked, domain) do
        {:skip, "[SKIP] #{domain} was already blocked by bot protection in this session. Try a different website."}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp check_domain_skip(_, _), do: :ok

  # Track domains that return bot protection or JS-rendered errors
  defp maybe_block_domain(name, input, result) when name in ["browser_navigate", "web_fetch"] and is_binary(result) do
    if String.starts_with?(result, "[BOT-PROTECTED]") or String.starts_with?(result, "[JS-RENDERED PAGE]") do
      url = input["url"]

      if url do
        domain = URI.parse(url).host
        blocked = Process.get(:blocked_domains, MapSet.new())
        Process.put(:blocked_domains, MapSet.put(blocked, domain))
        Logger.info("[Eclaw.Agent] Blocked domain: #{domain}")
      end
    end
  end

  defp maybe_block_domain(_, _, _), do: :ok

  defp build_tool_context(:no_stream), do: %{channel: :cli}
  defp build_tool_context({:stream, _on_chunk}), do: %{channel: :cli}

  # ── Helpers ───────────────────────────────────────────────────────

  # Extract plain text from prompt — handles both string and content block list
  defp extract_prompt_text(prompt) when is_binary(prompt), do: prompt

  defp extract_prompt_text(prompt) when is_list(prompt) do
    prompt
    |> Enum.filter(fn block -> is_map(block) and block["type"] == "text" end)
    |> Enum.map_join(" ", fn block -> block["text"] end)
  end

  defp extract_prompt_text(_), do: ""

  defp extract_text(content_blocks), do: Context.extract_text(content_blocks)

  defp notify({:stream, on_chunk}, event) do
    on_chunk.(event)
    Events.broadcast(event)
  end

  defp notify(:no_stream, event), do: Events.broadcast(event)

  # ── Usage tracking ────────────────────────────────────────────────

  defp extract_usage(%{"usage" => %{"input_tokens" => input, "output_tokens" => output}}) do
    %{input_tokens: input, output_tokens: output, requests: 1}
  end

  defp extract_usage(_), do: @empty_usage

  defp merge_usage(acc, new) do
    %{
      input_tokens: acc.input_tokens + new.input_tokens,
      output_tokens: acc.output_tokens + new.output_tokens,
      requests: acc.requests + new.requests
    }
  end

  # Clean up in-flight task on shutdown
  @impl true
  def terminate(_reason, state) do
    if state.agent_task_ref do
      Process.demonitor(state.agent_task_ref, [:flush])
    end

    :ok
  end

  # Session agents have idle timeout, singleton does not
  defp idle_timeout(nil), do: :infinity
  defp idle_timeout(_session_id), do: @idle_timeout
end
