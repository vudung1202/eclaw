defmodule EclawWeb.Plugs.ApiAuth do
  @moduledoc """
  Bearer token authentication for API endpoints.

  Set ECLAW_API_TOKEN env var to enable. When unset, API is blocked by default.
  Set ECLAW_API_OPEN=true to explicitly allow unauthenticated access (dev only).
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    token = Application.get_env(:eclaw, :api_token)
    api_open = Application.get_env(:eclaw, :api_open, false)

    cond do
      # Token configured — require it
      is_binary(token) and token != "" ->
        verify_bearer(conn, token)

      # Explicitly opened (dev mode)
      api_open == true ->
        conn

      # No token, not explicitly open — deny
      true ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "API authentication not configured. Set ECLAW_API_TOKEN env var."})
        |> halt()
    end
  end

  defp verify_bearer(conn, token) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> provided] ->
        if Plug.Crypto.secure_compare(provided, token) do
          conn
        else
          reject(conn)
        end

      _ ->
        reject(conn)
    end
  end

  defp reject(conn) do
    conn
    |> put_status(401)
    |> Phoenix.Controller.json(%{error: "Unauthorized"})
    |> halt()
  end
end
