defmodule Eclaw.ConfigTest do
  use ExUnit.Case

  alias Eclaw.Config

  # Reset any config overrides after each test
  setup do
    original_model = Application.get_env(:eclaw, :model)
    original_max_tokens = Application.get_env(:eclaw, :max_tokens)
    original_max_iterations = Application.get_env(:eclaw, :max_iterations)
    original_command_timeout = Application.get_env(:eclaw, :command_timeout)
    original_provider = Application.get_env(:eclaw, :provider)

    on_exit(fn ->
      if original_model, do: Application.put_env(:eclaw, :model, original_model), else: Application.delete_env(:eclaw, :model)
      if original_max_tokens, do: Application.put_env(:eclaw, :max_tokens, original_max_tokens), else: Application.delete_env(:eclaw, :max_tokens)
      if original_max_iterations, do: Application.put_env(:eclaw, :max_iterations, original_max_iterations), else: Application.delete_env(:eclaw, :max_iterations)
      if original_command_timeout, do: Application.put_env(:eclaw, :command_timeout, original_command_timeout), else: Application.delete_env(:eclaw, :command_timeout)
      if original_provider, do: Application.put_env(:eclaw, :provider, original_provider), else: Application.delete_env(:eclaw, :provider)
    end)

    :ok
  end

  # ── model/0 ────────────────────────────────────────────────────────

  describe "model/0" do
    test "returns default model when not configured" do
      Application.delete_env(:eclaw, :model)
      assert Config.model() == "claude-sonnet-4-20250514"
    end

    test "returns configured model" do
      Application.put_env(:eclaw, :model, "gpt-4o")
      assert Config.model() == "gpt-4o"
    end
  end

  # ── max_tokens/0 ───────────────────────────────────────────────────

  describe "max_tokens/0" do
    test "returns default max_tokens when not configured" do
      Application.delete_env(:eclaw, :max_tokens)
      assert Config.max_tokens() == 8192
    end

    test "returns configured max_tokens" do
      Application.put_env(:eclaw, :max_tokens, 4096)
      assert Config.max_tokens() == 4096
    end
  end

  # ── max_iterations/0 ───────────────────────────────────────────────

  describe "max_iterations/0" do
    test "returns default max_iterations when not configured" do
      Application.delete_env(:eclaw, :max_iterations)
      assert Config.max_iterations() == 25
    end

    test "returns configured max_iterations" do
      Application.put_env(:eclaw, :max_iterations, 50)
      assert Config.max_iterations() == 50
    end
  end

  # ── command_timeout/0 ──────────────────────────────────────────────

  describe "command_timeout/0" do
    test "returns default command_timeout when not configured" do
      Application.delete_env(:eclaw, :command_timeout)
      assert Config.command_timeout() == 30_000
    end

    test "returns configured command_timeout" do
      Application.put_env(:eclaw, :command_timeout, 60_000)
      assert Config.command_timeout() == 60_000
    end
  end

  # ── provider/0 ─────────────────────────────────────────────────────

  describe "provider/0" do
    test "returns default provider when not configured" do
      Application.delete_env(:eclaw, :provider)
      assert Config.provider() == :anthropic
    end

    test "returns configured provider" do
      Application.put_env(:eclaw, :provider, :openai)
      assert Config.provider() == :openai
    end
  end

  # ── api_url/0 ──────────────────────────────────────────────────────

  describe "api_url/0" do
    test "returns default api_url" do
      Application.delete_env(:eclaw, :api_url)
      assert Config.api_url() == "https://api.anthropic.com/v1/messages"
    end
  end

  # ── anthropic_version/0 ────────────────────────────────────────────

  describe "anthropic_version/0" do
    test "returns default anthropic_version" do
      Application.delete_env(:eclaw, :anthropic_version)
      assert Config.anthropic_version() == "2023-06-01"
    end
  end

  # ── get/2 ──────────────────────────────────────────────────────────

  describe "get/2" do
    test "returns default when key not set" do
      Application.delete_env(:eclaw, :nonexistent_key_test)
      assert Config.get(:nonexistent_key_test, "default_val") == "default_val"
    end

    test "returns configured value when set" do
      Application.put_env(:eclaw, :test_config_key, "configured_val")
      assert Config.get(:test_config_key, "default") == "configured_val"
      Application.delete_env(:eclaw, :test_config_key)
    end
  end

  # ── system_prompt/0 ────────────────────────────────────────────────

  describe "system_prompt/0" do
    test "returns a non-empty string" do
      prompt = Config.system_prompt()
      assert is_binary(prompt)
    end

    test "returns override when system_prompt config is set" do
      original = Application.get_env(:eclaw, :system_prompt)

      Application.put_env(:eclaw, :system_prompt, "Custom prompt override")
      assert Config.system_prompt() == "Custom prompt override"

      if original do
        Application.put_env(:eclaw, :system_prompt, original)
      else
        Application.delete_env(:eclaw, :system_prompt)
      end
    end
  end
end
