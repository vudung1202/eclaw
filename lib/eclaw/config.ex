defmodule Eclaw.Config do
  @moduledoc """
  Centralized configuration access for the application.

  Priority: env var (runtime.exs) > config.exs > default value.
  """

  @spec model() :: String.t()
  def model, do: get(:model, "claude-sonnet-4-20250514")

  @spec max_tokens() :: pos_integer()
  def max_tokens, do: get(:max_tokens, 8192)

  @spec api_url() :: String.t()
  def api_url, do: get(:api_url, "https://api.anthropic.com/v1/messages")

  @spec anthropic_version() :: String.t()
  def anthropic_version, do: get(:anthropic_version, "2023-06-01")

  @spec max_iterations() :: pos_integer()
  def max_iterations, do: get(:max_iterations, 25)

  @spec system_prompt() :: String.t()
  def system_prompt do
    cwd = File.cwd!()
    workspace = Path.dirname(cwd)

    get(
      :system_prompt,
      """
      You are Eclaw, a versatile AI agent. You have tools available — USE them proactively to answer questions.

      AVAILABLE TOOLS:
      - execute_bash: Run terminal commands (ls, git, grep, curl, etc.)
      - read_file / write_file: Read and write files
      - list_directory / search_files: Explore and search codebases
      - web_fetch: Fetch web pages and APIs — USE THIS for real-time information (prices, news, weather, docs, etc.)
      - browser_* tools: Full browser automation (navigate, screenshot, click, type, evaluate JS) — use when web_fetch isn't enough

      RULES:
      1. LANGUAGE: Always reply in the SAME language as the user. Vietnamese → Vietnamese. English → English.
      2. USE TOOLS: When the user asks about real-time data (prices, news, weather, sports scores, etc.), USE web_fetch to look it up. Do NOT say "I can't access real-time data" — you CAN via web_fetch.
      3. EFFICIENCY: Minimize tool calls. Combine multiple bash commands into ONE call when possible.
      4. NAVIGATION: Projects are in #{workspace}/. Go directly — do NOT list directories to search.
      5. GIT: Use `gh pr list`, `gh pr view` for PRs. Use `git log --oneline -10` for history. Always `cd` to the project first.
      6. SAFETY: NEVER run git init, rm -rf, or any destructive command.
      7. CONCISE: Give short, direct answers. No unnecessary explanations or suggestions.

      Current working directory: #{cwd}
      Workspace: #{workspace}
      """
    )
  end

  @spec command_timeout() :: pos_integer()
  def command_timeout, do: get(:command_timeout, 30_000)

  @spec provider() :: atom()
  def provider, do: get(:provider, :anthropic)

  @spec api_key!() :: String.t()
  def api_key! do
    provider_key =
      case provider() do
        :anthropic -> get(:anthropic_api_key, nil)
        :openai -> get(:openai_api_key, nil)
        :gemini -> get(:gemini_api_key, nil)
        _ -> nil
      end

    case provider_key do
      nil ->
        raise """
        Missing API key for provider #{provider()}.

        Set it via environment variable:
            export ANTHROPIC_API_KEY="sk-ant-..."
            # or
            export OPENAI_API_KEY="sk-..."
            # or
            export GEMINI_API_KEY="AI..."
        """

      key ->
        key
    end
  end

  @doc "Generic config accessor."
  @spec get(atom(), term()) :: term()
  def get(key, default) do
    Application.get_env(:eclaw, key, default)
  end
end
