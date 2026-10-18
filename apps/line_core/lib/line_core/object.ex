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
    attrs = maybe_default_parent(type, name, attrs)

    %Object{}
    |> Object.changeset(Map.merge(%{type: type, name: name}, attrs))
    |> Repo.insert()
  end

  defp maybe_default_parent(type, name, attrs) when is_binary(name) do
    has_parent =
      Map.has_key?(attrs, :parent_id) or
        Map.has_key?(attrs, "parent_id")

    cond do
      has_parent ->
        attrs

      String.starts_with?(name, "$") ->
        attrs

      true ->
        case LineCore.Archetypes.default_parent_id(type) do
          nil -> attrs
          parent_id -> Map.put(attrs, :parent_id, parent_id)
        end
    end
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

  @doc "Get a local property value only, without consulting inheritance."
  def get_local_property(object_id, key) do
    from(p in Property, where: p.object_id == ^object_id and p.key == ^key, select: p.value)
    |> Repo.one()
    |> case do
      %{"v" => value} -> value
      nil -> nil
      other -> other
    end
  end

  @doc "Get the effective property value, walking parent objects when absent locally."
  def get_property(object_id, key) do
    do_get_property(object_id, key, MapSet.new())
  end

  @doc "Get an effective property with a default if not found."
  def get_property(object_id, key, default) do
    case get_property(object_id, key) do
      nil -> default
      value -> value
    end
  end

  defp do_get_property(object_id, key, seen) do
    if MapSet.member?(seen, object_id) do
      nil
    else
      case get_local_property(object_id, key) do
        nil ->
          case parent(object_id) do
            nil -> nil
            parent -> do_get_property(parent.id, key, MapSet.put(seen, object_id))
          end

        value ->
          value
      end
    end
  end

  @doc "Set a property locally. Upserts; inherited values are never mutated."
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

  @doc "Get all properties whose key starts with the given prefix."
  def properties_by_prefix(object_id, prefix) when is_binary(prefix) do
    like_pattern = prefix <> "%"

    from(p in Property,
      where: p.object_id == ^object_id and like(p.key, ^like_pattern),
      select: {p.key, p.value}
    )
    |> Repo.all()
    |> Enum.map(fn {k, v} -> {k, unwrap(v)} end)
  end

  ## Inheritance

  @doc "Return the object's direct inheritance parent, or nil."
  def parent(object_id) do
    case get(object_id) do
      %{parent_id: nil} -> nil
      %{parent_id: parent_id} -> get(parent_id)
      nil -> nil
    end
  end

  @doc "Return direct parent first, then each ancestor up to the root."
  def ancestors(object_id) do
    do_ancestors(object_id, MapSet.new())
  end

  defp do_ancestors(object_id, seen) do
    if MapSet.member?(seen, object_id) do
      []
    else
      case parent(object_id) do
        nil ->
          []

        ancestor ->
          [ancestor | do_ancestors(ancestor.id, MapSet.put(seen, object_id))]
      end
    end
  end

  @doc "True when object_id inherits from ancestor_id at any depth."
  def descendant_of?(object_id, ancestor_id) do
    Enum.any?(ancestors(object_id), &(&1.id == ancestor_id))
  end

  @doc "Direct inheritance children, oldest first."
  def children(parent_id) do
    from(o in Object,
      where: o.parent_id == ^parent_id and is_nil(o.deleted_at),
      order_by: [asc: o.inserted_at, asc: o.id]
    )
    |> Repo.all()
  end

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
      where: r.from_id == ^container_id and r.type == :contains and is_nil(o.deleted_at),
      order_by: [asc: o.inserted_at, asc: o.id]
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

  @doc "True when object_id is transitively contained by container_id."
  def contained_by?(object_id, container_id) do
    do_contained_by?(object_id, container_id, MapSet.new())
  end

  defp do_contained_by?(object_id, container_id, seen) do
    cond do
      object_id == container_id ->
        true

      MapSet.member?(seen, object_id) ->
        false

      true ->
        case container_of(object_id) do
          nil ->
            false

          %{id: ^container_id} ->
            true

          parent_container ->
            do_contained_by?(
              parent_container.id,
              container_id,
              MapSet.put(seen, object_id)
            )
        end
    end
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

  @doc "Find an object anywhere in the live object graph by the same name rules as local resolution."
  def find_global_by_name(name) when is_binary(name) do
    from(o in Object,
      where: is_nil(o.deleted_at),
      order_by: [asc: o.inserted_at, asc: o.id]
    )
    |> Repo.all()
    |> find_by_name(name)
  end

  @doc """
  Find an object by visible name.

  Exact case-insensitive names win over substring matches. A leading one-based
  selector such as `1.bag` or `2.bag` selects among the ordered matches,
  preserving ordinary MOO duplicate-name disambiguation.
  """
  def find_by_name(objects, name) do
    {ordinal, query} = parse_match_selector(name)
    normalized = String.downcase(query)

    exact =
      Enum.filter(objects, fn object ->
        String.downcase(object.name) == normalized
      end)

    matches =
      if exact == [] do
        Enum.filter(objects, fn object ->
          String.contains?(String.downcase(object.name), normalized)
        end)
      else
        exact
      end

    Enum.at(matches, ordinal - 1)
  end

  defp parse_match_selector(name) do
    trimmed = String.trim(name)

    case Regex.run(~r/^(\d+)\.(.+)$/, trimmed) do
      [_, ordinal, query] ->
        case Integer.parse(ordinal) do
          {n, ""} when n > 0 -> {n, String.trim(query)}
          _ -> {1, trimmed}
        end

      _ ->
        {1, trimmed}
    end
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

  @doc "Objects owned by owner_id through the ordinary :owns relation."
  def owned(owner_id), do: related_by(owner_id, :owns)

  @doc "True when owner_id owns object_id."
  def owns?(owner_id, object_id) do
    Enum.any?(owned(owner_id), &(&1.id == object_id))
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
