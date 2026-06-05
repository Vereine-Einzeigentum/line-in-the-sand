defmodule LineCore.PresenceTest do
  use ExUnit.Case, async: false

  alias LineCore.Presence

  setup do
    # Registry entries vanish asynchronously when the process that registered
    # them dies. A prior test's process may still be reaping its registration,
    # so wait for a clean slate before starting. (Calling `unregister` here is a
    # no-op for entries owned by an already-dead process — only the owning
    # process can unregister itself — so we must poll instead.)
    wait_until(fn ->
      not Presence.online?("test-player-1") and not Presence.online?("test-player-2")
    end)

    :ok
  end

  defp wait_until(fun, retries \\ 100) do
    cond do
      fun.() ->
        :ok

      retries == 0 ->
        flunk("Presence registry did not reach a clean state in time")

      true ->
        Process.sleep(10)
        wait_until(fun, retries - 1)
    end
  end

  test "register and unregister round-trip" do
    assert :ok == Presence.unregister("test-player-1")
    refute Presence.online?("test-player-1")

    assert {:ok, _pid} = Presence.register("test-player-1", %{source: :test})
    assert Presence.online?("test-player-1")
    assert %{source: :test} == Presence.metadata("test-player-1")

    Presence.unregister("test-player-1")
    refute Presence.online?("test-player-1")
  end

  test "online_player_ids lists everyone registered" do
    Presence.register("test-player-1")
    Presence.register("test-player-2")

    ids = Presence.online_player_ids()
    assert "test-player-1" in ids
    assert "test-player-2" in ids
  end

  test "count returns registry size" do
    initial = Presence.count()

    Presence.register("test-player-1")
    assert Presence.count() == initial + 1

    Presence.unregister("test-player-1")
    assert Presence.count() == initial
  end

  test "second register from same process is a no-op error" do
    Presence.register("test-player-1")
    assert {:error, {:already_registered, _}} = Presence.register("test-player-1")
  end
end
