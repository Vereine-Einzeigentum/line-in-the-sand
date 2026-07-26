defmodule LineCore.Verbs.Give do
  @moduledoc """
  `give <item> to <player>` — transfer an item from the actor's inventory to
  another player or NPC in the same room.

  The item must already be in the actor's inventory. The recipient must be
  present in the current room.
  """

  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(_ctx, []), do: {:error, :give_what}
  def execute(_ctx, [_item]), do: {:error, :give_to_whom}

  def execute(ctx, [item_name, recipient_name]) do
    item = find_in_inventory(ctx.actor.id, item_name)
    recipient = find_in_room(ctx.room_contents, recipient_name)

    cond do
      item == nil -> {:error, :not_holding}
      recipient == nil -> {:error, :not_found}
      recipient.id == ctx.actor.id -> {:error, :cannot_give_self}
      true -> resolve_give(ctx, item, recipient)
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Helpers

  defp find_in_inventory(actor_id, name) do
    name_down = String.downcase(name)

    actor_id
    |> Object.contents()
    |> Enum.filter(&(&1.type == :item))
    |> Enum.find(fn item ->
      item_name = String.downcase(item.name)
      item_name == name_down or String.contains?(item_name, name_down)
    end)
  end

  defp find_in_room(room_contents, name) do
    name_down = String.downcase(name)

    Enum.find(room_contents, fn obj ->
      obj.type in [:player, :npc] and
        (String.downcase(obj.name) == name_down or
           String.contains?(String.downcase(obj.name), name_down))
    end)
  end

  defp resolve_give(ctx, item, recipient) do
    {:ok,
     [
       {:move, item.id, recipient.id, :contains},
       {:notify_actor, "You give the #{item.name} to #{recipient.name}."},
       {:notify_object, recipient.id, "#{ctx.actor.name} gives you a #{item.name}."},
       {:notify_room, "#{ctx.actor.name} gives something to #{recipient.name}.",
        except: [ctx.actor.id, recipient.id]}
     ]}
  end
end
