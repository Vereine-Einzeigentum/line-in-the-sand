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
  import Ecto.Query

  @safehouse_name "District One: Safehouse"

  def seed do
    # Generics must exist before any Genesis call. Idempotent — safe to call
    # every time the seed runs, even when already seeded.
    LineCore.Seed.Generics.seed()

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
    safehouse =
      Genesis.room!(@safehouse_name,
        description:
          "A concrete cube, low ceiling, single hanging bulb. A folding chair leans against one wall. The hum of THE LINE's massive ventilation never quite stops."
      )

    fence_shop =
      Genesis.room!("District One: Fence Shop",
        description:
          "Steel bins of sorted parts line the walls. Behind the counter, a faded poster of the King smiles at nothing in particular. The fluorescent flickers."
      )

    sz_center =
      Genesis.room!("District One: Scrap Zone Center",
        description:
          "Rusted lattice underfoot, dust thick on every surface. The remains of a service catwalk overhead drip slow brown water. Junk in every direction."
      )

    sz_n =
      Genesis.room!("District One: Scrap Zone (North)",
        description: "Stripped panels and twisted rebar. Dust here is older."
      )

    sz_e =
      Genesis.room!("District One: Scrap Zone (East)",
        description:
          "A collapsed compressor cabinet, its guts trailing copper into a puddle of fluorescent coolant."
      )

    sz_w =
      Genesis.room!("District One: Scrap Zone (West)",
        description:
          "Burnt-out elevator shaft, the doors prised open and never closed since. Wind moves up the shaft."
      )

    # Connect rooms
    connect(safehouse, sz_center, "north")
    connect(safehouse, fence_shop, "east")
    connect(sz_center, sz_n, "north")
    connect(sz_center, sz_e, "east")
    connect(sz_center, sz_w, "west")

    # Fence NPC
    fence =
      Genesis.npc!(fence_shop, "Hamid",
        description:
          "A short, paunchy man in a stained workshirt. His hands are calloused; his eyes miss nothing. The kind of fence who weighs your scrap with his eyes before you've finished walking in.",
        properties: %{
          buys: ["scrap", "tool", "weapon"],
          buy_multiplier: 1.0
        }
      )

    # Starter items scattered in the scrap zone.
    # Items tagged "scrap" derive from the Scrap generic (inherits scrap/sell verbs,
    # scrap_value default). Weapons derive from the Weapon generic (inherits wield/unwield).
    Genesis.item!(sz_center, "twisted pipe",
      template: :scrap,
      description: "A length of corroded steel pipe, threaded at one end.",
      properties: %{scrap_value: 12, tag: "scrap"}
    )

    Genesis.item!(sz_n, "copper wire bundle",
      template: :scrap,
      description: "A few meters of stripped copper wire, kinked and dusty.",
      properties: %{scrap_value: 8, tag: "scrap"}
    )

    Genesis.item!(sz_e, "shattered display",
      template: :scrap,
      description:
        "What was once a flat-panel display. The glass is mostly gone; the controller board remains.",
      properties: %{scrap_value: 18, tag: "scrap"}
    )

    Genesis.item!(sz_w, "scrap pistol frame",
      template: :weapon,
      description: "The bare frame of a cheap automatic. No magazine, no slide, no trigger group. Salvageable.",
      properties: %{scrap_value: 30, tag: "weapon"}
    )

    Genesis.item!(sz_center, "bent crowbar",
      template: :weapon,
      description: "Steel crowbar, bent at the hook. Still useful as a weapon.",
      properties: %{scrap_value: 15, damage: 18, tag: "tool"}
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
    fence_shop =
      from(o in ObjSchema,
        where: o.type == :room and o.name == "District One: Fence Shop" and is_nil(o.deleted_at),
        limit: 1
      )
      |> Repo.one()

    fence =
      if fence_shop do
        from(o in ObjSchema,
          where: o.type == :npc and o.name == "Hamid" and is_nil(o.deleted_at),
          limit: 1
        )
        |> Repo.one()
      end

    %{
      safehouse: safehouse,
      fence_shop: fence_shop,
      fence: fence,
      scrap_zones: %{}
    }
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
