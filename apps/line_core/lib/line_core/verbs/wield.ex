defmodule LineCore.Verbs.Wield do
  @moduledoc """
  `wield <item>` — equip an item in the main hand (default).
  `wield <item> main` — explicit main hand.
  `wield <item> off` — equip in off hand.
  `hold <item>`, `equip <item>` — aliases.

  The item must already be in the actor's inventory (`:contains`). Wielding
  removes the `:contains` relationship and adds `:wields_main` or `:wields_off`.

  If something is already wielded in that hand, it's moved back to `:contains`.

  Uses new `:relate` and `:unrelate` dispatcher events shipped in this drop.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Object, Repo}
  alias LineCore.Schemas.Relationship
  import Ecto.Query

  @impl true
  def execute(_ctx, []), do: {:error, :wield_what}
  def execute(ctx, [name]), do: do_wield(ctx, name, :wields_main, "main")
  def execute(ctx, [name, "main"]), do: do_wield(ctx, name, :wields_main, "main")
  def execute(ctx, [name, "off"]), do: do_wield(ctx, name, :wields_off, "off")
  def execute(_ctx, _args), do: {:error, :bad_args}

  defp do_wield(ctx, name, hand_relation, hand_label) do
    candidate =
      ctx.actor.id
      |> Object.contents()
      |> Enum.filter(&(&1.type == :item))
      |> find_by_name(name)

    case candidate do
      nil ->
        {:error, :not_in_inventory}

      item ->
        existing = currently_wielded(ctx.actor.id, hand_relation)

        # Unequip existing wielded item back into :contains
        swap_events =
          case existing do
            nil ->
              []

            ex ->
              [
                {:unrelate, ctx.actor.id, ex.id, hand_relation},
                {:relate, ctx.actor.id, ex.id, :contains},
                {:notify_actor, "You stow the #{ex.name}."}
              ]
          end

        equip_events = [
          {:unrelate, ctx.actor.id, item.id, :contains},
          {:relate, ctx.actor.id, item.id, hand_relation},
          {:notify_actor, "You wield the #{item.name} in your #{hand_label} hand."},
          {:notify_room, "#{ctx.actor.name} wields a #{item.name}.", except: [ctx.actor.id]}
        ]

        {:ok, swap_events ++ equip_events}
    end
  end

  defp find_by_name(items, name) do
    name_down = String.downcase(name)

    Enum.find(items, fn item ->
      item_name = String.downcase(item.name)
      item_name == name_down or String.contains?(item_name, name_down)
    end)
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
end
