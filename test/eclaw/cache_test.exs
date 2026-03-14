defmodule Eclaw.CacheTest do
  use ExUnit.Case, async: false

  setup do
    # Clear cache before each test to ensure isolation
    Eclaw.Cache.clear()
    :ok
  end

  describe "get_or_compute/3" do
    test "computes and caches a value on first call" do
      result =
        Eclaw.Cache.get_or_compute(:test_key, 60_000, fn ->
          "computed_value"
        end)

      assert result == "computed_value"
    end

    test "returns cached value on subsequent calls" do
      call_count = :counters.new(1, [:atomics])

      compute = fn ->
        :counters.add(call_count, 1, 1)
        "computed_value"
      end

      result1 = Eclaw.Cache.get_or_compute(:counter_key, 60_000, compute)
      result2 = Eclaw.Cache.get_or_compute(:counter_key, 60_000, compute)

      assert result1 == "computed_value"
      assert result2 == "computed_value"
      assert :counters.get(call_count, 1) == 1
    end

    test "recomputes after TTL expires" do
      call_count = :counters.new(1, [:atomics])

      compute = fn ->
        :counters.add(call_count, 1, 1)
        "value_#{:counters.get(call_count, 1)}"
      end

      # Use a very short TTL
      result1 = Eclaw.Cache.get_or_compute(:ttl_key, 1, compute)
      assert result1 == "value_1"

      # Wait for TTL to expire
      Process.sleep(5)

      result2 = Eclaw.Cache.get_or_compute(:ttl_key, 1, compute)
      assert result2 == "value_2"
      assert :counters.get(call_count, 1) == 2
    end

    test "caches different keys independently" do
      Eclaw.Cache.get_or_compute(:key_a, 60_000, fn -> "value_a" end)
      Eclaw.Cache.get_or_compute(:key_b, 60_000, fn -> "value_b" end)

      assert Eclaw.Cache.get_or_compute(:key_a, 60_000, fn -> "stale" end) == "value_a"
      assert Eclaw.Cache.get_or_compute(:key_b, 60_000, fn -> "stale" end) == "value_b"
    end

    test "supports tuple keys" do
      result =
        Eclaw.Cache.get_or_compute({:web_fetch, "https://example.com"}, 60_000, fn ->
          "page content"
        end)

      assert result == "page content"

      cached =
        Eclaw.Cache.get_or_compute({:web_fetch, "https://example.com"}, 60_000, fn ->
          "should not compute"
        end)

      assert cached == "page content"
    end
  end

  describe "invalidate/1" do
    test "removes a specific cached entry" do
      Eclaw.Cache.get_or_compute(:inv_key, 60_000, fn -> "original" end)

      Eclaw.Cache.invalidate(:inv_key)

      result = Eclaw.Cache.get_or_compute(:inv_key, 60_000, fn -> "recomputed" end)
      assert result == "recomputed"
    end

    test "does not affect other entries" do
      Eclaw.Cache.get_or_compute(:keep, 60_000, fn -> "keep_value" end)
      Eclaw.Cache.get_or_compute(:remove, 60_000, fn -> "remove_value" end)

      Eclaw.Cache.invalidate(:remove)

      assert Eclaw.Cache.get_or_compute(:keep, 60_000, fn -> "stale" end) == "keep_value"
    end

    test "is safe to call on non-existent key" do
      assert Eclaw.Cache.invalidate(:nonexistent) == :ok
    end
  end

  describe "clear/0" do
    test "removes all cached entries" do
      Eclaw.Cache.get_or_compute(:c1, 60_000, fn -> "v1" end)
      Eclaw.Cache.get_or_compute(:c2, 60_000, fn -> "v2" end)

      Eclaw.Cache.clear()

      assert Eclaw.Cache.get_or_compute(:c1, 60_000, fn -> "new_v1" end) == "new_v1"
      assert Eclaw.Cache.get_or_compute(:c2, 60_000, fn -> "new_v2" end) == "new_v2"
    end

    test "resets stats counters" do
      Eclaw.Cache.get_or_compute(:s1, 60_000, fn -> "v1" end)
      Eclaw.Cache.get_or_compute(:s1, 60_000, fn -> "v1" end)

      Eclaw.Cache.clear()

      assert Eclaw.Cache.stats() == %{hits: 0, misses: 0}
    end
  end

  describe "stats/0" do
    test "tracks cache hits and misses" do
      # First call = miss
      Eclaw.Cache.get_or_compute(:stat_key, 60_000, fn -> "value" end)
      # Second call = hit
      Eclaw.Cache.get_or_compute(:stat_key, 60_000, fn -> "value" end)
      # Third call = hit
      Eclaw.Cache.get_or_compute(:stat_key, 60_000, fn -> "value" end)
      # Different key = miss
      Eclaw.Cache.get_or_compute(:stat_key2, 60_000, fn -> "value2" end)

      # Allow casts to be processed
      Process.sleep(10)

      stats = Eclaw.Cache.stats()
      assert stats.hits == 2
      assert stats.misses == 2
    end

    test "returns zero counts initially" do
      assert Eclaw.Cache.stats() == %{hits: 0, misses: 0}
    end
  end
end
