defmodule LineWebWeb.PlayerTokenTest do
  use LineWebWeb.ChannelCase, async: false

  alias LineCore.{Object, Repo, TestHarness}
  alias LineWebWeb.{PlayerToken, UserSocket}

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.JournalEntry)
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    :ok
  end

  describe "sign/verify" do
    test "a signed token round-trips to the player id" do
      assert {:ok, "abc-123"} = "abc-123" |> PlayerToken.sign() |> PlayerToken.verify()
    end

    test "garbage and non-binaries are rejected" do
      assert {:error, :invalid} = PlayerToken.verify("not-a-token")
      assert {:error, :invalid} = PlayerToken.verify(nil)
    end

    test "a token signed with a different salt is rejected" do
      forged = Phoenix.Token.sign(LineWebWeb.Endpoint, "some other salt", "abc-123")
      assert {:error, :invalid} = PlayerToken.verify(forged)
    end

    test "a token older than max_age is expired" do
      stale_age = -(PlayerToken.max_age() + 60)

      stale =
        Phoenix.Token.sign(LineWebWeb.Endpoint, "player socket auth", "abc-123",
          signed_at: System.system_time(:second) + stale_age
        )

      assert {:error, :expired} = PlayerToken.verify(stale)
    end
  end

  describe "UserSocket.connect/3" do
    test "connects with a valid token" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Tokened")

      assert {:ok, socket} = connect(UserSocket, %{"token" => PlayerToken.sign(player.id)})
      assert socket.assigns.player_id == player.id
    end

    test "a raw player_id is refused — identifiers are not credentials" do
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Raw")

      assert :error = connect(UserSocket, %{"player_id" => player.id})
    end

    test "a well-signed token for a non-player object is refused" do
      {:ok, crate} = Object.create(:item, "Crate")

      assert :error = connect(UserSocket, %{"token" => PlayerToken.sign(crate.id)})
    end

    test "a well-signed token for a removed player is refused" do
      # Players are not deleted by any normal lifecycle — a session ending
      # leaves the body in the world, and combat respawns rather than deletes.
      # This constructs the state deliberately, out of band, because the socket
      # should still refuse a token naming an object that is genuinely gone
      # however it came to be gone.
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Ghost")
      token = PlayerToken.sign(player.id)

      {:ok, _} =
        player.id
        |> Object.get()
        |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
        |> Repo.update()

      assert :error = connect(UserSocket, %{"token" => token})
    end

    test "a well-signed token for an offline player still connects" do
      # The ordinary case now: you log back into the body you left.
      room = TestHarness.spawn_room("Hub")
      player = TestHarness.spawn_player_in(room, "Returner")
      LineCore.Catchup.mark_offline(player.id)

      assert {:ok, socket} = connect(UserSocket, %{"token" => PlayerToken.sign(player.id)})
      assert socket.assigns.player_id == player.id
    end

    test "connect without params is refused" do
      assert :error = connect(UserSocket, %{})
    end
  end
end
