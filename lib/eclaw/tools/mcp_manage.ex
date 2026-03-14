defmodule Eclaw.Tools.McpManage do
  @moduledoc """
  Tool for runtime MCP server management.

  Allows the agent to connect to new MCP servers, disconnect from existing ones,
  and list available servers and their tools — all at runtime via natural language.

  Implements `Eclaw.ToolBehaviour`.
  """

  @behaviour Eclaw.ToolBehaviour

  require Logger

  @impl true
  def name, do: "mcp_manage"

  @impl true
  def description do
    "Manage MCP (Model Context Protocol) server connections at runtime. " <>
      "Actions: connect (to a new server), disconnect, list_servers, list_tools."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["connect", "disconnect", "list_servers", "list_tools"],
          "description" =>
            "Action to perform: " <>
              "'connect' to add a new MCP server, " <>
              "'disconnect' to remove one, " <>
              "'list_servers' to see connected servers, " <>
              "'list_tools' to see all MCP tools."
        },
        "name" => %{
          "type" => "string",
          "description" => "Server name (required for connect/disconnect)"
        },
        "transport" => %{
          "type" => "string",
          "enum" => ["stdio", "http"],
          "description" => "Transport type: 'stdio' for local process, 'http' for remote HTTP/SSE (default: auto-detect)"
        },
        "command" => %{
          "type" => "string",
          "description" => "Command to run (stdio transport only, e.g., 'npx')"
        },
        "args" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Command arguments (stdio transport only)"
        },
        "url" => %{
          "type" => "string",
          "description" => "Server URL (http transport only, e.g., 'http://localhost:3000/sse')"
        }
      },
      "required" => ["action"]
    }
  end

  @impl true
  def execute(input) do
    action = input["action"]
    Logger.debug("[Eclaw.Tools.McpManage] Executing action=#{action}")

    case action do
      "connect" -> handle_connect(input)
      "disconnect" -> handle_disconnect(input)
      "list_servers" -> handle_list_servers()
      "list_tools" -> handle_list_tools()
      _ -> {:error, "Unknown action: #{action}. Valid actions: connect, disconnect, list_servers, list_tools"}
    end
  rescue
    e ->
      Logger.error("[Eclaw.Tools.McpManage] Error: #{Exception.message(e)}")
      {:error, "MCP management error: #{Exception.message(e)}"}
  end

  # ── Action Handlers ────────────────────────────────────────────────

  defp handle_connect(input) do
    name = input["name"]

    if is_nil(name) or name == "" do
      {:error, "Missing required parameter: 'name'. Provide a unique name for the MCP server."}
    else
      config = build_config(input)

      case Eclaw.MCP.connect(config) do
        :ok ->
          # List tools from the newly connected server
          tools = Eclaw.MCP.list_tools()
          server_tools = Enum.filter(tools, fn t -> t.server == name end)
          tool_names = Enum.map(server_tools, fn t -> t.name end)

          result =
            "Connected to MCP server '#{name}' successfully.\n" <>
              "Discovered #{length(tool_names)} tool(s):\n" <>
              format_tool_list(tool_names)

          {:ok, result}

        {:error, reason} ->
          {:error, "Failed to connect to '#{name}': #{format_error(reason)}"}
      end
    end
  end

  defp handle_disconnect(input) do
    name = input["name"]

    if is_nil(name) or name == "" do
      {:error, "Missing required parameter: 'name'. Specify which server to disconnect."}
    else
      case Eclaw.MCP.disconnect(name) do
        :ok ->
          {:ok, "Disconnected from MCP server '#{name}'."}

        {:error, reason} ->
          {:error, "Failed to disconnect from '#{name}': #{format_error(reason)}"}
      end
    end
  end

  defp handle_list_servers do
    servers = Eclaw.MCP.list_servers()

    if servers == [] do
      {:ok, "No MCP servers connected."}
    else
      lines =
        Enum.map(servers, fn s ->
          "- #{s.name} (#{s.transport}, #{s.status}, #{s.tool_count} tools)"
        end)

      {:ok, "Connected MCP servers:\n" <> Enum.join(lines, "\n")}
    end
  end

  defp handle_list_tools do
    tools = Eclaw.MCP.list_tools()

    if tools == [] do
      {:ok, "No MCP tools available. Connect to an MCP server first."}
    else
      # Group by server
      grouped = Enum.group_by(tools, fn t -> t.server end)

      lines =
        Enum.flat_map(grouped, fn {server, server_tools} ->
          ["[#{server}]:" | Enum.map(server_tools, fn t ->
            desc = if t.description, do: " - #{t.description}", else: ""
            "  - #{t.name}#{desc}"
          end)]
        end)

      {:ok, "MCP tools (#{length(tools)} total):\n" <> Enum.join(lines, "\n")}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp build_config(input) do
    base = %{name: input["name"]}

    base =
      if input["transport"] do
        Map.put(base, :transport, input["transport"])
      else
        base
      end

    base =
      if input["command"] do
        base
        |> Map.put(:command, input["command"])
        |> Map.put(:args, input["args"] || [])
      else
        base
      end

    base =
      if input["url"] do
        Map.put(base, :url, input["url"])
      else
        base
      end

    base
  end

  defp format_tool_list([]), do: "  (none)"

  defp format_tool_list(names) do
    Enum.map_join(names, "\n", fn name -> "  - #{name}" end)
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
