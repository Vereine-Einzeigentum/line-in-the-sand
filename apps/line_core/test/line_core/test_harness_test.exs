defmodule LineCore.TestHarnessTest do
  use ExUnit.Case, async: false

  alias LineCore.{Object, Repo, TestHarness}

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

  test "spawn_room creates a room with description" do
    room = TestHarness.spawn_room("Hub", "Concrete cube.")
    assert room.type == :room
    assert room.name == "Hub"
    assert room.description == "Concrete cube."
  end

  test "spawn_player_in places the player in the room and subscribes caller" do
    room = TestHarness.spawn_room("Hub")
    player = TestHarness.spawn_player_in(room, "Tester")

    container = Object.container_of(player.id)
    assert container.id == room.id

    # Caller is subscribed — dispatch a look and we should receive a message
    TestHarness.dispatch(player, LineCore.Verbs.Look, [])
    TestHarness.assert_msg(~r/Hub/)
  end

  test "connect_rooms creates bidirectional exits" do
    a = TestHarness.spawn_room("A")
    b = TestHarness.spawn_room("B")

    TestHarness.connect_rooms(a, b, "north")

    assert %{id: b_id} = Object.resolve_exit(a.id, "n")
    assert b_id == b.id

    assert %{id: a_id} = Object.resolve_exit(b.id, "s")
    assert a_id == a.id
  end

  test "connect_rooms one_way only creates outbound exit" do
    a = TestHarness.spawn_room("A")
    b = TestHarness.spawn_room("B")

    TestHarness.connect_rooms(a, b, "north", one_way: true)

    assert %{id: _} = Object.resolve_exit(a.id, "n")
    assert nil == Object.resolve_exit(b.id, "s")
  end

  test "assert_msg with regex pattern" do
    room = TestHarness.spawn_room("Bazaar", "A noisy market.")
    player = TestHarness.spawn_player_in(room)

    TestHarness.dispatch(player, LineCore.Verbs.Look, [])

    msg = TestHarness.assert_msg(~r/noisy market/)
    assert is_binary(msg)
  end

  test "refute_msg passes when nothing arrives" do
    _player = TestHarness.spawn_player()
    # No dispatch happened, so no msg should arrive
    TestHarness.refute_msg(50)
  end

  test "drain returns and clears all pending messages" do
    room = TestHarness.spawn_room("Hub", "A room.")
    player = TestHarness.spawn_player_in(room)

    TestHarness.dispatch(player, LineCore.Verbs.Look, [])
    TestHarness.dispatch(player, LineCore.Verbs.Look, [])
    TestHarness.dispatch(player, LineCore.Verbs.Look, [])

    msgs = TestHarness.drain()
    assert length(msgs) == 3

    # Mailbox now empty
    TestHarness.refute_msg(50)
  end
end
