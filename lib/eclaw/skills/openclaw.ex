defmodule Eclaw.Skills.OpenClaw do
  @moduledoc """
  OpenClaw skill discovery and loading.

  Manages local clones of:
  - `openclaw/skills` — actual skill definitions (SKILL.md files)
  - `VoltAgent/awesome-openclaw-skills` — curated index (5,400+ skills in 30 categories)

  Flow:
  1. `sync/0` clones or pulls both repos to ~/.eclaw/openclaw/
  2. `build_index/0` parses category .md files → ETS-backed search index
  3. `search/1` finds skills by keyword matching against name + description
  4. `load_skill/2` reads the actual SKILL.md content from openclaw/skills
  """

  use GenServer
  require Logger

  @base_dir Path.expand("~/.eclaw/openclaw")
  @skills_repo "https://github.com/openclaw/skills.git"
  @awesome_repo "https://github.com/VoltAgent/awesome-openclaw-skills.git"
  @skills_dir Path.join(@base_dir, "skills")
  @awesome_dir Path.join(@base_dir, "awesome")
  @index_table :eclaw_openclaw_index

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Clone or pull both repos. Returns :ok or {:error, reason}."
  @spec sync() :: :ok | {:error, term()}
  def sync do
    GenServer.call(__MODULE__, :sync, 120_000)
  end

  @doc "Build/rebuild ETS index from awesome-openclaw-skills category files."
  @spec build_index() :: {:ok, non_neg_integer()}
  def build_index do
    GenServer.call(__MODULE__, :build_index, 30_000)
  end

  @doc "Search skills by keyword. Returns up to `limit` results."
  @spec search(String.t(), keyword()) :: [map()]
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    category = Keyword.get(opts, :category, nil)
    do_search(query, limit, category)
  end

  @doc "Load a skill's SKILL.md content by author and slug."
  @spec load_skill(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_skill(author, slug) do
    path = Path.join([@skills_dir, "skills", author, slug, "SKILL.md"])

    case File.read(path) do
      {:ok, raw} ->
        {meta, content} = parse_skill_md(raw)

        {:ok,
         %{
           author: author,
           slug: slug,
           name: meta["name"] || slug,
           description: meta["description"] || "",
           content: String.trim(content),
           path: path
         }}

      {:error, reason} ->
        {:error, "Cannot read skill #{author}/#{slug}: #{inspect(reason)}"}
    end
  end

  @doc "List available categories."
  @spec categories() :: [String.t()]
  def categories do
    dir = Path.join(@awesome_dir, "categories")

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(&String.trim_trailing(&1, ".md"))
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  @doc "Check if repos are cloned and index is built."
  @spec status() :: map()
  def status do
    %{
      repos_cloned: File.dir?(@skills_dir) and File.dir?(@awesome_dir),
      index_size: if(:ets.whereis(@index_table) != :undefined, do: :ets.info(@index_table, :size), else: 0),
      skills_dir: @skills_dir,
      awesome_dir: @awesome_dir
    }
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    # Create ETS table for the skill index
    :ets.new(@index_table, [:named_table, :bag, :public, read_concurrency: true])

    # Auto-sync in background: clone if missing, build index
    Task.Supervisor.start_child(Eclaw.TaskSupervisor, fn ->
      if File.dir?(@awesome_dir) and File.dir?(Path.join(@skills_dir, ".git")) do
        # Repos already cloned — just build index
        count = do_build_index()
        Logger.info("[OpenClaw] Index loaded: #{count} skills")
      else
        # First run — clone repos then build index
        Logger.info("[OpenClaw] First run — cloning skill repos in background...")

        case do_sync() do
          :ok ->
            count = do_build_index()
            Logger.info("[OpenClaw] Sync complete. Index: #{count} skills")

          {:error, reason} ->
            Logger.error("[OpenClaw] Auto-sync failed: #{inspect(reason)}")
        end
      end
    end)

    {:ok, %{syncing: false}}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    result = do_sync()

    case result do
      :ok ->
        count = do_build_index()
        Logger.info("[OpenClaw] Sync complete. Index: #{count} skills")
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:build_index, _from, state) do
    count = do_build_index()
    {:reply, {:ok, count}, state}
  end

  # ── Sync ───────────────────────────────────────────────────────────

  defp do_sync do
    File.mkdir_p!(@base_dir)

    # Sync both repos in parallel — they are independent
    tasks = [
      Task.async(fn -> sync_repo(@skills_repo, @skills_dir, depth: 1) end),
      Task.async(fn -> sync_repo(@awesome_repo, @awesome_dir) end)
    ]

    results = Task.await_many(tasks, 120_000)

    case Enum.find(results, &(&1 != :ok)) do
      nil -> :ok
      error -> error
    end
  end

  defp sync_repo(url, dir, opts \\ []) do
    if File.dir?(Path.join(dir, ".git")) do
      Logger.info("[OpenClaw] Pulling #{Path.basename(dir)}...")

      case System.cmd("git", ["-C", dir, "pull", "--ff-only"], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, _} -> {:error, "git pull failed: #{output}"}
      end
    else
      Logger.info("[OpenClaw] Cloning #{url}...")
      args = ["clone"] ++ if(opts[:depth], do: ["--depth", "#{opts[:depth]}"], else: []) ++ [url, dir]

      case System.cmd("git", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, _} -> {:error, "git clone failed: #{output}"}
      end
    end
  end

  # ── Index Building ─────────────────────────────────────────────────

  defp do_build_index do
    :ets.delete_all_objects(@index_table)

    categories_dir = Path.join(@awesome_dir, "categories")

    if File.dir?(categories_dir) do
      categories_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.each(fn file ->
        category = String.trim_trailing(file, ".md")
        path = Path.join(categories_dir, file)
        parse_category_file(category, path)
      end)

      :ets.info(@index_table, :size)
    else
      Logger.warning("[OpenClaw] Categories directory not found: #{categories_dir}")
      0
    end
  end

  defp parse_category_file(category, path) do
    case File.read(path) do
      {:ok, content} ->
        # Each skill entry: - [name](https://github.com/openclaw/skills/tree/main/skills/author/slug/SKILL.md) - Description
        ~r/^-\s+\[([^\]]+)\]\(https:\/\/github\.com\/openclaw\/skills\/tree\/main\/skills\/([^\/]+)\/([^\/)]+)(?:\/SKILL\.md)?\)\s*-?\s*(.*)/m
        |> Regex.scan(content)
        |> Enum.each(fn
          [_, name, author, slug, description] ->
            entry = %{
              name: String.trim(name),
              author: String.trim(author),
              slug: String.trim(slug),
              description: String.trim(description),
              category: category
            }

            :ets.insert(@index_table, {category, entry})

          _ ->
            :ok
        end)

      {:error, reason} ->
        Logger.warning("[OpenClaw] Failed to read #{path}: #{inspect(reason)}")
    end
  end

  # ── Search ─────────────────────────────────────────────────────────

  defp do_search(query, limit, category_filter) do
    query_lower = String.downcase(query)
    query_words = query_lower |> String.split(~r/[\s,\.\-_]+/) |> Enum.reject(&(&1 == ""))

    # Use ets.foldl to score entries in-place instead of copying entire table with tab2list
    scored =
      if category_filter do
        :ets.lookup(@index_table, category_filter)
        |> Enum.reduce([], fn {_, entry}, acc ->
          case score_entry(entry, query_lower, query_words) do
            0 -> acc
            score -> [{entry, score} | acc]
          end
        end)
      else
        :ets.foldl(
          fn {_, entry}, acc ->
            case score_entry(entry, query_lower, query_words) do
              0 -> acc
              score -> [{entry, score} | acc]
            end
          end,
          [],
          @index_table
        )
      end

    scored
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {entry, score} -> Map.put(entry, :score, score) end)
  end

  defp score_entry(entry, query_lower, query_words) do
    name_lower = String.downcase(entry.name)
    desc_lower = String.downcase(entry.description)
    slug_lower = String.downcase(entry.slug)

    # Exact name/slug match (strongest)
    name_exact = if name_lower == query_lower or slug_lower == query_lower, do: 10, else: 0

    # Name contains query
    name_contains = if String.contains?(name_lower, query_lower), do: 5, else: 0

    # Word overlap with name + description
    searchable = name_lower <> " " <> desc_lower <> " " <> slug_lower
    word_score = Enum.count(query_words, fn w -> String.contains?(searchable, w) end)

    name_exact + name_contains + word_score
  end

  # ── SKILL.md Parsing ───────────────────────────────────────────────

  defp parse_skill_md(raw) do
    case String.split(raw, ~r/^---\s*$/m, parts: 3) do
      ["", yaml, content] ->
        meta = parse_yaml_simple(yaml)
        {meta, content}

      _ ->
        {%{}, raw}
    end
  end

  defp parse_yaml_simple(yaml) do
    yaml
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      case String.split(line, ~r/:\s*/, parts: 2) do
        [key, value] when key != "" ->
          Map.put(acc, key, String.trim(value))

        _ ->
          acc
      end
    end)
  end
end
