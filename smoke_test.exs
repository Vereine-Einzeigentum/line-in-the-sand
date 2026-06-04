# Smoke test script — runs the Handler's IEx smoke test non-interactively
IO.puts("=== LINE IN THE SAND — Smoke Test ===\n")

# Create a room
IO.puts("Creating room...")
{:ok, room} = LineCore.Object.create(:room, "Hub",
  %{description: "A small concrete cube with a folding chair."})
IO.puts("  Room created: #{room.id} (#{room.name})")

# Create a player
IO.puts("Creating player...")
{:ok, player} = LineCore.Object.create(:player, "Graves")
IO.puts("  Player created: #{player.id} (#{player.name})")

# Place player in room
IO.puts("Placing player in room...")
{:ok, _} = LineCore.Object.relate(room.id, player.id, :contains)
IO.puts("  Relationship created.")

# Subscribe to the player's actor topic
IO.puts("Subscribing to {:actor, #{player.id}}...")
:ok = LineCore.PubSub.subscribe({:actor, player.id})
IO.puts("  Subscribed.")

# Dispatch a bare look
IO.puts("Dispatching look verb...")
result = LineCore.Dispatcher.dispatch(player.id, LineCore.Verbs.Look, [], "look")
IO.puts("  Dispatch returned: #{inspect(result)}")

# Drain mailbox
IO.puts("\nMailbox contents:")
receive do
  {:msg, text} ->
    IO.puts("  {:msg, #{inspect(text)}}")
    IO.puts("\n=== PASS ===")
after
  1000 ->
    IO.puts("  (empty — no messages received)")
    IO.puts("\n=== FAIL — no message in mailbox ===")
    System.halt(1)
end
