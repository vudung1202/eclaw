defmodule EclawWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :eclaw

  @session_options [
    store: :cookie,
    key: "_eclaw_key",
    signing_salt: "eclaw_dev_salt_change_me",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :eclaw,
    gzip: false,
    only: ~w(assets favicon.ico robots.txt)

  plug Plug.RequestId
  plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], json_decoder: Jason
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug EclawWeb.Router

  def init(_key, config) do
    # Override session signing salt at runtime if configured
    salt = Application.get_env(:eclaw, :session_signing_salt, "eclaw_dev_salt_change_me")

    if salt == "eclaw_dev_salt_change_me" and config[:env] == :prod do
      raise "ECLAW_SESSION_SALT must be set in production! Generate with: mix phx.gen.secret 32"
    end

    session_opts = Keyword.put(@session_options, :signing_salt, salt)
    config = Keyword.put(config, :session_options, session_opts)

    # Also update LiveView signing salt (safe access — config[:live_view] may be nil)
    endpoint_conf = Application.get_env(:eclaw, EclawWeb.Endpoint, [])
    live_signing_salt = get_in(endpoint_conf, [:live_view, :signing_salt]) || salt

    config =
      update_in(config, [:live_view], fn
        nil -> [signing_salt: live_signing_salt]
        lv -> Keyword.put(lv, :signing_salt, live_signing_salt)
      end)

    {:ok, config}
  end
end
