defmodule EclawWeb.Plugs.EclawSession do
  @moduledoc """
  Assigns a persistent, opaque session ID for agent sessions.

  Generates a random ID on first visit and stores it in the Phoenix session.
  This avoids using the CSRF token (which is visible in page source) as a session identifier.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :eclaw_session_id) do
      nil ->
        id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
        put_session(conn, :eclaw_session_id, id)

      _existing ->
        conn
    end
  end
end
