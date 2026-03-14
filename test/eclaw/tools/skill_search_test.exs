defmodule Eclaw.Tools.SkillSearchTest do
  use ExUnit.Case, async: true

  alias Eclaw.Tools.SkillSearch

  describe "ToolBehaviour implementation" do
    test "name/0 returns expected tool name" do
      assert SkillSearch.name() == "skill_search"
    end

    test "description/0 returns a non-empty string" do
      desc = SkillSearch.description()
      assert is_binary(desc)
      assert String.length(desc) > 0
    end

    test "input_schema/0 returns valid schema with action property" do
      schema = SkillSearch.input_schema()
      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "action")
      assert "action" in schema["required"]
    end

    test "input_schema/0 includes all expected action values" do
      schema = SkillSearch.input_schema()
      actions = schema["properties"]["action"]["enum"]
      assert "search" in actions
      assert "load" in actions
      assert "categories" in actions
      assert "sync" in actions
      assert "status" in actions
    end
  end

  describe "execute/1" do
    test "search with missing query returns error" do
      assert {:error, msg} = SkillSearch.execute(%{"action" => "search"})
      assert msg =~ "Missing 'query'"
    end

    test "search with empty query returns error" do
      assert {:error, _} = SkillSearch.execute(%{"action" => "search", "query" => ""})
    end

    test "load with missing author/slug returns error" do
      assert {:error, msg} = SkillSearch.execute(%{"action" => "load"})
      assert msg =~ "Missing 'author'"
    end

    test "load with nonexistent skill returns error" do
      result = SkillSearch.execute(%{"action" => "load", "author" => "__none__", "slug" => "__none__"})
      assert {:error, _} = result
    end

    test "categories returns ok" do
      assert {:ok, _} = SkillSearch.execute(%{"action" => "categories"})
    end

    test "status returns ok with status info" do
      assert {:ok, text} = SkillSearch.execute(%{"action" => "status"})
      assert text =~ "Repos cloned"
      assert text =~ "Index size"
    end

    test "unknown action returns error" do
      assert {:error, msg} = SkillSearch.execute(%{"action" => "invalid"})
      assert msg =~ "Unknown action"
    end

    test "missing action returns error" do
      assert {:error, _} = SkillSearch.execute(%{})
    end
  end
end
