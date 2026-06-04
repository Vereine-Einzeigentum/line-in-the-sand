defmodule LineCore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LineCore.Repo
    ]

    opts = [strategy: :one_for_one, name: LineCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
