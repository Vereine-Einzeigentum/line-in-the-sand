defmodule LineCore.ScrapLoopTest do
  use ExUnit.Case, async: false

  alias LineCore.{Object, Repo, TestHarness}
  alias LineCore.Verbs.{Scrap, Sell, Get, Go}

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

  ## Scrap

  describe "Scrap verb" do
    test "scraps an item from inventory for dirham and XP" do
      room = TestHarness.spawn_room("Scrap Zone")
      player = TestHarness.spawn_player_in(room, "Scrapper")
      {:ok, pipe} = Object.create(:item, "twisted pipe")
      Object.relate(player.id, pipe.id, :contains)
      Object.set_property(pipe.id, "scrap_value", 15)

      TestHarness.dispatch(player, Scrap, ["pipe"])
      TestHarness.assert_msg(~r/break down the twisted pipe.*\+15 Dh.*\+1 Scrap XP/)

      assert Object.get_property(player.id, "dirham") == 15
      assert Object.get_property(player.id, "skill_scrap_xp") == 1

      # Item soft-deleted
      assert Object.get(pipe.id) == nil
    end

    test "accumulates across multiple scraps" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Scrapper")

      Enum.each(1..3, fn i ->
        {:ok, item} = Object.create(:item, "junk_#{i}")
        Object.relate(player.id, item.id, :contains)
        Object.set_property(item.id, "scrap_value", 10)
        TestHarness.dispatch(player, Scrap, ["junk_#{i}"])
        TestHarness.assert_msg(~r/break down/)
      end)

      assert Object.get_property(player.id, "dirham") == 30
      assert Object.get_property(player.id, "skill_scrap_xp") == 3
    end

    test "refuses unscrappable items" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Scrapper")
      {:ok, item} = Object.create(:item, "letter")
      Object.relate(player.id, item.id, :contains)
      # No scrap_value property

      assert {:error, :unscrappable} = TestHarness.dispatch(player, Scrap, ["letter"])
    end

    test "errors when item not in inventory" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :not_in_inventory} = TestHarness.dispatch(player, Scrap, ["nothing"])
    end
  end

  ## Sell

  describe "Sell verb" do
    test "sells an item to an NPC fence" do
      room = TestHarness.spawn_room("Fence's Shop")
      player = TestHarness.spawn_player_in(room, "Seller")
      fence = TestHarness.spawn_npc_in(room, "Hamid the Fence")
      Object.set_property(fence.id, "buys", ["scrap", "tool", "weapon"])
      Object.set_property(fence.id, "buy_multiplier", 1.5)

      {:ok, pipe} = Object.create(:item, "rusty pipe")
      Object.relate(player.id, pipe.id, :contains)
      Object.set_property(pipe.id, "scrap_value", 20)
      Object.set_property(pipe.id, "tag", "scrap")

      TestHarness.dispatch(player, Sell, ["pipe", "Hamid"])

      # 20 * 1.5 = 30
      TestHarness.assert_msg(~r/pay you 30 Dh/)
      assert Object.get_property(player.id, "dirham") == 30

      # Item now in fence's inventory
      fence_inv = Object.contents(fence.id)
      assert Enum.any?(fence_inv, &(&1.id == pipe.id))
    end

    test "fence pays default 1.0 multiplier when unset" do
      room = TestHarness.spawn_room("Shop")
      player = TestHarness.spawn_player_in(room, "Seller")
      fence = TestHarness.spawn_npc_in(room, "Cheap Fence")
      Object.set_property(fence.id, "buys", ["scrap"])
      # No buy_multiplier set

      {:ok, item} = Object.create(:item, "widget")
      Object.relate(player.id, item.id, :contains)
      Object.set_property(item.id, "scrap_value", 25)
      Object.set_property(item.id, "tag", "scrap")

      TestHarness.dispatch(player, Sell, ["widget", "Cheap"])
      TestHarness.assert_msg(~r/pay you 25 Dh/)
    end

    test "fence refuses items they don't buy" do
      room = TestHarness.spawn_room("Shop")
      player = TestHarness.spawn_player_in(room, "Seller")
      fence = TestHarness.spawn_npc_in(room, "Choosy Fence")
      Object.set_property(fence.id, "buys", ["tool"])

      {:ok, item} = Object.create(:item, "love letter")
      Object.relate(player.id, item.id, :contains)
      Object.set_property(item.id, "scrap_value", 5)
      Object.set_property(item.id, "tag", "personal")

      assert {:error, :buyer_uninterested} =
               TestHarness.dispatch(player, Sell, ["letter", "Choosy"])
    end

    test "errors when buyer not present" do
      room = TestHarness.spawn_room("Empty")
      player = TestHarness.spawn_player_in(room)
      {:ok, item} = Object.create(:item, "thing")
      Object.relate(player.id, item.id, :contains)

      assert {:error, :no_such_buyer} =
               TestHarness.dispatch(player, Sell, ["thing", "Nobody"])
    end

    test "errors with no recipient" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :sell_to_whom} = TestHarness.dispatch(player, Sell, ["thing"])
    end
  end

  ## Full Scrap Run end-to-end

  describe "Full Scrap Run loop" do
    test "complete loop: walk → get → walk back → scrap → sell" do
      # World
      safehouse = TestHarness.spawn_room("Safehouse", "A concrete cube.")
      scrap_zone = TestHarness.spawn_room("Scrap Zone", "Rusted metal everywhere.")
      fence_shop = TestHarness.spawn_room("Fence's Shop", "Bins of parts.")

      TestHarness.connect_rooms(safehouse, scrap_zone, "north")
      TestHarness.connect_rooms(safehouse, fence_shop, "east")

      # Junk in scrap zone
      {:ok, pipe} = Object.create(:item, "twisted pipe")
      Object.relate(scrap_zone.id, pipe.id, :contains)
      Object.set_property(pipe.id, "scrap_value", 12)
      Object.set_property(pipe.id, "tag", "scrap")

      {:ok, wire} = Object.create(:item, "copper wire")
      Object.relate(scrap_zone.id, wire.id, :contains)
      Object.set_property(wire.id, "scrap_value", 8)
      Object.set_property(wire.id, "tag", "scrap")

      # Fence
      fence = TestHarness.spawn_npc_in(fence_shop, "Hamid")
      Object.set_property(fence.id, "buys", ["scrap"])
      Object.set_property(fence.id, "buy_multiplier", 1.5)

      # Player starts in safehouse
      player = TestHarness.spawn_player_in(safehouse, "Runner")

      # 1. Walk north to scrap zone
      TestHarness.dispatch(player, Go, ["n"])
      TestHarness.assert_msg(~r/walk north/)

      # 2. Pick up pipe and wire
      TestHarness.dispatch(player, Get, ["pipe"])
      TestHarness.assert_msg(~r/pick up the twisted pipe/)

      TestHarness.dispatch(player, Get, ["wire"])
      TestHarness.assert_msg(~r/pick up the copper wire/)

      # 3. Walk back south
      TestHarness.dispatch(player, Go, ["s"])
      TestHarness.assert_msg(~r/walk south/)

      # 4. Scrap one item for direct value (12 Dh, 1 XP)
      TestHarness.dispatch(player, Scrap, ["pipe"])
      TestHarness.assert_msg(~r/\+12 Dh/)
      assert Object.get_property(player.id, "dirham") == 12
      assert Object.get_property(player.id, "skill_scrap_xp") == 1

      # 5. Walk east to fence
      TestHarness.dispatch(player, Go, ["e"])
      TestHarness.assert_msg(~r/walk east/)

      # 6. Sell the wire to fence (8 * 1.5 = 12)
      TestHarness.dispatch(player, Sell, ["wire", "Hamid"])
      TestHarness.assert_msg(~r/pay you 12 Dh/)

      # Total dirham: 12 (scrap) + 12 (sell) = 24
      assert Object.get_property(player.id, "dirham") == 24
    end
  end
end
