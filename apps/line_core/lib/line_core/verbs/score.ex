defmodule LineCore.Verbs.Score do
  @moduledoc """
  `score` / `stats` / `sc` — display the actor's character sheet.

  Shows current HP, max HP, dirham, and any stat_* and skill_* properties
  the actor possesses. Notification to actor only.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Combat, Object}

  @impl true
  def execute(ctx, []) do
    {hp_current, hp_max} = Combat.hp(ctx.actor.id)
    dirham = Object.get_property(ctx.actor.id, "dirham", 0)

    # Fetch all properties for this actor
    all_properties = Object.properties(ctx.actor.id)

    # Filter for stats and skills
    stats_and_skills =
      all_properties
      |> Enum.filter(fn {key, _value} ->
        String.starts_with?(key, "stat_") or String.starts_with?(key, "skill_")
      end)
      |> Enum.sort_by(fn {key, _} -> key end)

    lines = build_score_lines(hp_current, hp_max, dirham, stats_and_skills)

    {:ok, [{:notify_actor, Enum.join(lines, "\n")}]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Helpers

  defp build_score_lines(hp_current, hp_max, dirham, stats_and_skills) do
    [
      "=== Character Sheet ===",
      "HP: #{hp_current}/#{hp_max}",
      "Dirham: #{dirham}"
    ] ++
      case stats_and_skills do
        [] -> []
        items -> [""] ++ Enum.map(items, fn {key, value} -> format_property(key, value) end)
      end
  end

  defp format_property(key, value) do
    formatted_key = key |> String.replace(~r/^(stat|skill)_/, "") |> String.capitalize()
    "#{formatted_key}: #{format_value(value)}"
  end

  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value), do: inspect(value)
end
