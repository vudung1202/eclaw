defmodule Mix.Tasks.Eclaw do
  @shortdoc "Start the Eclaw AI Agent REPL"
  @moduledoc "Start the Eclaw interactive CLI. Usage: `mix eclaw`"

  use Mix.Task

  @impl true
  def run(_args) do
    # Ensure application (and supervision tree) is started
    Mix.Task.run("app.start")
    Eclaw.CLI.main()
  end
end
