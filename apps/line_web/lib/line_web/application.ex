defmodule LineWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LineWebWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:line_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LineWeb.PubSub},
      # Start a worker by calling: LineWeb.Worker.start_link(arg)
      # {LineWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      LineWebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LineWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LineWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
