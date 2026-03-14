defmodule Eclaw.ContextTest do
  use ExUnit.Case, async: true

  alias Eclaw.Context

  # ── estimate_tokens/1 ──────────────────────────────────────────────

  describe "estimate_tokens/1" do
    test "returns 0 for empty message list" do
      assert Context.estimate_tokens([]) == 0
    end

    test "estimates tokens for a short text message" do
      messages = [%{"content" => "Hello, world!"}]
      tokens = Context.estimate_tokens(messages)
      # "Hello, world!" = 13 chars / 3.5 = ~4 tokens
      assert tokens > 0
      assert tokens == ceil(13 / 3.5)
    end

    test "estimates tokens for multiple messages" do
      messages = [
        %{"content" => "Hello"},
        %{"content" => "How are you?"}
      ]

      tokens = Context.estimate_tokens(messages)
      # "Hello" (5) + "How are you?" (12) = 17 chars / 3.5 = ~5
      expected = ceil(17 / 3.5)
      assert tokens == expected
    end

    test "estimates tokens for long text" do
      long_text = String.duplicate("a", 3500)
      messages = [%{"content" => long_text}]
      tokens = Context.estimate_tokens(messages)
      # 3500 / 3.5 = 1000 tokens
      assert tokens == 1000
    end

    test "handles content blocks (Anthropic format)" do
      messages = [
        %{
          "content" => [
            %{"type" => "text", "text" => "Hello world"},
            %{"type" => "text", "text" => "More text"}
          ]
        }
      ]

      tokens = Context.estimate_tokens(messages)
      # "Hello world" (11) + "More text" (9) = 20 / 3.5 = ~6
      assert tokens == ceil(20 / 3.5)
    end

    test "handles messages with no content" do
      messages = [%{"role" => "user"}]
      tokens = Context.estimate_tokens(messages)
      assert tokens == 0
    end
  end

  # ── truncate_tool_result/1 ─────────────────────────────────────────

  describe "truncate_tool_result/1" do
    test "passes through short results unchanged" do
      short = "This is a short result"
      assert Context.truncate_tool_result(short) == short
    end

    test "passes through results at exactly the limit" do
      # @max_tool_result_chars is 4_000
      at_limit = String.duplicate("x", 4_000)
      assert Context.truncate_tool_result(at_limit) == at_limit
    end

    test "truncates long results with head+tail" do
      long = String.duplicate("a", 8_000)
      result = Context.truncate_tool_result(long)

      # Should contain omission marker
      assert result =~ "[..."
      assert result =~ "chars omitted"

      # Result should be shorter than original
      assert String.length(result) < String.length(long)
    end

    test "truncated result starts with head of original" do
      # Create recognizable head and tail
      head = String.duplicate("H", 3_000)
      tail = String.duplicate("T", 3_000)
      original = head <> tail

      result = Context.truncate_tool_result(original)

      # Head portion should be preserved
      assert String.starts_with?(result, "HHHH")
      # Tail portion should be preserved
      assert String.ends_with?(result, "TTTT")
    end

    test "omission marker shows correct character count" do
      long = String.duplicate("x", 8_000)
      result = Context.truncate_tool_result(long)

      # head_size = 2000, tail_size = 2000, omitted = 8000 - 2000 - 2000 = 4000
      assert result =~ "4000 chars omitted"
    end

    test "handles UTF-8 content safely" do
      # Vietnamese text (multi-byte UTF-8)
      long_vn = String.duplicate("Xin chao! ", 2_000)
      result = Context.truncate_tool_result(long_vn)

      # Should not crash and should be valid UTF-8
      assert String.valid?(result)
    end
  end

  # ── extract_text/1 ─────────────────────────────────────────────────

  describe "extract_text/1" do
    test "extracts text from content blocks" do
      blocks = [
        %{"type" => "text", "text" => "Hello"},
        %{"type" => "tool_use", "name" => "bash", "input" => %{}},
        %{"type" => "text", "text" => "World"}
      ]

      assert Context.extract_text(blocks) == "Hello\nWorld"
    end

    test "returns empty string for empty list" do
      assert Context.extract_text([]) == ""
    end

    test "returns empty string for non-list input" do
      assert Context.extract_text(nil) == ""
      assert Context.extract_text("string") == ""
    end

    test "filters out non-text blocks" do
      blocks = [
        %{"type" => "tool_use", "name" => "bash", "input" => %{"command" => "ls"}},
        %{"type" => "tool_result", "content" => "output"}
      ]

      assert Context.extract_text(blocks) == ""
    end
  end

  # ── needs_compaction?/1 ────────────────────────────────────────────

  describe "needs_compaction?/1" do
    test "does not need compaction for small message list" do
      messages = [%{"content" => "Hello"}]
      refute Context.needs_compaction?(messages)
    end

    test "needs compaction when exceeding budget" do
      # Default budget is 60_000 tokens = ~210_000 chars
      huge_content = String.duplicate("x", 250_000)
      messages = [%{"content" => huge_content}]
      assert Context.needs_compaction?(messages)
    end
  end

  # ── force_compact/2 ────────────────────────────────────────────────

  describe "force_compact/2" do
    test "keeps all messages if 2 or fewer" do
      msgs = [%{"role" => "user", "content" => "hi"}]
      assert {:ok, ^msgs} = Context.force_compact(msgs, "system")
    end

    test "drops old messages, keeps last 2" do
      msgs = [
        %{"role" => "user", "content" => "msg1"},
        %{"role" => "assistant", "content" => "msg2"},
        %{"role" => "user", "content" => "msg3"},
        %{"role" => "assistant", "content" => "msg4"},
        %{"role" => "user", "content" => "msg5"}
      ]

      {:ok, result} = Context.force_compact(msgs, "system")
      assert length(result) == 2
      # Should keep the last 2 messages
      assert List.last(result)["content"] == "msg5"
    end
  end
end
