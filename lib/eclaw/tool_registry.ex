defmodule Eclaw.ToolRegistry do
  @moduledoc """
  Registry for managing tool plugins.

  Keeps a list of registered tool modules. Agent and LLM query
  this registry to get tool definitions and dispatch execution.

  Built-in tools (execute_bash, read_file, etc.) remain in `Eclaw.Tools`.
  Plugin tools registered via registry are merged into the tools list
  sent to the LLM.
  """

  use GenServer
  require Logger

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register a tool module implementing Eclaw.ToolBehaviour."
  @spec register(module()) :: :ok | {:error, term()}
  def register(tool_module) do
    GenServer.call(__MODULE__, {:register, tool_module})
  end

  @doc "Register a raw tool definition map (for MCP tools, etc.)."
  @spec register_tool_definition(map(), function() | nil) :: :ok
  def register_tool_definition(tool_def, executor \\ nil) do
    GenServer.call(__MODULE__, {:register_definition, tool_def, executor})
  end

  @doc "Unregister a tool by name."
  @spec unregister(String.t()) :: :ok
  def unregister(tool_name) do
    GenServer.call(__MODULE__, {:unregister, tool_name})
  end

  @doc "Get tool definitions (Anthropic API format) from all plugins."
  @spec tool_definitions() :: [map()]
  def tool_definitions do
    GenServer.call(__MODULE__, :tool_definitions)
  end

  @doc "Execute a plugin tool by name. Returns nil if not found."
  @spec execute(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()} | nil
  def execute(tool_name, input) do
    # Lookup tool info in GenServer, execute in caller's process to avoid blocking registry
    case GenServer.call(__MODULE__, {:lookup, tool_name}) do
      nil -> nil
      tool_info -> do_execute(tool_name, input, tool_info)
    end
  end

  defp do_execute(_tool_name, input, %{type: :module, module: module}) do
    try do
      module.execute(input)
    rescue
      e -> {:error, "Plugin error: #{Exception.message(e)}"}
    end
  end

  defp do_execute(tool_name, input, %{type: :multi, module: module}) do
    try do
      module.execute(tool_name, input)
    rescue
      e -> {:error, "Plugin error: #{Exception.message(e)}"}
    end
  end

  defp do_execute(tool_name, input, %{type: :definition, executor: executor}) when is_function(executor) do
    try do
      executor.(tool_name, input)
    rescue
      e -> {:error, "Plugin error: #{Exception.message(e)}"}
    end
  end

  defp do_execute(tool_name, input, %{type: :definition}) do
    # MCP tools — route to MCP module
    execute_mcp_tool(tool_name, input)
  end

  @doc "List all registered tool names."
  @spec list() :: [String.t()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    # tools: %{name => %{type: :module | :multi | :definition, ...}}
    # Auto-register built-in plugins after init
    send(self(), :auto_register_plugins)
    {:ok, %{tools: %{}}}
  end

  @impl true
  def handle_info(:auto_register_plugins, state) do
    # Register Browser plugin
    new_state =
      if Code.ensure_loaded?(Eclaw.Browser) do
        case do_register(Eclaw.Browser, state) do
          {:ok, updated} -> updated
          :error -> state
        end
      else
        state
      end

    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:register, module}, _from, state) do
    case do_register(module, state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      :error -> {:reply, {:error, :invalid_tool_module}, state}
    end
  end

  @impl true
  def handle_call({:register_definition, tool_def, executor}, _from, state) do
    name = tool_def["name"]
    Logger.info("[Eclaw.ToolRegistry] Registered definition: #{name}")
    {:reply, :ok, put_in(state, [:tools, name], %{type: :definition, definition: tool_def, executor: executor})}
  end

  @impl true
  def handle_call({:unregister, tool_name}, _from, state) do
    Logger.info("[Eclaw.ToolRegistry] Unregistered: #{tool_name}")
    {:reply, :ok, %{state | tools: Map.delete(state.tools, tool_name)}}
  end

  @impl true
  def handle_call(:tool_definitions, _from, state) do
    definitions =
      state.tools
      |> Enum.map(fn {_name, info} ->
        case info do
          %{type: :module, module: module} ->
            %{
              "name" => module.name(),
              "description" => module.description(),
              "input_schema" => module.input_schema()
            }

          %{type: :multi, definition: definition} ->
            definition

          %{type: :definition, definition: definition} ->
            definition
        end
      end)

    {:reply, definitions, state}
  end

  @impl true
  def handle_call({:lookup, tool_name}, _from, state) do
    {:reply, Map.get(state.tools, tool_name), state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.keys(state.tools), state}
  end

  # ── Private ────────────────────────────────────────────────────────

  # Shared registration logic used by both handle_call and auto-register
  defp do_register(module, state) do
    cond do
      function_exported?(module, :tools, 0) and function_exported?(module, :execute, 2) ->
        tool_defs = module.tools()
        new_tools =
          Enum.reduce(tool_defs, state.tools, fn tool_def, acc ->
            name = tool_def["name"]
            Logger.info("[Eclaw.ToolRegistry] Registered multi-tool: #{name}")
            Map.put(acc, name, %{type: :multi, module: module, definition: tool_def})
          end)

        {:ok, %{state | tools: new_tools}}

      function_exported?(module, :name, 0) and
        function_exported?(module, :description, 0) and
        function_exported?(module, :input_schema, 0) and
        function_exported?(module, :execute, 1) ->
        name = module.name()
        Logger.info("[Eclaw.ToolRegistry] Registered plugin tool: #{name}")
        {:ok, put_in(state, [:tools, name], %{type: :module, module: module})}

      true ->
        :error
    end
  end

  # Route MCP tools: name format is "mcp::server::tool"
  defp execute_mcp_tool(tool_name, input) do
    case Eclaw.MCP.parse_tool_name(tool_name) do
      {:ok, server_name, original_tool} ->
        Eclaw.MCP.call_tool(server_name, original_tool, input)

      :error ->
        {:error, "Cannot route MCP tool: #{tool_name}"}
    end
  end
end
