defmodule LineCore.Verbs.Help do
  @behaviour LineCore.Verb

  @summary """
  Commands: look/l, examine/ex, inventory/i, get/take, drop/throw, put/insert,
  give/hand, say, emote/:, whisper, page, who/@who, whereis, go/directions,
  home/@sethome, map/lmap, exits, score/sc/stats, skills/sk, gear/eq/equipment,
  wield/unwield, wear/remove, open/close/lock/unlock, help/info/?.
  Moderator building: @create, @dig, @open, @link, @unlink, @move, @recycle,
  @rename, @describe, @addalias/@rmalias/@aliases, @examine/@show/@display,
  @contents, @parent/@parents, @kids, @verbs, @properties, @property/@rmproperty,
  @chparent, @set, @clear, @count, @audit/@owned, @classes, @quota.
  """

  @impl true
  def execute(_ctx, []), do: {:ok, [{:notify_actor, String.trim(@summary)}]}

  def execute(_ctx, [topic]) do
    {:ok, [{:notify_actor, topic(topic)}]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp topic(topic) do
    case String.downcase(String.trim(topic)) do
      "building" ->
        "Moderator building: @create, @dig, @open, @link, @unlink, @move, @recycle, @rename, @describe, @addalias/@rmalias/@aliases, @examine/@show/@display, @contents, @parent/@parents, @kids, @verbs, @properties, @property/@rmproperty, @chparent, @set, @clear, @count, @audit/@owned, @classes, @quota."

      "combat" ->
        "Combat: attack/hit/shoot/stab/slash/punch, wield/unwield, gear, score, skills."

      "communication" ->
        "Communication: say or \", :emote, whisper <text> to <player>, page <player> <text>, who, whereis."

      _ ->
        String.trim(@summary)
    end
  end
end

defmodule LineCore.Verbs.Score do
  @behaviour LineCore.Verb

  alias LineCore.{Combat, Object}

  @stats ~w(wire shade grit face wit iron rigor vigor)

  @impl true
  def execute(ctx, []) do
    {hp, hp_max} = Combat.hp(ctx.actor.id)
    fatigue = Object.get_property(ctx.actor.id, "fatigue_current", 0)
    fatigue_max = Object.get_property(ctx.actor.id, "fatigue_max", 0)
    stress = Object.get_property(ctx.actor.id, "stress_current", 0)
    stress_max = Object.get_property(ctx.actor.id, "stress_max", 0)
    dirham = Object.get_property(ctx.actor.id, "dirham", 0)
    yuan = Object.get_property(ctx.actor.id, "yuan", 0)
    upload = Object.get_property(ctx.actor.id, "signal_upload", 0)
    download = Object.get_property(ctx.actor.id, "signal_download", 0)

    stat_line =
      @stats
      |> Enum.map(fn stat ->
        "#{String.capitalize(stat)} #{Object.get_property(ctx.actor.id, "stat_" <> stat, 0)}"
      end)
      |> Enum.join("  ")

    text =
      [
        ctx.actor.name,
        stat_line,
        "HP #{hp}/#{hp_max}  Fatigue #{fatigue}/#{fatigue_max}  Stress #{stress}/#{stress_max}",
        "#{dirham} Dh  #{yuan} Yuan  Signal ↑#{upload} ↓#{download}"
      ]
      |> Enum.join("\n")

    {:ok, [{:notify_actor, text}]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.Skills do
  @behaviour LineCore.Verb

  alias LineCore.{Archetypes, Object}

  @impl true
  def execute(ctx, []) do
    skill_root = Archetypes.get(:skill)

    lines =
      skill_root.id
      |> Object.children()
      |> Enum.map(fn skill ->
        stat_a = Object.get_property(skill.id, "stat_a")
        stat_b = Object.get_property(skill.id, "stat_b")
        a = Object.get_property(ctx.actor.id, "stat_" <> stat_a, 0)
        b = Object.get_property(ctx.actor.id, "stat_" <> stat_b, 0)
        xp_key = "skill_" <> String.trim_leading(skill.name, "$") <> "_xp"
        xp = Object.get_property(ctx.actor.id, xp_key, 0)
        name = skill.name |> String.trim_leading("$") |> String.capitalize()
        "#{name}: #{a + b} (#{String.capitalize(stat_a)} + #{String.capitalize(stat_b)}; XP #{xp})"
      end)

    text =
      case lines do
        [] -> "No skills are seeded."
        _ -> "Skills\n" <> Enum.join(lines, "\n")
      end

    {:ok, [{:notify_actor, text}]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.Gear do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, []) do
    lines =
      ctx.actor.id
      |> Object.equipped()
      |> Enum.map(fn
        {:wields_main, object} -> "Main hand: #{object.name}"
        {:wields_off, object} -> "Off hand: #{object.name}"
        {:wears, object} -> "Wearing: #{object.name}"
      end)

    text = if lines == [], do: "You have nothing equipped.", else: Enum.join(lines, "\n")
    {:ok, [{:notify_actor, text}]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.LocalMap do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, []) do
    exits = Object.exits(ctx.room.id) |> Enum.sort_by(fn {dir, _room} -> dir end)

    body =
      case exits do
        [] -> "No exits."
        _ -> Enum.map_join(exits, "\n", fn {dir, room} -> "#{dir} -> #{room.name}" end)
      end

    {:ok, [{:notify_actor, "#{ctx.room.name}\n#{body}"}]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.Exits do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, []) do
    exits =
      ctx.room.id
      |> Object.exits()
      |> Enum.sort_by(fn {dir, _room} -> dir end)
      |> Enum.map_join(", ", fn {dir, room} -> "#{dir} (#{room.name})" end)

    {:ok, [{:notify_actor, if(exits == "", do: "Exits: none.", else: "Exits: " <> exits)}]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
