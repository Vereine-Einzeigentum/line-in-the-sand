defmodule LineCore.Repo.Migrations.PropertiesHoldReferences do
  use Ecto.Migration

  @moduledoc """
  Collapses relationships into properties.

  There is no separate edge table and there are no edge types. A property is
  either inert (`value`) or a reference to another object (`ref_id`), with an
  optional number attached (`num`). The property's key carries the meaning:
  the room's `north` names an exit object, the room's `knife` names a knife.

  Both ends are indexed, so one row is readable in either direction — a
  container's contents and a thing's whereabouts are the same fact.
  """

  def up do
    alter table(:object_properties) do
      add :ref_id, references(:objects, type: :binary_id, on_delete: :delete_all)
      add :num, :float
    end

    # An inert property carries a value; a reference carries a ref_id instead.
    execute "ALTER TABLE object_properties ALTER COLUMN value DROP NOT NULL"

    create index(:object_properties, [:ref_id])

    drop table(:object_relationships)
  end

  def down do
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

    drop index(:object_properties, [:ref_id])

    execute "DELETE FROM object_properties WHERE value IS NULL"
    execute "ALTER TABLE object_properties ALTER COLUMN value SET NOT NULL"

    alter table(:object_properties) do
      remove :ref_id
      remove :num
    end
  end
end
