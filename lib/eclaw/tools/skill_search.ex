defmodule Eclaw.Tools.SkillSearch do
  @moduledoc """
  Tool for the agent to search and activate OpenClaw skills.

  Actions:
  - search: Find skills by keyword
  - load: Load a specific skill's instructions
  - categories: List available skill categories
  - sync: Update skill repositories
  - status: Check skill system status
  """

  @behaviour Eclaw.ToolBehaviour

  require Logger

  alias Eclaw.Skills.OpenClaw

  @impl true
  def name, do: "skill_search"

  @impl true
  def description do
    "Search and load skills from OpenClaw registry (5,400+ skills). " <>
      "Use 'search' to find skills by keyword, 'load' to get skill instructions, " <>
      "'categories' to list skill categories, 'sync' to update repos."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["search", "load", "categories", "sync", "status"],
          "description" => "Action to perform"
        },
        "query" => %{
          "type" => "string",
          "description" => "Search query (for 'search' action)"
        },
        "author" => %{
          "type" => "string",
          "description" => "Skill author (for 'load' action)"
        },
        "slug" => %{
          "type" => "string",
          "description" => "Skill slug/name (for 'load' action)"
        },
        "category" => %{
          "type" => "string",
          "description" => "Filter by category (for 'search' action)"
        },
        "limit" => %{
          "type" => "integer",
          "description" => "Max results (default 10, for 'search' action)"
        }
      },
      "required" => ["action"]
    }
  end

  @impl true
  def execute(%{"action" => "search"} = input) do
    query = input["query"] || ""

    if query == "" do
      {:error, "Missing 'query' for search action"}
    else
      opts = []
      opts = if input["category"], do: [{:category, input["category"]} | opts], else: opts
      opts = if input["limit"], do: [{:limit, input["limit"]} | opts], else: opts

      results = OpenClaw.search(query, opts)

      if results == [] do
        {:ok, "No skills found for '#{query}'. Try different keywords or run 'sync' first."}
      else
        lines =
          Enum.map_join(results, "\n", fn skill ->
            "- #{skill.name} (#{skill.author}/#{skill.slug}) [#{skill.category}] — #{skill.description}"
          end)

        {:ok, "Found #{length(results)} skill(s):\n#{lines}"}
      end
    end
  end

  def execute(%{"action" => "load", "author" => author, "slug" => slug})
      when is_binary(author) and is_binary(slug) do
    case OpenClaw.load_skill(author, slug) do
      {:ok, skill} ->
        {:ok, "# Skill: #{skill.name}\n**Author:** #{skill.author}\n**Description:** #{skill.description}\n\n---\n\n#{skill.content}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(%{"action" => "load"}) do
    {:error, "Missing 'author' and 'slug' for load action"}
  end

  def execute(%{"action" => "categories"}) do
    cats = OpenClaw.categories()

    if cats == [] do
      {:ok, "No categories found. Run 'sync' to clone skill repositories first."}
    else
      lines = Enum.map_join(cats, "\n", fn cat -> "- #{cat}" end)
      {:ok, "#{length(cats)} categories:\n#{lines}"}
    end
  end

  def execute(%{"action" => "sync"}) do
    Logger.info("[SkillSearch] Syncing OpenClaw repos...")

    case OpenClaw.sync() do
      :ok ->
        status = OpenClaw.status()
        {:ok, "Sync complete. Index: #{status.index_size} skills."}

      {:error, reason} ->
        {:error, "Sync failed: #{inspect(reason)}"}
    end
  end

  def execute(%{"action" => "status"}) do
    status = OpenClaw.status()

    {:ok,
     """
     OpenClaw Skills Status:
     - Repos cloned: #{status.repos_cloned}
     - Index size: #{status.index_size} skills
     - Skills dir: #{status.skills_dir}
     - Awesome dir: #{status.awesome_dir}
     """}
  end

  def execute(%{"action" => action}) do
    {:error, "Unknown action: #{action}. Use: search, load, categories, sync, status"}
  end

  def execute(_) do
    {:error, "Missing 'action' parameter"}
  end
end
