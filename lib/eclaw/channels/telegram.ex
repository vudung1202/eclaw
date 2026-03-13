defmodule Eclaw.Channels.Telegram do
  @moduledoc """
  Telegram Bot adapter for Eclaw.

  Uses long polling (getUpdates) to receive messages.
  Polling runs in a separate Task — GenServer stays responsive for send operations.

  ## Configuration

      export TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."

  ## Registration

      Eclaw.ChannelManager.register(Eclaw.Channels.Telegram, token: token)
  """

  @behaviour Eclaw.Channel
  use GenServer
  require Logger

  @base_url "https://api.telegram.org/bot"
  @max_message_length 4096

  # ── Channel Behaviour ─────────────────────────────────────────────

  @impl Eclaw.Channel
  def name, do: :telegram

  @impl Eclaw.Channel
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Eclaw.Channel
  def send_message(chat_id, text, _opts) do
    GenServer.cast(__MODULE__, {:send, chat_id, text})
  end

  @impl Eclaw.Channel
  def handle_incoming(%{"message" => message}) do
    chat_id = get_in(message, ["chat", "id"])
    text = message["text"] || ""
    from = get_in(message, ["from", "id"])

    {:ok, %{from: "#{from || chat_id}", text: text}}
  end

  def handle_incoming(_), do: {:error, :no_message}

  @doc "Send typing indicator."
  @impl Eclaw.Channel
  def send_typing(chat_id) do
    GenServer.cast(__MODULE__, {:typing, chat_id})
  end

  # ── GenServer ──────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    token = Keyword.get(opts, :token) || Application.get_env(:eclaw, :telegram_token) || System.get_env("TELEGRAM_BOT_TOKEN")

    if is_nil(token) or token == "" do
      Logger.error("[Telegram] Missing TELEGRAM_BOT_TOKEN")
      {:stop, :missing_token}
    else
      # Ensure token is available via Application config for functions called outside GenServer
      Application.put_env(:eclaw, :telegram_token, token)
      Logger.info("[Telegram] Bot starting...")

      state = %{
        token: token,
        offset: 0,
        base_url: "#{@base_url}#{token}",
        poll_ref: nil
      }

      # Verify token + log bot info
      case get_me(state) do
        {:ok, bot_info} ->
          Logger.info("[Telegram] Bot @#{bot_info["username"]} (#{bot_info["first_name"]}) ready")
          {:ok, start_poll(state)}

        {:error, reason} ->
          Logger.error("[Telegram] Invalid token: #{inspect(reason)}")
          {:stop, :invalid_token}
      end
    end
  end

  # ── Send (always processed immediately, not blocked by poll) ─────────────

  @impl true
  def handle_cast({:send, chat_id, text}, state) do
    send_text(state, chat_id, text)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:typing, chat_id}, state) do
    # Fire-and-forget in separate Task to avoid blocking GenServer
    Task.start(fn ->
      api_request(state, "sendChatAction", %{chat_id: chat_id, action: "typing"})
    end)
    {:noreply, state}
  end

  # ── Poll results (sent back from Task) ──────────────────────────────────

  @impl true
  def handle_info({ref, {:poll_result, result}}, %{poll_ref: ref} = state) do
    # Task completed — process results
    Process.demonitor(ref, [:flush])

    new_state =
      case result do
        {:ok, updates, new_offset} ->
          Enum.each(updates, &process_update/1)
          %{state | offset: new_offset}

        :no_updates ->
          state

        {:error, reason} ->
          Logger.warning("[Telegram] Poll error: #{inspect(reason)}")
          state
      end

    # Start next poll immediately
    {:noreply, start_poll(new_state)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{poll_ref: ref} = state) do
    # Poll task crashed — restart poll
    Logger.warning("[Telegram] Poll task crashed, restarting...")
    {:noreply, start_poll(%{state | poll_ref: nil})}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Polling in separate Task ─────────────────────────────────────

  defp start_poll(state) do
    base_url = state.base_url
    offset = state.offset

    task =
      Task.Supervisor.async_nolink(Eclaw.TaskSupervisor, fn ->
        params = %{offset: offset, timeout: 15, allowed_updates: ["message"]}
        url = "#{base_url}/getUpdates"
        body = Jason.encode!(params)

        case Req.post(url, body: body, headers: [{"content-type", "application/json"}], receive_timeout: 20_000) do
          {:ok, %{status: 200, body: %{"ok" => true, "result" => updates}}} when updates != [] ->
            last_id = updates |> List.last() |> Map.get("update_id")
            {:poll_result, {:ok, updates, last_id + 1}}

          {:ok, %{status: 200, body: body}} when is_binary(body) ->
            case Jason.decode(body) do
              {:ok, %{"ok" => true, "result" => updates}} when updates != [] ->
                last_id = updates |> List.last() |> Map.get("update_id")
                {:poll_result, {:ok, updates, last_id + 1}}

              _ ->
                {:poll_result, :no_updates}
            end

          {:ok, %{status: 200}} ->
            {:poll_result, :no_updates}

          {:ok, %{status: status, body: err}} ->
            {:poll_result, {:error, {:api, status, err}}}

          {:error, reason} ->
            {:poll_result, {:error, reason}}
        end
      end)

    %{state | poll_ref: task.ref}
  end

  # ── Update processing ──────────────────────────────────────────

  defp process_update(update) do
    with {:ok, %{from: from_id, text: text}} <- handle_incoming(update),
         true <- authorized_user?(from_id) || {:unauthorized, from_id} do
      text = String.trim(text)

      if text != "" do
        case text do
          "/start" ->
            send_text_direct(from_id, "Hello! I'm Eclaw, your AI assistant. Ask me anything!")

          "/reset" ->
            session_id = "telegram:#{from_id}"
            Eclaw.SessionManager.stop(session_id)
            send_text_direct(from_id, "Conversation reset. Starting fresh!")

          "/help" ->
            help_text = """
            🦀 *Eclaw Bot Commands*

            /start — Start a conversation
            /reset — Reset conversation
            /help — Show available commands

            Send any message to chat with the AI agent.
            The agent can execute bash commands, read/write files, and search files.
            """

            send_text_direct(from_id, help_text)

          _ ->
            Eclaw.ChannelManager.handle_message(:telegram, from_id, text)
        end
      end
    else
      {:unauthorized, from_id} ->
        Logger.warning("[Telegram] Unauthorized user: #{from_id}")
        send_text_direct(from_id, "Access denied. Your user ID is not authorized.")

      {:error, _} ->
        :ok
    end
  end

  defp authorized_user?(user_id) do
    case Application.get_env(:eclaw, :telegram_allowed_users) do
      nil ->
        Logger.warning("[Telegram] No TELEGRAM_ALLOWED_USERS configured — rejecting user #{user_id}. " <>
          "Set TELEGRAM_ALLOWED_USERS=id1,id2 to allow specific users.")
        false

      [] ->
        Logger.warning("[Telegram] TELEGRAM_ALLOWED_USERS is empty — rejecting user #{user_id}")
        false

      allowed when is_list(allowed) ->
        to_string(user_id) in allowed
    end
  end

  # ── API helpers ──────────────────────────────────────────────────

  defp get_me(state) do
    case api_request(state, "getMe", %{}) do
      {:ok, %{"ok" => true, "result" => info}} -> {:ok, info}
      {:ok, %{"ok" => false, "description" => desc}} -> {:error, desc}
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_text(state, chat_id, text) do
    text
    |> split_message()
    |> Enum.each(fn chunk ->
      api_request(state, "sendMessage", %{
        chat_id: chat_id,
        text: chunk,
        parse_mode: "Markdown"
      })
      |> case do
        {:ok, _} -> :ok
        {:error, %{"description" => desc}} when is_binary(desc) ->
          if String.contains?(desc, "parse") do
            api_request(state, "sendMessage", %{chat_id: chat_id, text: chunk})
          end
        {:error, reason} ->
          Logger.warning("[Telegram] Send failed: #{inspect(reason)}")
      end
    end)
  end

  defp send_text_direct(chat_id, text) do
    token = Application.get_env(:eclaw, :telegram_token, "")
    url = "#{@base_url}#{token}/sendMessage"
    body = Jason.encode!(%{chat_id: chat_id, text: text, parse_mode: "Markdown"})
    Req.post(url, body: body, headers: [{"content-type", "application/json"}])
  end

  defp api_request(state, method, params) do
    url = "#{state.base_url}/#{method}"
    body = Jason.encode!(params)

    case Req.post(url, body: body, headers: [{"content-type", "application/json"}], receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Telegram] API #{method} returned #{status}")
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("[Telegram] API #{method} exception: #{inspect(e)}")
      {:error, e}
  end

  defp split_message(text) do
    if String.length(text) <= @max_message_length do
      [text]
    else
      do_split_message(text, [])
    end
  end

  defp do_split_message("", acc), do: Enum.reverse(acc)

  defp do_split_message(text, acc) do
    chunk = String.slice(text, 0, @max_message_length)
    rest = String.slice(text, @max_message_length..-1//1)
    do_split_message(rest, [chunk | acc])
  end
end
