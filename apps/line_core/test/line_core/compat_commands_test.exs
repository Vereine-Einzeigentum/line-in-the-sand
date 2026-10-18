defmodule LineCore.CompatCommandsTest do
  use ExUnit.Case, async: false

  alias LineCore.{Archetypes, CommandRouter, Object, Repo, TestHarness}

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      System.delete_env("SAFEHOUSE_ROOM_ID")
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    tree = Archetypes.seed()
    room = TestHarness.spawn_room("Hub", "A test room.")
    player = TestHarness.spawn_player_in(room, "Alice")

    {:ok, tree: tree, room: room, player: player}
  end

  test "help, info, and ? expose the compatibility surface", ctx do
    for raw <- ["help", "info", "?"] do
      assert :ok = CommandRouter.dispatch(ctx.player.id, raw)
      TestHarness.assert_msg(~r/(look|inventory).*(score|skills)/is)
    end
  end

  test "score/stats/sc and skills/sk report character state from properties and skill objects", ctx do
    Object.set_property(ctx.player.id, "stat_wire", 3)
    Object.set_property(ctx.player.id, "stat_shade", 4)
    Object.set_property(ctx.player.id, "dirham", 17)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "score")
    TestHarness.assert_msg(~r/Wire.*3.*Shade.*4.*17 Dh/is)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "sk")
    TestHarness.assert_msg(~r/Blade.*Brawl.*Entry.*Scrap/is)
  end

  test "gear/equipment/eq reports wielded and worn objects", ctx do
    {:ok, knife} = Object.create(:item, "knife", %{parent_id: ctx.tree.weapon.id})
    {:ok, coat} = Object.create(:item, "coat", %{parent_id: ctx.tree.clothing.id})
    Object.relate(ctx.player.id, knife.id, :contains)
    Object.relate(ctx.player.id, coat.id, :contains)
    Object.relate(ctx.player.id, knife.id, :wields_main)
    Object.relate(ctx.player.id, coat.id, :wears)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "gear")
    TestHarness.assert_msg(~r/knife.*coat/is)
  end

  test "give/hand transfers a carried object to another local actor", ctx do
    bob = TestHarness.spawn_player_in(ctx.room, "Bob")
    coin = TestHarness.spawn_item_in(ctx.player, "coin")

    assert :ok = CommandRouter.dispatch(ctx.player.id, "give coin to Bob")
    assert Object.container_of(coin.id).id == bob.id
    TestHarness.assert_msg(~r/give.*coin.*Bob/i)
  end

  test "wield preserves containment; unwield removes only the attachment", ctx do
    {:ok, knife} = Object.create(:item, "knife", %{parent_id: ctx.tree.weapon.id})
    Object.relate(ctx.player.id, knife.id, :contains)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "wield knife")
    assert Object.container_of(knife.id).id == ctx.player.id
    assert Enum.any?(Object.related_by(ctx.player.id, :wields_main), &(&1.id == knife.id))

    assert :ok = CommandRouter.dispatch(ctx.player.id, "unwield knife")
    assert Object.container_of(knife.id).id == ctx.player.id
    assert Object.related_by(ctx.player.id, :wields_main) == []
  end

  test "wear/remove attaches clothing without removing it from inventory", ctx do
    {:ok, coat} = Object.create(:item, "coat", %{parent_id: ctx.tree.clothing.id})
    Object.relate(ctx.player.id, coat.id, :contains)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "wear coat")
    assert Object.container_of(coat.id).id == ctx.player.id
    assert Enum.any?(Object.related_by(ctx.player.id, :wears), &(&1.id == coat.id))

    assert :ok = CommandRouter.dispatch(ctx.player.id, "remove coat")
    assert Object.related_by(ctx.player.id, :wears) == []
  end

  test "take/remove from, throw, and insert retain LambdaCore manipulation aliases", ctx do
    {:ok, box} = Object.create(:item, "box", %{parent_id: ctx.tree.container.id})
    coin = TestHarness.spawn_item_in(ctx.player, "coin")
    Object.relate(ctx.room.id, box.id, :contains)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "insert coin into box")
    assert Object.container_of(coin.id).id == box.id

    assert :ok = CommandRouter.dispatch(ctx.player.id, "remove coin from box")
    assert Object.container_of(coin.id).id == ctx.player.id

    assert :ok = CommandRouter.dispatch(ctx.player.id, "throw coin")
    assert Object.container_of(coin.id).id == ctx.room.id
  end

  test "open/close and keyed lock/unlock are ordinary container verbs", ctx do
    {:ok, box} = Object.create(:item, "box", %{parent_id: ctx.tree.container.id})
    {:ok, key} = Object.create(:item, "brass key")
    Object.relate(ctx.room.id, box.id, :contains)
    Object.relate(ctx.player.id, key.id, :contains)
    Object.set_property(box.id, "open", true)
    Object.set_property(box.id, "key_id", key.id)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "close box")
    assert Object.get_property(box.id, "open") == false

    assert :ok = CommandRouter.dispatch(ctx.player.id, "lock box with brass key")
    assert Object.get_property(box.id, "locked") == true

    assert :ok = CommandRouter.dispatch(ctx.player.id, "unlock box with brass key")
    assert Object.get_property(box.id, "locked") == false

    assert :ok = CommandRouter.dispatch(ctx.player.id, "open box")
    assert Object.get_property(box.id, "open") == true
  end

  test "@sethome and home round-trip the player", ctx do
    destination = TestHarness.spawn_room("Elsewhere")
    TestHarness.connect_rooms(ctx.room, destination, "north")

    assert :ok = CommandRouter.dispatch(ctx.player.id, "@sethome")
    assert Object.get_property(ctx.player.id, "home_room_id") == ctx.room.id

    assert :ok = CommandRouter.dispatch(ctx.player.id, "north")
    assert Object.container_of(ctx.player.id).id == destination.id

    assert :ok = CommandRouter.dispatch(ctx.player.id, "home")
    assert Object.container_of(ctx.player.id).id == ctx.room.id
  end

  test "whisper is local; page and whereis resolve players globally", ctx do
    bob = TestHarness.spawn_player_in(ctx.room, "Bob")
    LineCore.PubSub.subscribe({:actor, bob.id})

    assert :ok = CommandRouter.dispatch(ctx.player.id, ~s(whisper "quiet" to Bob))
    assert_receive {:msg, whisper}, 200
    assert whisper =~ "quiet"
    TestHarness.drain()

    other = TestHarness.spawn_room("Other")
    {:ok, _} = Object.move(bob.id, other.id)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "page Bob hello from Hub")
    assert_receive {:msg, page}, 200
    assert page =~ "hello from Hub"
    TestHarness.drain()

    assert :ok = CommandRouter.dispatch(ctx.player.id, "whereis Bob")
    TestHarness.assert_msg(~r/Bob.*Other/i)
  end

  test "@who aliases who", ctx do
    assert :ok = CommandRouter.dispatch(ctx.player.id, "@who")
    TestHarness.assert_msg(~r/Online.*Alice/i)
  end

  test "map/lmap and exits report local topology", ctx do
    north = TestHarness.spawn_room("North")
    east = TestHarness.spawn_room("East")
    TestHarness.connect_rooms(ctx.room, north, "north", one_way: true)
    TestHarness.connect_rooms(ctx.room, east, "east", one_way: true)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "lmap")
    map = TestHarness.assert_msg(~r/Hub/is)
    assert map =~ "north"
    assert map =~ "east"

    assert :ok = CommandRouter.dispatch(ctx.player.id, "exits")
    exits = TestHarness.assert_msg(~r/Exits:/i)
    assert exits =~ "north"
    assert exits =~ "east"
  end

  test "@describe is a LambdaCore alias for self description", ctx do
    assert :ok = CommandRouter.dispatch(ctx.player.id, "@describe me as wired and awake")
    assert Object.get_property(ctx.player.id, "custom_description") == "wired and awake"
  end

  test "@rename renames self", ctx do
    assert :ok = CommandRouter.dispatch(ctx.player.id, "@rename me to Alicia")
    assert Object.get(ctx.player.id).name == "Alicia"
  end

  test "moderator builder basics create, audit, move, and recycle owned objects", ctx do
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    assert :ok = CommandRouter.dispatch(mod.id, "@create $container named satchel")
    TestHarness.assert_msg(~r/Created satchel/i)
    satchel = Object.contents(mod.id) |> Object.find_by_name("satchel")
    assert satchel
    assert Object.descendant_of?(satchel.id, ctx.tree.container.id)

    assert :ok = CommandRouter.dispatch(mod.id, "@count")
    TestHarness.assert_msg(~r/1 object/i)

    assert :ok = CommandRouter.dispatch(mod.id, "@audit")
    TestHarness.assert_msg(~r/satchel/i)

    assert :ok = CommandRouter.dispatch(mod.id, "@move satchel to here")
    TestHarness.assert_msg(~r/Moved satchel/i)
    assert Object.container_of(satchel.id).id == ctx.room.id

    assert :ok = CommandRouter.dispatch(mod.id, "@recycle satchel")
    TestHarness.assert_msg(~r/Recycled satchel/i)
    assert Object.get(satchel.id) == nil
  end

  test "ordinary players cannot use moderator builder commands", ctx do
    assert {:error, :permission_denied} =
             CommandRouter.dispatch(ctx.player.id, "@create $container named satchel")
  end
end
