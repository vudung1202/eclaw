defmodule EclawWeb.Plugs.WebAuth do
  @moduledoc """
  HTTP Basic Auth for web dashboard and chat routes.

  Set ECLAW_WEB_PASSWORD env var to enable. When unset, web UI is open (dev/localhost only).
  """

  import Plug.Conn
  require Logger

  @realm "Eclaw Dashboard"

  def init(opts), do: opts

  def call(conn, _opts) do
    password = Application.get_env(:eclaw, :web_password)

    if is_nil(password) or password == "" do
      conn
    else
      case get_req_header(conn, "authorization") do
        ["Basic " <> encoded] ->
          case Base.decode64(encoded) do
            {:ok, credentials} ->
              case String.split(credentials, ":", parts: 2) do
                [user, provided] ->
                  if Plug.Crypto.secure_compare(provided, password) do
                    Logger.debug("[WebAuth] Authenticated user: #{sanitize_for_log(user)}")
                    conn
                  else
                    Logger.warning("[WebAuth] Failed auth attempt for user: #{sanitize_for_log(user)}")
                    unauthorized(conn)
                  end

                _ ->
                  unauthorized(conn)
              end

            :error ->
              unauthorized(conn)
          end

        _ ->
          unauthorized(conn)
      end
    end
  end

  defp sanitize_for_log(text) do
    text
    |> String.replace(~r/[\r\n\x1b]/, "")
    |> String.slice(0, 100)
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=\"#{@realm}\"")
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
