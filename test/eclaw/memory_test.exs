defmodule Eclaw.MemoryTest do
  use ExUnit.Case

  # Memory uses the singleton GenServer started by the application.
  # We test against the running instance but clean up after ourselves.
  # Use a unique prefix to avoid collisions with real data.
  @test_prefix "eclaw_unit_test_"

  setup do
    on_exit(fn ->
      # Remove only entries we created during this test
      Eclaw.Memory.list_all()
      |> Enum.filter(fn entry -> String.starts_with?(entry.key, @test_prefix) end)
      |> Enum.each(fn entry -> Eclaw.Memory.delete(entry.key) end)
    end)

    :ok
  end

  defp test_key(suffix) do
    "#{@test_prefix}#{suffix}_#{System.unique_integer([:positive])}"
  end

  # ── store/3 and list_all/0 ─────────────────────────────────────────

  describe "store/3 and list_all/0" do
    test "stores an entry and retrieves it" do
      key = test_key("store")
      assert :ok = Eclaw.Memory.store(key, "Test content for memory", :fact)

      entries = Eclaw.Memory.list_all()
      found = Enum.find(entries, &(&1.key == key))

      assert found != nil
      assert found.content == "Test content for memory"
      assert found.type == :fact
    end

    test "stores entries with different types" do
      key1 = test_key("fact")
      key2 = test_key("pref")

      :ok = Eclaw.Memory.store(key1, "A fact", :fact)
      :ok = Eclaw.Memory.store(key2, "A preference", :preference)

      entries = Eclaw.Memory.list_all()
      fact = Enum.find(entries, &(&1.key == key1))
      pref = Enum.find(entries, &(&1.key == key2))

      assert fact.type == :fact
      assert pref.type == :preference
    end

    test "stores entry with tags" do
      key = test_key("tagged")
      :ok = Eclaw.Memory.store(key, "Tagged content", :fact, tags: ["elixir", "test"])

      entries = Eclaw.Memory.list_all()
      found = Enum.find(entries, &(&1.key == key))

      assert found.tags == ["elixir", "test"]
    end

    test "overwrites entry with same key" do
      key = test_key("overwrite")
      :ok = Eclaw.Memory.store(key, "First version", :fact)
      :ok = Eclaw.Memory.store(key, "Second version", :fact)

      entries = Eclaw.Memory.list_all()
      found = Enum.filter(entries, &(&1.key == key))

      # Should only have one entry with this key
      assert length(found) == 1
      assert hd(found).content == "Second version"
    end
  end

  # ── search/2 ───────────────────────────────────────────────────────

  describe "search/2" do
    test "finds entries by keyword match" do
      key = test_key("search")
      unique_word = "xyzfunctional#{System.unique_integer([:positive])}"
      :ok = Eclaw.Memory.store(key, "Elixir is a #{unique_word} programming language", :fact)

      Process.sleep(50)

      results = Eclaw.Memory.search(unique_word, vector: false)
      found = Enum.find(results, &(&1.key == key))

      assert found != nil
      assert found.relevance > 0.0
    end

    test "returns no results with high relevance for nonsense query" do
      nonsense = "zzzznonexistenttermzzzz_#{System.unique_integer([:positive])}"
      results = Eclaw.Memory.search(nonsense, vector: false)

      # Keyword search gives 0.0 word_score for nonsense terms.
      # Recent entries may still get a 0.1 recency bonus, so they can appear.
      # But no entry should have a high relevance score for nonsense.
      Enum.each(results, fn entry ->
        assert entry.relevance <= 0.1,
               "Expected low relevance for nonsense query, got #{entry.relevance} for #{entry.key}"
      end)
    end

    test "respects limit option" do
      base = System.unique_integer([:positive])
      unique_word = "searchlimit#{base}"

      for i <- 1..5 do
        :ok = Eclaw.Memory.store(test_key("limit_#{i}"), "Content #{unique_word} entry #{i}", :fact)
      end

      Process.sleep(50)

      results = Eclaw.Memory.search(unique_word, limit: 2, vector: false)
      assert length(results) <= 2
    end
  end

  # ── delete/1 ───────────────────────────────────────────────────────

  describe "delete/1" do
    test "removes an entry by key" do
      key = test_key("delete")
      :ok = Eclaw.Memory.store(key, "To be deleted", :fact)

      # Verify it exists
      entries = Eclaw.Memory.list_all()
      assert Enum.any?(entries, &(&1.key == key))

      # Delete it
      :ok = Eclaw.Memory.delete(key)

      # Verify it's gone
      entries = Eclaw.Memory.list_all()
      refute Enum.any?(entries, &(&1.key == key))
    end
  end

  # ── count/0 ────────────────────────────────────────────────────────

  describe "count/0" do
    test "returns non-negative integer" do
      count = Eclaw.Memory.count()
      assert is_integer(count)
      assert count >= 0
    end

    test "increments after store" do
      count_before = Eclaw.Memory.count()
      key = test_key("count")
      :ok = Eclaw.Memory.store(key, "Counting test", :fact)
      count_after = Eclaw.Memory.count()

      assert count_after == count_before + 1
    end
  end

  # ── to_context/2 ───────────────────────────────────────────────────

  describe "to_context/2" do
    test "returns formatted context string when entries exist" do
      key = test_key("ctx")
      unique_word = "xyzcontextword#{System.unique_integer([:positive])}"
      :ok = Eclaw.Memory.store(key, "Context test #{unique_word}", :fact)

      Process.sleep(50)

      # Search for the unique word so we get a targeted result
      result = Eclaw.Memory.to_context(unique_word, 10)

      assert result =~ "[MEMORY"
      assert result =~ "[END MEMORY]"
      assert result =~ unique_word
    end

    test "returns context with header and footer format" do
      # to_context with empty query returns all entries, which will exist
      # since the application has persistent memory. Just verify the format.
      key = test_key("ctx2")
      unique_word = "xyzformatword#{System.unique_integer([:positive])}"
      :ok = Eclaw.Memory.store(key, "Format test #{unique_word}", :fact)

      Process.sleep(50)

      result = Eclaw.Memory.to_context(unique_word, 10)

      if result != "" do
        assert result =~ "[MEMORY"
        assert result =~ "[END MEMORY]"
      end
    end
  end
end
