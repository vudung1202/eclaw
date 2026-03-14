defmodule Eclaw.ChannelManager do
  @moduledoc """
  Manages channel adapters.

  - Register adapters (Telegram, Discord, Slack)
  - Route incoming messages → per-user Agent session
  - Route Agent responses → correct channel
  - Async processing — does not block GenServer

  Runs under DynamicSupervisor — each adapter is a child process.
  """

  use GenServer
  require Logger

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register and start a channel adapter."
  @spec register(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def register(adapter_module, opts \\ []) do
    GenServer.call(__MODULE__, {:register, adapter_module, opts})
  end

  @doc "Unregister an adapter."
  @spec unregister(atom()) :: :ok
  def unregister(channel_name) do
    GenServer.call(__MODULE__, {:unregister, channel_name})
  end

  @doc "List active channels."
  @spec list() :: [%{name: atom(), pid: pid(), module: module()}]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Handle incoming message from a channel adapter (async).

  Called by the adapter when a new message is received.
  ChannelManager creates/finds a session for the user, sends to Agent, then replies via the channel.
  Attachments (optional) are converted to Anthropic vision content blocks.
  """
  @spec handle_message(atom(), String.t(), String.t(), list()) :: :ok
  def handle_message(channel_name, from_id, text, attachments \\ []) do
    GenServer.cast(__MODULE__, {:message, channel_name, from_id, text, attachments})
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{channels: %{}}}
  end

  @impl true
  def handle_call({:register, module, opts}, _from, state) do
    name = module.name()
    Logger.info("[ChannelManager] Registering channel: #{name}")

    case DynamicSupervisor.start_child(Eclaw.ChannelSupervisor, {module, opts}) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        channels = Map.put(state.channels, name, %{pid: pid, module: module, monitor_ref: ref})
        {:reply, {:ok, pid}, %{state | channels: channels}}

      {:error, reason} ->
        Logger.error("[ChannelManager] Failed to start #{name}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister, name}, _from, state) do
    case Map.pop(state.channels, name) do
      {nil, _} ->
        {:reply, :ok, state}

      {%{pid: pid, monitor_ref: ref}, channels} ->
        Process.demonitor(ref, [:flush])
        DynamicSupervisor.terminate_child(Eclaw.ChannelSupervisor, pid)
        Logger.info("[ChannelManager] Unregistered channel: #{name}")
        {:reply, :ok, %{state | channels: channels}}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    list =
      Enum.map(state.channels, fn {name, %{pid: pid, module: mod}} ->
        %{name: name, pid: pid, module: mod}
      end)

    {:reply, list, state}
  end

  # Clean up stale channel PIDs when adapter crashes
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case Enum.find(state.channels, fn {_name, %{pid: p}} -> p == pid end) do
      {name, _} ->
        Logger.warning("[ChannelManager] Channel adapter #{name} exited: #{inspect(reason)}")
        {:noreply, %{state | channels: Map.delete(state.channels, name)}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:message, channel_name, from_id, text, attachments}, state) do
    Logger.info("[ChannelManager] Message from #{channel_name}/#{from_id}: #{String.slice(text, 0, 200)}" <>
      if(attachments != [], do: " [#{length(attachments)} attachment(s)]", else: ""))

    # Session ID = "channel:user_id"
    session_id = "#{channel_name}:#{from_id}"
    channel_info = Map.get(state.channels, channel_name)

    # Process async via Task.Supervisor — does not block ChannelManager
    Task.Supervisor.start_child(Eclaw.TaskSupervisor, fn ->
      process_message(session_id, text, attachments, channel_name, from_id, channel_info)
    end)

    {:noreply, state}
  end

  # Backward compat: handle_cast with 4-element tuple (no attachments)
  @impl true
  def handle_cast({:message, channel_name, from_id, text}, state) do
    handle_cast({:message, channel_name, from_id, text, []}, state)
  end

  # ── Private ──────────────────────────────────────────────────────

  defp process_message(session_id, text, attachments, _channel_name, from_id, channel_info) do
    case Eclaw.SessionManager.get_or_create(session_id) do
      {:ok, agent_pid} ->
        # Notify channel adapter before processing (typing indicator)
        if channel_info, do: notify_typing(channel_info.module, from_id)

        # Build prompt: plain string or structured content blocks with vision
        prompt = build_prompt(text, attachments)

        case chat_with_retry(agent_pid, prompt, session_id) do
          {:ok, response} ->
            if channel_info do
              channel_info.module.send_message(from_id, response, [])
            end

          {:error, reason} ->
            Logger.error("[ChannelManager] Agent error for #{session_id}: #{inspect(reason)}")

            if channel_info do
              channel_info.module.send_message(from_id, "Sorry, an error occurred. Please try again.", [])
            end
        end

      {:error, reason} ->
        Logger.error("[ChannelManager] Cannot create session #{session_id}: #{inspect(reason)}")
    end
  end

  # Build prompt content — plain text, vision content blocks, or voice transcription
  defp build_prompt(text, []) do
    text
  end

  defp build_prompt(text, attachments) do
    # Separate voice and image attachments
    {voice_attachments, other_attachments} = Enum.split_with(attachments, fn att -> att.type == :voice end)

    # Transcribe voice messages and prepend to text
    text = transcribe_voice_attachments(text, voice_attachments)

    # Convert image attachments to Anthropic vision content blocks
    image_blocks =
      other_attachments
      |> Enum.filter(fn att -> att.type == :image end)
      |> Enum.map(fn %{data: base64, mime: mime} ->
        %{
          "type" => "image",
          "source" => %{
            "type" => "base64",
            "media_type" => mime,
            "data" => base64
          }
        }
      end)

    if image_blocks == [] do
      # Voice-only message — return plain text
      text
    else
      caption = if text == "", do: "What's in this image?", else: text
      text_block = %{"type" => "text", "text" => caption}

      Logger.debug("[ChannelManager] Built vision prompt with #{length(image_blocks)} image(s), caption: #{String.slice(caption, 0, 100)}")

      image_blocks ++ [text_block]
    end
  end

  # Transcribe voice attachments via Whisper and prepend to text
  defp transcribe_voice_attachments(text, []), do: text

  defp transcribe_voice_attachments(text, voice_attachments) do
    transcriptions =
      Enum.map(voice_attachments, fn %{data: data} ->
        Logger.info("[ChannelManager] Transcribing voice message (#{byte_size(data)} bytes)...")

        case Eclaw.Speech.transcribe(data) do
          {:ok, transcription} ->
            Logger.info("[ChannelManager] Voice transcribed: #{String.slice(transcription, 0, 100)}")
            "[Voice message] #{transcription}"

          {:error, reason} ->
            Logger.warning("[ChannelManager] Voice transcription failed: #{inspect(reason)}")
            "[Voice message - transcription failed]"
        end
      end)

    # Combine transcriptions with any existing text (caption)
    parts = transcriptions ++ if(text != "", do: [text], else: [])
    Enum.join(parts, "\n")
  end

  # Retry chat if agent is busy — wait and retry up to 30s
  defp chat_with_retry(agent_pid, prompt, session_id, attempts \\ 0) do
    case Eclaw.Agent.chat(agent_pid, prompt) do
      {:error, :busy} when attempts < 10 ->
        Logger.debug("[ChannelManager] Agent busy for #{session_id}, waiting 3s (attempt #{attempts + 1})")
        Process.sleep(3_000)
        chat_with_retry(agent_pid, prompt, session_id, attempts + 1)

      result ->
        result
    end
  end

  defp notify_typing(module, from_id) do
    if function_exported?(module, :send_typing, 1) do
      module.send_typing(from_id)
    end
  rescue
    e ->
      Logger.debug("[ChannelManager] Typing notification failed: #{inspect(e)}")
      :ok
  end
end
