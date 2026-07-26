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

  alias LineCore.{Object, Repo}
  alias LineCore.Schemas.Object, as: ObjSchema
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
    {:ok, safehouse} =
      Object.create(:room, @safehouse_name,
        %{
          description:
            "A concrete cube, low ceiling, single hanging bulb. A folding chair leans against one wall. The hum of THE LINE's massive ventilation never quite stops."
        }
      )

    {:ok, fence_shop} =
      Object.create(:room, "District One: Fence Shop",
        %{
          description:
            "Steel bins of sorted parts line the walls. Behind the counter, a faded poster of the King smiles at nothing in particular. The fluorescent flickers."
        }
      )

    {:ok, sz_center} =
      Object.create(:room, "District One: Scrap Zone Center",
        %{
          description:
            "Rusted lattice underfoot, dust thick on every surface. The remains of a service catwalk overhead drip slow brown water. Junk in every direction."
        }
      )

    {:ok, sz_n} =
      Object.create(:room, "District One: Scrap Zone (North)",
        %{
          description: "Stripped panels and twisted rebar. Dust here is older."
        }
      )

    {:ok, sz_e} =
      Object.create(:room, "District One: Scrap Zone (East)",
        %{
          description:
            "A collapsed compressor cabinet, its guts trailing copper into a puddle of fluorescent coolant."
        }
      )

    {:ok, sz_w} =
      Object.create(:room, "District One: Scrap Zone (West)",
        %{
          description:
            "Burnt-out elevator shaft, the doors prised open and never closed since. Wind moves up the shaft."
        }
      )

    # Connect rooms
    connect(safehouse, sz_center, "north")
    connect(safehouse, fence_shop, "east")
    connect(sz_center, sz_n, "north")
    connect(sz_center, sz_e, "east")
    connect(sz_center, sz_w, "west")

    # Fence NPC
    {:ok, fence} =
      Object.create(:npc, "Hamid",
        %{
          description:
            "A short, paunchy man in a stained workshirt. His hands are calloused; his eyes miss nothing. The kind of fence who weighs your scrap with his eyes before you've finished walking in."
        }
      )

    {:ok, _} = Object.relate(fence_shop.id, fence.id, :contains)
    Object.set_property(fence.id, "buys", ["scrap", "tool", "weapon"])
    Object.set_property(fence.id, "buy_multiplier", 1.0)

    # Starter items scattered in the scrap zone
    seed_item(sz_center, "twisted pipe",
      "A length of corroded steel pipe, threaded at one end.", 12, "scrap"
    )

    seed_item(sz_n, "copper wire bundle",
      "A few meters of stripped copper wire, kinked and dusty.", 8, "scrap"
    )

    seed_item(sz_e, "shattered display",
      "What was once a flat-panel display. The glass is mostly gone; the controller board remains.",
      18, "scrap"
    )

    seed_item(sz_w, "scrap pistol frame",
      "The bare frame of a cheap automatic. No magazine, no slide, no trigger group. Salvageable.",
      30, "weapon"
    )

    seed_item(sz_center, "bent crowbar",
      "Steel crowbar, bent at the hook. Still useful as a weapon.", 15, "tool"
    )

    # Make the crowbar a usable weapon — damage property
    crowbar =
      from(o in ObjSchema,
        where: o.name == "bent crowbar" and is_nil(o.deleted_at),
        order_by: [desc: o.inserted_at],
        limit: 1
      )
      |> Repo.one()

    if crowbar, do: Object.set_property(crowbar.id, "damage", 18)

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

  defp seed_item(room, name, description, scrap_value, tag) do
    {:ok, item} = Object.create(:item, name, %{description: description})
    {:ok, _} = Object.relate(room.id, item.id, :contains)
    Object.set_property(item.id, "scrap_value", scrap_value)
    Object.set_property(item.id, "tag", tag)
    item
  end
end
