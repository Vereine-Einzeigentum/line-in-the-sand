defmodule LineCore.Parser do
  @moduledoc """
  Translates raw command strings into `{verb_module, args}` tuples.

  Step 6 additions: `scrap` and `sell` verbs. Sell uses two-object syntax:
  `sell <item> to <npc>` is parsed into two args via the "X to Y" pattern.
  """

  alias LineCore.Verbs

  @directions ~w(n north s south e east w west u up d down ne northeast nw northwest se southeast sw southwest in out)

  @verb_map %{
    "look" => Verbs.Look,
    "l" => Verbs.Look,
    "examine" => Verbs.Examine,
    "ex" => Verbs.Examine,
    "x" => Verbs.Examine,
    "go" => Verbs.Go,
    "move" => Verbs.Go,
    "inventory" => Verbs.Inventory,
    "inv" => Verbs.Inventory,
    "i" => Verbs.Inventory,
    "get" => Verbs.Get,
    "grab" => Verbs.Get,
    "gather" => Verbs.Get,
    "pickup" => Verbs.Get,
    "take" => Verbs.Get,
    "drop" => Verbs.Drop,
    "leave" => Verbs.Drop,
    "put" => Verbs.Drop,
    "discard" => Verbs.Drop,
    "say" => Verbs.Say,
    "emote" => Verbs.Emote,
    "me" => Verbs.Emote,
    "text" => Verbs.Text,
    "txt" => Verbs.Text,
    "tell" => Verbs.Text,
    "who" => Verbs.Who,
    "desc" => Verbs.Desc,
    "describe" => Verbs.Desc,
    "attack" => Verbs.Attack,
    "kill" => Verbs.Attack,
    "k" => Verbs.Attack,
    "hit" => Verbs.Attack,
    "stab" => Verbs.Attack,
    "slash" => Verbs.Attack,
    "shoot" => Verbs.Attack,
    "punch" => Verbs.Attack,
    "wield" => Verbs.Wield,
    "hold" => Verbs.Wield,
    "equip" => Verbs.Wield,
    "score" => Verbs.Score,
    "stats" => Verbs.Score,
    "sc" => Verbs.Score,

    # Scrap loop
    "scrap" => Verbs.Scrap,
    "salvage" => Verbs.Scrap,
    "sell" => Verbs.Sell,
    "fence" => Verbs.Sell
  }

  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      trimmed == "" ->
        {:empty, ""}

      String.starts_with?(trimmed, "\"") ->
        message = String.trim_leading(trimmed, "\"") |> String.trim()
        {:ok, Verbs.Say, [message]}

      String.starts_with?(trimmed, ":") ->
        message = String.trim_leading(trimmed, ":") |> String.trim()
        {:ok, Verbs.Emote, [message]}

      String.downcase(trimmed) in @directions ->
        {:ok, Verbs.Go, [String.downcase(trimmed)]}

      true ->
        parse_verb(trimmed)
    end
  end

  defp parse_verb(input) do
    {verb, rest} = split_verb(input)
    verb_down = String.downcase(verb)

    case Map.get(@verb_map, verb_down) do
      nil -> {:unknown, verb_down, input}
      module -> {:ok, module, parse_args(module, rest)}
    end
  end

  defp split_verb(input) do
    case String.split(input, " ", parts: 2) do
      [verb] -> {verb, ""}
      [verb, rest] -> {verb, String.trim(rest)}
    end
  end

  defp parse_args(_module, ""), do: []

  defp parse_args(Verbs.Text, rest) do
    case String.split(rest, " ", parts: 2) do
      [target] -> [target]
      [target, message] -> [target, message]
    end
  end

  defp parse_args(Verbs.Desc, rest) do
    case Regex.run(~r/^(.+?)\s+as\s+(.+)$/i, rest) do
      [_, "me", description] -> [description]
      [_, "self", description] -> [description]
      [_, object, description] -> [object, description]
      _ -> [rest]
    end
  end

  defp parse_args(Verbs.Who, rest) do
    case rest do
      "" -> []
      name -> [name]
    end
  end

  defp parse_args(Verbs.Go, rest), do: [String.downcase(rest)]
  defp parse_args(Verbs.Inventory, _rest), do: []
  defp parse_args(Verbs.Score, _rest), do: []

  defp parse_args(Verbs.Wield, rest) do
    case Regex.run(~r/^(.+?)\s+(main|off)$/i, rest) do
      [_, item, hand] -> [String.trim(item), String.downcase(hand)]
      _ -> [rest]
    end
  end

  # Sell uses "X to Y" syntax: split on " to " or " at " for `fence` alias
  defp parse_args(Verbs.Sell, rest) do
    case Regex.run(~r/^(.+?)\s+(?:to|at)\s+(.+)$/i, rest) do
      [_, item, target] -> [String.trim(item), String.trim(target)]
      _ -> [rest]
    end
  end

  defp parse_args(_module, rest), do: [rest]

  def verb_map, do: @verb_map
  def known_verbs, do: @verb_map |> Map.values() |> Enum.uniq()
end
