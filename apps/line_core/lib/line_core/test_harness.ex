defmodule LineCore.TestHarness do
  @moduledoc """
  Ergonomic harness for driving the MOO in tests.

  Spawns ephemeral players, subscribes the calling test process to actor
  notifications, dispatches verbs synchronously, and provides assertion
  helpers for received messages.

  Bypasses HTTP/websockets entirely — tests run in-process against the
  dispatcher directly.

  ## Example

      test "player can look at a room and see the description" do
        room = TestHarness.spawn_room("Hub", "A small concrete cube.")
        player = TestHarness.spawn_player_in(room, "Tester")

        TestHarness.dispatch(player, LineCore.Verbs.Look, [])

        TestHarness.assert_msg("Hub")
        TestHarness.assert_msg(~r/concrete cube/)
      end
  """

  alias LineCore.{Dispatcher, Object, PubSub}

  ## Spawning helpers

  @doc "Create a room with the given name and description."
  def spawn_room(name, description \\ "An unremarkable room.") do
    {:ok, room} = Object.create(:room, name, %{description: description})
    room
  end

  @doc "Create a player and subscribe the calling test process to their actor topic."
  def spawn_player(name \\ "Tester") do
    {:ok, player} = Object.create(:player, name)
    :ok = PubSub.subscribe({:actor, player.id})
    player
  end

  @doc "Create a player and place them in the given room. Subscribes caller to actor topic."
  def spawn_player_in(room, name \\ "Tester") do
    player = spawn_player(name)
    {:ok, _} = Object.relate(room.id, player.id, :contains)
    player
  end

  @doc "Create an item and place it in the given container."
  def spawn_item_in(container, name, attrs \\ %{}) do
    {:ok, item} = Object.create(:item, name, attrs)
    {:ok, _} = Object.relate(container.id, item.id, :contains)
    item
  end

  @doc "Create an NPC and place it in the given room."
  def spawn_npc_in(room, name, attrs \\ %{}) do
    {:ok, npc} = Object.create(:npc, name, attrs)
    {:ok, _} = Object.relate(room.id, npc.id, :contains)
    npc
  end

  @doc "Connect two rooms with an exit in the given direction. Bidirectional unless opts[:one_way]."
  def connect_rooms(from, to, direction, opts \\ []) do
    {:ok, _} = Object.relate(from.id, to.id, :exit_to, %{"direction" => direction})

    unless opts[:one_way] do
      {:ok, _} = Object.relate(to.id, from.id, :exit_to, %{"direction" => opposite(direction)})
    end

    :ok
  end

  defp opposite("north"), do: "south"
  defp opposite("south"), do: "north"
  defp opposite("east"), do: "west"
  defp opposite("west"), do: "east"
  defp opposite("up"), do: "down"
  defp opposite("down"), do: "up"
  defp opposite("northeast"), do: "southwest"
  defp opposite("southwest"), do: "northeast"
  defp opposite("northwest"), do: "southeast"
  defp opposite("southeast"), do: "northwest"
  defp opposite("in"), do: "out"
  defp opposite("out"), do: "in"
  defp opposite(other), do: other

  ## Dispatch

  @doc "Dispatch a verb as a given actor. Returns the dispatcher result."
  def dispatch(actor, verb_module, args, raw_command \\ "") do
    raw =
      if raw_command == "" do
        "#{inspect(verb_module)} #{inspect(args)}"
      else
        raw_command
      end

    Dispatcher.dispatch(actor.id, verb_module, args, raw)
  end

  ## Assertions

  @doc """
  Assert the test process receives a `{:msg, ...}` matching the given pattern
  within `timeout` ms (default 200).

  Pattern can be a string (exact match), regex, or function `(msg -> boolean)`.
  """
  def assert_msg(pattern, timeout \\ 200) do
    receive do
      {:msg, msg} ->
        if matches?(msg, pattern) do
          msg
        else
          flunk("received {:msg, _} but it didn't match #{inspect(pattern)}: #{inspect(msg)}")
        end
    after
      timeout ->
        flunk("did not receive {:msg, _} matching #{inspect(pattern)} within #{timeout}ms")
    end
  end

  @doc """
  Assert the test process receives a `{:room_msg, ...}` matching the pattern.
  """
  def assert_room_msg(pattern, timeout \\ 200) do
    receive do
      {:room_msg, msg, _except} ->
        if matches?(msg, pattern) do
          msg
        else
          flunk(
            "received {:room_msg, _, _} but it didn't match #{inspect(pattern)}: #{inspect(msg)}"
          )
        end
    after
      timeout ->
        flunk("did not receive {:room_msg, _, _} matching #{inspect(pattern)} within #{timeout}ms")
    end
  end

  @doc "Assert no `{:msg, ...}` arrives within `timeout` (default 100 ms)."
  def refute_msg(timeout \\ 100) do
    receive do
      {:msg, msg} -> flunk("expected no message, but received: #{inspect(msg)}")
    after
      timeout -> :ok
    end
  end

  @doc "Drain all pending messages from the test process mailbox. Returns the list."
  def drain do
    do_drain([])
  end

  defp do_drain(acc) do
    receive do
      msg -> do_drain([msg | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  ## Internal

  defp matches?(msg, pattern) when is_binary(pattern), do: msg == pattern
  defp matches?(msg, %Regex{} = pattern), do: Regex.match?(pattern, msg)
  defp matches?(msg, fun) when is_function(fun, 1), do: fun.(msg)
  defp matches?(_, _), do: false

  defp flunk(reason), do: ExUnit.Assertions.flunk(reason)
end
