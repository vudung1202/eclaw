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

  @custom_prompt_path Path.expand("~/.eclaw/system_prompt.md")

  @spec system_prompt() :: String.t()
  def system_prompt do
    cwd = File.cwd!()
    workspace = Path.dirname(cwd)

    # Priority: env var > template file + custom file
    case get(:system_prompt, nil) do
      nil ->
        template = load_prompt_file(template_prompt_path(), "")
        custom = load_prompt_file(@custom_prompt_path, "")

        (template <> "\n\n" <> custom)
        |> String.replace("{{cwd}}", cwd)
        |> String.replace("{{workspace}}", workspace)
        |> String.trim()

      override ->
        override
    end
  end

  defp template_prompt_path do
    case :code.priv_dir(:eclaw) do
      {:error, _} -> Path.join(File.cwd!(), "priv/system_prompt.md")
      dir -> Path.join(List.to_string(dir), "system_prompt.md")
    end
  end

  defp load_prompt_file(path, default) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> default
    end
  end

  @spec command_timeout() :: pos_integer()
  def command_timeout, do: get(:command_timeout, 30_000)

  @spec cache_ttl_web_fetch() :: pos_integer()
  def cache_ttl_web_fetch, do: get(:cache_ttl_web_fetch, 300_000)

  @spec cache_ttl_web_search() :: pos_integer()
  def cache_ttl_web_search, do: get(:cache_ttl_web_search, 600_000)

  @spec routing_enabled() :: boolean()
  def routing_enabled, do: get(:routing_enabled, false)

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
