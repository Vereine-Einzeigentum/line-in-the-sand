defmodule LineCore.Verbs.Unwield do
  @moduledoc """
  `unwield` — stop wielding everything.
  `unwield <item>` — stop wielding a specific item.

  Unequips items from `:wields_main` or `:wields_off` and returns them to
  the actor's inventory (`:contains`).
  """

  @behaviour LineCore.Verb

  alias LineCore.{Object, Repo}
  alias LineCore.Schemas.Relationship
  import Ecto.Query

  @impl true
  def execute(ctx, []), do: do_unwield_all(ctx)
  def execute(ctx, [item_name]), do: do_unwield_specific(ctx, item_name)
  def execute(_ctx, _args), do: {:error, :bad_args}

  defp do_unwield_all(ctx) do
    main_wielded = currently_wielded(ctx.actor.id, :wields_main)
    off_wielded = currently_wielded(ctx.actor.id, :wields_off)

    wielded_items = [main_wielded, off_wielded] |> Enum.reject(&is_nil/1)

    if wielded_items == [] do
      {:error, :not_wielding}
    else
      events =
        Enum.flat_map(wielded_items, fn item ->
          hand_relation = get_hand_relation(ctx.actor.id, item.id)
          unwield_events(ctx, item, hand_relation)
        end)

      {:ok, events}
    end
  end

  defp do_unwield_specific(ctx, item_name) do
    candidate =
      ctx.actor.id
      |> Object.contents()
      |> Enum.concat(get_all_wielded(ctx.actor.id))
      |> Enum.filter(&(&1.type == :item))
      |> find_by_name(item_name)

    case candidate do
      nil ->
        {:error, :not_holding}

      item ->
        hand_relation = get_hand_relation(ctx.actor.id, item.id)

        if hand_relation == nil do
          {:error, :not_wielding}
        else
          {:ok, unwield_events(ctx, item, hand_relation)}
        end
    end
  end

  defp unwield_events(ctx, item, hand_relation) do
    hand_label =
      case hand_relation do
        :wields_main -> "main hand"
        :wields_off -> "off hand"
        _ -> "hand"
      end

    [
      {:unrelate, ctx.actor.id, item.id, hand_relation},
      {:relate, ctx.actor.id, item.id, :contains},
      {:notify_actor, "You unwield the #{item.name} from your #{hand_label}."},
      {:notify_room, "#{ctx.actor.name} unwields a #{item.name}.", except: [ctx.actor.id]}
    ]
  end

  defp find_by_name(items, name) do
    name_down = String.downcase(name)

    Enum.find(items, fn item ->
      item_name = String.downcase(item.name)
      item_name == name_down or String.contains?(item_name, name_down)
    end)
  end

  defp get_all_wielded(actor_id) do
    from(o in LineCore.Schemas.Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where:
        r.from_id == ^actor_id and
          r.type in [:wields_main, :wields_off] and
          is_nil(o.deleted_at)
    )
    |> Repo.all()
  end

  defp currently_wielded(actor_id, hand_relation) do
    from(o in LineCore.Schemas.Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where: r.from_id == ^actor_id and r.type == ^hand_relation and is_nil(o.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end

  defp get_hand_relation(actor_id, item_id) do
    from(r in Relationship,
      where:
        r.from_id == ^actor_id and r.to_id == ^item_id and
          r.type in [:wields_main, :wields_off],
      select: r.type,
      limit: 1
    )
    |> Repo.one()
  end
end
