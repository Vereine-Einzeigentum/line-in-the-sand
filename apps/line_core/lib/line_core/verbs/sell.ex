defmodule LineCore.Verbs.Sell do
  @moduledoc """
  `sell <item> to <npc>` — transfer an item from inventory to an NPC in
  exchange for the NPC's buy price.

  The NPC must:
  - Be in the current room
  - Have a `buys` property listing acceptable item types/tags
  - Have a `buy_multiplier` property (defaults to 1.0) applied to the item's
    `scrap_value` (or `value` fallback)

  Phase 0 mechanic: the NPC pays scrap_value * buy_multiplier. Negotiation,
  faction-rep modifiers, and skill checks come Phase 1+.
  """

  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(_ctx, []), do: {:error, :sell_what}
  def execute(_ctx, [_item]), do: {:error, :sell_to_whom}

  def execute(ctx, [item_name, npc_name]) do
    item = find_in_inventory(ctx.actor.id, item_name)
    npc = find_npc_in_room(ctx.room_contents, npc_name)

    cond do
      item == nil -> {:error, :not_in_inventory}
      npc == nil -> {:error, :no_such_buyer}
      true -> resolve_sale(ctx, item, npc)
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Helpers

  defp find_in_inventory(actor_id, name) do
    actor_id
    |> Object.contents()
    |> Enum.filter(&(&1.type == :item))
    |> Object.find_by_name(name)
  end

  defp find_npc_in_room(room_contents, name) do
    room_contents
    |> Enum.filter(&(&1.type == :npc))
    |> Object.find_by_name(name)
  end

  defp resolve_sale(ctx, item, npc) do
    buys = Object.get_property(npc.id, "buys", [])
    item_tag = Object.get_property(item.id, "tag", "misc")

    cond do
      buys != [] and item_tag not in buys ->
        {:error, :buyer_uninterested}

      true ->
        base_value =
          Object.get_property(item.id, "scrap_value") ||
            Object.get_property(item.id, "value", 0)

        multiplier = Object.get_property(npc.id, "buy_multiplier", 1.0)
        # Defensive: multiplier may have arrived as Decimal or float
        price = round(base_value * to_float(multiplier))

        current_dirham = Object.get_property(ctx.actor.id, "dirham", 0)

        {:ok,
         [
           {:move, item.id, npc.id, :contains},
           {:set_property, ctx.actor.id, "dirham", current_dirham + price},
           {:notify_actor, "You hand the #{item.name} to #{npc.name}. They pay you #{price} Dh."},
           {:notify_object, npc.id,
            "#{ctx.actor.name} sells you a #{item.name} for #{price} Dh."},
           {:notify_room, "#{ctx.actor.name} sells something to #{npc.name}.",
            except: [ctx.actor.id, npc.id]}
         ]}
    end
  end

  defp to_float(n) when is_float(n), do: n
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(_), do: 1.0
end
