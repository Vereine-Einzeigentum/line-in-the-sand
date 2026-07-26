defmodule LineCore.Seed.DistrictOneTest do
  use ExUnit.Case, async: false

  alias LineCore.{Object, Repo}
  alias LineCore.Seed.DistrictOne
  alias LineCore.Verbs.{Go, Get, Look, Scrap}

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    :ok
  end

  test "seed creates safehouse, fence shop, scrap zone, fence NPC, starter items" do
    result = DistrictOne.seed()

    assert result.safehouse.type == :room
    assert result.safehouse.name == "District One: Safehouse"
    assert result.fence_shop.type == :room
    assert result.fence.type == :npc
    assert result.fence.name == "Hamid"

    # Fence has the right buys list
    buys = Object.get_property(result.fence.id, "buys")
    assert "scrap" in buys
    assert "tool" in buys

    # Items exist in scrap zones
    sz_center_items =
      Object.contents(result.scrap_zones.center.id) |> Enum.filter(&(&1.type == :item))

    assert length(sz_center_items) >= 1
  end

  test "seed is idempotent" do
    r1 = DistrictOne.seed()
    r2 = DistrictOne.seed()

    # Same safehouse on second call
    assert r1.safehouse.id == r2.safehouse.id
  end

  test "rooms are connected in expected topology" do
    result = DistrictOne.seed()

    # Safehouse → Scrap Zone (north)
    assert %{id: sz_id} = Object.resolve_exit(result.safehouse.id, "north")
    assert sz_id == result.scrap_zones.center.id

    # Safehouse → Fence Shop (east)
    assert %{id: fs_id} = Object.resolve_exit(result.safehouse.id, "east")
    assert fs_id == result.fence_shop.id

    # Reverse: Scrap Zone center → Safehouse (south)
    assert %{id: sh_id} = Object.resolve_exit(result.scrap_zones.center.id, "south")
    assert sh_id == result.safehouse.id

    # Scrap Zone center → North wing
    assert %{} = Object.resolve_exit(result.scrap_zones.center.id, "north")
    # Scrap Zone center → East wing
    assert %{} = Object.resolve_exit(result.scrap_zones.center.id, "east")
    # Scrap Zone center → West wing
    assert %{} = Object.resolve_exit(result.scrap_zones.center.id, "west")
  end

  test "full Scrap Run on seeded data: walk → grab → scrap → walk → sell" do
    result = DistrictOne.seed()
    safehouse = result.safehouse

    # Place a player in the safehouse and subscribe
    {:ok, player} = Object.create(:player, "FullRunTester")
    Object.relate(safehouse.id, player.id, :contains)
    LineCore.PubSub.subscribe({:actor, player.id})

    # 1. Walk into scrap zone
    LineCore.Dispatcher.dispatch(player.id, Go, ["n"], "go n")
    assert_receive {:msg, _}, 500

    # 2. Look at the room
    LineCore.Dispatcher.dispatch(player.id, Look, [], "look")
    assert_receive {:msg, room_desc}, 500
    assert room_desc =~ "Scrap Zone Center"

    # 3. Pick up the twisted pipe
    LineCore.Dispatcher.dispatch(player.id, Get, ["pipe"], "get pipe")
    assert_receive {:msg, msg}, 500
    assert msg =~ "twisted pipe"

    # 4. Walk back to safehouse
    LineCore.Dispatcher.dispatch(player.id, Go, ["s"], "go s")
    assert_receive {:msg, _}, 500

    # 5. Scrap the pipe for 12 Dh
    LineCore.Dispatcher.dispatch(player.id, Scrap, ["pipe"], "scrap pipe")
    assert_receive {:msg, scrap_msg}, 500
    assert scrap_msg =~ "+12 Dh"

    assert Object.get_property(player.id, "dirham") == 12

    # 6. Walk east to fence shop
    LineCore.Dispatcher.dispatch(player.id, Go, ["e"], "go e")
    assert_receive {:msg, _}, 500

    # Verify fence is there
    fs_contents = Object.contents(result.fence_shop.id)
    assert Enum.any?(fs_contents, &(&1.id == result.fence.id))
  end
end
