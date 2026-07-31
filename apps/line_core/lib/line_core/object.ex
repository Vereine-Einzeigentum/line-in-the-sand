defmodule LineCore.Object do
  @moduledoc """
  Programmatic interface to the object graph.

  Use this instead of touching schemas directly. Handles property casting,
  relationship traversal, and the small set of queries every verb needs:
  find by id, find in room, room contents, inventory.
  """

  import Ecto.Query
  alias LineCore.Repo
  alias LineCore.Schemas.{Object, Property, Relationship}

  @type id :: binary()

  ## Creation

  @doc "Create an object of the given type with the given name."
  def create(type, name, attrs \\ %{}) do
    %Object{}
    |> Object.changeset(Map.merge(%{type: type, name: name}, attrs))
    |> Repo.insert()
  end

  ## Read

  @doc "Fetch an object by id. Returns nil if not found or deleted."
  def get(id) do
    from(o in Object, where: o.id == ^id and is_nil(o.deleted_at))
    |> Repo.one()
  end

  @doc "Fetch an object by id or raise."
  def get!(id), do: get(id) || raise("object not found: #{id}")

  ## Properties

  @doc "Get a property value by key. Returns nil if not set."
  def get_property(object_id, key) do
    from(p in Property, where: p.object_id == ^object_id and p.key == ^key, select: p.value)
    |> Repo.one()
    |> case do
      %{"v" => value} -> value
      nil -> nil
      other -> other
    end
  end

  @doc "Get a property with a default if not set."
  def get_property(object_id, key, default) do
    case get_property(object_id, key) do
      nil -> default
      value -> value
    end
  end

  @doc "Set a property. Upserts."
  def set_property(object_id, key, value) do
    # Wrap scalar values in a map so JSONB can store them uniformly.
    stored_value = if is_map(value), do: value, else: %{"v" => value}

    %Property{}
    |> Property.changeset(%{object_id: object_id, key: key, value: stored_value})
    |> Repo.insert(
      on_conflict: [set: [value: stored_value, updated_at: DateTime.utc_now()]],
      conflict_target: [:object_id, :key]
    )
  end

  @doc "Get all properties for an object as a map."
  def properties(object_id) do
    from(p in Property, where: p.object_id == ^object_id, select: {p.key, p.value})
    |> Repo.all()
    |> Enum.into(%{}, fn {k, v} ->
      {k, unwrap(v)}
    end)
  end

  defp unwrap(%{"v" => v}), do: v
  defp unwrap(other), do: other

  ## Relationships

  @doc "Create a relationship between two objects."
  def relate(from_id, to_id, type, metadata \\ %{}) do
    %Relationship{}
    |> Relationship.changeset(%{
      from_id: from_id,
      to_id: to_id,
      type: type,
      metadata: metadata
    })
    |> Repo.insert()
  end

  @doc "Remove a relationship."
  def unrelate(from_id, to_id, type) do
    from(r in Relationship,
      where: r.from_id == ^from_id and r.to_id == ^to_id and r.type == ^type
    )
    |> Repo.delete_all()
  end

  @doc "Move an object from its current container to a new one. Atomic."
  def move(object_id, new_container_id, type \\ :contains) do
    Repo.transaction(fn ->
      from(r in Relationship,
        where: r.to_id == ^object_id and r.type == ^type
      )
      |> Repo.delete_all()

      relate(new_container_id, object_id, type)
    end)
  end

  ## Containment queries

  @doc "All objects directly contained in a container (room contents, inventory)."
  def contents(container_id) do
    from(o in Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where: r.from_id == ^container_id and r.type == :contains and is_nil(o.deleted_at)
    )
    |> Repo.all()
  end

  @doc "The container an object is in (its room, or the player holding it)."
  def container_of(object_id) do
    from(o in Object,
      join: r in Relationship,
      on: r.from_id == o.id,
      where: r.to_id == ^object_id and r.type == :contains and is_nil(o.deleted_at)
    )
    |> Repo.one()
  end

  ## Exit queries

  @doc "All exits from a room: list of {direction_string, destination_room_object}."
  def exits(room_id) do
    from(o in Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where: r.from_id == ^room_id and r.type == :exit_to and is_nil(o.deleted_at),
      select: {fragment("?->>'direction'", r.metadata), o}
    )
    |> Repo.all()
  end

  @doc "Resolve an exit direction (e.g. 'n', 'north') from a room. Returns destination room object or nil."
  def resolve_exit(room_id, direction) do
    canonical = canonicalize_direction(direction)

    from(o in Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where:
        r.from_id == ^room_id and
          r.type == :exit_to and
          fragment("?->>'direction'", r.metadata) == ^canonical and
          is_nil(o.deleted_at)
    )
    |> Repo.one()
  end

  ## Name search

  @doc "Find the first object in a list whose name matches (case-insensitive exact or substring)."
  def find_by_name(objects, name) do
    name_down = String.downcase(name)

    Enum.find(objects, fn o ->
      String.contains?(String.downcase(o.name), name_down)
    end)
  end

  ## Equipment / relationship queries

  @doc "All objects related FROM owner_id by the given relationship type."
  def related_by(owner_id, rel_type) when is_atom(rel_type) do
    from(o in Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where: r.from_id == ^owner_id and r.type == ^rel_type and is_nil(o.deleted_at)
    )
    |> Repo.all()
  end

  @doc "All wielded and worn objects. Returns [{rel_type, object}]."
  def equipped(owner_id) do
    from(o in Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where:
        r.from_id == ^owner_id and
          r.type in [:wields_main, :wields_off, :wears] and
          is_nil(o.deleted_at),
      select: {r.type, o}
    )
    |> Repo.all()
  end

  @doc "Find a player by name (case-insensitive). Returns the object or nil."
  def find_player_by_name(name) when is_binary(name) do
    normalized = String.downcase(String.trim(name))

    from(o in Object,
      where: o.type == :player and is_nil(o.deleted_at),
      where: fragment("lower(?) = ?", o.name, ^normalized),
      limit: 1
    )
    |> Repo.one()
  end

  ## Direction canonicalization

  @directions %{
    "n" => "north",
    "s" => "south",
    "e" => "east",
    "w" => "west",
    "u" => "up",
    "d" => "down",
    "ne" => "northeast",
    "nw" => "northwest",
    "se" => "southeast",
    "sw" => "southwest",
    "in" => "in",
    "out" => "out",
    "north" => "north",
    "south" => "south",
    "east" => "east",
    "west" => "west",
    "up" => "up",
    "down" => "down",
    "northeast" => "northeast",
    "northwest" => "northwest",
    "southeast" => "southeast",
    "southwest" => "southwest"
  }

  def canonicalize_direction(d) when is_binary(d), do: Map.get(@directions, String.downcase(d), d)
end
