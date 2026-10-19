defmodule LineWebWeb.PlayerChannelTest do
  use LineWebWeb.ChannelCase, async: false

  alias LineCore.{Archetypes, Repo, TestHarness}
  alias LineWebWeb.{PlayerChannel, PlayerSocket}

  setup do
    Archetypes.seed()

    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    room = TestHarness.spawn_room("Hub")
    player = TestHarness.spawn_player_in(room, "Alice")

    socket =
      socket(PlayerSocket, "player_socket:#{player.id}", %{player_id: player.id})

    {:ok, _, socket} =
      subscribe_and_join(socket, PlayerChannel, "player:#{player.id}")

    {:ok, socket: socket, player: player}
  end

  test "command errors are returned once and are not also pushed as system errors", ctx do
    ref = push(ctx.socket, "cmd", %{"raw" => "north"})

    assert_reply ref, :error, %{reason: reason}
    assert is_binary(reason)
    refute_push "system", %{kind: "error"}, 100
  end

  test "player channel supplies its server-owned session to dispatch", ctx do
    ref = push(ctx.socket, "cmd", %{"raw" => "look", "session_id" => Ecto.UUID.generate()})
    assert_reply ref, :ok
    Process.unlink(ctx.socket.channel_pid)
    close(ctx.socket)
    entries = LineCore.Journal.export(ctx.player.id)
    assert Enum.map(entries, & &1.event_type) == ["LOGIN", "COMMAND", "DISCONNECT"]
    assert length(Enum.uniq_by(entries, & &1.session_id)) == 1
  end
end
