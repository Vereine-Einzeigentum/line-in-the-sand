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

  alias LineCore.{Combat, Object, Repo}
  alias LineCore.Schemas.Relationship
  import Ecto.Query

  @base_unarmed_damage 10

  @impl true
  def execute(_ctx, []), do: {:error, :attack_who}

  def execute(ctx, [target_name]) do
    target = find_target(ctx, target_name)

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

  defp find_target(ctx, name) do
    name_down = String.downcase(name)

    Enum.find(ctx.room_contents, fn o ->
      o.id != ctx.actor.id and
        o.type in [:player, :npc] and
        (String.downcase(o.name) == name_down or
           String.contains?(String.downcase(o.name), name_down))
    end)
  end

  defp compute_damage(actor_id) do
    case wielded_weapon(actor_id) do
      nil -> @base_unarmed_damage
      weapon -> Object.get_property(weapon.id, "damage", @base_unarmed_damage)
    end
  end

  defp wielded_weapon(actor_id) do
    from(o in LineCore.Schemas.Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where:
        r.from_id == ^actor_id and
          r.type == :wields_main and
          is_nil(o.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end
end
