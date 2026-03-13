defmodule EclawWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EclawWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug EclawWeb.Plugs.EclawSession
    plug EclawWeb.Plugs.WebAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug EclawWeb.Plugs.ApiAuth
  end

  scope "/", EclawWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/chat", ChatLive, :index
  end

  scope "/api", EclawWeb do
    pipe_through :api

    post "/webhook", WebhookController, :create
    get "/status", StatusController, :index
  end
end
