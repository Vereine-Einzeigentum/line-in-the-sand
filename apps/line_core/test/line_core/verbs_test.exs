defmodule LineCore.VerbsTest do
  use ExUnit.Case, async: false

  alias LineCore.{Object, Repo, TestHarness}
  alias LineCore.Verbs.{Go, Get, Drop, Examine, Inventory, Say, Text, Who, Desc, Emote, Score}

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

  ## Go

  describe "Go" do
    test "moves actor through a valid exit" do
      a = TestHarness.spawn_room("Room A")
      b = TestHarness.spawn_room("Room B")
      TestHarness.connect_rooms(a, b, "north")
      player = TestHarness.spawn_player_in(a)

      TestHarness.dispatch(player, Go, ["north"])

      TestHarness.assert_msg(~r/You walk north/)
      assert %{id: b_id} = Object.container_of(player.id)
      assert b_id == b.id
    end

    test "accepts short direction aliases" do
      a = TestHarness.spawn_room("A")
      b = TestHarness.spawn_room("B")
      TestHarness.connect_rooms(a, b, "north")
      player = TestHarness.spawn_player_in(a)

      TestHarness.dispatch(player, Go, ["n"])
      TestHarness.assert_msg(~r/You walk north/)
    end

    test "errors with no direction" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :no_direction} = TestHarness.dispatch(player, Go, [])
    end

    test "errors with invalid exit" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :no_such_exit} = TestHarness.dispatch(player, Go, ["n"])
    end
  end

  ## Get / Drop

  describe "Get" do
    test "picks up an item in the room" do
      room = TestHarness.spawn_room("Hub")
      _knife = TestHarness.spawn_item_in(room, "rusty knife")
      player = TestHarness.spawn_player_in(room)

      TestHarness.dispatch(player, Get, ["knife"])

      TestHarness.assert_msg(~r/You pick up the rusty knife/)

      inv = Object.contents(player.id)
      assert Enum.any?(inv, &(&1.name == "rusty knife"))
    end

    test "case-insensitive partial match" do
      room = TestHarness.spawn_room("Hub")
      _knife = TestHarness.spawn_item_in(room, "Rusty Knife")
      player = TestHarness.spawn_player_in(room)

      TestHarness.dispatch(player, Get, ["KNIFE"])
      TestHarness.assert_msg(~r/pick up/)
    end

    test "errors when item not found" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :not_found} = TestHarness.dispatch(player, Get, ["sword"])
    end

    test "errors with no target" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :get_what} = TestHarness.dispatch(player, Get, [])
    end
  end

  describe "Drop" do
    test "drops an item from inventory" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      {:ok, knife} = Object.create(:item, "rusty knife")
      Object.relate(player.id, knife.id, :contains)

      TestHarness.dispatch(player, Drop, ["knife"])

      TestHarness.assert_msg(~r/You drop the rusty knife/)
      room_items = Object.contents(room.id) |> Enum.filter(&(&1.type == :item))
      assert Enum.any?(room_items, &(&1.id == knife.id))
    end

    test "errors when not in inventory" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :not_in_inventory} = TestHarness.dispatch(player, Drop, ["sword"])
    end
  end

  ## Examine

  describe "Examine" do
    test "shows the target's full description" do
      room = TestHarness.spawn_room("Hub")
      TestHarness.spawn_item_in(room, "rusty knife", %{description: "Chipped at the edge."})
      player = TestHarness.spawn_player_in(room)

      TestHarness.dispatch(player, Examine, ["knife"])
      TestHarness.assert_msg(~r/Chipped at the edge/)
    end

    test "errors with no target" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :examine_what} = TestHarness.dispatch(player, Examine, [])
    end

    test "errors when target not found" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :not_found} = TestHarness.dispatch(player, Examine, ["nothing"])
    end
  end

  ## Inventory

  describe "Inventory" do
    test "lists items being carried" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      {:ok, k} = Object.create(:item, "knife")
      {:ok, r} = Object.create(:item, "rope")
      Object.relate(player.id, k.id, :contains)
      Object.relate(player.id, r.id, :contains)

      TestHarness.dispatch(player, Inventory, [])
      msg = TestHarness.assert_msg(~r/carrying/)
      assert msg =~ "knife"
      assert msg =~ "rope"
    end

    test "reports empty inventory" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      TestHarness.dispatch(player, Inventory, [])
      TestHarness.assert_msg(~r/aren't carrying/)
    end
  end

  ## Say

  describe "Say" do
    test "broadcasts to room" do
      room = TestHarness.spawn_room("Hub")
      alice = TestHarness.spawn_player_in(room, "Alice")
      _bob = TestHarness.spawn_player_in(room, "Bob")
      LineCore.PubSub.subscribe({:room, room.id})

      TestHarness.dispatch(alice, Say, ["hello"])

      TestHarness.assert_msg(~s(You say, "hello"))
      TestHarness.assert_room_msg(~r/Alice says, "hello"/)
    end

    test "errors with empty message" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :say_what} = TestHarness.dispatch(player, Say, [""])
      assert {:error, :say_what} = TestHarness.dispatch(player, Say, [])
    end
  end

  ## Text

  describe "Text" do
    test "sends private message to named player" do
      room_a = TestHarness.spawn_room("Room A")
      room_b = TestHarness.spawn_room("Room B")
      alice = TestHarness.spawn_player_in(room_a, "Alice")
      _bob = TestHarness.spawn_player_in(room_b, "Bob")

      TestHarness.dispatch(alice, Text, ["Bob", "are you there"])

      TestHarness.assert_msg(~r/You text Bob/)

      # Bob's mailbox should have the text
      receive do
        {:msg, msg} -> assert msg =~ "[txt from Alice]"
      after
        500 -> flunk("Bob did not receive text")
      end
    end

    test "errors with no recipient" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :text_who} = TestHarness.dispatch(player, Text, [])
    end

    test "errors when target doesn't exist" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :no_such_player} = TestHarness.dispatch(player, Text, ["Nobody", "hi"])
    end
  end

  ## Who

  describe "Who" do
    test "bare who lists no players when presence is empty" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      TestHarness.dispatch(player, Who, [])
      TestHarness.assert_msg(~r/No one else is online/)
    end

    test "who <player> reports offline status" do
      room = TestHarness.spawn_room("Hub")
      {:ok, _target} = Object.create(:player, "Graves")
      player = TestHarness.spawn_player_in(room)
      TestHarness.dispatch(player, Who, ["Graves"])
      TestHarness.assert_msg(~r/Graves is offline/)
    end

    test "who <player> for nonexistent player" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      TestHarness.dispatch(player, Who, ["Nobody"])
      TestHarness.assert_msg(~r/No player by that name/)
    end
  end

  ## Desc

  describe "Desc" do
    test "sets custom_description property" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)

      TestHarness.dispatch(player, Desc, ["scarred and quiet"])
      TestHarness.assert_msg(~r/You set your description/)

      assert Object.get_property(player.id, "custom_description") == "scarred and quiet"
    end

    test "examining a player with custom_description renders it" do
      room = TestHarness.spawn_room("Hub")
      alice = TestHarness.spawn_player_in(room, "Alice")
      bob = TestHarness.spawn_player_in(room, "Bob")

      TestHarness.dispatch(alice, Desc, ["wired and watching"])
      TestHarness.assert_msg(~r/set your description/)

      TestHarness.dispatch(bob, Examine, ["Alice"])
      TestHarness.assert_msg(~r/wired and watching/)
    end

    test "errors with empty description" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :empty_description} = TestHarness.dispatch(player, Desc, [""])
    end
  end

  ## Emote

  describe "Emote" do
    test "broadcasts action to the room with actor name" do
      room = TestHarness.spawn_room("Hub")
      alice = TestHarness.spawn_player_in(room, "Alice")
      bob = TestHarness.spawn_player_in(room, "Bob")

      {:ok, events} =
        Emote.execute(
          %LineCore.Verb.Context{
            actor: alice,
            room: room,
            room_contents: [alice, bob]
          },
          ["waves"]
        )

      assert events == [{:notify_room, "Alice waves"}]
    end

    test "includes the actor name in emote message" do
      room = TestHarness.spawn_room("Hub")
      alice = TestHarness.spawn_player_in(room, "Alice")

      {:ok, events} =
        Emote.execute(
          %LineCore.Verb.Context{
            actor: alice,
            room: room,
            room_contents: [alice]
          },
          ["grins mischievously"]
        )

      assert events == [{:notify_room, "Alice grins mischievously"}]
    end

    test "errors with no action" do
      assert {:error, :emote_what} = Emote.execute(%LineCore.Verb.Context{}, [])
    end

    test "errors with empty message" do
      assert {:error, :emote_what} = Emote.execute(%LineCore.Verb.Context{}, [""])
    end
  end

  ## Score

  describe "Score" do
    test "shows HP and dirham to actor" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      Object.set_property(player.id, "hp_current", 30)
      Object.set_property(player.id, "hp_max", 50)
      Object.set_property(player.id, "dirham", 100)

      TestHarness.dispatch(player, Score, [])

      msg = TestHarness.assert_msg(~r/Character Sheet/)
      assert msg =~ "30/50"
      assert msg =~ "100"
    end

    test "shows default HP when not set" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)

      TestHarness.dispatch(player, Score, [])

      msg = TestHarness.assert_msg(~r/Character Sheet/)
      assert msg =~ "50/50"
    end

    test "shows stat and skill properties" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      Object.set_property(player.id, "stat_wire", 8)
      Object.set_property(player.id, "skill_scrap", 5)

      TestHarness.dispatch(player, Score, [])

      msg = TestHarness.assert_msg(~r/Character Sheet/)
      assert msg =~ "Wire: 8"
      assert msg =~ "Scrap: 5"
    end

    test "errors with arguments" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room)
      assert {:error, :bad_args} = TestHarness.dispatch(player, Score, ["arg"])
    end
  end
end
