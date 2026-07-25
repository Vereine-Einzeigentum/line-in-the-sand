defmodule LineCore.Schemas.JournalEntry do
  @moduledoc """
  One row per successful dispatch: who did what, where, phrased how, and the
  full event list the verb produced.

  This is the append-only training corpus for the world/object models and the
  system-of-record for "what happened" (debugging, audit, replay). Entries are
  written inside the same transaction as the events they describe, so the
  journal can never disagree with the world state.

  Following the repo's JSONB conventions, `args` and `events` are wrapped as
  `%{"v" => list}`. Events are serialized by `LineCore.Journal` into maps of
  the shape `%{"type" => name, "args" => [...]}`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "journal_entries" do
    field(:actor_id, :binary_id)
    field(:room_id, :binary_id)
    field(:verb, :string)
    field(:raw, :string)
    field(:args, :map, default: %{"v" => []})
    field(:events, :map)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:actor_id, :room_id, :verb, :raw, :args, :events])
    |> validate_required([:actor_id, :verb, :events])
  end
end
