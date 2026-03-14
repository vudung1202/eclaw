defmodule Eclaw.Skills.OpenClawTest do
  use ExUnit.Case, async: true

  alias Eclaw.Skills.OpenClaw

  describe "status/0" do
    test "returns a map with expected keys" do
      status = OpenClaw.status()
      assert is_map(status)
      assert Map.has_key?(status, :repos_cloned)
      assert Map.has_key?(status, :index_size)
      assert Map.has_key?(status, :skills_dir)
      assert Map.has_key?(status, :awesome_dir)
    end

    test "index_size is a non-negative integer" do
      assert OpenClaw.status().index_size >= 0
    end
  end

  describe "categories/0" do
    test "returns a list" do
      assert is_list(OpenClaw.categories())
    end
  end

  describe "search/2" do
    test "returns a list" do
      assert is_list(OpenClaw.search("nonexistent_skill_xyz"))
    end

    test "returns empty list for nonsense query" do
      assert OpenClaw.search("zzzzxyznonexistent9999") == []
    end

    test "respects limit option" do
      results = OpenClaw.search("test", limit: 2)
      assert length(results) <= 2
    end
  end

  describe "load_skill/2" do
    test "returns error for nonexistent skill" do
      assert {:error, _} = OpenClaw.load_skill("nonexistent_author", "nonexistent_slug")
    end
  end

  describe "parse_skill_md (via load_skill)" do
    test "handles missing SKILL.md gracefully" do
      assert {:error, msg} = OpenClaw.load_skill("__test__", "__missing__")
      assert is_binary(msg)
      assert msg =~ "Cannot read skill"
    end
  end
end
