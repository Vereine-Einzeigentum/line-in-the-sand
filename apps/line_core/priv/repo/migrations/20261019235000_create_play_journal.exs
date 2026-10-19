defmodule LineCore.Repo.Migrations.CreatePlayJournal do
  use Ecto.Migration

  def change do
    create table(:play_journal, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:schema_version, :integer, null: false)
      # Historical identities survive object deletion; no cascading foreign keys.
      add(:actor_id, :binary_id, null: false)
      add(:position, :bigint, null: false)
      add(:event_type, :string, null: false)
      add(:outcome, :string, null: false)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:elapsed_us, :bigint)
      add(:session_id, :binary_id)
      add(:session_position, :bigint)
      add(:session_elapsed_us, :bigint)
      add(:location_id, :binary_id)
      add(:target_id, :binary_id)
      add(:faction_id, :binary_id)
      add(:content_id, :binary_id)
      add(:data, :map, null: false, default: %{})
    end

    create(unique_index(:play_journal, [:actor_id, :position]))
    create(index(:play_journal, [:session_id, :session_position]))
    create(index(:play_journal, [:occurred_at]))
    create(constraint(:play_journal, :positive_journal_position, check: "position > 0"))
  end
end
