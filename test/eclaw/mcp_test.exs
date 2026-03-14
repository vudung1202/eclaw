defmodule Eclaw.MCPTest do
  use ExUnit.Case, async: true

  alias Eclaw.MCP

  describe "parse_tool_name/1" do
    test "parses valid MCP tool name" do
      assert {:ok, "filesystem", "read_file"} = MCP.parse_tool_name("mcp::filesystem::read_file")
    end

    test "parses tool name with underscores" do
      assert {:ok, "my_server", "my_tool_name"} =
               MCP.parse_tool_name("mcp::my_server::my_tool_name")
    end

    test "handles tool name with separator in tool part" do
      assert {:ok, "server", "tool::sub"} = MCP.parse_tool_name("mcp::server::tool::sub")
    end

    test "returns :error for non-MCP names" do
      assert :error = MCP.parse_tool_name("not_mcp_tool")
    end

    test "returns :error for malformed names" do
      assert :error = MCP.parse_tool_name("mcp::only_server")
    end

    test "returns :error for empty string" do
      assert :error = MCP.parse_tool_name("")
    end
  end
end
