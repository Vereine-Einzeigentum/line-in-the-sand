defmodule LineCore.Repo.Migrations.CreateJournalEntries do
  use Ecto.Migration

  def change do
    # Append-only gameplay log. Unlike the object graph, this table uses a
    # bigserial primary key: strict insert ordering is the point of a journal,
    # and entries are never referenced by other rows. No foreign keys either —
    # the journal must outlive anything it mentions (objects are soft-deleted,
    # but the journal should not depend on that).
    create table(:journal_entries) do
      add(:actor_id, :binary_id, null: false)
      add(:room_id, :binary_id)
      add(:verb, :string, null: false)
      add(:raw, :text)
      add(:args, :map, null: false, default: %{})
      add(:events, :map, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:journal_entries, [:actor_id]))
    create(index(:journal_entries, [:room_id]))
    create(index(:journal_entries, [:inserted_at]))
  end
end
