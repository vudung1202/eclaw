defmodule Eclaw.Channels.Webhook do
  @moduledoc """
  Webhook channel adapter — receives messages via HTTP POST.

  Endpoint: POST /api/webhook
  Body: {"from": "user-id", "text": "message"}
  Response: {"reply": "agent response"}

  This is the simplest adapter, serving as a reference implementation
  and for integration testing.
  """

  @behaviour Eclaw.Channel
  use GenServer

  @impl Eclaw.Channel
  def name, do: :webhook

  @impl Eclaw.Channel
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Eclaw.Channel
  def send_message(_channel_id, text, _opts) do
    # Webhook is request-response, no need to send separately
    {:ok, text}
  end

  @impl Eclaw.Channel
  def handle_incoming(%{"from" => from, "text" => text}) do
    {:ok, %{from: from, text: text}}
  end

  def handle_incoming(_), do: {:error, :invalid_message}

  # GenServer (placeholder — stateless for webhook)
  @impl GenServer
  def init(_opts), do: {:ok, %{}}
end
