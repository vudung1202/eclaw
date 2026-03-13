defmodule Eclaw.Channel do
  @moduledoc """
  Behaviour for messaging channel adapters.

  Allows Eclaw to receive and reply to messages from multiple platforms
  (Telegram, Discord, Slack, etc.)

  ## Implementing a new adapter

      defmodule Eclaw.Channels.Telegram do
        @behaviour Eclaw.Channel

        @impl true
        def name, do: :telegram

        @impl true
        def start_link(opts) do
          # Start polling/webhook GenServer
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end

        @impl true
        def send_message(channel_id, text, _opts) do
          # Call Telegram Bot API
          {:ok, message_id}
        end

        @impl true
        def handle_incoming(message) do
          # Parse Telegram message → Eclaw format
          {:ok, %{from: message.chat.id, text: message.text}}
        end
      end

  ## Registering an adapter

      Eclaw.ChannelManager.register(Eclaw.Channels.Telegram, token: "bot123:...")
  """

  @doc "Channel name (e.g. :telegram, :discord, :slack)."
  @callback name() :: atom()

  @doc "Start channel adapter (GenServer or Supervisor)."
  @callback start_link(opts :: keyword()) :: GenServer.on_start()

  @doc "Send a message to the channel."
  @callback send_message(channel_id :: String.t(), text :: String.t(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @doc "Parse incoming message from platform-specific format."
  @callback handle_incoming(raw_message :: term()) ::
              {:ok, %{from: String.t(), text: String.t()}} | {:error, term()}

  @doc "Send typing indicator (optional)."
  @callback send_typing(channel_id :: String.t()) :: :ok
  @optional_callbacks [send_typing: 1]
end
