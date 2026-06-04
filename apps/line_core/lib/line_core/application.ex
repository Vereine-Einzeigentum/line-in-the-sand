defmodule LineCore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LineCore.Repo,
      {Phoenix.PubSub, name: LineCore.PubSub.Bus}
    ]

    opts = [strategy: :one_for_one, name: LineCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
