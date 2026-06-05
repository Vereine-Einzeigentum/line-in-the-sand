defmodule Mix.Tasks.LineCore.Seed do
  @moduledoc """
  Seeds the canonical Phase 0 content into the database.

      mix line_core.seed

  Runs `LineCore.Seed.DistrictOne.seed/0`. Idempotent — running it twice
  produces the same state. Prints the seeded room IDs for use as env vars
  (`PLAYTEST_STARTING_ROOM_ID`, `SAFEHOUSE_ROOM_ID`).
  """
  use Mix.Task

  @shortdoc "Seed Phase 0 content (District One)"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Seeding District One...")
    result = LineCore.Seed.DistrictOne.seed()

    IO.puts("")
    IO.puts("=== Seed complete ===")
    IO.puts("Safehouse:   #{result.safehouse.id}")
    if result.fence_shop, do: IO.puts("Fence Shop:  #{result.fence_shop.id}")
    if result.fence, do: IO.puts("Fence (NPC): #{result.fence.id} (#{result.fence.name})")

    if Map.get(result.scrap_zones, :center) do
      IO.puts("Scrap Zone:  #{result.scrap_zones.center.id} (center)")
    end

    IO.puts("")
    IO.puts("Suggested env vars:")
    IO.puts("  export PLAYTEST_STARTING_ROOM_ID=#{result.safehouse.id}")
    IO.puts("  export SAFEHOUSE_ROOM_ID=#{result.safehouse.id}")
    :ok
  end
end
