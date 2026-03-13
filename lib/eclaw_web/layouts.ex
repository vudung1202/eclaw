defmodule EclawWeb.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Eclaw Dashboard</title>
        <script src="https://cdn.tailwindcss.com">
        </script>
        <script defer phx-track-static src={"https://cdn.jsdelivr.net/npm/phoenix@1.7.14/priv/static/phoenix.min.js"}>
        </script>
        <script defer phx-track-static src={"https://cdn.jsdelivr.net/npm/phoenix_live_view@1.0.0/priv/static/phoenix_live_view.min.js"}>
        </script>
        <style>
          .animate-pulse-fast { animation: pulse 1s cubic-bezier(0.4, 0, 0.6, 1) infinite; }
        </style>
      </head>
      <body class="bg-gray-950 text-gray-100 min-h-screen">
        {@inner_content}
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <main class="max-w-7xl mx-auto px-4 py-6">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    """
  end

  def flash_group(assigns) do
    ~H"""
    <div :if={Phoenix.Flash.get(@flash, :info)} class="bg-blue-900/50 border border-blue-700 rounded p-3 mb-4 text-blue-200">
      {Phoenix.Flash.get(@flash, :info)}
    </div>
    <div :if={Phoenix.Flash.get(@flash, :error)} class="bg-red-900/50 border border-red-700 rounded p-3 mb-4 text-red-200">
      {Phoenix.Flash.get(@flash, :error)}
    </div>
    """
  end
end
