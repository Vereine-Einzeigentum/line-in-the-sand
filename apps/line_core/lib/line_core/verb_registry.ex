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
    "attack" => Verbs.Attack,
    "wield" => Verbs.Wield,
    "scrap" => Verbs.Scrap,
    "sell" => Verbs.Sell
  }

  def resolve(key) when is_binary(key), do: Map.fetch(@modules, key)
  def keys, do: Map.keys(@modules)
end
