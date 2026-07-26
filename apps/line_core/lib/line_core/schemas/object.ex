defmodule LineCore.Schemas.Object do
  @moduledoc """
  Base entity in the MOO graph.

  Every thing in THE LINE is an object: players, rooms, items, NPCs.
  Type discriminates behavior; properties hold mutable state; relationships
  connect objects to other objects (containment, exits, ownership).

  This is the spine of the world. Verbs operate on objects. Look output
  renders from objects. Persistence is objects. Nothing else is foundational.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias LineCore.Schemas.{Property, Relationship}

  @type id :: binary()
  @type object_type :: :player | :room | :item | :npc | :exit

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "objects" do
    field(:type, Ecto.Enum, values: [:player, :room, :item, :npc, :exit])
    field(:name, :string)
    field(:description, :string)

    # Verbs available on this object. Stored as a list of atoms identifying
    # registered verb handlers. The Object LM "knows" mechanical verbs; this
    # field declares which verbs this specific object responds to.
    field(:verbs, {:array, :string}, default: [])

    # Soft-deletion. Deleted objects stay in the graph (for journal integrity)
    # but are filtered from queries.
    field(:deleted_at, :utc_datetime_usec)

    # EAV pattern for flexible properties. Hot properties (HP, location)
    # might get promoted to columns later if profiling demands it.
    has_many(:properties, Property, foreign_key: :object_id)

    # Outgoing edges (this object is the source).
    has_many(:outgoing_relationships, Relationship, foreign_key: :from_id)

    # Incoming edges (this object is the target).
    has_many(:incoming_relationships, Relationship, foreign_key: :to_id)

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :name]
  @optional_fields [:description, :verbs, :deleted_at]

  def changeset(object, attrs) do
    object
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 120)
  end
end
