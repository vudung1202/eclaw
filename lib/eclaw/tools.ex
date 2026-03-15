defmodule Eclaw.Tools do
  @moduledoc """
  Execute tools on the operating system.

  Each tool returns a result string (or error message).
  Long tool results are automatically truncated via `Eclaw.Context`.
  Commands and paths are validated via `Eclaw.Security`.
  """

  require Logger

  alias Eclaw.{Cache, Config, Context, Security}

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Dispatch and execute tool by name.

  The optional `context` map may contain:
  - `:approval_callback` — `fn command, reason -> boolean()` for channel-aware approval
    Defaults to CLI IO.gets approval if not provided.
  """
  @spec execute(String.t(), map(), map()) :: String.t()
  def execute(tool_name, input, context \\ %{})

  def execute("execute_bash", %{"command" => command}, ctx), do: execute_bash(command, ctx)
  def execute("read_file", %{"path" => path}, _ctx), do: read_file(path)
  def execute("write_file", %{"path" => path, "content" => content}, _ctx), do: write_file(path, content)
  def execute("list_directory", %{"path" => path}, _ctx), do: list_directory(path)
  def execute("search_files", input, _ctx), do: search_files(input)
  def execute("web_fetch", %{"url" => url}, _ctx), do: web_fetch(url)
  def execute("web_search", %{"query" => query}, _ctx), do: web_search(query)
  def execute("store_memory", input, _ctx), do: store_memory(input)
  def execute("recall_memory", %{"query" => query}, _ctx), do: recall_memory(query)

  def execute(tool_name, input, _ctx) do
    # Fallback: try plugin registry
    case Eclaw.ToolRegistry.execute(tool_name, input) do
      {:ok, result} -> result
      {:error, reason} -> "Plugin error: #{reason}"
      nil -> "Error: Unknown tool '#{tool_name}'"
    end
  end

  # ── execute_bash ──────────────────────────────────────────────────

  @spec execute_bash(String.t(), map()) :: String.t()
  def execute_bash(command, context \\ %{}) do
    case Security.validate_command(command) do
      {:error, reason} ->
        Logger.warning("[Eclaw.Tools] Command blocked: #{reason}")
        "Security error: #{reason}"

      {:blocked, reason} ->
        Logger.warning("[Eclaw.Tools] Command permanently blocked: #{reason}")
        "Security error: #{reason}"

      {:needs_approval, reason} ->
        Logger.warning("[Eclaw.Tools] Command needs approval: #{reason}")
        approved = request_approval(command, reason, context)

        if approved do
          Logger.info("[Eclaw.Tools] Command approved by user")
          do_execute_bash(command)
        else
          Logger.info("[Eclaw.Tools] Command rejected by user")
          "Command rejected by user: #{reason}. The user declined to execute this command."
        end

      :ok ->
        do_execute_bash(command)
    end
  end

  # Use channel-specific approval callback, or fall back to CLI IO.gets
  defp request_approval(command, reason, %{approval_callback: callback}) when is_function(callback, 2) do
    callback.(command, reason)
  end

  defp request_approval(_command, _reason, _context) do
    # This runs inside a Task (not the Agent GenServer), so we can't check Process identity.
    # Without an explicit approval_callback, deny by default for safety.
    Logger.warning("[Eclaw.Tools] No approval callback provided, denying command")
    false
  end

  # Only these environment variables are passed to bash commands (allowlist approach).
  # Everything else (API keys, tokens, secrets) is stripped automatically.
  @safe_env_vars ~w(
    PATH HOME USER LANG LC_ALL LC_CTYPE TERM SHELL TMPDIR
    EDITOR VISUAL PAGER COLORTERM FORCE_COLOR NO_COLOR
    XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR
    NODE_PATH GOPATH CARGO_HOME RUSTUP_HOME MIX_ENV
    HEX_HOME
  )

  defp do_execute_bash(command) do
    timeout = Config.command_timeout()
    Logger.info("[Eclaw.Tools] bash: #{redact_secrets(command)}")

    # Build sanitized environment — only pass safe variables (allowlist)
    sanitized_env =
      @safe_env_vars
      |> Enum.map(fn var -> {var, System.get_env(var)} end)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    # Also strip all current env vars not in the allowlist
    all_env_keys = System.get_env() |> Map.keys()
    strip_env = Enum.map(all_env_keys -- @safe_env_vars, fn var -> {var, nil} end)
    sanitized_env = strip_env ++ sanitized_env

    # Run via Task.Supervisor — crash-isolated from Agent GenServer
    task =
      Task.Supervisor.async_nolink(Eclaw.TaskSupervisor, fn ->
        System.cmd("bash", ["-c", command],
          stderr_to_stdout: true,
          env: sanitized_env
        )
      end)

    case Task.yield(task, timeout + 5_000) || Task.shutdown(task) do
      {:ok, {output, exit_code}} ->
        result =
          case exit_code do
            0 ->
              if String.trim(output) == "", do: "(command succeeded with no output)", else: output

            code ->
              "Command exited with code #{code}:\n#{output}"
          end

        Context.truncate_tool_result(result)

      {:exit, reason} ->
        "Error: Command crashed: #{inspect(reason)}"

      nil ->
        "Error: Command timed out after #{div(timeout, 1000)}s"
    end
  end

  # ── read_file ─────────────────────────────────────────────────────

  @spec read_file(String.t()) :: String.t()
  def read_file(path) do
    expanded = Path.expand(path)

    case Security.validate_path(expanded) do
      {:error, reason} ->
        "Security error: #{reason}"

      :ok ->
        Logger.info("[Eclaw.Tools] read: #{expanded}")

        case File.read(expanded) do
          {:ok, content} -> Context.truncate_tool_result(content)
          {:error, :enoent} -> "Error: File not found at '#{expanded}'"
          {:error, :eacces} -> "Error: Permission denied for '#{expanded}'"
          {:error, :eisdir} -> "Error: '#{expanded}' is a directory, not a file"
          {:error, reason} -> "Error reading file: #{inspect(reason)}"
        end
    end
  end

  # ── write_file ────────────────────────────────────────────────────

  @spec write_file(String.t(), String.t()) :: String.t()
  def write_file(path, content) do
    expanded = Path.expand(path)

    case Security.validate_path(expanded) do
      {:error, reason} ->
        "Security error: #{reason}"

      :ok ->
        Logger.info("[Eclaw.Tools] write: #{expanded} (#{byte_size(content)} bytes)")
        dir = Path.dirname(expanded)

        case File.mkdir_p(dir) do
          :ok ->
            case File.write(expanded, content) do
              :ok -> "Successfully wrote #{byte_size(content)} bytes to '#{expanded}'"
              {:error, :eacces} -> "Error: Permission denied for '#{expanded}'"
              {:error, reason} -> "Error writing file: #{inspect(reason)}"
            end

          {:error, reason} ->
            "Error: Cannot create directory '#{dir}': #{inspect(reason)}"
        end
    end
  end

  # ── list_directory ────────────────────────────────────────────────

  @spec list_directory(String.t()) :: String.t()
  def list_directory(path) do
    expanded = Path.expand(path)

    case Security.validate_path(expanded) do
      {:error, reason} ->
        "Security error: #{reason}"

      :ok ->
        list_directory_safe(expanded)
    end
  end

  defp list_directory_safe(expanded) do
    Logger.info("[Eclaw.Tools] ls: #{expanded}")

    case File.ls(expanded) do
      {:ok, entries} ->
        result =
          entries
          |> Enum.sort()
          |> Enum.map(fn entry ->
            full_path = Path.join(expanded, entry)
            type = if File.dir?(full_path), do: "[dir] ", else: "[file]"
            "#{type} #{entry}"
          end)
          |> Enum.join("\n")

        Context.truncate_tool_result(result)

      {:error, :enoent} -> "Error: Directory not found at '#{expanded}'"
      {:error, :enotdir} -> "Error: '#{expanded}' is not a directory"
      {:error, reason} -> "Error listing directory: #{inspect(reason)}"
    end
  end

  # ── search_files ──────────────────────────────────────────────────

  @spec search_files(map()) :: String.t()
  def search_files(%{"pattern" => pattern, "path" => path} = input) do
    expanded = Path.expand(path)

    case Security.validate_path(expanded) do
      {:error, reason} ->
        "Security error: #{reason}"

      :ok ->
        search_files_safe(pattern, expanded, input)
    end
  end

  defp search_files_safe(pattern, expanded, input) do
    glob = Map.get(input, "glob", "**/*")

    # Block path traversal in glob patterns
    if String.contains?(glob, "..") or String.starts_with?(glob, "/") do
      "Security error: Glob pattern must not contain path traversal (..) or absolute paths"
    else
      Logger.info("[Eclaw.Tools] search: '#{pattern}' in #{expanded} (#{glob})")
      do_search_files(pattern, expanded, glob)
    end
  end

  defp do_search_files(pattern, expanded, glob) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        results =
          Path.join(expanded, glob)
          |> Path.wildcard()
          # Filter results to only include files under the validated directory
          # Resolve symlinks to prevent escaping the validated directory via symlinks
          |> Enum.filter(fn path ->
            resolved = Eclaw.Security.resolve_real_path(Path.expand(path))
            resolved == expanded or String.starts_with?(resolved, expanded <> "/")
          end)
          |> Enum.filter(&File.regular?/1)
          |> Enum.flat_map(&search_in_file(&1, regex, expanded))
          |> Enum.take(100)

        result =
          if results == [] do
            "No matches found for '#{pattern}' in #{expanded}"
          else
            count = length(results)
            "Found #{count} match#{if count > 1, do: "es", else: ""}:\n" <> Enum.join(results, "\n")
          end

        Context.truncate_tool_result(result)

      {:error, reason} ->
        "Error: Invalid regex pattern '#{pattern}': #{inspect(reason)}"
    end
  end

  defp search_in_file(file, regex, base_path) do
    relative = Path.relative_to(file, base_path)

    try do
      file
      |> File.stream!()
      |> Stream.with_index(1)
      |> Stream.filter(fn {line, _num} -> Regex.match?(regex, line) end)
      |> Enum.map(fn {line, num} -> "#{relative}:#{num}: #{String.trim(line)}" end)
    rescue
      _ -> []
    end
  end

  # ── web_fetch ───────────────────────────────────────────────────

  @spec web_fetch(String.t()) :: String.t()
  def web_fetch(url) do
    cond do
      not (String.starts_with?(url, "http://") or String.starts_with?(url, "https://")) ->
        "Error: URL must start with http:// or https://"

      not Security.safe_url?(url) ->
        Logger.warning("[Eclaw.Tools] SSRF blocked: #{url}")
        "Security error: Access to internal/private network addresses is blocked"

      true ->
        Cache.get_or_compute({:web_fetch, url}, Config.cache_ttl_web_fetch(), fn ->
          do_web_fetch(url)
        end)
    end
  end

  defp do_web_fetch(url) do
    Logger.info("[Eclaw.Tools] fetch: #{url}")

    task =
      Task.Supervisor.async_nolink(Eclaw.TaskSupervisor, fn ->
        # Disable redirects to prevent SSRF via redirect to internal IPs
        case Req.get(url, receive_timeout: 15_000, redirect: false) do
          {:ok, %{status: status, headers: headers}} when status in [301, 302, 303, 307, 308] ->
            location =
              case get_redirect_location(headers) do
                nil -> nil
                loc -> resolve_redirect(loc, url)
              end

            if location && Security.safe_url?(location) do
              case Req.get(location, receive_timeout: 15_000, redirect: false) do
                {:ok, %{status: 200, body: body}} when is_binary(body) ->
                  body |> process_html_body() |> Context.truncate_tool_result()

                {:ok, %{status: 200, body: body}} when is_map(body) ->
                  body |> Jason.encode!(pretty: true) |> Context.truncate_tool_result()

                {:ok, %{status: s}} ->
                  "Error: HTTP #{s} (after redirect)"

                {:error, reason} ->
                  "Error: #{inspect(reason)}"
              end
            else
              "Security error: Redirect target blocked by SSRF protection"
            end

          {:ok, %{status: 200, body: body}} when is_binary(body) ->
            body |> process_html_body() |> Context.truncate_tool_result()

          {:ok, %{status: 200, body: body}} when is_map(body) ->
            body |> Jason.encode!(pretty: true) |> Context.truncate_tool_result()

          {:ok, %{status: status}} ->
            "Error: HTTP #{status}"

          {:error, reason} ->
            "Error: #{inspect(reason)}"
        end
      end)

    case Task.yield(task, 20_000) || Task.shutdown(task) do
      {:ok, result} -> result
      {:exit, reason} -> "Error: Fetch crashed: #{inspect(reason)}"
      nil -> "Error: Fetch timed out"
    end
  end

  defp get_redirect_location(headers) do
    Enum.find_value(headers, fn
      {"location", [value | _]} when is_binary(value) -> value
      {"location", value} when is_binary(value) -> value
      _ -> nil
    end)
  end

  # Resolve relative redirect URL against the original URL
  defp resolve_redirect(location, original_url) do
    case URI.parse(location) do
      %URI{host: nil} ->
        # Relative URL — resolve against original
        original = URI.parse(original_url)
        URI.to_string(%{original | path: location, query: nil, fragment: nil})

      _ ->
        location
    end
  end

  # ── web_search ──────────────────────────────────────────────────

  @spec web_search(String.t()) :: String.t()
  def web_search(query) do
    Cache.get_or_compute({:web_search, query}, Config.cache_ttl_web_search(), fn ->
      do_web_search(query)
    end)
  end

  defp do_web_search(query) do
    Logger.info("[Eclaw.Tools] search: #{query}")
    encoded_query = URI.encode_www_form(query)
    url = "https://html.duckduckgo.com/html/?q=#{encoded_query}"

    task =
      Task.Supervisor.async_nolink(Eclaw.TaskSupervisor, fn ->
        case Req.get(url,
               receive_timeout: 15_000,
               redirect: true,
               headers: [{"user-agent", "Mozilla/5.0 (compatible; Eclaw/1.0)"}]
             ) do
          {:ok, %{status: 200, body: body}} when is_binary(body) ->
            parse_duckduckgo_results(body)

          {:ok, %{status: status}} ->
            "Error: DuckDuckGo returned HTTP #{status}"

          {:error, reason} ->
            "Error: #{inspect(reason)}"
        end
      end)

    case Task.yield(task, 20_000) || Task.shutdown(task) do
      {:ok, result} -> Context.truncate_tool_result(result)
      {:exit, reason} -> "Error: Search crashed: #{inspect(reason)}"
      nil -> "Error: Search timed out"
    end
  end

  defp parse_duckduckgo_results(html) do
    # DuckDuckGo HTML version uses <a class="result__a"> for titles and
    # <a class="result__snippet"> for snippets
    results =
      Regex.scan(
        ~r/<a[^>]+class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>.*?<a[^>]+class="result__snippet"[^>]*>(.*?)<\/a>/s,
        html
      )
      |> Enum.take(8)
      |> Enum.with_index(1)
      |> Enum.map(fn {[_full, url, title, snippet], idx} ->
        title = title |> strip_tags() |> String.trim()
        snippet = snippet |> strip_tags() |> String.trim()
        url = decode_ddg_url(url)
        "#{idx}. #{title}\n   #{url}\n   #{snippet}"
      end)

    if results == [] do
      "No search results found for: #{html |> strip_tags() |> String.slice(0, 200)}"
    else
      Enum.join(results, "\n\n")
    end
  end

  defp decode_ddg_url(url) do
    # DuckDuckGo wraps URLs in a redirect: //duckduckgo.com/l/?uddg=<encoded_url>&...
    case Regex.run(~r/uddg=([^&]+)/, url) do
      [_, encoded] -> URI.decode_www_form(encoded)
      _ -> url
    end
  end

  defp strip_tags(html) do
    html
    |> String.replace(~r/<b>|<\/b>/, "")
    |> String.replace(~r/<[^>]+>/, "")
    |> decode_html_entities()
  end

  # ── store_memory / recall_memory ─────────────────────────────────

  @spec store_memory(map()) :: String.t()
  def store_memory(%{"key" => key, "content" => content} = input) do
    type =
      case Map.get(input, "type", "fact") do
        "preference" -> :preference
        "context" -> :context
        _ -> :fact
      end

    Logger.info("[Eclaw.Tools] store_memory: #{key} (#{type})")
    Eclaw.Memory.store(key, content, type)
    "Stored in memory: [#{key}] #{content}"
  end

  @spec recall_memory(String.t()) :: String.t()
  def recall_memory(query) do
    Logger.info("[Eclaw.Tools] recall_memory: #{query}")

    case Eclaw.Memory.search(query, limit: 10) do
      [] ->
        "No memories found for: #{query}"

      entries ->
        entries
        |> Enum.map(fn entry ->
          "- [#{entry.type}] #{entry.key}: #{entry.content}"
        end)
        |> Enum.join("\n")
    end
  end

  # Redact potential secrets from log output
  defp redact_secrets(text) do
    text
    |> String.replace(~r/(sk-[a-zA-Z0-9]{10})[a-zA-Z0-9]+/, "\\1***")
    |> String.replace(~r/(Bearer\s+)[^\s"']+/, "\\1[REDACTED]")
    |> String.replace(~r/((?:API_KEY|SECRET|TOKEN|PASSWORD|PASSWD)\s*=\s*)[^\s"']+/i, "\\1[REDACTED]")
  end

  # Process HTML body: strip tags and detect JS-rendered pages with no useful content.
  defp process_html_body(html) do
    stripped = strip_html(html)
    content_len = String.length(String.trim(stripped))
    html_len = String.length(html)

    # If the page had significant HTML but very little text content,
    # it's likely a JS-rendered page (React/Vue/Angular SPA).
    if html_len > 1_000 and content_len < 200 do
      stripped <>
        "\n\n[WARNING: This page appears to load content dynamically via JavaScript. " <>
        "The actual data is not available via web_fetch. " <>
        "Use browser_navigate or browser_evaluate to extract data from JS-rendered pages.]"
    else
      stripped
    end
  end

  # Strip HTML to clean text content.
  # Removes noise elements (nav, header, footer, menus) to minimize token usage.
  defp strip_html(html) do
    html
    # Remove noise elements entirely (non-greedy, dotall)
    |> String.replace(~r/<(script|style|noscript|svg|iframe)[^>]*>.*?<\/\1>/si, "")
    |> String.replace(~r/<(nav|header|footer|aside)[^>]*>.*?<\/\1>/si, "")
    # Remove HTML comments
    |> String.replace(~r/<!--.*?-->/s, "")
    # Preserve table structure: convert cells to tab-separated, rows to newlines
    |> String.replace(~r/<\/t[dh]>/i, "\t")
    |> String.replace(~r/<\/tr>/i, "\n")
    # Preserve line breaks for block elements
    |> String.replace(~r/<\/(p|div|li|h[1-6]|br\s*\/?)>/i, "\n")
    |> String.replace(~r/<br\s*\/?\s*>/i, "\n")
    # Remove remaining tags
    |> String.replace(~r/<[^>]+>/, " ")
    # Decode HTML entities
    |> decode_html_entities()
    # Collapse spaces (but preserve newlines and tabs for table layout)
    |> String.replace(~r/[^\S\n\t]+/, " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # Decode common HTML entities (numeric + named)
  defp decode_html_entities(text) do
    text
    # Numeric entities: &#226; → â
    |> String.replace(~r/&#(\d+);/, &decode_numeric_entity/1)
    # Hex entities: &#x00E2; → â
    |> String.replace(~r/&#x([0-9a-fA-F]+);/, &decode_hex_entity/1)
    # Named entities
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&mdash;", "—")
    |> String.replace("&ndash;", "–")
    |> String.replace("&laquo;", "«")
    |> String.replace("&raquo;", "»")
    |> String.replace("&copy;", "©")
    |> String.replace("&reg;", "®")
    |> String.replace("&trade;", "™")
  end

  defp decode_numeric_entity(match) do
    code = match |> String.trim_leading("&#") |> String.trim_trailing(";")
    <<String.to_integer(code)::utf8>>
  rescue
    _ -> match
  end

  defp decode_hex_entity(match) do
    hex = match |> String.trim_leading("&#x") |> String.trim_trailing(";")
    <<String.to_integer(hex, 16)::utf8>>
  rescue
    _ -> match
  end
end
