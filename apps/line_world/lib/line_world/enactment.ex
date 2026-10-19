defmodule LineWorld.Enactment do
  @moduledoc false
  @behaviour LineCore.Verb

  @impl true
  def execute(ctx, [consequence]) do
    consequence
    |> LineWorld.decide(ctx)
    |> LineWorld.EventModel.build()
  end
end
