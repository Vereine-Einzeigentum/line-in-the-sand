defmodule LineCore.Seed.Generics do
  @moduledoc """
  The prototype root of the world: a mother object and the generics that derive
  from it.

  This is the MOO idiom. You do not build a room from nothing; you derive one
  from the Room generic, which already knows what rooms are like. Anything a
  descendant does not define resolves upward, so changing a generic changes
  every object descended from it — including objects an object model generates
  later, which is the point: a generated NPC should inherit NPC-ness rather
  than mint every property from scratch.

  ## Taxonomy

      The Line  (mother — everything descends from here)
      ├── Room                      instance_type: "room"
      ├── Thing                     (abstract)
      │   ├── Weapon                instance_type: "item"
      │   └── Scrap                 instance_type: "item"
      └── Mob                       (abstract)
          ├── Human                 (abstract)
          │   ├── NPC               instance_type: "npc"
          │   └── PC                instance_type: "player"
          └── Agent                 (abstract)
              └── Operator          instance_type: "npc"

  **Only leaf generics declare `instance_type`.**  Abstract intermediates
  (`Thing`, `Mob`, `Human`, `Agent`) deliberately omit it, so spawning from
  them via `LineCore.Genesis` returns `{:error, :abstract_generic}` rather than
  silently producing a wrongly-typed object.

  Idempotent, keyed on the mother object's name.
  """

  alias LineCore.Object

  @mother "The Line"

  @doc "Seed the prototype chain. Returns a map of generic name => object."
  def seed do
    case find(@mother) do
      nil -> do_seed()
      mother -> collect(mother)
    end
  end

  @doc "The mother object, or nil before seeding."
  def mother, do: find(@mother)

  defp do_seed do
    {:ok, mother} =
      Object.create(:generic, @mother, %{
        description:
          "The building itself. Everything in THE LINE descends from this, whether it knows it or not.",
        verbs: ["look", "examine"]
      })

    # ── Rooms ────────────────────────────────────────────────────────────────
    {:ok, room} =
      Object.create(:generic, "Room", %{
        parent_id: mother.id,
        description: "A space with edges and ways out.",
        verbs: ["go"]
      })

    # ── Things ───────────────────────────────────────────────────────────────
    {:ok, thing} =
      Object.create(:generic, "Thing", %{
        parent_id: mother.id,
        description: "An object with mass, salvage value, and a history.",
        verbs: ["get", "drop", "give"]
      })

    {:ok, weapon} =
      Object.create(:generic, "Weapon", %{
        parent_id: thing.id,
        description: "A thing shaped, or repurposed, for damage.",
        verbs: ["wield", "unwield"]
      })

    {:ok, scrap} =
      Object.create(:generic, "Scrap", %{
        parent_id: thing.id,
        description: "Material worth more taken apart than whole.",
        verbs: ["scrap", "sell"]
      })

    # ── Beings ───────────────────────────────────────────────────────────────
    {:ok, mob} =
      Object.create(:generic, "Mob", %{
        parent_id: mother.id,
        description: "Something alive enough to be hurt.",
        verbs: ["say", "emote", "attack"]
      })

    {:ok, human} =
      Object.create(:generic, "Human", %{
        parent_id: mob.id,
        description: "A resident of THE LINE, shaped by it."
      })

    {:ok, npc} =
      Object.create(:generic, "NPC", %{
        parent_id: human.id,
        description: "Someone who lives here and was not summoned by a login."
      })

    {:ok, pc} =
      Object.create(:generic, "PC", %{
        parent_id: human.id,
        description: "A resident of THE LINE, restored more times than they admit.",
        verbs: ["inventory", "score", "who", "help", "desc", "text"]
      })

    # ── Staff ─────────────────────────────────────────────────────────────────
    {:ok, agent} =
      Object.create(:generic, "Agent", %{
        parent_id: mob.id,
        description: "An entity of the building, not of the residents."
      })

    {:ok, operator} =
      Object.create(:generic, "Operator", %{
        parent_id: agent.id,
        description: "A named presence with responsibilities."
      })

    # ── instance_type on leaf generics ────────────────────────────────────────
    # Only leaves declare this. Genesis reads it to resolve the Ecto object type
    # when the caller does not name it explicitly.  Abstract intermediates (Mob,
    # Human, Agent, Thing) are left unset so spawning from them is a hard error.
    Object.set_property(room.id, "instance_type", "room")
    Object.set_property(weapon.id, "instance_type", "item")
    Object.set_property(scrap.id, "instance_type", "item")
    Object.set_property(npc.id, "instance_type", "npc")
    Object.set_property(pc.id, "instance_type", "player")
    Object.set_property(operator.id, "instance_type", "npc")

    # ── Defaults live on generics so descendants only store what differs ───────
    Object.set_property(mob.id, "hp_max", 20)
    Object.set_property(mob.id, "hp_current", 20)

    # A PC is sturdier than a baseline Mob. 50 is what `LineCore.Combat`
    # documents as the player HP model and falls back to when nothing is set,
    # so the generic and the fallback now agree instead of contradicting each
    # other — which they quietly did for as long as nothing descended from the
    # generics and the fallback was the only value anyone ever saw.
    Object.set_property(pc.id, "hp_max", 50)
    Object.set_property(pc.id, "hp_current", 50)

    Object.set_property(pc.id, "dirham", 0)
    Object.set_property(scrap.id, "scrap_value", 5)
    Object.set_property(weapon.id, "damage", 3)

    %{
      mother: mother,
      room: room,
      thing: thing,
      mob: mob,
      human: human,
      npc: npc,
      pc: pc,
      weapon: weapon,
      scrap: scrap,
      agent: agent,
      operator: operator
    }
  end

  defp collect(mother) do
    %{
      mother: mother,
      room: find("Room"),
      thing: find("Thing"),
      mob: find("Mob"),
      human: find("Human"),
      npc: find("NPC"),
      pc: find("PC"),
      weapon: find("Weapon"),
      scrap: find("Scrap"),
      agent: find("Agent"),
      operator: find("Operator")
    }
  end

  defp find(name) do
    import Ecto.Query

    from(o in LineCore.Schemas.Object,
      where: o.name == ^name and o.type == :generic and is_nil(o.deleted_at),
      limit: 1
    )
    |> LineCore.Repo.one()
  end
end
