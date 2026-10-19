defmodule LineCore.Journal.Entry do
  @moduledoc "Versioned observations of committed dispatches and distinct diagnostics."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "play_journal" do
    field(:schema_version, :integer, default: 1)
    field(:actor_id, :binary_id)
    field(:position, :integer)
    field(:event_type, :string)
    field(:outcome, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:elapsed_us, :integer)
    field(:session_id, :binary_id)
    field(:session_position, :integer)
    field(:session_elapsed_us, :integer)
    field(:location_id, :binary_id)
    field(:target_id, :binary_id)
    field(:faction_id, :binary_id)
    field(:content_id, :binary_id)
    field(:data, :map, default: %{})
  end
end
