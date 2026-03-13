defmodule Eclaw.Skills do
  @moduledoc """
  Dynamic skill system — loads Markdown skill files and injects them into the system prompt.

  Skills are .md files in `priv/skills/` containing instructions for the LLM.
  Each skill has YAML frontmatter defining metadata:

      ---
      name: git-pr-review
      description: Review and manage GitHub Pull Requests
      triggers: [pr, pull request, review, merge]
      ---

      ## Instructions
      When user asks about PRs, use `gh` CLI...

  Skills are automatically matched against user prompts and injected into context.
  """

  require Logger

  @skills_dir "priv/skills"
  @cache_ttl_ms 60_000

  @doc "Load all skills from priv/skills/*/SKILL.md. Cached for 60 seconds."
  @spec load_all() :: [map()]
  def load_all do
    case Process.get(:eclaw_skills_cache) do
      {skills, expires_at} when is_list(skills) ->
        if System.monotonic_time(:millisecond) < expires_at, do: skills, else: do_load_all()

      _ ->
        do_load_all()
    end
  end

  defp do_load_all do
    skills_path = Application.app_dir(:eclaw, @skills_dir)

    skills =
      if File.dir?(skills_path) do
        skills_path
        |> Path.join("*/SKILL.md")
        |> Path.wildcard()
        |> Enum.map(&parse_skill/1)
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    Process.put(:eclaw_skills_cache, {skills, System.monotonic_time(:millisecond) + @cache_ttl_ms})
    skills
  end

  @doc """
  Find skills matching the user's prompt.

  Matches based on triggers (keywords) in frontmatter.
  Returns up to 3 best matching skills.
  """
  @spec match(String.t()) :: [map()]
  def match(prompt) do
    prompt_lower = String.downcase(prompt)
    words = prompt_lower |> String.split(~r/[\s,\.!?\-]+/) |> MapSet.new()

    load_all()
    |> Enum.map(fn skill ->
      score = calculate_score(skill, prompt_lower, words)
      {skill, score}
    end)
    |> Enum.filter(fn {_skill, score} -> score > 0 end)
    |> Enum.sort_by(fn {_skill, score} -> score end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {skill, _score} -> skill end)
  end

  @doc """
  Build skill context string to inject into the system prompt.

  Only injects when skills match the prompt.
  """
  @spec build_context(String.t()) :: String.t()
  def build_context(prompt) do
    case match(prompt) do
      [] ->
        ""

      skills ->
        skill_texts =
          skills
          |> Enum.map(fn skill ->
            "[SKILL: #{skill.name}]\n#{skill.content}"
          end)
          |> Enum.join("\n\n")

        "\n\n## Active Skills\nFollow these skill instructions when relevant:\n\n" <> skill_texts
    end
  end

  # ── Private ──────────────────────────────────────────────────────

  defp parse_skill(path) do
    # Skill name = directory name containing SKILL.md
    dir_name = path |> Path.dirname() |> Path.basename()

    case File.read(path) do
      {:ok, raw} ->
        case parse_frontmatter(raw) do
          {:ok, meta, content} ->
            %{
              name: meta["name"] || dir_name,
              description: meta["description"] || "",
              triggers: parse_triggers(meta["triggers"]),
              content: String.trim(content),
              file: dir_name
            }

          :no_frontmatter ->
            %{
              name: dir_name,
              description: "",
              triggers: [],
              content: String.trim(raw),
              file: dir_name
            }
        end

      {:error, reason} ->
        Logger.warning("[Skills] Failed to read #{path}: #{inspect(reason)}")
        nil
    end
  end

  defp parse_frontmatter(raw) do
    case String.split(raw, ~r/^---\s*$/m, parts: 3) do
      ["", yaml, content] ->
        meta = parse_yaml_simple(yaml)
        {:ok, meta, content}

      _ ->
        :no_frontmatter
    end
  end

  # Simple YAML parser for frontmatter (key: value, key: [a, b, c])
  defp parse_yaml_simple(yaml) do
    yaml
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      case String.split(line, ~r/:\s*/, parts: 2) do
        [key, value] when key != "" ->
          value = String.trim(value)
          value = parse_yaml_value(value)
          Map.put(acc, key, value)

        _ ->
          acc
      end
    end)
  end

  defp parse_yaml_value("[" <> _ = value) do
    value
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(~r/,\s*/)
    |> Enum.map(&String.trim/1)
  end

  defp parse_yaml_value(value), do: value

  defp parse_triggers(nil), do: []
  defp parse_triggers(triggers) when is_list(triggers), do: triggers
  defp parse_triggers(triggers) when is_binary(triggers), do: [triggers]

  defp calculate_score(skill, prompt_lower, words) do
    # Trigger match (strongest signal)
    trigger_score =
      skill.triggers
      |> Enum.count(fn trigger ->
        String.contains?(prompt_lower, String.downcase(trigger))
      end)
      |> Kernel.*(3)

    # Name match
    name_score =
      if String.contains?(prompt_lower, String.downcase(skill.name)), do: 2, else: 0

    # Description word overlap
    desc_words =
      skill.description
      |> String.downcase()
      |> String.split(~r/[\s,\.!?\-]+/)
      |> MapSet.new()

    overlap = MapSet.intersection(words, desc_words) |> MapSet.size()

    trigger_score + name_score + overlap
  end
end
