defmodule Eclaw.Security do
  @moduledoc """
  Security checks for tool execution.

  - Command validation: blocks dangerous commands
  - Path sanitization: prevents path traversal attacks
  - Input size limits: restricts input size
  """

  import Bitwise

  # Command validation is now handled by Eclaw.Approval module
  # which separates commands into :blocked and :needs_approval categories.

  # Forbidden path patterns
  @forbidden_paths [
    ~r/^\/etc\/shadow$/,
    ~r/^\/etc\/passwd$/,
    ~r/^\/etc\/sudoers/,
    ~r/^\/root\//,
    ~r/\.ssh\/.*private/,
    ~r/\.ssh\/id_/,
    ~r/\.env$/,
    ~r/\.env\.local$/,
    ~r/credentials\.json$/,
    ~r/\/\.aws\//,
    ~r/\/\.gnupg\//,
    ~r/^\/proc\//
  ]

  @max_command_length 10_000
  @max_path_length 4_096

  # Private/internal IP ranges to block (SSRF protection)
  @blocked_ip_ranges [
    {0, 0, 0, 0, 8},
    {127, 0, 0, 0, 8},
    {10, 0, 0, 0, 8},
    {172, 16, 0, 0, 12},
    {192, 168, 0, 0, 16},
    {169, 254, 0, 0, 16},
    {100, 64, 0, 0, 10}
  ]

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Validate bash command before execution.

  Returns:
  - `:ok` — safe to execute
  - `{:error, reason}` — blocked or failed validation
  - `{:needs_approval, reason}` — requires human approval before execution
  """
  @spec validate_command(String.t()) :: :ok | {:error, String.t()} | {:blocked, String.t()} | {:needs_approval, String.t()}
  def validate_command(command) do
    cond do
      String.length(command) > @max_command_length ->
        {:error, "Command too long (max #{@max_command_length} chars)"}

      String.trim(command) == "" ->
        {:error, "Empty command"}

      true ->
        Eclaw.Approval.check_command(command)
    end
  end

  @doc """
  Validate file path before read/write.

  Checks for path traversal and forbidden paths.
  """
  @spec validate_path(String.t()) :: :ok | {:error, String.t()}
  def validate_path(path) do
    expanded = Path.expand(path)

    cond do
      String.length(path) > @max_path_length ->
        {:error, "Path too long (max #{@max_path_length} chars)"}

      path_traversal?(expanded) ->
        {:error, "Path traversal detected"}

      forbidden_path?(resolve_real_path(expanded)) ->
        {:error, "Access to '#{expanded}' is restricted by security policy"}

      true ->
        :ok
    end
  end

  @doc "Check if URL is safe (not targeting internal/private networks)."
  @spec safe_url?(String.t()) :: boolean()
  def safe_url?(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        host_lower = String.downcase(host)

        cond do
          internal_host?(host_lower) -> false
          internal_ip?(host_lower) -> false
          # DNS resolution check: resolve hostname and verify the IP is not internal
          resolves_to_internal?(host_lower) -> false
          true -> true
        end

      _ ->
        false
    end
  end

  # ── Private ────────────────────────────────────────────────────────

  defp internal_host?(host) do
    host == "localhost" or
      host == "metadata.google.internal" or
      String.ends_with?(host, ".local") or
      String.ends_with?(host, ".internal")
  end

  defp internal_ip?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {a, b, c, d}} ->
        ipv4_blocked?({a, b, c, d})

      {:ok, ipv6} ->
        ipv6_blocked?(ipv6)

      _ ->
        false
    end
  end

  defp ipv4_blocked?({a, b, c, d}) do
    Enum.any?(@blocked_ip_ranges, fn {na, nb, nc, nd, prefix_len} ->
      ip_in_cidr?({a, b, c, d}, {na, nb, nc, nd}, prefix_len)
    end)
  end

  defp ipv6_blocked?({0, 0, 0, 0, 0, 0, 0, 1}), do: true  # ::1 loopback

  defp ipv6_blocked?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}) do
    # IPv6-mapped IPv4 — extract and check the IPv4 address
    a = hi >>> 8
    b = hi &&& 0xFF
    c = lo >>> 8
    d = lo &&& 0xFF
    ipv4_blocked?({a, b, c, d})
  end

  defp ipv6_blocked?({w1, _, _, _, _, _, _, _}) do
    # fe80::/10 — link-local
    (w1 &&& 0xFFC0) == 0xFE80 or
    # fc00::/7 — unique local address
    (w1 &&& 0xFE00) == 0xFC00 or
    # ff00::/8 — multicast
    (w1 &&& 0xFF00) == 0xFF00
  end

  # Resolve hostname via DNS and check if the resolved IP is internal
  defp resolves_to_internal?(host) do
    case :inet.getaddr(String.to_charlist(host), :inet) do
      {:ok, {a, b, c, d}} ->
        ipv4_blocked?({a, b, c, d})

      _ ->
        # Also check IPv6 resolution
        case :inet.getaddr(String.to_charlist(host), :inet6) do
          {:ok, ipv6} -> ipv6_blocked?(ipv6)
          _ -> false
        end
    end
  end

  defp ip_in_cidr?({a, b, c, d}, {na, nb, nc, nd}, prefix_len) do
    ip = (a <<< 24) + (b <<< 16) + (c <<< 8) + d
    net = (na <<< 24) + (nb <<< 16) + (nc <<< 8) + nd
    mask = ~~~((1 <<< (32 - prefix_len)) - 1) &&& 0xFFFFFFFF
    (ip &&& mask) == (net &&& mask)
  end

  defp path_traversal?(expanded) do
    # Resolve symlinks to get the real path for the prefix check
    real =
      try do
        resolve_real_path(expanded)
      rescue
        _ -> expanded
      end
    cwd = File.cwd!()
    home = System.user_home!()
    tmp = System.tmp_dir!()

    # Allow: cwd (project), ~/.eclaw (data), /tmp (temp files)
    safe_prefixes = [cwd, Path.join(home, ".eclaw"), tmp]

    not Enum.any?(safe_prefixes, fn prefix ->
      real == prefix or String.starts_with?(real, prefix <> "/")
    end)
  end

  @max_symlink_depth 20

  # Resolve all symlinks in the path (including parent directories).
  # Falls back to the expanded path if the file doesn't exist yet.
  # Public so it can be used by tools for glob result filtering.
  @doc false
  def resolve_real_path(path) do
    parts = Path.split(path)
    resolve_path_components(parts, "", 0)
  end

  defp resolve_path_components([], acc, _depth), do: acc

  defp resolve_path_components(_parts, _acc, depth) when depth >= @max_symlink_depth do
    # Prevent infinite symlink loops
    raise "Symlink resolution exceeded maximum depth of #{@max_symlink_depth}"
  end

  defp resolve_path_components([part | rest], acc, depth) do
    current = if acc == "", do: part, else: Path.join(acc, part)

    resolved =
      case :file.read_link_info(String.to_charlist(current)) do
        {:ok, {:file_info, _, :symlink, _, _, _, _, _, _, _, _, _, _, _}} ->
          case :file.read_link(String.to_charlist(current)) do
            {:ok, target} ->
              target_path = List.to_string(target)

              if Path.type(target_path) == :relative do
                current |> Path.dirname() |> Path.join(target_path) |> Path.expand()
              else
                Path.expand(target_path)
              end

            _ ->
              current
          end

        _ ->
          current
      end

    resolve_path_components(rest, resolved, depth + 1)
  end

  defp forbidden_path?(expanded_path) do
    Enum.any?(@forbidden_paths, &Regex.match?(&1, expanded_path))
  end
end
