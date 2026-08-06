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
        {:ok,
         [
           {:move, item.id, ctx.room.id, :contains},
           {:notify_actor, "You drop the #{item.name}."},
           {:notify_room, "#{ctx.actor.name} drops a #{item.name}.", except: [ctx.actor.id]}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
