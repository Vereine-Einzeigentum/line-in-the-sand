defmodule LineCore.Release do
  @moduledoc false

  @app :line_core

  def prepare do
    migrate()
    seed_world_and_bootstrap_admin()
    :ok
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end
  end

  def seed_world_and_bootstrap_admin do
    load_app()

    for repo <- repos() do
      {:ok, {_world, admin_result}, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          archetypes = LineCore.Archetypes.seed()
          world = LineCore.Seed.DistrictOne.seed()
          {:ok, adminland} = LineCore.Adminland.ensure()

          admin_result =
            LineCore.BootstrapAdmin.bootstrap_from_env(
              starting_room_id: adminland.id
            )

          case admin_result do
            {:ok, {_state, admin}} ->
              {:ok, _room} = LineCore.Adminland.load_if_admin(admin.id)

            :skip ->
              :ok
          end

          :ok = LineCore.Archetypes.adopt_existing(archetypes)

          {world, admin_result}
        end)

      case admin_result do
        :skip ->
          IO.puts("Admin bootstrap skipped: credentials not configured")

        {:ok, {:created, admin}} ->
          IO.puts("Admin bootstrap created #{admin.name} in Adminland")

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
