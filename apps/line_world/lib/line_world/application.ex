defmodule LineWorld.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Enactment is synchronous; deferred proposals are explicitly resubmitted.
    children = []
    opts = [strategy: :one_for_one, name: LineWorld.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
