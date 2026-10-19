defmodule LineCore.Verbs.Wield do
  @moduledoc """
  `wield <item>` — equip an item in the main hand (default).
  `wield <item> main` — explicit main hand.
  `wield <item> off` — equip in off hand.
  `hold <item>`, `equip <item>` — aliases.

  The item must already be in the actor's inventory (`:contains`). Wielding
  keeps containment intact and adds `:wields_main` or `:wields_off`.

  If something is already wielded in that hand, only its wield relationship
  is removed. Carrying and wielding are independent relations.
  """

  @behaviour LineCore.Verb

  alias LineCore.Object

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
      |> Object.find_by_name(name)

    case candidate do
      nil ->
        {:error, :not_in_inventory}

      item ->
        existing =
          Object.related_by(ctx.actor.id, hand_relation)
          |> List.first()

        swap_events =
          case existing do
            nil ->
              []

            ex ->
              [
                {:unrelate, ctx.actor.id, ex.id, hand_relation},
                {:notify_actor, "You stow the #{ex.name}."}
              ]
          end

        equip_events = [
          {:relate, ctx.actor.id, item.id, hand_relation},
          {:notify_actor, "You wield the #{item.name} in your #{hand_label} hand."},
          {:notify_room, "#{ctx.actor.name} wields a #{item.name}.", except: [ctx.actor.id]}
        ]

        {:ok, swap_events ++ equip_events}
    end
  end
end
