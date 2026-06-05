defmodule LineCore.CombatTest do
  use ExUnit.Case, async: false

  alias LineCore.{Combat, Object, Repo, TestHarness}
  alias LineCore.Verbs.{Attack, Wield, Inventory}

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    # Seed a safehouse for respawn
    {:ok, safehouse} = Object.create(:room, "Safehouse", %{description: "Restored."})
    System.put_env("SAFEHOUSE_ROOM_ID", safehouse.id)

    on_exit(fn ->
      System.delete_env("SAFEHOUSE_ROOM_ID")
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    {:ok, safehouse: safehouse}
  end

  describe "Combat helpers" do
    test "hp/1 returns defaults for unset properties" do
      {:ok, p} = Object.create(:player, "Test")
      {current, max} = Combat.hp(p.id)
      assert current == 50
      assert max == 50
    end

    test "alive?/1 reflects HP" do
      {:ok, p} = Object.create(:player, "Test")
      assert Combat.alive?(p.id)

      Object.set_property(p.id, "hp_current", 0)
      refute Combat.alive?(p.id)
    end

    test "would_kill?/2 calculates lethality" do
      {:ok, p} = Object.create(:player, "Test")
      refute Combat.would_kill?(p.id, 10)
      assert Combat.would_kill?(p.id, 50)
      assert Combat.would_kill?(p.id, 9999)
    end
  end

  describe "Wield verb" do
    test "wields an item from inventory in main hand" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Wielder")
      {:ok, knife} = Object.create(:item, "rusty knife")
      Object.relate(player.id, knife.id, :contains)

      TestHarness.dispatch(player, Wield, ["knife"])
      TestHarness.assert_msg(~r/You wield the rusty knife in your main hand/)

      # Inventory should reflect it as wielded, not carried
      TestHarness.dispatch(player, Inventory, [])
      msg = TestHarness.assert_msg(~r/Wielding in main hand: rusty knife/)
      refute msg =~ "carrying:\n  - rusty knife"
    end

    test "wields in off hand explicitly" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Wielder")
      {:ok, pistol} = Object.create(:item, "scrap pistol")
      Object.relate(player.id, pistol.id, :contains)

      TestHarness.dispatch(player, Wield, ["pistol", "off"])
      TestHarness.assert_msg(~r/in your off hand/)

      TestHarness.dispatch(player, Inventory, [])
      TestHarness.assert_msg(~r/Wielding in off hand: scrap pistol/)
    end

    test "swaps existing wielded item back to inventory" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Wielder")
      {:ok, knife} = Object.create(:item, "knife")
      {:ok, club} = Object.create(:item, "club")
      Object.relate(player.id, knife.id, :contains)
      Object.relate(player.id, club.id, :contains)

      TestHarness.dispatch(player, Wield, ["knife"])
      TestHarness.assert_msg(~r/wield the knife/)

      TestHarness.dispatch(player, Wield, ["club"])
      TestHarness.assert_msg(~r/stow the knife/)
      TestHarness.assert_msg(~r/wield the club/)
    end

    test "errors when item not in inventory" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :not_in_inventory} = TestHarness.dispatch(player, Wield, ["nothing"])
    end
  end

  describe "Attack verb — non-lethal" do
    test "applies damage to target" do
      room = TestHarness.spawn_room("Arena")
      attacker = TestHarness.spawn_player_in(room, "Attacker")
      target = TestHarness.spawn_player_in(room, "Target")

      TestHarness.dispatch(attacker, Attack, ["Target"])
      TestHarness.assert_msg(~r/You hit Target for 10 damage/)

      {current, _} = Combat.hp(target.id)
      assert current == 40
    end

    test "errors when target not in room" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :not_found} = TestHarness.dispatch(player, Attack, ["GhostPerson"])
    end

    test "errors when attacking self" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Solo")
      # find_target/2 excludes the actor from candidates, so self-name resolves to nil → :not_found
      assert {:error, :not_found} = TestHarness.dispatch(player, Attack, ["Solo"])
    end

    test "wielded weapon damage overrides unarmed base" do
      room = TestHarness.spawn_room("Arena")
      attacker = TestHarness.spawn_player_in(room, "Attacker")
      _target = TestHarness.spawn_player_in(room, "Target")

      # Give attacker a weapon with damage=20
      {:ok, knife} = Object.create(:item, "sharp knife", %{})
      Object.relate(attacker.id, knife.id, :wields_main)
      Object.set_property(knife.id, "damage", 20)

      TestHarness.dispatch(attacker, Attack, ["Target"])
      TestHarness.assert_msg(~r/You hit Target for 20 damage/)
    end
  end

  describe "Attack verb — lethal & respawn" do
    test "killing a target moves them to safehouse, restores HP, drops items", %{
      safehouse: safehouse
    } do
      room = TestHarness.spawn_room("Arena", "A pit.")
      attacker = TestHarness.spawn_player_in(room, "Attacker")
      target = TestHarness.spawn_player_in(room, "Target")
      Object.set_property(target.id, "hp_current", 5)
      Object.set_property(target.id, "dirham", 100)

      # Give target an item to verify drop-on-death
      {:ok, knife} = Object.create(:item, "spare knife")
      Object.relate(target.id, knife.id, :contains)

      TestHarness.dispatch(attacker, Attack, ["Target"])

      # Target now at safehouse with restored HP, lost dirham, knife dropped in arena
      Process.sleep(50)
      assert %{id: id} = Object.container_of(target.id)
      assert id == safehouse.id

      {current, max} = Combat.hp(target.id)
      assert current == max
      assert current == 50

      assert Object.get_property(target.id, "dirham") == 50

      # Knife is in the arena
      arena_items = Object.contents(room.id) |> Enum.filter(&(&1.type == :item))
      assert Enum.any?(arena_items, &(&1.id == knife.id))
    end

    test "dirham penalty floors at zero", %{safehouse: _safehouse} do
      room = TestHarness.spawn_room("Arena")
      attacker = TestHarness.spawn_player_in(room, "Attacker")
      target = TestHarness.spawn_player_in(room, "Broke")
      Object.set_property(target.id, "hp_current", 5)
      Object.set_property(target.id, "dirham", 10)

      TestHarness.dispatch(attacker, Attack, ["Broke"])
      Process.sleep(50)
      assert Object.get_property(target.id, "dirham") == 0
    end

    test "cannot attack already-dead actor", %{safehouse: _safehouse} do
      room = TestHarness.spawn_room("Arena")
      attacker = TestHarness.spawn_player_in(room, "Attacker")
      victim = TestHarness.spawn_player_in(room, "Corpse")
      Object.set_property(victim.id, "hp_current", 0)

      assert {:error, :already_dead} = TestHarness.dispatch(attacker, Attack, ["Corpse"])
    end
  end
end
