defmodule LineCore.Verbs.Scrap do
  @moduledoc """
  `scrap <item>` — break down an item from inventory into dirham + Scrap skill XP.

  The item must be in the actor's inventory and have a `scrap_value` property
  (in dirham). The item is soft-deleted. The actor's `dirham` property goes up
  by the scrap value, and their `skill_scrap_xp` property goes up by 1.

  Items without `scrap_value` cannot be scrapped.
  """

  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(_ctx, []), do: {:error, :scrap_what}

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
        case Object.get_property(item.id, "scrap_value") do
          nil ->
            {:error, :unscrappable}

          value when is_integer(value) and value > 0 ->
            current_dirham = Object.get_property(ctx.actor.id, "dirham", 0)
            current_xp = Object.get_property(ctx.actor.id, "skill_scrap_xp", 0)

            {:ok,
             [
               {:delete_object, item.id},
               {:set_property, ctx.actor.id, "dirham", current_dirham + value},
               {:set_property, ctx.actor.id, "skill_scrap_xp", current_xp + 1},
               {:notify_actor,
                "You break down the #{item.name} into scrap. (+#{value} Dh, +1 Scrap XP)"},
               {:notify_room, "#{ctx.actor.name} breaks something down for parts.",
                except: [ctx.actor.id]}
             ]}

          _ ->
            {:error, :unscrappable}
        end
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
