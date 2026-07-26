defmodule LineCore.Seed.DistrictOne do
  @moduledoc """
  Seeds the first district: a Safehouse, four-room Scrap Zone, Fence Shop,
  and one fence NPC with a few starter items.

  Map (top-down):

              [scrap zone N]
                   |
      [scrap zone W] - [scrap zone center] - [scrap zone E]
                   |
                [safehouse] - [fence shop]

  All connections are bidirectional.

  Everything here is built with `LineCore.Genesis`, so every room, item and NPC
  derives from a generic and inherits from it. `Generics.seed/0` runs first —
  the prototype chain has to exist before anything can descend from it.

  Idempotent: running this seed when District One already exists is a no-op
  (detected via `District One: Safehouse` name uniqueness within type=:room).

  Returns a map of named rooms and the fence for downstream use:

      %{
        safehouse: %Object{},
        fence_shop: %Object{},
        fence: %Object{},
        scrap_zones: %{center: ..., n: ..., e: ..., w: ...}
      }
  """

  alias LineCore.{Genesis, Object, Repo}
  alias LineCore.Schemas.Object, as: ObjSchema
  alias LineCore.Seed.Generics
  import Ecto.Query

  @safehouse_name "District One: Safehouse"

  def seed do
    case existing_safehouse() do
      nil ->
        do_seed()

      safehouse ->
        # Already seeded — rehydrate the structure
        rehydrate(safehouse)
    end
  end

  defp existing_safehouse do
    from(o in ObjSchema,
      where: o.type == :room and o.name == ^@safehouse_name and is_nil(o.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end

  defp do_seed do
    # District One descends from the generics, so they have to be there first.
    Generics.seed()

    safehouse =
      Genesis.room!(@safehouse_name,
        source: :seed,
        description:
          "A concrete cube, low ceiling, single hanging bulb. A folding chair leans against one wall. The hum of THE LINE's massive ventilation never quite stops."
      )

    fence_shop =
      Genesis.room!("District One: Fence Shop",
        source: :seed,
        description:
          "Steel bins of sorted parts line the walls. Behind the counter, a faded poster of the King smiles at nothing in particular. The fluorescent flickers."
      )

    sz_center =
      Genesis.room!("District One: Scrap Zone Center",
        source: :seed,
        description:
          "Rusted lattice underfoot, dust thick on every surface. The remains of a service catwalk overhead drip slow brown water. Junk in every direction."
      )

    sz_n =
      Genesis.room!("District One: Scrap Zone (North)",
        source: :seed,
        description: "Stripped panels and twisted rebar. Dust here is older."
      )

    sz_e =
      Genesis.room!("District One: Scrap Zone (East)",
        source: :seed,
        description:
          "A collapsed compressor cabinet, its guts trailing copper into a puddle of fluorescent coolant."
      )

    sz_w =
      Genesis.room!("District One: Scrap Zone (West)",
        source: :seed,
        description:
          "Burnt-out elevator shaft, the doors prised open and never closed since. Wind moves up the shaft."
      )

    # Connect rooms
    connect(safehouse, sz_center, "north")
    connect(safehouse, fence_shop, "east")
    connect(sz_center, sz_n, "north")
    connect(sz_center, sz_e, "east")
    connect(sz_center, sz_w, "west")

    # Fence NPC. Derives from Generic NPC, so he arrives with the health bars
    # and chargen attributes every Mob has.
    fence =
      Genesis.npc!(fence_shop, "Hamid",
        source: :seed,
        description:
          "A short, paunchy man in a stained workshirt. His hands are calloused; his eyes miss nothing. The kind of fence who weighs your scrap with his eyes before you've finished walking in.",
        properties: %{
          "buys" => ["scrap", "tool", "weapon"],
          "buy_multiplier" => 1.0
        }
      )

    # Starter items scattered in the scrap zone. The template decides what each
    # one *is* — a :scrap derivative can be scrapped and sold, a :weapon
    # derivative can be wielded, and neither has to list those verbs itself.
    Genesis.item!(sz_center, "twisted pipe",
      source: :seed,
      template: :scrap,
      description: "A length of corroded steel pipe, threaded at one end.",
      properties: %{"scrap_value" => 12, "tag" => "scrap"}
    )

    Genesis.item!(sz_n, "copper wire bundle",
      source: :seed,
      template: :scrap,
      description: "A few meters of stripped copper wire, kinked and dusty.",
      properties: %{"scrap_value" => 8, "tag" => "scrap"}
    )

    Genesis.item!(sz_e, "shattered display",
      source: :seed,
      template: :scrap,
      description:
        "What was once a flat-panel display. The glass is mostly gone; the controller board remains.",
      properties: %{"scrap_value" => 18, "tag" => "scrap"}
    )

    Genesis.item!(sz_w, "scrap pistol frame",
      source: :seed,
      template: :weapon,
      description:
        "The bare frame of a cheap automatic. No magazine, no slide, no trigger group. Salvageable.",
      properties: %{"scrap_value" => 30, "tag" => "weapon"}
    )

    # One object, one transaction, no re-query to bolt the damage on afterwards.
    Genesis.item!(sz_center, "bent crowbar",
      source: :seed,
      template: :weapon,
      description: "Steel crowbar, bent at the hook. Still useful as a weapon.",
      properties: %{"scrap_value" => 15, "damage" => 18, "tag" => "tool"}
    )

    %{
      safehouse: safehouse,
      fence_shop: fence_shop,
      fence: fence,
      scrap_zones: %{
        center: sz_center,
        n: sz_n,
        e: sz_e,
        w: sz_w
      }
    }
  end

  defp rehydrate(safehouse) do
    fence_shop = find(:room, "District One: Fence Shop")

    %{
      safehouse: safehouse,
      fence_shop: fence_shop,
      fence: if(fence_shop, do: find(:npc, "Hamid")),
      scrap_zones: %{
        center: find(:room, "District One: Scrap Zone Center"),
        n: find(:room, "District One: Scrap Zone (North)"),
        e: find(:room, "District One: Scrap Zone (East)"),
        w: find(:room, "District One: Scrap Zone (West)")
      }
    }
  end

  defp find(type, name) do
    from(o in ObjSchema,
      where: o.type == ^type and o.name == ^name and is_nil(o.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end

  defp connect(a, b, dir) do
    {:ok, _} = Object.relate(a.id, b.id, :exit_to, %{"direction" => dir})
    {:ok, _} = Object.relate(b.id, a.id, :exit_to, %{"direction" => opposite(dir)})
    :ok
  end

  defp opposite("north"), do: "south"
  defp opposite("south"), do: "north"
  defp opposite("east"), do: "west"
  defp opposite("west"), do: "east"
  defp opposite(d), do: d
end
