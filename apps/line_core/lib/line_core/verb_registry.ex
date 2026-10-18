defmodule LineCore.VerbRegistry do
  @moduledoc """
  Trusted Elixir implementations referenced by persistent verb objects.

  World data selects among this registry; arbitrary module names from world
  state are never converted into atoms or executed.
  """

  alias LineCore.Verbs

  @modules %{
    "look" => Verbs.Look,
    "examine" => Verbs.Examine,
    "go" => Verbs.Go,
    "inventory" => Verbs.Inventory,
    "get" => Verbs.Get,
    "put" => Verbs.Put,
    "drop" => Verbs.Drop,
    "say" => Verbs.Say,
    "emote" => Verbs.Emote,
    "attack" => Verbs.Attack,
    "wield" => Verbs.Wield,
    "scrap" => Verbs.Scrap,
    "sell" => Verbs.Sell,
    "score" => Verbs.Score,
    "skills" => Verbs.Skills,
    "gear" => Verbs.Gear,
    "give" => Verbs.Give,
    "unwield" => Verbs.Unwield,
    "wear" => Verbs.Wear,
    "remove_wear" => Verbs.RemoveWear,
    "open" => Verbs.Open,
    "close" => Verbs.Close,
    "lock" => Verbs.Lock,
    "unlock" => Verbs.Unlock,
    "home" => Verbs.Home,
    "sethome" => Verbs.SetHome,
    "whisper" => Verbs.Whisper,
    "map" => Verbs.LocalMap,
    "exits" => Verbs.Exits
  }

  def resolve(key) when is_binary(key), do: Map.fetch(@modules, key)
  def keys, do: Map.keys(@modules)
end
