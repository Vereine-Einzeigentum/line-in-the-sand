defmodule LineCore.Verbs.Attack do
  @moduledoc """
  `attack <target>` / `kill <target>` / `hit <target>` / `k <target>` —
  attack a target in the current room.

  Phase 0 combat model:
  - Damage = base 10 if unarmed, else the wielded item's `damage` property
  - HP applied via Combat helpers
  - On lethal damage: death events fire (drop items, broadcast death, move to
    safehouse, restore HP, deduct dirham penalty)

  Stat checks (to-hit, dodge) and weapon skill progression come in Phase 1+.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Combat, Object}

  @base_unarmed_damage 10

  @impl true
  def execute(_ctx, []), do: {:error, :attack_who}

  def execute(ctx, [target_name]) do
    candidates =
      Enum.filter(ctx.room_contents, fn o ->
        o.id != ctx.actor.id and o.type in [:player, :npc]
      end)

    target = Object.find_by_name(candidates, target_name)

    cond do
      target == nil ->
        {:error, :not_found}

      target.id == ctx.actor.id ->
        {:error, :cannot_self_target}

      target.type not in [:player, :npc] ->
        {:error, :invalid_target}

      not Combat.alive?(target.id) ->
        {:error, :already_dead}

      true ->
        damage = compute_damage(ctx.actor.id)

        if Combat.would_kill?(target.id, damage) do
          {:ok,
           Combat.damage_events(ctx.actor.id, target.id, damage) ++
             Combat.death_events(target.id)}
        else
          {:ok, Combat.damage_events(ctx.actor.id, target.id, damage)}
        end
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Helpers

  defp compute_damage(actor_id) do
    case Object.related_by(actor_id, :wields_main) do
      [] -> @base_unarmed_damage
      [weapon | _] -> Object.get_property(weapon.id, "damage", @base_unarmed_damage)
    end
  end
end
