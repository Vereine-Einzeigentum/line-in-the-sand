defmodule LineCore.Repo.Migrations.AddObjectInheritance do
  use Ecto.Migration

  def change do
    alter table(:objects) do
      add :parent_id,
          references(:objects,
            type: :binary_id,
            on_delete: :nilify_all
          )
    end

    create index(:objects, [:parent_id])
  end
end
