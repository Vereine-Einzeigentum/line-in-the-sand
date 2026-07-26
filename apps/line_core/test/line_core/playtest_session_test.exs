defmodule LineCore.PlaytestSessionTest do
  use ExUnit.Case, async: false

  alias LineCore.{Object, PlaytestSession, Repo, TestHarness}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

    # Generics must be seeded so Genesis.player! can derive from the PC generic.
    LineCore.Seed.Generics.seed()

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)

    :ok
  end

  test "create spawns a player in the starting room" do
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

  test "terminate tears down the session but the player body persists" do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = PlaytestSession.create(room.id)

    {:ok, info} = PlaytestSession.info(token)
    player_id = info.player_id

    assert :ok = PlaytestSession.terminate(token)
    Process.sleep(50)

    # Session is gone
    refute PlaytestSession.exists?(token)

    # Player body persists in the world — only the connection is gone
    assert %{type: :player} = Object.get(player_id)
    assert Object.get_property(player_id, "active_state") == "offline"
  end

  test "a player object survives session idle-expiry" do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = PlaytestSession.create(room.id)
    {:ok, info} = PlaytestSession.info(token)
    player_id = info.player_id

    # Directly invoke cleanup to simulate idle expiry without waiting 15 minutes
    PlaytestSession.terminate(token)
    Process.sleep(50)

    assert %{type: :player} = Object.get(player_id)
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
