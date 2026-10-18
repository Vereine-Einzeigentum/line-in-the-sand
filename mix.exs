defmodule LineInTheSand.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # The test alias ensures the database is created and migrated before
  # the suite runs, both locally and in CI.
  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp releases do
    [
      lits: [
        applications: [
          line_shared: :permanent,
          line_core: :permanent,
          line_world: :permanent,
          line_ml: :permanent,
          line_web: :permanent
        ]
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    []
  end
end
