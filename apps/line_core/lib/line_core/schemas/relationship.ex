defmodule LineCore.Schemas.Relationship do
  @moduledoc """
  Directed edges between objects.

  The MOO is a graph. Relationships are the edges. Different relationship
  types model different game concepts:

  - :contains       — a room contains items/NPCs/players; a player contains
                      items (inventory); a container contains contents
  - :exit_to        — from_id is a room, to_id is a room, direction stored
                      in metadata. One row per exit direction.
  - :owns           — from_id owns to_id (an account owns a player object,
                      an org owns a storefront, etc.)
  - :wields_main    — player wields item in main hand
  - :wields_off     — player wields item in off hand
  - :wears          — player wears armor/clothing
  - :follows        — npc/pet follows player
  - :targeting      — player/npc currently targeting another for combat

  The `metadata` JSONB field holds per-edge data (direction for exits,
  attachment slot for wears, target lock state for targeting, etc.).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias LineCore.Schemas.Object

  @relationship_types ~w(contains exit_to owns wields_main wields_off wears follows targeting)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "object_relationships" do
    belongs_to :from, Object, foreign_key: :from_id
    belongs_to :to, Object, foreign_key: :to_id

    field :type, Ecto.Enum, values: @relationship_types
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:from_id, :to_id, :type]
  @optional_fields [:metadata]

  def changeset(rel, attrs) do
    rel
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:from_id)
    |> foreign_key_constraint(:to_id)
  end

  @doc "List of all valid relationship types."
  def types, do: @relationship_types
end
