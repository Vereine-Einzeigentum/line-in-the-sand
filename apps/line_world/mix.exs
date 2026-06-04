defmodule LineWorld.MixProject do
  use Mix.Project

  def project do
    [
      app: :line_world,
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
      mod: {LineWorld.Application, []}
    ]
  end

  defp deps do
    [
      {:line_core, in_umbrella: true},
      {:line_shared, in_umbrella: true}
    ]
  end
end
