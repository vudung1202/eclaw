defmodule EclawWeb.WebhookController do
  use Phoenix.Controller, formats: [:json]

  require Logger

  @max_from_length 64
  @max_text_length 10_000

  def create(conn, %{"from" => from, "text" => text}) when is_binary(from) and is_binary(text) do
    from = String.slice(from, 0, @max_from_length)
    text = String.slice(text, 0, @max_text_length)

    if Regex.match?(~r/^[a-zA-Z0-9_\-.@]+$/, from) do
      agent = get_or_start_agent("webhook:#{from}")

      case Eclaw.Agent.chat(agent, text) do
        {:ok, response} ->
          json(conn, %{status: "ok", response: response})

        {:error, reason} ->
          Logger.error("[Webhook] Agent error for #{from}: #{inspect(reason)}")

          conn
          |> put_status(500)
          |> json(%{error: "Internal server error"})
      end
    else
      conn
      |> put_status(400)
      |> json(%{error: "Invalid 'from' field — must be alphanumeric"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing 'from' and 'text' fields"})
  end

  defp get_or_start_agent(session_id) do
    Eclaw.SessionManager.get_or_start!(session_id)
  end
end
