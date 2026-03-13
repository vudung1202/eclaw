defmodule Eclaw.MCP do
  @moduledoc """
  Model Context Protocol (MCP) client.

  Connects to MCP-compatible servers to discover and invoke external tools.
  Supports stdio-based MCP transport.

  ## Configuration

      config :eclaw, :mcp_servers, [
        %{name: "filesystem", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]},
        %{name: "github", command: "npx", args: ["-y", "@modelcontextprotocol/server-github"]}
      ]

  ## Usage

      # Start MCP client (registers tools automatically)
      Eclaw.MCP.start_link()

      # List discovered tools
      Eclaw.MCP.list_tools()

      # Execute a tool
      Eclaw.MCP.call_tool("filesystem", "read_file", %{"path" => "/tmp/test.txt"})
  """

  use GenServer
  require Logger

  # Separator for MCP tool names: "mcp::server::tool"
  # Using "::" avoids collision with underscores in server/tool names.
  @separator "::"

  @type server_config :: %{
          name: String.t(),
          command: String.t(),
          args: [String.t()],
          env: [{String.t(), String.t()}]
        }

  defstruct servers: %{}, tools: %{}, next_id: 1

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "List all tools discovered from MCP servers."
  @spec list_tools() :: [map()]
  def list_tools do
    GenServer.call(__MODULE__, :list_tools)
  end

  @doc "Get tool definitions in Anthropic format (for injection into LLM calls)."
  @spec tool_definitions() :: [map()]
  def tool_definitions do
    GenServer.call(__MODULE__, :tool_definitions)
  end

  @doc "Call a tool on an MCP server."
  @spec call_tool(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def call_tool(server_name, tool_name, arguments) do
    GenServer.call(__MODULE__, {:call_tool, server_name, tool_name, arguments}, 30_000)
  end

  @doc "Connect to a new MCP server at runtime."
  @spec connect(server_config()) :: :ok | {:error, term()}
  def connect(config) do
    GenServer.call(__MODULE__, {:connect, config}, 30_000)
  end

  @doc "Disconnect from an MCP server."
  @spec disconnect(String.t()) :: :ok
  def disconnect(server_name) do
    GenServer.call(__MODULE__, {:disconnect, server_name})
  end

  @doc "Parse a full MCP tool name into {server_name, original_tool_name}."
  @spec parse_tool_name(String.t()) :: {:ok, String.t(), String.t()} | :error
  def parse_tool_name(full_name) do
    case String.split(full_name, @separator, parts: 3) do
      ["mcp", server_name, tool_name] -> {:ok, server_name, tool_name}
      _ -> :error
    end
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    # Defer connections to handle_continue so port messages can be received
    {:ok, %__MODULE__{}, {:continue, :connect_servers}}
  end

  @impl true
  def handle_continue(:connect_servers, state) do
    servers_config = Application.get_env(:eclaw, :mcp_servers, [])

    state =
      Enum.reduce(servers_config, state, fn config, acc ->
        name = config[:name] || config["name"]

        case do_connect(config, acc.next_id) do
          {:ok, server_state, next_id} ->
            %{acc | servers: Map.put(acc.servers, name, server_state), next_id: next_id}

          {:error, reason} ->
            Logger.warning("[Eclaw.MCP] Failed to connect to #{name}: #{inspect(reason)}")
            acc
        end
      end)

    # Discover tools from all connected servers
    state = discover_all_tools(state)

    count = map_size(state.tools)
    if count > 0 do
      Logger.info("[Eclaw.MCP] Connected to #{map_size(state.servers)} servers, #{count} tools available")
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    tools =
      state.tools
      |> Enum.map(fn {name, info} ->
        %{name: name, server: info.server, description: info.description}
      end)

    {:reply, tools, state}
  end

  @impl true
  def handle_call(:tool_definitions, _from, state) do
    definitions =
      state.tools
      |> Enum.map(fn {_name, info} -> info.definition end)

    {:reply, definitions, state}
  end

  @impl true
  def handle_call({:call_tool, server_name, tool_name, arguments}, _from, state) do
    case Map.get(state.servers, server_name) do
      nil ->
        {:reply, {:error, :server_not_found}, state}

      server ->
        {result, server, next_id} = send_jsonrpc(server, "tools/call", %{
          "name" => tool_name,
          "arguments" => arguments
        }, state.next_id)

        state = %{state |
          servers: Map.put(state.servers, server_name, server),
          next_id: next_id
        }

        case result do
          {:ok, %{"content" => content}} ->
            text = extract_mcp_content(content)
            {:reply, {:ok, text}, state}

          {:ok, _other} ->
            {:reply, {:ok, "Tool executed successfully"}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:connect, config}, _from, state) do
    name = config[:name] || config["name"]

    case do_connect(config, state.next_id) do
      {:ok, server_state, next_id} ->
        state = %{state |
          servers: Map.put(state.servers, name, server_state),
          next_id: next_id
        }
        state = discover_all_tools(state)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:disconnect, server_name}, _from, state) do
    case Map.get(state.servers, server_name) do
      nil ->
        {:reply, :ok, state}

      server ->
        cleanup_server(server)
        servers = Map.delete(state.servers, server_name)
        tools = state.tools |> Enum.reject(fn {_k, v} -> v.server == server_name end) |> Map.new()
        {:reply, :ok, %{state | servers: servers, tools: tools}}
    end
  end

  # Handle port exit messages
  @impl true
  def handle_info({port, {:exit_status, status}}, state) do
    # Find which server this port belongs to
    case Enum.find(state.servers, fn {_name, s} -> s.port == port end) do
      {name, _server} ->
        Logger.warning("[Eclaw.MCP] Server #{name} exited with status #{status}")
        servers = Map.delete(state.servers, name)
        tools = state.tools |> Enum.reject(fn {_k, v} -> v.server == name end) |> Map.new()
        {:noreply, %{state | servers: servers, tools: tools}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.servers, fn {_name, server} -> cleanup_server(server) end)
    :ok
  end

  # ── Private: Connection ────────────────────────────────────────────

  defp do_connect(%{command: command, args: args} = config, next_id) do
    env = Map.get(config, :env, []) |> Enum.map(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    executable = System.find_executable(command)

    if executable == nil do
      {:error, {:executable_not_found, command}}
    else
      try do
        port = Port.open(
          {:spawn_executable, executable},
          [:binary, :exit_status, {:args, args}, {:env, env}, :use_stdio, {:line, 1_000_000}]
        )

        server = %{
          port: port,
          name: config[:name] || config["name"]
        }

        # Send initialize request
        {result, server, next_id} = send_jsonrpc(server, "initialize", %{
          "protocolVersion" => "2024-11-05",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "eclaw", "version" => "0.1.0"}
        }, next_id)

        case result do
          {:ok, _result} ->
            # Send initialized notification
            send_notification(server, "notifications/initialized", %{})
            {:ok, server, next_id}

          {:error, reason} ->
            Port.close(port)
            {:error, reason}
        end
      rescue
        e ->
          {:error, {:launch_failed, Exception.message(e)}}
      end
    end
  end

  defp do_connect(_, _next_id), do: {:error, :invalid_config}

  defp cleanup_server(%{port: port}) do
    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end
  end

  defp cleanup_server(_), do: :ok

  # ── Private: JSON-RPC over stdio ───────────────────────────────────

  # Returns {result, updated_server, next_id}
  defp send_jsonrpc(%{port: port} = server, method, params, next_id) do
    id = next_id

    message = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => params
    }

    json = Jason.encode!(message)

    try do
      Port.command(port, json <> "\n")
    rescue
      ArgumentError ->
        {{:error, :port_closed}, server, next_id + 1}
    else
      _ ->
        # Wait for response (with timeout) — validate response ID matches request
        result =
          receive do
            {^port, {:data, {:eol, line}}} ->
              case Jason.decode(line) do
                {:ok, %{"id" => ^id, "result" => result}} -> {:ok, result}
                {:ok, %{"id" => ^id, "error" => error}} -> {:error, error}
                {:ok, %{"id" => _wrong_id}} -> {:error, :id_mismatch}
                _ -> {:error, :invalid_response}
              end
          after
            15_000 -> {:error, :timeout}
          end

        {result, server, next_id + 1}
    end
  end

  defp send_notification(%{port: port}, method, params) do
    message = %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }

    json = Jason.encode!(message)

    try do
      Port.command(port, json <> "\n")
      :ok
    rescue
      ArgumentError -> {:error, :port_closed}
    end
  end

  # ── Private: Tool Discovery ────────────────────────────────────────

  defp discover_all_tools(state) do
    {tools, next_id} =
      Enum.reduce(state.servers, {%{}, state.next_id}, fn {server_name, server}, {acc, nid} ->
        {result, _server, nid} = send_jsonrpc(server, "tools/list", %{}, nid)

        case result do
          {:ok, %{"tools" => tool_list}} ->
            new_tools =
              Enum.reduce(tool_list, acc, fn tool, tool_acc ->
                full_name = "mcp#{@separator}#{server_name}#{@separator}#{tool["name"]}"

                definition = %{
                  "name" => full_name,
                  "description" => "[MCP:#{server_name}] #{tool["description"] || tool["name"]}",
                  "input_schema" => tool["inputSchema"] || %{"type" => "object", "properties" => %{}}
                }

                info = %{
                  server: server_name,
                  original_name: tool["name"],
                  description: tool["description"],
                  definition: definition
                }

                Map.put(tool_acc, full_name, info)
              end)

            {new_tools, nid}

          {:error, reason} ->
            Logger.warning("[Eclaw.MCP] Failed to list tools from #{server_name}: #{inspect(reason)}")
            {acc, nid}
        end
      end)

    %{state | tools: tools, next_id: next_id}
  end

  defp extract_mcp_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      other -> inspect(other)
    end)
    |> Enum.join("\n")
  end

  defp extract_mcp_content(content) when is_binary(content), do: content
  defp extract_mcp_content(content), do: inspect(content)
end
