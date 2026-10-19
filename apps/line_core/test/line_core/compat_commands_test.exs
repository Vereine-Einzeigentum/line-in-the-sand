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
    gear = TestHarness.assert_msg(~r/(Main hand|Wearing)/)
    assert gear =~ "knife"
    assert gear =~ "coat"
  end

  test "ordinary emote command matches the colon shorthand", ctx do
    assert :ok = CommandRouter.dispatch(ctx.player.id, "emote leans against the wall.")
    TestHarness.assert_msg("Alice leans against the wall.")
  end

  test "look in a container reports its direct contents", ctx do
    {:ok, box} = Object.create(:item, "box", %{parent_id: ctx.tree.container.id})
    {:ok, coin} = Object.create(:item, "coin")
    {:ok, _} = Object.relate(ctx.room.id, box.id, :contains)
    {:ok, _} = Object.relate(box.id, coin.id, :contains)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "look in box")
    TestHarness.assert_msg(~r/box.*coin/is)
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

  test "moderator @dig creates a real exit object and traversable direction", ctx do
    destination = TestHarness.spawn_room("Destination")
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    {:ok, _} = Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    assert :ok = CommandRouter.dispatch(mod.id, "@dig north to Destination")
    TestHarness.assert_msg(~r/Dug exit north/i)

    assert %{id: destination_id} = Object.resolve_exit(ctx.room.id, "north")
    assert destination_id == destination.id

    exits =
      Object.contents(ctx.room.id)
      |> Enum.filter(&Object.descendant_of?(&1.id, ctx.tree.exit.id))

    assert [exit] = exits
    assert Object.owns?(mod.id, exit.id)
  end


  test "get all and drop all operate on ordinary room and inventory containment", ctx do
    a = TestHarness.spawn_item_in(ctx.room, "washer")
    b = TestHarness.spawn_item_in(ctx.room, "bolt")

    assert :ok = CommandRouter.dispatch(ctx.player.id, "get all")
    assert Object.container_of(a.id).id == ctx.player.id
    assert Object.container_of(b.id).id == ctx.player.id

    assert :ok = CommandRouter.dispatch(ctx.player.id, "drop all")
    assert Object.container_of(a.id).id == ctx.room.id
    assert Object.container_of(b.id).id == ctx.room.id
  end

  test "exit objects can be opened, locked, and actually gate movement", ctx do
    destination = TestHarness.spawn_room("Behind Door")
    {:ok, exit} =
      Object.create(:exit, "steel door", %{parent_id: ctx.tree.exit.id})

    {:ok, key} = Object.create(:item, "door key")
    {:ok, _} = Object.relate(ctx.room.id, exit.id, :contains)
    {:ok, _} = Object.relate(ctx.player.id, key.id, :contains)
    {:ok, _} = Object.relate(ctx.room.id, destination.id, :exit_to, %{"direction" => "north"})
    Object.set_property(exit.id, "direction", "north")
    Object.set_property(exit.id, "destination_id", destination.id)
    Object.set_property(exit.id, "open", false)
    Object.set_property(exit.id, "locked", true)
    Object.set_property(exit.id, "key_id", key.id)

    assert {:error, :exit_locked} = CommandRouter.dispatch(ctx.player.id, "north")
    assert :ok = CommandRouter.dispatch(ctx.player.id, "unlock steel door with door key")
    assert :ok = CommandRouter.dispatch(ctx.player.id, "open steel door")
    assert :ok = CommandRouter.dispatch(ctx.player.id, "north")
    assert Object.container_of(ctx.player.id).id == destination.id
  end

  test "moderator @open creates an exit and builder introspection sees ordinary object state", ctx do
    destination = TestHarness.spawn_room("Destination")
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    {:ok, _} = Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    assert :ok = CommandRouter.dispatch(mod.id, "@open east to Destination")
    TestHarness.assert_msg(~r/(Opened|Dug) exit east/i)
    assert %{id: destination_id} = Object.resolve_exit(ctx.room.id, "east")
    assert destination_id == destination.id

    assert :ok = CommandRouter.dispatch(mod.id, "@create $container named satchel")
    TestHarness.assert_msg(~r/Created satchel/i)
    satchel = Object.contents(mod.id) |> Object.find_by_name("satchel")
    Object.set_property(satchel.id, "open", true)

    assert :ok = CommandRouter.dispatch(mod.id, "@examine satchel")
    exam = TestHarness.assert_msg(~r/satchel/i)
    assert exam =~ satchel.id
    assert exam =~ "$container"

    assert :ok = CommandRouter.dispatch(mod.id, "@show satchel")
    TestHarness.assert_msg(~r/satchel/i)

    assert :ok = CommandRouter.dispatch(mod.id, "@display satchel")
    TestHarness.assert_msg(~r/satchel/i)

    assert :ok = CommandRouter.dispatch(mod.id, "@examine ##{satchel.id}")
    TestHarness.assert_msg(~r/satchel/i)

    assert :ok = CommandRouter.dispatch(mod.id, "@describe satchel as patched canvas bag")
    TestHarness.assert_msg(~r/set satchel.*description/i)
    assert Object.get_property(satchel.id, "custom_description") == "patched canvas bag"

    assert :ok = CommandRouter.dispatch(mod.id, "@contents me")
    TestHarness.assert_msg(~r/satchel/i)

    assert :ok = CommandRouter.dispatch(mod.id, "@parents satchel")
    TestHarness.assert_msg(~r/\$container.*\$item.*\$root/is)

    assert :ok = CommandRouter.dispatch(mod.id, "@parent satchel")
    TestHarness.assert_msg(~r/\$container.*\$item.*\$root/is)

    assert :ok = CommandRouter.dispatch(mod.id, "@kids $item")
    TestHarness.assert_msg(~r/\$container.*\$wieldable.*\$clothing/is)

    assert :ok = CommandRouter.dispatch(mod.id, "@properties satchel")
    TestHarness.assert_msg(~r/open.*true/is)

    assert :ok = CommandRouter.dispatch(mod.id, "@verbs satchel")
    verbs = TestHarness.assert_msg(~r/Verbs on satchel/i)
    assert verbs =~ "put"
    assert verbs =~ "open"
    assert verbs =~ "lock"

    assert :ok = CommandRouter.dispatch(mod.id, "@owned")
    TestHarness.assert_msg(~r/satchel/i)

    assert :ok = CommandRouter.dispatch(mod.id, "@audit me")
    TestHarness.assert_msg(~r/satchel/i)
  end

  test "moderator can chparent owned objects and edit local properties", ctx do
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    {:ok, _} = Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    assert :ok = CommandRouter.dispatch(mod.id, "@create $item named crate")
    TestHarness.assert_msg(~r/Created crate/i)
    crate = Object.contents(mod.id) |> Object.find_by_name("crate")
    assert crate.parent_id == ctx.tree.item.id

    assert :ok = CommandRouter.dispatch(mod.id, "@chparent crate to $container")
    assert Object.get(crate.id).parent_id == ctx.tree.container.id

    assert :ok = CommandRouter.dispatch(mod.id, "@set crate.open to false")
    assert Object.get_local_property(crate.id, "open") == false

    assert :ok = CommandRouter.dispatch(mod.id, "@clear crate.open")
    assert Object.get_local_property(crate.id, "open") == nil
  end


  test "bulk container manipulation supports all", ctx do
    {:ok, box} = Object.create(:item, "box", %{parent_id: ctx.tree.container.id})
    a = TestHarness.spawn_item_in(ctx.player, "washer")
    b = TestHarness.spawn_item_in(ctx.player, "bolt")
    {:ok, _} = Object.relate(ctx.room.id, box.id, :contains)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "put all in box")
    assert Object.container_of(a.id).id == box.id
    assert Object.container_of(b.id).id == box.id

    assert :ok = CommandRouter.dispatch(ctx.player.id, "get all from box")
    assert Object.container_of(a.id).id == ctx.player.id
    assert Object.container_of(b.id).id == ctx.player.id
  end

  test "moderator @link/@unlink retarget an owned exit and @move can move self", ctx do
    a = TestHarness.spawn_room("Destination A")
    b = TestHarness.spawn_room("Destination B")
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    {:ok, _} = Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    assert :ok = CommandRouter.dispatch(mod.id, "@open east to Destination A")
    TestHarness.assert_msg(~r/(Opened|Dug) exit east/i)
    assert Object.resolve_exit(ctx.room.id, "east").id == a.id

    assert :ok = CommandRouter.dispatch(mod.id, "@link east exit to Destination B")
    assert Object.resolve_exit(ctx.room.id, "east").id == b.id

    assert :ok = CommandRouter.dispatch(mod.id, "@unlink east exit")
    assert Object.resolve_exit(ctx.room.id, "east") == nil

    assert :ok = CommandRouter.dispatch(mod.id, "@move me to Destination B")
    assert Object.container_of(mod.id).id == b.id
  end


  test "moderator @classes lists nested archetypes, not only root children", ctx do
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    {:ok, _} = Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    assert :ok = CommandRouter.dispatch(mod.id, "@classes")
    classes = TestHarness.assert_msg(~r/Classes:/)
    assert classes =~ "$container"
    assert classes =~ "$weapon"
    assert classes =~ "$clothing"
  end


  test "LambdaCore object aliases participate in ordinary resolution", ctx do
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    {:ok, _} = Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    assert :ok = CommandRouter.dispatch(mod.id, "@create $container named satchel,bag,sack")
    TestHarness.assert_msg(~r/Created satchel/i)
    satchel = Object.contents(mod.id) |> Object.find_by_name("satchel")
    assert satchel
    assert Object.find_by_name(Object.contents(mod.id), "bag").id == satchel.id

    assert :ok = CommandRouter.dispatch(mod.id, "@addalias pouch to satchel")
    TestHarness.assert_msg(~r/alias.*pouch/i)
    assert Object.find_by_name(Object.contents(mod.id), "pouch").id == satchel.id

    assert :ok = CommandRouter.dispatch(mod.id, "@aliases satchel")
    aliases = TestHarness.assert_msg(~r/Aliases/i)
    assert aliases =~ "bag"
    assert aliases =~ "sack"
    assert aliases =~ "pouch"

    assert :ok = CommandRouter.dispatch(mod.id, "@rmalias bag from satchel")
    TestHarness.assert_msg(~r/removed.*bag/i)
    assert Object.find_by_name(Object.contents(mod.id), "bag") == nil
  end

  test "LambdaCore @property and @rmproperty edit owned local properties", ctx do
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    {:ok, _} = Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    assert :ok = CommandRouter.dispatch(mod.id, "@create $item named widget")
    TestHarness.assert_msg(~r/Created widget/i)
    widget = Object.contents(mod.id) |> Object.find_by_name("widget")

    assert :ok = CommandRouter.dispatch(mod.id, ~s(@property widget:color "red"))
    assert Object.get_local_property(widget.id, "color") == "red"

    assert :ok = CommandRouter.dispatch(mod.id, "@rmproperty widget:color")
    assert Object.get_local_property(widget.id, "color") == nil
  end

  test "moderator @eject expels objects from a place and sends homed actors home", ctx do
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    {:ok, _} = Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    junk = TestHarness.spawn_item_in(ctx.room, "junk")
    bob = TestHarness.spawn_player_in(ctx.room, "Bob")
    home = TestHarness.spawn_room("Bob Home")
    {:ok, _} = Object.set_property(bob.id, "home_room_id", home.id)

    assert :ok = CommandRouter.dispatch(mod.id, "@eject junk")
    assert Object.container_of(junk.id) == nil
    TestHarness.assert_msg(~r/eject.*junk/i)

    assert :ok = CommandRouter.dispatch(mod.id, "@eject Bob from Hub")
    assert Object.container_of(bob.id).id == home.id
    TestHarness.assert_msg(~r/eject.*Bob.*Hub/i)
  end

  test "@eject can expel an object from moderator inventory with from me", ctx do
    {:ok, mod} = Object.create(:player, "Mod", %{parent_id: ctx.tree.mod.id})
    {:ok, _} = Object.relate(ctx.room.id, mod.id, :contains)
    LineCore.PubSub.subscribe({:actor, mod.id})

    junk = TestHarness.spawn_item_in(mod, "junk")

    assert :ok = CommandRouter.dispatch(mod.id, "@eject junk from me")
    assert Object.container_of(junk.id) == nil
  end

  test "ordinary players cannot use moderator builder commands", ctx do
    assert {:error, :permission_denied} =
             CommandRouter.dispatch(ctx.player.id, "@create $container named satchel")
  end
end
