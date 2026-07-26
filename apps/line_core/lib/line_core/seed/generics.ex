defmodule LineCore.Seed.Generics do
  @moduledoc """
  The prototype root of the world: a mother object and the generics that derive
  from it.

  This is the MOO idiom. You do not build a room from nothing; you derive one
  from the generic room, which already knows what rooms are like. Anything a
  descendant does not define resolves upward, so changing a generic changes
  every object descended from it — including objects an object model generates
  later, which is the point: a generated NPC should inherit NPC-ness rather
  than mint every property from scratch.

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

    # Every thing that can be looked at, carried, or talked to hangs off one of
    # these. Verbs are additive down the chain, so each generic lists only what
    # it introduces.
    {:ok, room} =
      Object.create(:generic, "Generic Room", %{
        parent_id: mother.id,
        description: "A space with edges and ways out.",
        verbs: ["go"]
      })

    {:ok, thing} =
      Object.create(:generic, "Generic Thing", %{
        parent_id: mother.id,
        description: "An object with mass, salvage value, and a history.",
        verbs: ["get", "drop", "give"]
      })

    {:ok, being} =
      Object.create(:generic, "Generic Being", %{
        parent_id: mother.id,
        description: "Something alive enough to be hurt.",
        verbs: ["say", "emote", "attack"]
      })

    {:ok, player} =
      Object.create(:generic, "Generic Player", %{
        parent_id: being.id,
        description: "A resident of THE LINE, restored more times than they admit.",
        verbs: ["inventory", "score", "who", "help", "desc", "text"]
      })

    {:ok, npc} =
      Object.create(:generic, "Generic NPC", %{
        parent_id: being.id,
        description: "Someone who lives here and was not summoned by a login."
      })

    {:ok, weapon} =
      Object.create(:generic, "Generic Weapon", %{
        parent_id: thing.id,
        description: "A thing shaped, or repurposed, for damage.",
        verbs: ["wield", "unwield"]
      })

    {:ok, scrap} =
      Object.create(:generic, "Generic Scrap", %{
        parent_id: thing.id,
        description: "Material worth more taken apart than whole.",
        verbs: ["scrap", "sell"]
      })

    # Defaults live on the generics so descendants only store what differs.
    Object.set_property(being.id, "hp_max", 20)
    Object.set_property(being.id, "hp_current", 20)
    Object.set_property(player.id, "dirham", 0)
    Object.set_property(scrap.id, "scrap_value", 5)
    Object.set_property(weapon.id, "damage", 3)

    %{
      mother: mother,
      room: room,
      thing: thing,
      being: being,
      player: player,
      npc: npc,
      weapon: weapon,
      scrap: scrap
    }
  end

  defp collect(mother) do
    %{
      mother: mother,
      room: find("Generic Room"),
      thing: find("Generic Thing"),
      being: find("Generic Being"),
      player: find("Generic Player"),
      npc: find("Generic NPC"),
      weapon: find("Generic Weapon"),
      scrap: find("Generic Scrap")
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
