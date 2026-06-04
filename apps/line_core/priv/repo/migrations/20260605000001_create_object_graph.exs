defmodule LineCore.Repo.Migrations.CreateObjectGraph do
  use Ecto.Migration

  def change do
    create table(:objects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :name, :string, null: false, size: 120
      add :description, :text
      add :verbs, {:array, :string}, null: false, default: []
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:objects, [:type])
    create index(:objects, [:deleted_at])

    create table(:object_properties, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :object_id, references(:objects, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :string, null: false, size: 64
      add :value, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:object_properties, [:object_id, :key])
    create index(:object_properties, [:key])

    create table(:object_relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :from_id, references(:objects, type: :binary_id, on_delete: :delete_all), null: false
      add :to_id, references(:objects, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:object_relationships, [:from_id, :type])
    create index(:object_relationships, [:to_id, :type])
    create index(:object_relationships, [:type])
  end
end
