defmodule LineCore.Verbs.Help do
  @moduledoc """
  `help` — the command index, grouped by what you are trying to do.
  `help <command>` — detail on one command, with its aliases.

  Modelled on LambdaMOO's help index: categories of related commands rather
  than an alphabetical dump of every alias, since a flat list of ~45 aliases
  tells a new player nothing about where to start.

  Categories are curated (`@categories`), but the verbs inside them resolve
  through `LineCore.Parser`, and anything uncategorised falls into a catch-all
  group. A newly registered verb can therefore never go missing from the index —
  at worst it lands under "Other". A test asserts every known verb is both
  listed and described.

  Pure: produces a single notify_actor event.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Parser, Verbs}

  @categories [
    {"Looking around", [Verbs.Look, Verbs.Examine]},
    {"Getting around", [Verbs.Go]},
    {"Talking", [Verbs.Say, Verbs.Emote, Verbs.Text, Verbs.Who]},
    {"Carrying things", [Verbs.Inventory, Verbs.Get, Verbs.Drop, Verbs.Give]},
    {"Staying alive", [Verbs.Attack, Verbs.Wield, Verbs.Unwield, Verbs.Score]},
    {"The scrap trade", [Verbs.Scrap, Verbs.Sell]},
    {"Yourself and this list", [Verbs.Desc, Verbs.Help]}
  ]

  # Player-facing one-liners, in the game's register. Deliberately not sourced
  # from @moduledoc — those describe the implementation, not the world.
  @summaries %{
    Verbs.Look => "Take in the room, its ways out, and who is standing in it.",
    Verbs.Examine => "Look closely at one thing.",
    Verbs.Go => "Walk. Bare directions work alone: n, s, e, w, u, d, in, out.",
    Verbs.Say => "Speak aloud to the room.",
    Verbs.Emote => "Act rather than speak.",
    Verbs.Text => "Message one person privately, wherever they are.",
    Verbs.Who => "See who else is awake in THE LINE.",
    Verbs.Inventory => "What you are carrying.",
    Verbs.Get => "Pick something up.",
    Verbs.Drop => "Put something down.",
    Verbs.Give => "Hand something to someone standing with you.",
    Verbs.Attack => "Commit to violence against someone in the room.",
    Verbs.Wield => "Take a weapon in hand — main or off.",
    Verbs.Unwield => "Put a weapon away.",
    Verbs.Score => "Your condition: hit points, dirham, what you are good at.",
    Verbs.Scrap => "Break something down into what it is actually worth.",
    Verbs.Sell => "Trade something to a fence for dirham.",
    Verbs.Desc => "Set how you, or something you own, reads to others.",
    Verbs.Help => "This index. `help <command>` for one command."
  }

  @impl true
  def execute(_ctx, []), do: {:ok, [{:notify_actor, index()}]}

  def execute(_ctx, [name]) do
    lookup = name |> to_string() |> String.trim() |> String.downcase()

    case Map.get(Parser.verb_map(), lookup) do
      nil -> {:error, :unknown_verb}
      module -> {:ok, [{:notify_actor, detail(module)}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Index

  defp index do
    (["THE LINE — command index", "========================"] ++
       Enum.flat_map(groups(), &render_group/1) ++
       ["", "Type `help <command>` for detail on any one of them."])
    |> Enum.join("\n")
  end

  # Curated categories first, then whatever they missed, so a newly registered
  # verb still shows up without anyone remembering to file it.
  defp groups do
    categorised = Enum.flat_map(@categories, fn {_name, mods} -> mods end)

    case Parser.known_verbs() -- categorised do
      [] -> @categories
      others -> @categories ++ [{"Other", Enum.sort_by(others, &canonical_name/1)}]
    end
  end

  defp render_group({heading, modules}) do
    ["", heading] ++ Enum.map(modules, &("  " <> line_for(&1)))
  end

  defp line_for(module) do
    padded = module |> canonical_name() |> String.pad_trailing(10)

    case aliases_for(module) do
      [] -> "#{padded} #{summary(module)}"
      aliases -> "#{padded} #{summary(module)} (also: #{Enum.join(aliases, ", ")})"
    end
  end

  ## Detail

  defp detail(module) do
    name = canonical_name(module)

    header =
      case aliases_for(module) do
        [] -> name
        aliases -> "#{name} — also: #{Enum.join(aliases, ", ")}"
      end

    Enum.join([header, String.duplicate("-", String.length(header)), summary(module)], "\n")
  end

  ## Naming

  # Derived from the module rather than a hand-kept list, so the canonical name
  # cannot drift from the registry.
  defp canonical_name(module) do
    module |> Module.split() |> List.last() |> Macro.underscore()
  end

  # Word aliases from the verb table, plus the punctuation shorthands the
  # parser matches as prefixes (`"` for say, `:` for emote) — those never
  # appear in verb_map/0, but to a player they are aliases like any other.
  defp aliases_for(module) do
    canonical = canonical_name(module)

    words =
      Parser.verb_map()
      |> Enum.filter(fn {_alias, mod} -> mod == module end)
      |> Enum.map(fn {alias_name, _} -> alias_name end)
      |> Enum.reject(&(&1 == canonical))
      |> Enum.sort()

    shorthands =
      Parser.shorthands()
      |> Enum.filter(fn {_prefix, mod} -> mod == module end)
      |> Enum.map(fn {prefix, _} -> prefix end)

    shorthands ++ words
  end

  defp summary(module), do: Map.get(@summaries, module, "No description yet.")

  @doc "Verb modules this index has player-facing text for. Used by tests."
  def described_verbs, do: Map.keys(@summaries)
end
