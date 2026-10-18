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
  for world topology, while semantic parentage is repaired to the current
  archetype spine.
  """

  alias LineCore.{Archetypes, Object, Repo}
  alias LineCore.Schemas.Object, as: ObjSchema
  import Ecto.Query

  @safehouse_name "District One: Safehouse"

  @room_names %{
    safehouse: @safehouse_name,
    fence_shop: "District One: Fence Shop",
    center: "District One: Scrap Zone Center",
    n: "District One: Scrap Zone (North)",
    e: "District One: Scrap Zone (East)",
    w: "District One: Scrap Zone (West)"
  }

  @generic_items [
    "twisted pipe",
    "copper wire bundle",
    "shattered display",
    "scrap pistol frame"
  ]

  def seed(tree \\ Archetypes.seed()) do
    case existing_safehouse() do
      nil ->
        do_seed(tree)

      _safehouse ->
        repair_semantic_parents(tree)
        rehydrate()
    end
  end

  defp existing_safehouse do
    from(o in ObjSchema,
      where: o.type == :room and o.name == ^@safehouse_name and is_nil(o.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end

  defp do_seed(tree) do
    {:ok, safehouse} =
      Object.create(:room, @safehouse_name, %{
        parent_id: tree.room.id,
        description:
          "A concrete cube, low ceiling, single hanging bulb. A folding chair leans against one wall. The hum of THE LINE's massive ventilation never quite stops."
      })

    {:ok, fence_shop} =
      Object.create(:room, @room_names.fence_shop, %{
        parent_id: tree.room.id,
        description:
          "Steel bins of sorted parts line the walls. Behind the counter, a faded poster of the King smiles at nothing in particular. The fluorescent flickers."
      })

    {:ok, sz_center} =
      Object.create(:room, @room_names.center, %{
        parent_id: tree.room.id,
        description:
          "Rusted lattice underfoot, dust thick on every surface. The remains of a service catwalk overhead drip slow brown water. Junk in every direction."
      })

    {:ok, sz_n} =
      Object.create(:room, @room_names.n, %{
        parent_id: tree.room.id,
        description: "Stripped panels and twisted rebar. Dust here is older."
      })

    {:ok, sz_e} =
      Object.create(:room, @room_names.e, %{
        parent_id: tree.room.id,
        description:
          "A collapsed compressor cabinet, its guts trailing copper into a puddle of fluorescent coolant."
      })

    {:ok, sz_w} =
      Object.create(:room, @room_names.w, %{
        parent_id: tree.room.id,
        description:
          "Burnt-out elevator shaft, the doors prised open and never closed since. Wind moves up the shaft."
      })

    connect(safehouse, sz_center, "north")
    connect(safehouse, fence_shop, "east")
    connect(sz_center, sz_n, "north")
    connect(sz_center, sz_e, "east")
    connect(sz_center, sz_w, "west")

    {:ok, fence} =
      Object.create(:npc, "Hamid", %{
        parent_id: tree.npc.id,
        description:
          "A short, paunchy man in a stained workshirt. His hands are calloused; his eyes miss nothing. The kind of fence who weighs your scrap with his eyes before you've finished walking in."
      })

    {:ok, _} = Object.relate(fence_shop.id, fence.id, :contains)
    Object.set_property(fence.id, "buys", ["scrap", "tool", "weapon"])
    Object.set_property(fence.id, "buy_multiplier", 1.0)

    seed_item(
      tree.item,
      sz_center,
      "twisted pipe",
      "A length of corroded steel pipe, threaded at one end.",
      12,
      "scrap"
    )

    seed_item(
      tree.item,
      sz_n,
      "copper wire bundle",
      "A few meters of stripped copper wire, kinked and dusty.",
      8,
      "scrap"
    )

    seed_item(
      tree.item,
      sz_e,
      "shattered display",
      "What was once a flat-panel display. The glass is mostly gone; the controller board remains.",
      18,
      "scrap"
    )

    seed_item(
      tree.item,
      sz_w,
      "scrap pistol frame",
      "The bare frame of a cheap automatic. No magazine, no slide, no trigger group. Salvageable.",
      30,
      "weapon"
    )

    crowbar =
      seed_item(
        tree.weapon,
        sz_center,
        "bent crowbar",
        "Steel crowbar, bent at the hook. Still useful as a weapon.",
        15,
        "tool"
      )

    Object.set_property(crowbar.id, "damage", 18)

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

  defp repair_semantic_parents(tree) do
    Enum.each(Map.values(@room_names), &reparent_named(&1, tree.room.id))
    reparent_named("Hamid", tree.npc.id)
    Enum.each(@generic_items, &reparent_named(&1, tree.item.id))
    reparent_named("bent crowbar", tree.weapon.id)
    :ok
  end

  defp rehydrate do
    safehouse = find_named(@room_names.safehouse)
    fence_shop = find_named(@room_names.fence_shop)

    %{
      safehouse: safehouse,
      fence_shop: fence_shop,
      fence: find_named("Hamid"),
      scrap_zones: %{
        center: find_named(@room_names.center),
        n: find_named(@room_names.n),
        e: find_named(@room_names.e),
        w: find_named(@room_names.w)
      }
    }
  end

  defp reparent_named(name, parent_id) do
    case find_named(name) do
      nil ->
        :ok

      object when object.parent_id == parent_id ->
        :ok

      object ->
        object
        |> ObjSchema.changeset(%{parent_id: parent_id})
        |> Repo.update!()

        :ok
    end
  end

  defp find_named(name) do
    from(o in ObjSchema,
      where: o.name == ^name and is_nil(o.deleted_at),
      order_by: [asc: o.inserted_at],
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

  defp seed_item(parent, room, name, description, scrap_value, tag) do
    {:ok, item} =
      Object.create(:item, name, %{
        parent_id: parent.id,
        description: description
      })

    {:ok, _} = Object.relate(room.id, item.id, :contains)
    Object.set_property(item.id, "scrap_value", scrap_value)
    Object.set_property(item.id, "tag", tag)
    item
  end
end
