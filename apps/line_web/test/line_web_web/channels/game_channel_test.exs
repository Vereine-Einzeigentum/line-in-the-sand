defmodule LineWebWeb.GameChannelTest do
  use LineWebWeb.ChannelCase, async: false

  alias LineCore.{Object, Repo, TestHarness}
  alias LineWebWeb.{GameChannel, UserSocket}

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

  defp connect_player(player) do
    {:ok, socket} =
      connect(UserSocket, %{"token" => LineWebWeb.PlayerToken.sign(player.id)})

    {:ok, _, socket} = subscribe_and_join(socket, GameChannel, "game:#{player.id}")
    socket
  end

  test "joining game:<player_id> subscribes and registers presence" do
    room = TestHarness.spawn_room("Hub", "A room.")
    player = TestHarness.spawn_player_in(room, "Joiner")
    _socket = connect_player(player)

    # Presence should be registered (from after_join)
    Process.sleep(50)
    assert LineCore.Presence.online?(player.id)
  end

  test "command 'look' dispatches and pushes msg back" do
    room = TestHarness.spawn_room("Hub", "Tiny room.")
    player = TestHarness.spawn_player_in(room, "Looker")
    _socket = connect_player(player)

    ref = push(_socket = connect_player(player), "command", %{"raw" => "look"})
    assert_reply ref, :ok, %{status: "dispatched"}
    assert_push "msg", %{text: text}
    assert text =~ "Hub"
  end

  test "command 'n' moves player and resubscribes to new room" do
    a = TestHarness.spawn_room("A")
    b = TestHarness.spawn_room("B", "Different room.")
    TestHarness.connect_rooms(a, b, "north")
    player = TestHarness.spawn_player_in(a, "Walker")
    socket = connect_player(player)

    ref = push(socket, "command", %{"raw" => "n"})
    assert_reply ref, :ok, %{status: "dispatched"}

    new_container = Object.container_of(player.id)
    assert new_container.id == b.id
  end

  test "unknown verb returns error reply" do
    room = TestHarness.spawn_room("Hub")
    player = TestHarness.spawn_player_in(room)
    socket = connect_player(player)

    ref = push(socket, "command", %{"raw" => "blarg"})
    assert_reply ref, :error, %{reason: reason}
    assert reason =~ "unknown verb"
  end

  test "empty raw returns error" do
    room = TestHarness.spawn_room("Hub")
    player = TestHarness.spawn_player_in(room)
    socket = connect_player(player)

    ref = push(socket, "command", %{"raw" => ""})
    assert_reply ref, :error, %{reason: reason}
    assert reason =~ "empty"
  end

  test "joining with mismatched player_id is rejected" do
    {:ok, p1} = Object.create(:player, "Player1")
    {:ok, p2} = Object.create(:player, "Player2")

    {:ok, socket} = connect(UserSocket, %{"token" => LineWebWeb.PlayerToken.sign(p1.id)})

    assert {:error, %{reason: "player_id mismatch"}} =
             subscribe_and_join(socket, GameChannel, "game:#{p2.id}")
  end

  test "connect with no params is rejected" do
    assert :error = connect(UserSocket, %{})
  end

  test "connect with non-player player_id is rejected" do
    {:ok, room} = Object.create(:room, "Room")
    assert :error = connect(UserSocket, %{"player_id" => room.id})
  end

  test "room broadcasts are delivered to the channel client" do
    room = TestHarness.spawn_room("Stage")
    alice = TestHarness.spawn_player_in(room, "Alice")
    bob = TestHarness.spawn_player_in(room, "Bob")
    _socket_bob = connect_player(bob)

    # Alice says something via direct dispatcher call
    LineCore.Dispatcher.dispatch(alice.id, LineCore.Verbs.Say, ["hello"], "say hello")

    assert_push "room_msg", %{text: text}
    assert text =~ "Alice says"
  end
end
