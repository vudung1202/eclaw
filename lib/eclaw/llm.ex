defmodule Eclaw.LLM do
  @moduledoc """
  Facade module for LLM calls.

  Delegates to the actual provider (Anthropic, OpenAI, etc.) based on config.
  Merges built-in tools with plugin tools from ToolRegistry.
  """

  require Logger

  alias Eclaw.Config

  # ── Model → Provider mapping ────────────────────────────────────

  @model_prefixes [
    {"claude", :anthropic},
    {"gpt", :openai},
    {"o1", :openai},
    {"o3", :openai},
    {"o4", :openai},
    {"gemini", :gemini}
  ]

  # ── Model pricing (per 1M tokens) ──────────────────────────────

  @pricing %{
    # Anthropic
    "claude-opus-4-20250514" => %{input: 15.0, output: 75.0},
    "claude-sonnet-4-20250514" => %{input: 3.0, output: 15.0},
    "claude-haiku-4-20250514" => %{input: 0.80, output: 4.0},
    # OpenAI
    "gpt-4o" => %{input: 2.50, output: 10.0},
    "gpt-4o-mini" => %{input: 0.15, output: 0.60},
    "gpt-4-turbo" => %{input: 10.0, output: 30.0},
    "o1" => %{input: 15.0, output: 60.0},
    "o3-mini" => %{input: 1.10, output: 4.40},
    # Google
    "gemini-2.0-flash" => %{input: 0.10, output: 0.40},
    "gemini-2.5-pro" => %{input: 1.25, output: 10.0}
  }

  # ── Built-in Tool Definitions ─────────────────────────────────────

  @builtin_tools [
    %{
      "name" => "execute_bash",
      "description" =>
        "Execute a bash command on the local system and return its stdout/stderr output. " <>
          "Use this for running terminal commands like ls, cat, grep, git, etc.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "string",
            "description" => "The bash command to execute"
          }
        },
        "required" => ["command"]
      }
    },
    %{
      "name" => "read_file",
      "description" =>
        "Read the full contents of a file at the given path. " <>
          "Returns the file content as a string, or an error message if the file cannot be read.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Absolute or relative path to the file to read"
          }
        },
        "required" => ["path"]
      }
    },
    %{
      "name" => "write_file",
      "description" =>
        "Write content to a file at the given path. Creates the file if it doesn't exist, " <>
          "overwrites if it does. Creates parent directories automatically.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Absolute or relative path to the file to write"
          },
          "content" => %{
            "type" => "string",
            "description" => "The content to write to the file"
          }
        },
        "required" => ["path", "content"]
      }
    },
    %{
      "name" => "list_directory",
      "description" =>
        "List all files and directories at the given path. " <>
          "Returns entries with type indicators: [dir] for directories, [file] for files.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Path to the directory to list. Defaults to current directory."
          }
        },
        "required" => ["path"]
      }
    },
    %{
      "name" => "search_files",
      "description" =>
        "Search for a pattern (regex or literal) in files within a directory. " <>
          "Similar to grep -rn. Returns matching lines with file path and line number.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{
            "type" => "string",
            "description" => "The search pattern (supports Elixir regex)"
          },
          "path" => %{
            "type" => "string",
            "description" => "Directory to search in. Defaults to current directory."
          },
          "glob" => %{
            "type" => "string",
            "description" => "File glob pattern to filter, e.g. \"*.ex\", \"*.md\". Defaults to all files."
          }
        },
        "required" => ["pattern", "path"]
      }
    },
    %{
      "name" => "web_fetch",
      "description" =>
        "Fetch the content of a web page URL. Returns the text content (HTML tags stripped). " <>
          "Use this to read web pages, API endpoints, documentation, etc. " <>
          "NOTE: Cannot render JavaScript. For pages that load data dynamically " <>
          "(e.g. gold prices, stock prices, SPAs), use browser_navigate instead.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "url" => %{
            "type" => "string",
            "description" => "The URL to fetch (must start with http:// or https://)"
          }
        },
        "required" => ["url"]
      }
    },
    %{
      "name" => "web_search",
      "description" =>
        "Search the web using DuckDuckGo and return results. " <>
          "Use this for real-time information: prices, news, weather, current events, etc.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "The search query"
          }
        },
        "required" => ["query"]
      }
    },
    %{
      "name" => "store_memory",
      "description" =>
        "Save important information to persistent memory for future sessions. " <>
          "Use this to remember user preferences, contacts, personal info, nicknames, etc. " <>
          "Examples: 'wife is Thao Phuong on Messenger', 'user prefers Vietnamese', 'default warehouse is HCM'.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "key" => %{
            "type" => "string",
            "description" => "Short identifier for this memory (e.g. 'wife_contact', 'language_pref')"
          },
          "content" => %{
            "type" => "string",
            "description" => "The information to remember"
          },
          "type" => %{
            "type" => "string",
            "enum" => ["fact", "preference", "context"],
            "description" => "Memory type: fact (contacts, names), preference (settings), context (situational)"
          }
        },
        "required" => ["key", "content"]
      }
    },
    %{
      "name" => "recall_memory",
      "description" =>
        "Search persistent memory for previously stored information. " <>
          "Use this to look up user contacts, preferences, or any previously saved facts.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "Search query (e.g. 'wife', 'messenger contact', 'language')"
          }
        },
        "required" => ["query"]
      }
    }
  ]

  # ── Provider mapping ──────────────────────────────────────────────

  @providers %{
    anthropic: Eclaw.Providers.Anthropic,
    openai: Eclaw.Providers.OpenAI,
    gemini: Eclaw.Providers.Gemini
  }

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Send messages to LLM (non-streaming).

  Options:
  - `:model` — override model (auto-detects provider from model name)
  - `:provider` — override provider explicitly
  """
  @spec chat(list(map()), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def chat(messages, system, opts \\ []) do
    {provider, provider_opts} = resolve_provider(opts)
    tools = all_tools()
    provider.chat(messages, system, tools, provider_opts)
  end

  @doc "Send messages with streaming. Accepts same opts as chat/3."
  @spec stream(list(map()), String.t(), function(), keyword()) :: {:ok, map()} | {:error, term()}
  def stream(messages, system, on_chunk, opts \\ []) do
    {provider, provider_opts} = resolve_provider(opts)
    tools = all_tools()
    provider.stream(messages, system, tools, on_chunk, provider_opts)
  end

  @doc "Calculate cost in USD for given token counts and model."
  @spec calculate_cost(non_neg_integer(), non_neg_integer(), String.t()) :: float()
  def calculate_cost(input_tokens, output_tokens, model) do
    pricing = find_pricing(model)
    input_tokens / 1_000_000 * pricing.input + output_tokens / 1_000_000 * pricing.output
  end

  @doc "Get pricing info for a model."
  @spec pricing_for(String.t()) :: %{input: float(), output: float()}
  def pricing_for(model), do: find_pricing(model)

  @doc "Detect provider from model name."
  @spec detect_provider(String.t()) :: atom() | nil
  def detect_provider(model) do
    Enum.find_value(@model_prefixes, fn {prefix, provider} ->
      if String.starts_with?(model, prefix), do: provider
    end)
  end

  @doc "Return all tool definitions (built-in + plugins). Cached for 5 seconds."
  @spec all_tools() :: [map()]
  def all_tools do
    case Process.get(:eclaw_tools_cache) do
      {tools, expires_at} when is_list(tools) ->
        if System.monotonic_time(:millisecond) < expires_at do
          tools
        else
          fetch_and_cache_tools()
        end

      _ ->
        fetch_and_cache_tools()
    end
  end

  @doc "Invalidate the cached tool definitions."
  @spec invalidate_tools_cache() :: :ok
  def invalidate_tools_cache do
    Process.delete(:eclaw_tools_cache)
    :ok
  end

  defp fetch_and_cache_tools do
    plugin_tools =
      try do
        Eclaw.ToolRegistry.tool_definitions()
      catch
        :exit, _ -> []
      end

    tools = @builtin_tools ++ plugin_tools
    expires_at = System.monotonic_time(:millisecond) + 5_000
    Process.put(:eclaw_tools_cache, {tools, expires_at})
    tools
  end

  @doc "Return list of built-in tools."
  @spec builtin_tools() :: [map()]
  def builtin_tools, do: @builtin_tools

  @doc "Validate that an API key is available for the given provider."
  @spec validate_api_key(atom() | nil) :: :ok | {:error, String.t()}
  def validate_api_key(provider) do
    case try_resolve_api_key(provider || :anthropic) do
      nil -> {:error, "No API key found for provider #{provider}. Set the appropriate env var."}
      _ -> :ok
    end
  end

  @doc "List supported models with pricing."
  @spec supported_models() :: map()
  def supported_models, do: @pricing

  # ── Private ────────────────────────────────────────────────────────

  defp resolve_provider(overrides) do
    model = Keyword.get(overrides, :model) || Config.model()
    provider_name = Keyword.get(overrides, :provider) || detect_provider(model) || Config.get(:provider, :anthropic)
    provider_module = Map.get(@providers, provider_name, Eclaw.Providers.Anthropic)

    # Resolve API key based on provider
    api_key = resolve_api_key(provider_name)

    base_opts = [
      api_key: api_key,
      model: model,
      max_tokens: Config.max_tokens()
    ]

    # Only pass api_url for Anthropic — other providers use their own default URLs
    opts =
      if provider_name == :anthropic do
        base_opts ++ [api_url: Config.api_url()]
      else
        base_opts
      end

    {provider_module, opts}
  end

  defp resolve_api_key(provider) do
    case try_resolve_api_key(provider) do
      nil -> Config.api_key!()
      key -> key
    end
  end

  defp try_resolve_api_key(:openai), do: System.get_env("OPENAI_API_KEY") || Config.get(:openai_api_key, nil)
  defp try_resolve_api_key(:gemini), do: System.get_env("GEMINI_API_KEY") || Config.get(:gemini_api_key, nil)
  defp try_resolve_api_key(:anthropic), do: System.get_env("ANTHROPIC_API_KEY") || Config.get(:anthropic_api_key, nil)
  defp try_resolve_api_key(_), do: nil

  defp find_pricing(model) do
    # Exact match first, then prefix match
    Map.get_lazy(@pricing, model, fn ->
      Enum.find_value(@pricing, %{input: 3.0, output: 15.0}, fn {key, pricing} ->
        if String.starts_with?(model, key), do: pricing
      end)
    end)
  end
end
