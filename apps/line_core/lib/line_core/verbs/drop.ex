defmodule LineCore.Verbs.Drop do
  @moduledoc """
  `drop <item>` — drop an item from inventory into the current room.

  Searches the actor's contents (inventory) for the named item. If found,
  moves it into the room.
  """

  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(_ctx, []), do: {:error, :drop_what}

  def execute(ctx, ["all"]) do
    items =
      ctx.actor.id
      |> Object.contents()
      |> Enum.filter(&(&1.type == :item))

    case items do
      [] ->
        {:error, :not_in_inventory}

      _ ->
        equipped = Object.equipped(ctx.actor.id)

        detach =
          equipped
          |> Enum.filter(fn {_type, object} -> Enum.any?(items, &(&1.id == object.id)) end)
          |> Enum.map(fn {type, object} -> {:unrelate, ctx.actor.id, object.id, type} end)

        moves = Enum.map(items, &{:move, &1.id, ctx.room.id, :contains})
        names = Enum.map_join(items, ", ", & &1.name)

        {:ok,
         detach ++
           moves ++
           [
             {:notify_actor, "You drop: #{names}."},
             {:notify_room, "#{ctx.actor.name} drops several things.", except: [ctx.actor.id]}
           ]}
    end
  end

  def execute(ctx, [name]) do
    candidate =
      ctx.actor.id
      |> Object.contents()
      |> Enum.filter(&(&1.type == :item))
      |> Object.find_by_name(name)

    case candidate do
      nil ->
        {:error, :not_in_inventory}

      item ->
        detach =
          ctx.actor.id
          |> Object.equipped()
          |> Enum.filter(fn {_type, object} -> object.id == item.id end)
          |> Enum.map(fn {type, object} -> {:unrelate, ctx.actor.id, object.id, type} end)

        {:ok,
         detach ++
           [
             {:move, item.id, ctx.room.id, :contains},
             {:notify_actor, "You drop the #{item.name}."},
             {:notify_room, "#{ctx.actor.name} drops a #{item.name}.", except: [ctx.actor.id]}
           ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
