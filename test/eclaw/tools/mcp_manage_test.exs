defmodule Eclaw.Tools.McpManageTest do
  use ExUnit.Case, async: true

  alias Eclaw.Tools.McpManage

  describe "ToolBehaviour implementation" do
    test "name/0 returns expected tool name" do
      assert McpManage.name() == "mcp_manage"
    end

    test "description/0 returns a non-empty string" do
      desc = McpManage.description()
      assert is_binary(desc)
      assert String.length(desc) > 0
    end

    test "input_schema/0 returns valid schema with action property" do
      schema = McpManage.input_schema()
      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "action")
      assert "action" in schema["required"]
    end

    test "input_schema/0 includes all expected action values" do
      schema = McpManage.input_schema()
      actions = schema["properties"]["action"]["enum"]
      assert "connect" in actions
      assert "disconnect" in actions
      assert "list_servers" in actions
      assert "list_tools" in actions
    end

    test "input_schema/0 includes server config properties" do
      schema = McpManage.input_schema()
      props = schema["properties"]
      assert Map.has_key?(props, "name")
      assert Map.has_key?(props, "transport")
      assert Map.has_key?(props, "command")
      assert Map.has_key?(props, "args")
      assert Map.has_key?(props, "url")
    end
  end
end
