defmodule LineCore.PlaytestSessionTest do
  use ExUnit.Case, async: false

  alias LineCore.{Catchup, Object, PlaytestSession, Repo, TestHarness}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)

    :ok
  end

  test "create spawns an ephemeral player in the starting room" do
    room = TestHarness.spawn_room("Hub", "A room.")
    {:ok, token} = PlaytestSession.create(room.id)

    {:ok, info} = PlaytestSession.info(token)
    assert info.token == token
    assert info.room_id == room.id

    player = Object.get(info.player_id)
    assert player.type == :player
    assert String.starts_with?(player.name, "Playtester-")
  end

  test "create with custom name uses it" do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = PlaytestSession.create(room.id, name: "AgentZero")

    {:ok, info} = PlaytestSession.info(token)
    player = Object.get(info.player_id)
    assert player.name == "AgentZero"
  end

  test "dispatch_command runs a verb and queues the response" do
    room = TestHarness.spawn_room("Hub", "A small room.")
    {:ok, token} = PlaytestSession.create(room.id)

    :ok = PlaytestSession.dispatch_command(token, LineCore.Verbs.Look, [], "look")

    # Give the session a moment to process the broadcast
    Process.sleep(50)

    {:ok, messages} = PlaytestSession.pull_messages(token)
    assert length(messages) >= 1

    assert Enum.any?(messages, fn
             {:msg, m} -> String.contains?(m, "Hub")
             _ -> false
           end)
  end

  test "pull_messages with limit returns at most N messages" do
    room = TestHarness.spawn_room("Hub", "A room.")
    {:ok, token} = PlaytestSession.create(room.id)

    Enum.each(1..5, fn _ ->
      PlaytestSession.dispatch_command(token, LineCore.Verbs.Look, [], "look")
    end)

    Process.sleep(100)

    {:ok, batch1} = PlaytestSession.pull_messages(token, 2)
    assert length(batch1) == 2

    {:ok, batch2} = PlaytestSession.pull_messages(token, 10)
    assert length(batch2) >= 3
  end

  test "terminate ends the session but the player survives it" do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = PlaytestSession.create(room.id)

    {:ok, info} = PlaytestSession.info(token)
    player_id = info.player_id

    assert :ok = PlaytestSession.terminate(token)
    Process.sleep(50)

    # The session is gone...
    refute PlaytestSession.exists?(token)

    # ...but a connection ending is not a reason to destroy a character.
    assert %{id: ^player_id} = Object.get(player_id)
  end

  test "a player left by a session stays in the room, marked unattended" do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = PlaytestSession.create(room.id)
    {:ok, %{player_id: player_id}} = PlaytestSession.info(token)

    PlaytestSession.terminate(token)
    Process.sleep(50)

    assert %{id: room_id} = Object.container_of(player_id)
    assert room_id == room.id
    assert Object.get_property(player_id, "active_state") == Catchup.offline_state()
    assert Object.contents(room.id) |> Enum.any?(&(&1.id == player_id))
  end

  test "a session marks its player online, clearing any prior offline state" do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = PlaytestSession.create(room.id)
    {:ok, %{player_id: player_id}} = PlaytestSession.info(token)

    assert Object.get_property(player_id, "active_state") == nil

    PlaytestSession.terminate(token)
    Process.sleep(50)
    assert Object.get_property(player_id, "active_state") == Catchup.offline_state()
  end

  test "operations on a non-existent token return errors gracefully" do
    assert {:error, :no_session} = PlaytestSession.info("not-a-real-token")
    assert {:error, :no_session} = PlaytestSession.pull_messages("not-a-real-token")
    assert {:error, :no_session} = PlaytestSession.terminate("not-a-real-token")
  end

  test "exists? correctly identifies live and dead sessions" do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = PlaytestSession.create(room.id)

    assert PlaytestSession.exists?(token)

    PlaytestSession.terminate(token)
    Process.sleep(50)

    refute PlaytestSession.exists?(token)
  end
end
