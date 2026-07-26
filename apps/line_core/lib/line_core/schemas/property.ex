defmodule LineCore.Schemas.Property do
  @moduledoc """
  Key-value properties attached to objects.

  EAV (entity-attribute-value) pattern. Each property is a row, which makes
  schema flexible (no migrations to add new attributes) and queryable
  (find all players with HP < 10).

  Value is stored as JSONB so it can hold numbers, strings, booleans, maps,
  or arrays. The application layer is responsible for type discipline.

  Examples:
    Player object:
      hp -> 50, max_hp -> 50, fatigue -> 0, max_fatigue -> 40,
      stress -> 0, dirham -> 100, yuan -> 0,
      stat_wire -> 3, stat_shade -> 4, ..., stat_vigor -> 5,
      skill_brawl -> 1, skill_scrap -> 2, skill_entry -> 0,
      faction_rep_triad -> 5

    Room object:
      ambient -> "smell of solder and dust",
      light -> :dim

    Item object:
      weight -> 1.5, condition -> 0.8, manufacturer -> "CRCC",
      damage -> 8, damage_type -> :piercing
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias LineCore.Schemas.Object

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "object_properties" do
    belongs_to(:object, Object)

    field(:key, :string)
    # JSONB column, but :map is Ecto's idiom for it
    field(:value, :map)

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:object_id, :key, :value]

  def changeset(property, attrs) do
    property
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:key, min: 1, max: 64)
    |> unique_constraint([:object_id, :key])
    |> foreign_key_constraint(:object_id)
  end
end
