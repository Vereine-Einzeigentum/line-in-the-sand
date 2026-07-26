defmodule LineCore.Verbs.Get do
  @moduledoc """
  `get <item>` — pick up an item from the current room into inventory.

  Searches the room contents for an item matching the name (case-insensitive,
  substring match). If found and gettable, moves it into the actor's contents.
  """

  @behaviour LineCore.Verb


  @impl true
  def execute(_ctx, []), do: {:error, :get_what}

  def execute(ctx, [name]) do
    name_down = String.downcase(name)

    candidate =
      ctx.room_contents
      |> Enum.reject(&(&1.id == ctx.actor.id))
      |> Enum.filter(&(&1.type == :item))
      |> Enum.find(fn item ->
        item_name = String.downcase(item.name)
        item_name == name_down or String.contains?(item_name, name_down)
      end)

    case candidate do
      nil ->
        {:error, :not_found}

      item ->
        {:ok,
         [
           {:move, item.id, ctx.actor.id, :contains},
           {:notify_actor, "You pick up the #{item.name}."},
           {:notify_room, "#{ctx.actor.name} picks up the #{item.name}.",
            except: [ctx.actor.id]}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
