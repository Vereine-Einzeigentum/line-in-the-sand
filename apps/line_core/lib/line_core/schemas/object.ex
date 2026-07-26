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
  @type object_type :: :player | :room | :item | :npc | :exit | :generic

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "objects" do
    # `:generic` marks a prototype — an object that exists to be inherited from
    # rather than to be walked into or picked up. Generics live outside
    # containment, so they never surface in room contents or inventories.
    field :type, Ecto.Enum, values: [:player, :room, :item, :npc, :exit, :generic]
    field :name, :string
    field :description, :string

    # Prototype inheritance. Properties and verbs resolve up this chain, with
    # the nearest definition winning, so a generic supplies defaults that any
    # descendant may shadow. See `LineCore.Object`.
    belongs_to :parent, __MODULE__, foreign_key: :parent_id

    # Verbs available on this object. Stored as a list of atoms identifying
    # registered verb handlers. The Object LM "knows" mechanical verbs; this
    # field declares which verbs this specific object responds to.
    field :verbs, {:array, :string}, default: []

    # Soft-deletion. Deleted objects stay in the graph (for journal integrity)
    # but are filtered from queries.
    field :deleted_at, :utc_datetime_usec

    # EAV pattern for flexible properties. Hot properties (HP, location)
    # might get promoted to columns later if profiling demands it.
    has_many :properties, Property, foreign_key: :object_id

    # Outgoing edges (this object is the source).
    has_many :outgoing_relationships, Relationship, foreign_key: :from_id

    # Incoming edges (this object is the target).
    has_many :incoming_relationships, Relationship, foreign_key: :to_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :name]

  # `:id` is castable so a caller can decide an object's id *before* it exists.
  # `LineCore.Genesis.plan/1` relies on this: it pre-generates the UUID and
  # threads it through the `:relate` and `:set_property` events that accompany
  # the `:create_object` event, which is what lets a whole object be described
  # as one ordered event list without the dispatcher having to resolve
  # forward references.
  @optional_fields [:id, :description, :verbs, :deleted_at, :parent_id]

  def changeset(object, attrs) do
    object
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 120)
    |> validate_not_self_parent()
    |> foreign_key_constraint(:parent_id)
  end

  defp validate_not_self_parent(changeset) do
    id = get_field(changeset, :id)
    parent_id = get_field(changeset, :parent_id)

    if not is_nil(id) and id == parent_id do
      add_error(changeset, :parent_id, "an object cannot be its own parent")
    else
      changeset
    end
  end
end
