defmodule LineCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :line_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {LineCore.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      # Postgrex needs a JSON codec for the JSONB property/journal columns.
      # It arrives transitively via line_web, but line_core must declare it to
      # run standalone (e.g. `mix test` from inside apps/line_core).
      {:jason, "~> 1.2"},
      {:phoenix_pubsub, "~> 2.1"},
      {:line_shared, in_umbrella: true}
    ]
  end
end
