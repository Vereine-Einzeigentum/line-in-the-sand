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
  - Carried items are dropped to the room
  - Wielded/worn items are unequipped (also dropped)
  - A "death notice" broadcasts to the room
  - The actor is moved to the configured safehouse room
  - HP is restored to max
  - A `dirham_penalty` is deducted from the actor's dirham property

  ## Respawn
  Configured via the `SAFEHOUSE_ROOM_ID` env var. If unset, respawn raises.
  (In production, this is the District 1 safehouse seeded by Step 8.)
  """

  alias LineCore.Object

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
      {:notify_actor, "You hit #{target.name} for #{damage} damage. (#{new_hp} HP remaining)"},
      {:notify_object, target_id,
       "#{attacker.name} hits you for #{damage} damage. (#{new_hp} HP remaining)"},
      {:notify_room, "#{attacker.name} hits #{target.name}.", except: [attacker_id, target_id]}
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
  Build the events for killing `victim_id`. Drops carried items, broadcasts
  death, moves to safehouse, restores HP, applies dirham penalty.

  Returns a list of dispatcher events.
  """
  def death_events(victim_id, opts \\ []) do
    safehouse_id = opts[:safehouse_id] || safehouse_room_id()
    penalty = opts[:dirham_penalty] || @default_dirham_penalty
    {_current, max_hp} = hp(victim_id)

    victim = Object.get(victim_id)

    drop_events = drop_carried_events(victim_id, victim)

    current_dirham = Object.get_property(victim_id, "dirham", 0)
    new_dirham = max(0, current_dirham - penalty)

    drop_events ++
      [
        {:notify_room, "#{victim.name} collapses, motionless."},
        {:move, victim_id, safehouse_id, :contains},
        {:set_property, victim_id, "hp_current", max_hp},
        {:set_property, victim_id, "dirham", new_dirham},
        {:notify_object, victim_id,
         "Everything goes dark. You wake at the safehouse, body restored — #{penalty} Dirham lighter."}
      ]
  end

  ## Helpers

  defp drop_carried_events(victim_id, victim) do
    carried =
      victim_id
      |> Object.contents()
      |> Enum.filter(&(&1.type == :item))

    equipped = Object.equipped(victim_id)
    room = Object.container_of(victim_id) || %{id: nil}

    case room.id do
      nil ->
        []

      room_id ->
        carry_drops =
          Enum.flat_map(carried, fn item ->
            [
              {:move, item.id, room_id, :contains},
              {:notify_room, "#{victim.name}'s #{item.name} clatters to the ground.",
               except: [victim_id]}
            ]
          end)

        equip_drops =
          Enum.flat_map(equipped, fn {rel_type, item} ->
            [
              {:unrelate, victim_id, item.id, rel_type},
              {:relate, room_id, item.id, :contains},
              {:notify_room, "#{victim.name}'s #{item.name} clatters to the ground.",
               except: [victim_id]}
            ]
          end)

        carry_drops ++ equip_drops
    end
  end

  defp safehouse_room_id do
    case System.get_env("SAFEHOUSE_ROOM_ID") do
      nil -> raise "SAFEHOUSE_ROOM_ID env var must be set for respawn to function"
      id -> id
    end
  end
end
