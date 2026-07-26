defmodule LineCore.PersistenceTest do
  @moduledoc """
  Falsifiable statements about persistent bodies.

  A character used to be destroyed because a *connection* ended. These describe
  the model that replaces that: the body stays in the world whether or not
  anyone is driving it, which also means it can be killed while unattended, and
  that what it lived through is recoverable when its player returns.
  """

  use ExUnit.Case, async: false

  alias LineCore.{Catchup, Dispatcher, Genesis, Object, PlaytestSession, Presence, Repo}
  alias LineCore.{TestHarness, Verbs}

  setup do
    # Shared owner: sessions are GenServers in their own processes and have to
    # see the same sandbox connection the test is holding.
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

    safehouse = TestHarness.spawn_room("Safehouse", "Restored.")
    System.put_env("SAFEHOUSE_ROOM_ID", safehouse.id)

    on_exit(fn ->
      System.delete_env("SAFEHOUSE_ROOM_ID")
      Application.delete_env(:line_core, :playtest_idle_timeout)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)

    {:ok, safehouse: safehouse}
  end

  describe "a body outlives the connection driving it" do
    test "a player survives session idle-expiry" do
      Application.put_env(:line_core, :playtest_idle_timeout, 50)

      room = TestHarness.spawn_room("Hub")
      {:ok, token} = PlaytestSession.create(room.id)
      {:ok, %{player_id: player_id}} = PlaytestSession.info(token)

      # Wait out the idle timeout rather than terminating explicitly — this is
      # the path that used to soft-delete the player.
      Process.sleep(200)

      refute PlaytestSession.exists?(token)
      assert %{id: ^player_id} = Object.get(player_id)
      assert Object.get_property(player_id, "active_state") == Catchup.offline_state()
    end

    test "the body stays in the room it was standing in" do
      room = TestHarness.spawn_room("Hub")
      {:ok, token} = PlaytestSession.create(room.id)
      {:ok, %{player_id: player_id}} = PlaytestSession.info(token)

      PlaytestSession.terminate(token)
      Process.sleep(50)

      assert %{id: room_id} = Object.container_of(player_id)
      assert room_id == room.id
    end

    test "an unattended body appears in look, marked unattended" do
      room = TestHarness.spawn_room("Hub")
      sleeper = TestHarness.spawn_player_in(room, "Sleeper")
      Catchup.mark_offline(sleeper.id)

      watcher = TestHarness.spawn_player_in(room, "Watcher")
      TestHarness.dispatch(watcher, Verbs.Look, [])

      msg = TestHarness.assert_msg(~r/Sleeper/)
      assert msg =~ Catchup.offline_state()
    end

    test "who lists only connected players, not every body in the world" do
      room = TestHarness.spawn_room("Hub")
      online = TestHarness.spawn_player_in(room, "Online")
      _offline = TestHarness.spawn_player_in(room, "Offline")

      Presence.register(online.id, %{source: :test})
      on_exit(fn -> Presence.unregister(online.id) end)

      TestHarness.dispatch(online, Verbs.Who, [])

      msg = TestHarness.assert_msg(~r/\[OOC\] Online/)
      assert msg =~ "Online"
      refute msg =~ "Offline"
    end
  end

  describe "players are never deleted" do
    test "a delete_object event against a player is refused" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Indestructible")

      result =
        Ecto.Multi.new()
        |> Dispatcher.apply_to_multi([{:delete_object, player.id}])
        |> Repo.transaction()

      assert {:error, _op, :cannot_delete_player, _changes} = result
      assert %{id: _} = Object.get(player.id)
    end

    test "non-players are still deletable" do
      room = TestHarness.spawn_room("Hub")
      item = TestHarness.spawn_item_in(room, "a rag")

      assert {:ok, _} =
               Ecto.Multi.new()
               |> Dispatcher.apply_to_multi([{:delete_object, item.id}])
               |> Repo.transaction()

      assert Object.get(item.id) == nil
    end

    test "a player survives combat death", %{safehouse: safehouse} do
      room = TestHarness.spawn_room("Arena")
      attacker = TestHarness.spawn_player_in(room, "Attacker")
      victim = TestHarness.spawn_player_in(room, "Victim")
      Object.set_property(victim.id, "hp_current", 1)

      TestHarness.dispatch(attacker, Verbs.Attack, ["Victim"])
      Process.sleep(50)

      assert %{id: _} = Object.get(victim.id)
      assert %{id: room_id} = Object.container_of(victim.id)
      assert room_id == safehouse.id
    end
  end

  describe "an unattended body is a vulnerable body" do
    test "an offline player can be attacked and killed", %{safehouse: safehouse} do
      room = TestHarness.spawn_room("Arena")
      attacker = TestHarness.spawn_player_in(room, "Attacker")
      victim = TestHarness.spawn_player_in(room, "Sleeper")

      Object.set_property(victim.id, "hp_current", 1)
      Object.set_property(victim.id, "dirham", 100)
      knife = TestHarness.spawn_item_in(victim, "spare knife")

      # Nobody is driving the victim. Attack.find_target/2 never consults
      # Presence, so an unattended body is already a legal target.
      Catchup.mark_offline(victim.id)

      assert :ok = TestHarness.dispatch(attacker, Verbs.Attack, ["Sleeper"])
      Process.sleep(50)

      # Items drop where the body fell...
      assert Object.contents(room.id) |> Enum.any?(&(&1.id == knife.id))

      # ...the penalty applies, and the body moves to the safehouse.
      assert Object.get_property(victim.id, "dirham") == 50
      assert %{id: room_id} = Object.container_of(victim.id)
      assert room_id == safehouse.id
    end
  end

  describe "catch-up on return" do
    test "a player killed while offline is told what happened on reconnect" do
      room = TestHarness.spawn_room("Arena")
      attacker = TestHarness.spawn_player_in(room, "Attacker")
      victim = TestHarness.spawn_player_in(room, "Sleeper")
      Object.set_property(victim.id, "hp_current", 1)

      Catchup.mark_offline(victim.id)
      # The stamp and the journal row must not land in the same microsecond.
      Process.sleep(10)

      TestHarness.dispatch(attacker, Verbs.Attack, ["Sleeper"])
      Process.sleep(50)

      # The death notice was published to an actor topic with no subscriber.
      # It is only recoverable from the journal.
      digest = Catchup.digest(victim.id)

      assert ["While you were away:" | messages] = digest
      assert Enum.any?(messages, &(&1 =~ "Everything goes dark"))
      assert Enum.any?(messages, &(&1 =~ "hits you"))
    end

    test "a player who has never been away gets no digest" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Fresh")

      assert Catchup.digest(player.id) == []
    end

    test "an uneventful absence produces no digest" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Quiet")

      Catchup.mark_offline(player.id)
      Process.sleep(10)

      assert Catchup.digest(player.id) == []
    end

    test "the digest excludes what happened before they left" do
      room = TestHarness.spawn_room("Arena")
      attacker = TestHarness.spawn_player_in(room, "Attacker")
      victim = TestHarness.spawn_player_in(room, "Target")

      # Hit them once while they are present...
      TestHarness.dispatch(attacker, Verbs.Attack, ["Target"])
      Process.sleep(50)
      Process.sleep(10)

      # ...then they leave. Nothing happens after that.
      Catchup.mark_offline(victim.id)

      assert Catchup.digest(victim.id) == []
    end

    test "coming back online clears the unattended marker" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Returner")

      Catchup.mark_offline(player.id)
      assert Object.get_property(player.id, "active_state") == Catchup.offline_state()

      Catchup.mark_online(player.id)
      assert Object.get_property(player.id, "active_state") == nil
    end

    test "last_seen_at round-trips as a timestamp" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Clock")

      assert Catchup.last_seen_at(player.id) == nil

      now = DateTime.utc_now()
      Catchup.mark_offline(player.id, now)

      seen = Catchup.last_seen_at(player.id)
      assert DateTime.diff(seen, now, :millisecond) == 0
    end
  end

  describe "provenance" do
    test "a playtest player is recorded as such, and is no less persistent" do
      room = TestHarness.spawn_room("Hub")
      {:ok, token} = PlaytestSession.create(room.id)
      {:ok, %{player_id: player_id}} = PlaytestSession.info(token)

      assert Object.own_property(player_id, "source") == "playtest"

      PlaytestSession.terminate(token)
      Process.sleep(50)

      assert %{id: ^player_id} = Object.get(player_id)
    end

    test "seeded content is recorded as seeded" do
      room = Genesis.room!("Hub", source: :seed)

      assert Object.own_property(room.id, "source") == "seed"
    end
  end
end
