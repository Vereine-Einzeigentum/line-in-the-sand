defmodule LineCore.Schemas.Property do
  @moduledoc """
  Everything an object holds, and everything it points at.

  A property is one row: a key, and one of two kinds of value.

  - **Inert** — `value` holds a number, string, boolean, map or list. JSONB, so
    scalars are wrapped as `%{"v" => scalar}` on the way in.
  - **A reference** — `ref_id` names another object, with an optional number in
    `num` attached to the reference.

  There is no third kind and there is no edge table. The key carries the
  meaning that a typed relationship used to: a room's `north` names an exit
  object, a room's `knife` names a knife, a body's `left hand` names what it is
  holding. Nothing declares that `north` is a direction or that `knife` is
  contained, because nothing needs to — those are the names those things go by
  here.

  Both ends are indexed. A container's contents and a thing's whereabouts are
  one row read from either side.

  Examples:
      hp -> 12                          (inert)
      ambient -> "solder and dust"      (inert)
      north -> #exit_object             (reference)
      knife -> #knife_object            (reference)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias LineCore.Schemas.Object

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "object_properties" do
    belongs_to :object, Object

    field :key, :string

    # JSONB column, but :map is Ecto's idiom for it. Nil when this property is
    # a reference.
    field :value, :map

    # The object this property points at. Nil when the property is inert.
    belongs_to :ref, Object, foreign_key: :ref_id

    # A number attached to a reference — a quantity, a level, a rating. Only
    # meaningful alongside `ref_id`.
    field :num, :float

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:object_id, :key]
  @optional_fields [:value, :ref_id, :num]

  def changeset(property, attrs) do
    property
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:key, min: 1, max: 64)
    |> validate_one_kind()
    |> unique_constraint([:object_id, :key])
    |> foreign_key_constraint(:object_id)
    |> foreign_key_constraint(:ref_id)
  end

  # Inert or a reference, not both and not neither.
  defp validate_one_kind(changeset) do
    value = get_field(changeset, :value)
    ref_id = get_field(changeset, :ref_id)

    case {is_nil(value), is_nil(ref_id)} do
      {false, false} ->
        add_error(changeset, :ref_id, "a property is inert or a reference, not both")

      {true, true} ->
        add_error(changeset, :value, "a property needs a value or a reference")

      _ ->
        changeset
    end
  end
end
