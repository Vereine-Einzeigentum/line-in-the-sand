defmodule LineCore.Release do
  @moduledoc false

  @app :line_core

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end
  end

  def bootstrap_admin do
    load_app()

    for repo <- repos() do
      {:ok, result, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          LineCore.BootstrapAdmin.bootstrap_from_env()
        end)

      case result do
        :skip ->
          IO.puts("Admin bootstrap skipped: credentials not configured")

        {:ok, {:created, admin}} ->
          IO.puts("Admin bootstrap created #{admin.name}")

        {:ok, {:existing, admin}} ->
          IO.puts("Admin bootstrap found existing #{admin.name}")

        {:error, reason} ->
          raise "Admin bootstrap failed: #{inspect(reason)}"
      end
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        Ecto.Migrator.run(repo, :down, to: version)
      end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
