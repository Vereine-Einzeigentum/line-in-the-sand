defmodule LineCore.Schemas.Object do
  @moduledoc """
  Base entity in the MOO graph.

  Every thing in THE LINE is an object: players, rooms, items, NPCs, exits.
  Type discriminates behavior; properties hold everything else — both the
  object's own state and every connection it has to another object.

  There are no edges here. A connection is a property whose value is a
  reference, filed under the name the referenced thing goes by. See
  `LineCore.Schemas.Property`.

  This is the spine of the world. Verbs operate on objects. Look output
  renders from objects. Persistence is objects. Nothing else is foundational.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias LineCore.Schemas.Property

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

    # Everything this object holds: its own state, and its references to other
    # objects filed under the names they go by here.
    has_many :properties, Property, foreign_key: :object_id

    # Every property, anywhere, that points at this object. Read this way round,
    # a reference answers "where am I, and what do they call me there".
    has_many :referenced_by, Property, foreign_key: :ref_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:type, :name]
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
