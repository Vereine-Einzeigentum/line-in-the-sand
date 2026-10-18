defmodule LineCore.Combat do
  @moduledoc """
  Core combat helpers — HP/damage application, death handling, respawn.

  Pure functions where possible; functions that build event lists for the
  dispatcher to apply transactionally.

  ## HP model
  - `hp_current` (property): current hit points
  - `hp_max` (property): maximum hit points
  - Default values: 50/50 for players; configurable per NPC

  ## Death
  When `hp_current` drops to or below 0, the actor is "dead". Death events:
  - A persistent `$corpse` container is created in the death room
  - Carried, wielded, and worn objects are moved into the corpse
  - A death notice broadcasts to the room
  - The actor is moved to the configured safehouse room
  - HP is restored to max
  - A `dirham_penalty` is deducted from the actor's dirham property

  ## Respawn
  Configured via the `SAFEHOUSE_ROOM_ID` env var. If unset, respawn raises.
  """

  alias LineCore.{Archetypes, Object}

  @default_hp_max 50
  @default_dirham_penalty 50

  ## HP accessors

  def hp(actor_id) do
    current = Object.get_property(actor_id, "hp_current", @default_hp_max)
    max = Object.get_property(actor_id, "hp_max", @default_hp_max)
    {current, max}
  end

  def alive?(actor_id) do
    {current, _} = hp(actor_id)
    current > 0
  end

  ## Damage event-list builders

  @doc """
  Build the events for applying `damage` to `target_id`, attributed to `attacker_id`.

  Returns a list of dispatcher events. Does not include death events — caller
  must check `would_kill?/2` and append death events if needed.
  """
  def damage_events(attacker_id, target_id, damage) when damage > 0 do
    {current, _max} = hp(target_id)
    new_hp = max(0, current - damage)

    target = Object.get(target_id) || %{name: "something"}
    attacker = Object.get(attacker_id) || %{name: "something"}

    [
      {:set_property, target_id, "hp_current", new_hp},
      {:notify_actor, "[combat] #{target.name}: -#{damage} (#{new_hp} hp)"},
      {:notify_object, target_id, "[combat] #{attacker.name}: -#{damage} (#{new_hp} hp)"},
      {:notify_room, "[combat] #{attacker.name} -> #{target.name}: #{damage}",
       except: [attacker_id, target_id]}
    ]
  end

  def damage_events(_attacker_id, _target_id, _damage), do: []

  @doc "Would this damage drop the target to 0 HP or below?"
  def would_kill?(target_id, damage) do
    {current, _max} = hp(target_id)
    current - damage <= 0
  end

  ## Death event-list builder

  @doc """
  Build the events for killing `victim_id`.

  The body that receives commands is respawned; the material state left behind
  is a normal persistent `$corpse -> $container` object. The corpse has no
  special loot table: former inventory and equipment are simply its contents.
  """
  def death_events(victim_id, opts \ []) do
    safehouse_id = opts[:safehouse_id] || safehouse_room_id()
    penalty = opts[:dirham_penalty] || @default_dirham_penalty
    {_current, max_hp} = hp(victim_id)

    victim = Object.get(victim_id)
    room = Object.container_of(victim_id)

    current_dirham = Object.get_property(victim_id, "dirham", 0)
    new_dirham = max(0, current_dirham - penalty)

    corpse_events(victim_id, victim, room) ++
      [
        {:notify_room, "[death] #{victim.name}"},
        {:move, victim_id, safehouse_id, :contains},
        {:set_property, victim_id, "hp_current", max_hp},
        {:set_property, victim_id, "dirham", new_dirham},
        {:notify_object, victim_id, "[death] respawned at safehouse (-#{penalty} dirham)"}
      ]
  end

  ## Helpers

  defp corpse_events(_victim_id, _victim, nil), do: []

  defp corpse_events(victim_id, victim, room) do
    corpse_parent =
      Archetypes.get(:corpse) ||
        raise "corpse archetype must be seeded before death handling"

    ref = {:corpse, victim_id}
    corpse = {:created, ref}

    carried = Object.contents(victim_id)
    equipped = Object.equipped(victim_id)

    create_events = [
      {:create_object, ref,
       %{
         type: :item,
         name: "corpse of #{victim.name}",
         description: "The remains of #{victim.name}.",
         parent_id: corpse_parent.id
       }},
      {:relate, room.id, corpse, :contains},
      {:set_property, corpse, "corpse_of", victim_id},
      {:set_property, corpse, "former_name", victim.name}
    ]

    carry_events =
      Enum.map(carried, fn object ->
        {:move, object.id, corpse, :contains}
      end)

    equipment_events =
      Enum.flat_map(equipped, fn {rel_type, object} ->
        [
          {:unrelate, victim_id, object.id, rel_type},
          {:relate, corpse, object.id, :contains}
        ]
      end)

    create_events ++ carry_events ++ equipment_events
  end

  defp safehouse_room_id do
    case System.get_env("SAFEHOUSE_ROOM_ID") do
      nil -> raise "SAFEHOUSE_ROOM_ID env var must be set for respawn to function"
      id -> id
    end
  end
end
