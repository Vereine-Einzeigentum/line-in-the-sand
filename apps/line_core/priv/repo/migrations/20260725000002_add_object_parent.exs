defmodule LineCore.Repo.Migrations.AddObjectParent do
  use Ecto.Migration

  def change do
    # Prototype inheritance, MOO-style: an object may derive from a generic,
    # inheriting its properties and verbs. Nullable — a generic at the top of a
    # chain has no parent.
    #
    # nilify_all rather than delete_all: losing a generic must never cascade
    # into deleting every object descended from it.
    alter table(:objects) do
      add :parent_id, references(:objects, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:objects, [:parent_id])
  end
end
