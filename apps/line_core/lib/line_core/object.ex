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

  ## Inheritance

  # Prototype chains are expected to be shallow (a handful of links). The cap
  # is a safety net against a cycle introduced outside `set_parent/2`, not a
  # design limit.
  @max_depth 16

  @doc """
  The object's prototype chain, nearest ancestor first, excluding the object.

  Walks `parent_id` **without** filtering `deleted_at`: soft-deleting a generic
  must not silently strip inherited properties from everything descended from
  it. Stops at the first repeat, so a malformed cycle degrades to a finite
  chain rather than hanging.
  """
  def ancestors(object_id) do
    walk_ancestors(parent_id_of(object_id), MapSet.new([object_id]), [])
  end

  @doc "The object itself followed by its ancestors — the full lookup order."
  def lineage(object_id), do: [object_id | ancestors(object_id)]

  defp walk_ancestors(nil, _seen, acc), do: Enum.reverse(acc)

  defp walk_ancestors(id, seen, acc) do
    cond do
      MapSet.member?(seen, id) -> Enum.reverse(acc)
      length(acc) >= @max_depth -> Enum.reverse(acc)
      true -> walk_ancestors(parent_id_of(id), MapSet.put(seen, id), [id | acc])
    end
  end

  defp parent_id_of(object_id) do
    from(o in Object, where: o.id == ^object_id, select: o.parent_id) |> Repo.one()
  end

  @doc """
  Set (or clear, with `nil`) an object's prototype.

  Refuses a parent that is the object itself or one of its own descendants,
  which would orphan a cycle out of the lookup order.
  """
  def set_parent(object_id, nil) do
    get!(object_id) |> Object.changeset(%{parent_id: nil}) |> Repo.update()
  end

  def set_parent(object_id, parent_id) do
    cond do
      object_id == parent_id ->
        {:error, :self_parent}

      object_id in lineage(parent_id) ->
        {:error, :cycle}

      true ->
        get!(object_id) |> Object.changeset(%{parent_id: parent_id}) |> Repo.update()
    end
  end

  @doc """
  Create an object deriving from `generic_id`, inheriting its type.

  The MOO idiom: you do not build a room from nothing, you derive one from the
  generic room. Pass `type` in `attrs` to override.
  """
  def spawn_from(generic_id, name, attrs \\ %{}) do
    case get(generic_id) do
      nil ->
        {:error, :generic_not_found}

      generic ->
        type = Map.get(attrs, :type, generic.type)

        attrs
        |> Map.merge(%{parent_id: generic_id, type: type})
        |> then(&create(type, name, &1))
    end
  end

  ## Properties

  @doc """
  Get a property value by key, inheriting from the prototype chain.

  The object's own value wins; failing that the nearest ancestor that defines
  the key supplies it. Returns nil if no one in the chain defines it.
  """
  def get_property(object_id, key) do
    case own_property(object_id, key) do
      nil -> inherited_property(object_id, key)
      value -> value
    end
  end

  @doc "Get a property defined directly on this object, ignoring inheritance."
  def own_property(object_id, key) do
    from(p in Property, where: p.object_id == ^object_id and p.key == ^key, select: p.value)
    |> Repo.one()
    |> unwrap_or_nil()
  end

  defp inherited_property(object_id, key) do
    case ancestors(object_id) do
      [] ->
        nil

      chain ->
        found =
          from(p in Property,
            where: p.object_id in ^chain and p.key == ^key,
            select: {p.object_id, p.value}
          )
          |> Repo.all()
          |> Map.new()

        chain
        |> Enum.find_value(fn id -> Map.get(found, id) end)
        |> unwrap_or_nil()
    end
  end

  defp unwrap_or_nil(nil), do: nil
  defp unwrap_or_nil(%{"v" => value}), do: value
  defp unwrap_or_nil(other), do: other

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

  @doc """
  All effective properties as a map, inherited values included.

  Merged furthest ancestor first so nearer definitions shadow further ones and
  the object's own values win outright.
  """
  def properties(object_id) do
    chain = lineage(object_id)

    rows =
      from(p in Property,
        where: p.object_id in ^chain,
        select: {p.object_id, p.key, p.value}
      )
      |> Repo.all()
      |> Enum.group_by(fn {id, _, _} -> id end)

    chain
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn id, acc ->
      rows
      |> Map.get(id, [])
      |> Enum.into(%{}, fn {_, k, v} -> {k, unwrap(v)} end)
      |> then(&Map.merge(acc, &1))
    end)
  end

  @doc "Properties defined directly on this object, ignoring inheritance."
  def own_properties(object_id) do
    from(p in Property, where: p.object_id == ^object_id, select: {p.key, p.value})
    |> Repo.all()
    |> Enum.into(%{}, fn {k, v} -> {k, unwrap(v)} end)
  end

  @doc """
  Verbs this object responds to, its prototype chain's included.

  Union rather than shadowing: a generic grants capabilities to everything
  descended from it, and a descendant adds its own.
  """
  def effective_verbs(object_id) do
    chain = lineage(object_id)

    from(o in Object, where: o.id in ^chain, select: o.verbs)
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
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
