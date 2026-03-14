defmodule Eclaw.MCP do
  @moduledoc """
  Model Context Protocol (MCP) client.

  Connects to MCP-compatible servers to discover and invoke external tools.
  Supports both stdio-based and HTTP/SSE-based MCP transports.

  ## Transport Types

  - **stdio** (default): Launches a local process, communicates via stdin/stdout JSON-RPC.
  - **http**: Connects to a remote MCP server via HTTP/SSE. Uses `Eclaw.MCP.HttpTransport`.

  ## Configuration

      config :eclaw, :mcp_servers, [
        # stdio transport
        %{name: "filesystem", transport: "stdio", command: "npx",
          args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]},
        # HTTP/SSE transport
        %{name: "remote", transport: "http", url: "http://localhost:3000/sse",
          headers: [{"Authorization", "Bearer token"}]}
      ]

  ## Usage

      # Start MCP client (registers tools automatically)
      Eclaw.MCP.start_link()

      # List discovered tools
      Eclaw.MCP.list_tools()

      # Execute a tool
      Eclaw.MCP.call_tool("filesystem", "read_file", %{"path" => "/tmp/test.txt"})

      # List connected servers
      Eclaw.MCP.list_servers()
  """

  use GenServer
  require Logger

  alias Eclaw.MCP.HttpTransport

  # Separator for MCP tool names: "mcp::server::tool"
  # Using "::" avoids collision with underscores in server/tool names.
  @separator "::"

  # Reconnection settings
  @initial_reconnect_delay 2_000
  @max_reconnect_delay 60_000
  @max_reconnect_attempts 10

  @type server_config :: %{
          name: String.t(),
          transport: String.t(),
          command: String.t(),
          args: [String.t()],
          env: [{String.t(), String.t()}],
          url: String.t(),
          headers: [{String.t(), String.t()}]
        }

  defstruct servers: %{}, tools: %{}, next_id: 1, reconnect_timers: %{}

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
  @spec connect(map()) :: :ok | {:error, term()}
  def connect(config) do
    GenServer.call(__MODULE__, {:connect, config}, 30_000)
  end

  @doc "Disconnect from an MCP server."
  @spec disconnect(String.t()) :: :ok
  def disconnect(server_name) do
    GenServer.call(__MODULE__, {:disconnect, server_name})
  end

  @doc "List connected servers with their status and transport type."
  @spec list_servers() :: [map()]
  def list_servers do
    GenServer.call(__MODULE__, :list_servers)
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
    servers_config = Eclaw.Config.get(:mcp_servers, [])

    state =
      Enum.reduce(servers_config, state, fn config, acc ->
        name = config[:name] || config["name"]

        case do_connect(config, acc.next_id) do
          {:ok, server_state, next_id} ->
            Logger.info("[Eclaw.MCP] Connected to server: #{name} (#{server_transport(server_state)})")
            %{acc | servers: Map.put(acc.servers, name, server_state), next_id: next_id}

          {:error, reason} ->
            Logger.warning("[Eclaw.MCP] Failed to connect to #{name}: #{inspect(reason)}")
            acc
        end
      end)

    # Discover tools from all connected servers
    state = discover_all_tools(state)

    count = map_size(state.tools)
    server_count = map_size(state.servers)

    if server_count > 0 do
      Logger.info("[Eclaw.MCP] Connected to #{server_count} server(s), #{count} tool(s) available")
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
  def handle_call(:list_servers, _from, state) do
    servers =
      state.servers
      |> Enum.map(fn {name, server} ->
        tool_count =
          state.tools
          |> Enum.count(fn {_k, v} -> v.server == name end)

        %{
          name: name,
          transport: server_transport(server),
          tool_count: tool_count,
          status: server_status(server)
        }
      end)

    {:reply, servers, state}
  end

  @impl true
  def handle_call({:call_tool, server_name, tool_name, arguments}, _from, state) do
    case Map.get(state.servers, server_name) do
      nil ->
        {:reply, {:error, :server_not_found}, state}

      %{transport: :http, pid: pid} ->
        # HTTP transport — delegate to HttpTransport process
        result =
          try do
            HttpTransport.send_request(pid, "tools/call", %{
              "name" => tool_name,
              "arguments" => arguments
            })
          catch
            :exit, reason ->
              Logger.error("[Eclaw.MCP] HTTP call_tool failed for #{server_name}: #{inspect(reason)}")
              {:error, {:transport_error, reason}}
          end

        case result do
          {:ok, %{"content" => content}} ->
            {:reply, {:ok, extract_mcp_content(content)}, state}

          {:ok, _other} ->
            {:reply, {:ok, "Tool executed successfully"}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      server ->
        # stdio transport
        {result, server, next_id} = send_jsonrpc_stdio(server, "tools/call", %{
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

    # Disconnect existing server with the same name first
    state = do_disconnect(name, state)

    case do_connect(config, state.next_id) do
      {:ok, server_state, next_id} ->
        Logger.info("[Eclaw.MCP] Connected to server: #{name} (#{server_transport(server_state)})")

        state = %{state |
          servers: Map.put(state.servers, name, server_state),
          next_id: next_id
        }

        state = discover_tools_for_server(state, name)
        register_tools_with_registry(state)
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("[Eclaw.MCP] Failed to connect to #{name}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:disconnect, server_name}, _from, state) do
    state = do_disconnect(server_name, state)
    register_tools_with_registry(state)
    {:reply, :ok, state}
  end

  # Handle port exit messages (stdio transport)
  @impl true
  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    case find_server_by_port(state, port) do
      {name, server} ->
        Logger.warning("[Eclaw.MCP] Server #{name} (stdio) exited with status #{status}")
        state = remove_server_tools(state, name)
        state = %{state | servers: Map.delete(state.servers, name)}

        # Attempt reconnection if we have the original config
        state = maybe_schedule_reconnect(state, name, server)
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  # Handle HTTP transport process exit (monitored)
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case find_server_by_pid(state, pid) do
      {name, server} ->
        Logger.warning("[Eclaw.MCP] Server #{name} (http) transport exited: #{inspect(reason)}")
        state = remove_server_tools(state, name)
        state = %{state | servers: Map.delete(state.servers, name)}

        # Attempt reconnection
        state = maybe_schedule_reconnect(state, name, server)
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  # Reconnection timer fired
  @impl true
  def handle_info({:reconnect, name}, state) do
    case Map.pop(state.reconnect_timers, name) do
      {nil, _} ->
        {:noreply, state}

      {%{config: config, attempt: attempt}, remaining_timers} ->
        state = %{state | reconnect_timers: remaining_timers}

        Logger.info("[Eclaw.MCP] Reconnecting to #{name} (attempt #{attempt})")

        case do_connect(config, state.next_id) do
          {:ok, server_state, next_id} ->
            Logger.info("[Eclaw.MCP] Reconnected to #{name} successfully")
            state = %{state |
              servers: Map.put(state.servers, name, server_state),
              next_id: next_id
            }
            state = discover_tools_for_server(state, name)
            register_tools_with_registry(state)
            {:noreply, state}

          {:error, reason} ->
            Logger.warning("[Eclaw.MCP] Reconnect to #{name} failed: #{inspect(reason)}")

            if attempt < @max_reconnect_attempts do
              state = schedule_reconnect(state, name, config, attempt + 1)
              {:noreply, state}
            else
              Logger.error("[Eclaw.MCP] Giving up reconnecting to #{name} after #{@max_reconnect_attempts} attempts")
              {:noreply, state}
            end
        end
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    # Cancel all reconnect timers
    Enum.each(state.reconnect_timers, fn
      {_name, %{timer: timer}} -> Process.cancel_timer(timer)
      _ -> :ok
    end)

    # Cleanup all servers
    Enum.each(state.servers, fn {_name, server} -> cleanup_server(server) end)
    :ok
  end

  # ── Private: Connection ────────────────────────────────────────────

  defp do_connect(config, next_id) do
    transport = get_transport(config)

    case transport do
      :http -> do_connect_http(config)
      :stdio -> do_connect_stdio(config, next_id)
      other -> {:error, {:unknown_transport, other}}
    end
  end

  defp get_transport(config) do
    transport = config[:transport] || config["transport"]

    cond do
      transport in ["http", "sse", "http+sse"] -> :http
      transport == "stdio" -> :stdio
      # Auto-detect: if url is present, use HTTP
      config[:url] || config["url"] -> :http
      # Default to stdio
      true -> :stdio
    end
  end

  # HTTP/SSE transport connection
  defp do_connect_http(config) do
    name = config[:name] || config["name"]
    url = config[:url] || config["url"]
    headers = config[:headers] || config["headers"] || []

    cond do
      is_nil(url) or url == "" ->
        {:error, {:missing_url, name}}

      not Eclaw.Security.safe_url?(url) ->
        Logger.error("[Eclaw.MCP] SSRF blocked: refusing to connect to #{url}")
        {:error, {:ssrf_blocked, url}}

      true ->
        transport_config = %{url: url, headers: headers}

      case HttpTransport.start_link(transport_config) do
        {:ok, pid} ->
          ref = Process.monitor(pid)

          # Wait for connection and run initialization
          case wait_for_http_connection(pid, 15_000) do
            :ok ->
              case initialize_http_server(pid) do
                :ok ->
                  server = %{
                    transport: :http,
                    pid: pid,
                    monitor_ref: ref,
                    name: name,
                    config: config
                  }

                  {:ok, server, 1}

                {:error, reason} ->
                  Process.demonitor(ref, [:flush])
                  GenServer.stop(pid, :normal)
                  {:error, reason}
              end

            {:error, reason} ->
              Process.demonitor(ref, [:flush])
              GenServer.stop(pid, :normal)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, {:http_transport_failed, reason}}
      end
    end
  end  # cond

  defp wait_for_http_connection(pid, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_loop(pid, deadline)
  end

  defp wait_loop(pid, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :connect_timeout}
    else
      if HttpTransport.connected?(pid) do
        :ok
      else
        Process.sleep(100)
        wait_loop(pid, deadline)
      end
    end
  end

  defp initialize_http_server(pid) do
    case HttpTransport.send_request(pid, "initialize", %{
           "protocolVersion" => "2024-11-05",
           "capabilities" => %{},
           "clientInfo" => %{"name" => "eclaw", "version" => "0.1.0"}
         }) do
      {:ok, _result} ->
        HttpTransport.send_notification(pid, "notifications/initialized", %{})
        :ok

      {:error, reason} ->
        {:error, {:initialize_failed, reason}}
    end
  end

  # stdio transport connection (existing logic, improved)
  defp do_connect_stdio(config, next_id) do
    command = config[:command] || config["command"]
    args = config[:args] || config["args"] || []
    name = config[:name] || config["name"]

    if is_nil(command) do
      {:error, {:missing_command, name}}
    else
      env =
        (config[:env] || config["env"] || [])
        |> Enum.map(fn {k, v} -> {to_charlist(to_string(k)), to_charlist(to_string(v))} end)

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
            transport: :stdio,
            port: port,
            name: name,
            config: config
          }

          # Send initialize request
          {result, server, next_id} = send_jsonrpc_stdio(server, "initialize", %{
            "protocolVersion" => "2024-11-05",
            "capabilities" => %{},
            "clientInfo" => %{"name" => "eclaw", "version" => "0.1.0"}
          }, next_id)

          case result do
            {:ok, _result} ->
              send_notification_stdio(server, "notifications/initialized", %{})
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
  end

  # Catch-all removed — do_connect_stdio/2 always has command available
  # because get_transport/1 routes configs without command/url to :stdio,
  # and missing command is handled explicitly in the function body above.

  # ── Private: Disconnect ────────────────────────────────────────────

  defp do_disconnect(server_name, state) do
    case Map.get(state.servers, server_name) do
      nil ->
        state

      server ->
        cleanup_server(server)
        servers = Map.delete(state.servers, server_name)
        state = remove_server_tools(%{state | servers: servers}, server_name)

        # Cancel any pending reconnect
        cancel_reconnect_timer(state, server_name)
    end
  end

  defp cleanup_server(%{transport: :http, pid: pid, monitor_ref: ref}) do
    Process.demonitor(ref, [:flush])

    try do
      GenServer.stop(pid, :normal, 5_000)
    catch
      :exit, _ -> :ok
    end
  end

  defp cleanup_server(%{transport: :stdio, port: port}) do
    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end
  end

  defp cleanup_server(_), do: :ok

  # ── Private: Reconnection ──────────────────────────────────────────

  defp maybe_schedule_reconnect(state, name, server) do
    config = Map.get(server, :config)

    if config do
      schedule_reconnect(state, name, config, 1)
    else
      state
    end
  end

  defp schedule_reconnect(state, name, config, attempt) do
    delay = reconnect_delay(attempt)
    # Add jitter: +/- 25%
    jitter = trunc(delay * 0.25 * (:rand.uniform() * 2 - 1))
    actual_delay = max(delay + jitter, 500)

    Logger.info("[Eclaw.MCP] Scheduling reconnect for #{name} in #{actual_delay}ms (attempt #{attempt}/#{@max_reconnect_attempts})")

    timer = Process.send_after(self(), {:reconnect, name}, actual_delay)

    entry = %{timer: timer, config: config, attempt: attempt}
    %{state | reconnect_timers: Map.put(state.reconnect_timers, name, entry)}
  end

  defp reconnect_delay(attempt) do
    delay = @initial_reconnect_delay * :math.pow(2, attempt - 1) |> trunc()
    min(delay, @max_reconnect_delay)
  end

  defp cancel_reconnect_timer(state, name) do
    case Map.pop(state.reconnect_timers, name) do
      {%{timer: timer}, remaining} ->
        Process.cancel_timer(timer)
        %{state | reconnect_timers: remaining}

      {nil, _} ->
        state
    end
  end

  # ── Private: JSON-RPC over stdio ───────────────────────────────────

  # Returns {result, updated_server, next_id}
  defp send_jsonrpc_stdio(%{port: port} = server, method, params, next_id) do
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
        Logger.error("[Eclaw.MCP] Port closed when sending #{method} to #{server.name}")
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
            15_000 ->
              Logger.warning("[Eclaw.MCP] Timeout waiting for response from #{server.name} (method=#{method})")
              {:error, :timeout}
          end

        {result, server, next_id + 1}
    end
  end

  defp send_notification_stdio(%{port: port} = server, method, params) do
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
      ArgumentError ->
        Logger.error("[Eclaw.MCP] Port closed when sending notification #{method} to #{server.name}")
        {:error, :port_closed}
    end
  end

  # ── Private: Tool Discovery ────────────────────────────────────────

  defp discover_all_tools(state) do
    Enum.reduce(Map.keys(state.servers), state, fn name, acc ->
      discover_tools_for_server(acc, name)
    end)
  end

  defp discover_tools_for_server(state, server_name) do
    case Map.get(state.servers, server_name) do
      nil ->
        state

      %{transport: :http, pid: pid} ->
        result =
          try do
            HttpTransport.send_request(pid, "tools/list", %{})
          catch
            :exit, reason ->
              Logger.error("[Eclaw.MCP] Failed to list tools from #{server_name}: #{inspect(reason)}")
              {:error, reason}
          end

        case result do
          {:ok, %{"tools" => tool_list}} ->
            new_tools = build_tool_map(server_name, tool_list)
            merged = Map.merge(state.tools, new_tools)
            %{state | tools: merged}

          {:error, reason} ->
            Logger.warning("[Eclaw.MCP] Failed to list tools from #{server_name}: #{inspect(reason)}")
            state
        end

      server ->
        # stdio transport
        {result, _server, next_id} = send_jsonrpc_stdio(server, "tools/list", %{}, state.next_id)

        case result do
          {:ok, %{"tools" => tool_list}} ->
            new_tools = build_tool_map(server_name, tool_list)
            merged = Map.merge(state.tools, new_tools)
            %{state | tools: merged, next_id: next_id}

          {:error, reason} ->
            Logger.warning("[Eclaw.MCP] Failed to list tools from #{server_name}: #{inspect(reason)}")
            %{state | next_id: next_id}
        end
    end
  end

  defp build_tool_map(server_name, tool_list) do
    Enum.reduce(tool_list, %{}, fn tool, acc ->
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

      Map.put(acc, full_name, info)
    end)
  end

  # ── Private: Server Helpers ────────────────────────────────────────

  defp remove_server_tools(state, server_name) do
    tools = state.tools |> Enum.reject(fn {_k, v} -> v.server == server_name end) |> Map.new()
    %{state | tools: tools}
  end

  defp find_server_by_port(state, port) do
    Enum.find(state.servers, fn
      {_name, %{transport: :stdio, port: ^port}} -> true
      _ -> false
    end)
  end

  defp find_server_by_pid(state, pid) do
    Enum.find(state.servers, fn
      {_name, %{transport: :http, pid: ^pid}} -> true
      _ -> false
    end)
  end

  defp server_transport(%{transport: :http}), do: "http"
  defp server_transport(%{transport: :stdio}), do: "stdio"
  defp server_transport(_), do: "unknown"

  defp server_status(%{transport: :http, pid: pid}) do
    if Process.alive?(pid), do: "connected", else: "disconnected"
  end

  defp server_status(%{transport: :stdio, port: port}) do
    try do
      Port.info(port)
      "connected"
    catch
      _, _ -> "disconnected"
    end
  end

  defp server_status(_), do: "unknown"

  defp register_tools_with_registry(state) do
    # Re-register all MCP tools with the ToolRegistry
    Enum.each(state.tools, fn {_name, info} ->
      Eclaw.ToolRegistry.register_tool_definition(info.definition)
    end)
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
