defmodule Eclaw.ToolBehaviour do
  @moduledoc """
  Behaviour for Eclaw tools — allows registering new tools as plugins.

  ## Creating a new tool

      defmodule MyApp.Tools.WeatherTool do
        @behaviour Eclaw.ToolBehaviour

        @impl true
        def name, do: "get_weather"

        @impl true
        def description, do: "Get current weather for a city"

        @impl true
        def input_schema do
          %{
            "type" => "object",
            "properties" => %{
              "city" => %{"type" => "string", "description" => "City name"}
            },
            "required" => ["city"]
          }
        end

        @impl true
        def execute(%{"city" => city}) do
          {:ok, "Weather in \#{city}: 25°C, sunny"}
        end
      end

  ## Registering a tool

      Eclaw.ToolRegistry.register(MyApp.Tools.WeatherTool)
  """

  @doc "Unique tool name (sent to LLM)."
  @callback name() :: String.t()

  @doc "Tool description (used by LLM to decide when to call)."
  @callback description() :: String.t()

  @doc "JSON Schema for input parameters."
  @callback input_schema() :: map()

  @doc """
  Execute tool with parsed input.

  Returns `{:ok, result_string}` or `{:error, reason_string}`.
  """
  @callback execute(input :: map()) :: {:ok, String.t()} | {:error, String.t()}
end
