defmodule LineCore.Genesis do
  @moduledoc """
  The single supported way to bring an object into the graph.

  Sits between `LineCore.Object` (graph primitives) and every caller that needs to
  create world objects: seeds, `PlaytestSession`, and any future verb that spawns
  something (though verbs use `plan/1` to stay pure).

  ## Design

  `plan/1` is pure — no Repo access. It accepts a fully-resolved spec (template
  already fetched as `%Object{}` or `nil`, type already resolved) and returns the
  UUID the object *will* have together with the ordered event list that materialises
  it. That event list is identical to the events any verb returns, so it can be
  embedded in a verb's `{:ok, events}` and applied by the dispatcher in a single
  transaction.

  `create/1` is the impure convenience wrapper: it resolves the template atom or
  id to an `%Object{}`, derives the type from the template's `instance_type`
  property when not stated, calls `plan/1`, then applies the events in one
  `Ecto.Multi` + `Repo.transaction`.

  ## Generic atoms

  Template atoms map to named generics in the seeded taxonomy:

      :room     → "Room"          instance_type: "room"
      :thing    → "Thing"         (abstract — no instance_type)
      :weapon   → "Weapon"        instance_type: "item"
      :scrap    → "Scrap"         instance_type: "item"
      :mob      → "Mob"           (abstract — no instance_type)
      :human    → "Human"         (abstract — no instance_type)
      :npc      → "NPC"           instance_type: "npc"
      :pc       → "PC"            instance_type: "player"

  Spawning from an abstract generic (one with no `instance_type` property) returns
  `{:error, :abstract_generic}` rather than silently producing a wrongly-typed
  object. Use a leaf atom or supply `:type` explicitly.

  ## Example

      # Pure event-list assembly — no DB
      generic_weapon = %LineCore.Schemas.Object{id: "...", type: :generic, ...}
      {:ok, %{id: crowbar_id, events: events}} = Genesis.plan(%{
        name: "bent crowbar",
        type: :item,
        template: generic_weapon,
        description: "Steel crowbar.",
        properties: %{"damage" => 18, "scrap_value" => 15}
      })

      # Impure one-liner for seeds and session init
      crowbar = Genesis.item!(sz_center, "bent crowbar",
        template: :weapon,
        description: "Steel crowbar, bent at the hook.",
        properties: %{scrap_value: 15, damage: 18}
      )
  """

  alias Ecto.Multi
  alias LineCore.Repo
  alias LineCore.Schemas.{Object, Property, Relationship}

  @type id :: binary()
  @type generic_ref :: atom() | id() | struct()

  @type spec :: %{
          required(:name) => String.t(),
          optional(:type) => atom(),
          optional(:template) => generic_ref(),
          optional(:description) => String.t(),
          optional(:verbs) => [String.t()],
          optional(:properties) => %{(String.t() | atom()) => term()},
          optional(:place_in) => id()
        }

  # Atom shortcuts → generic names in the seeded taxonomy.
  @generic_names %{
    room: "Room",
    thing: "Thing",
    weapon: "Weapon",
    scrap: "Scrap",
    mob: "Mob",
    human: "Human",
    npc: "NPC",
    pc: "PC"
  }

  ## Pure

  @doc """
  Produce the UUID and event list that will materialise `spec` in the graph.

  **Pure** — no Repo access. The caller must pre-resolve the spec:

  - `:template` must be a `%Object{}` or `nil` (use `create/1` for atom/id resolution).
  - `:type` must be set (use `create/1` for `instance_type`-based derivation).

  The returned events are in the same format the dispatcher applies, so they can
  be appended to a verb's event list and committed in one transaction.
  """
  @spec plan(spec()) :: {:ok, %{id: id(), events: [LineCore.Verb.event()]}} | {:error, term()}
  def plan(%{name: name} = spec) do
    template_obj = Map.get(spec, :template)

    with {:ok, validated_name} <- validate_name(name),
         :ok <- validate_template_resolved(template_obj),
         {:ok, type} <- fetch_type(spec) do
      id = Ecto.UUID.generate()

      object_attrs =
        %{id: id, type: type, name: validated_name}
        |> maybe_put(:description, spec[:description])
        |> maybe_put(:verbs, spec[:verbs])
        |> maybe_put(:parent_id, template_obj && template_obj.id)

      prop_events =
        (spec[:properties] || %{})
        |> Enum.map(fn {k, v} -> {:set_property, id, to_string(k), v} end)

      place_events =
        if place_in = spec[:place_in] do
          [{:relate, place_in, id, :contains}]
        else
          []
        end

      events = [{:create_object, object_attrs}] ++ prop_events ++ place_events

      {:ok, %{id: id, events: events}}
    end
  end

  def plan(%{}), do: {:error, {:missing_required_field, :name}}

  ## Impure

  @doc """
  Resolve template and type, plan the object, apply events in one transaction.

  Returns the created `%Object{}` or an error tuple.
  """
  @spec create(map()) :: {:ok, struct()} | {:error, term()}
  def create(%{} = spec) do
    with {:ok, resolved} <- resolve_spec(spec),
         {:ok, %{id: id, events: events}} <- plan(resolved),
         {:ok, _} <- apply_events(events) do
      {:ok, LineCore.Object.get!(id)}
    end
  end

  @doc "Like `create/1` but raises on error."
  @spec create!(map()) :: struct()
  def create!(%{} = spec) do
    case create(spec) do
      {:ok, obj} -> obj
      {:error, reason} -> raise "LineCore.Genesis.create! failed: #{inspect(reason)}"
    end
  end

  @doc """
  Create multiple objects in a single atomic transaction.

  All succeed or all roll back.
  """
  @spec create_many([map()]) :: {:ok, [struct()]} | {:error, term()}
  def create_many(specs) when is_list(specs) do
    with {:ok, plans} <- plan_all(specs),
         all_events = Enum.flat_map(plans, & &1.events),
         ids = Enum.map(plans, & &1.id),
         {:ok, _} <- apply_events(all_events) do
      objects = Enum.map(ids, &LineCore.Object.get!(&1))
      {:ok, objects}
    end
  end

  ## Readable helpers

  @doc """
  Create a room. Sets `type: :room` and `template: :room` by default.
  Opts: `:description`, `:verbs`, `:properties`, `:template`.
  """
  @spec room!(String.t(), keyword()) :: struct()
  def room!(name, opts \\ []) do
    spec = opts |> Enum.into(%{}) |> Map.merge(%{name: name, type: :room})
    spec = Map.put_new(spec, :template, :room)
    create!(spec)
  end

  @doc """
  Create an item and place it in `container`. Sets `type: :item`.
  Opts: `:description`, `:verbs`, `:properties`, `:template`.
  """
  @spec item!(struct(), String.t(), keyword()) :: struct()
  def item!(container, name, opts \\ []) do
    spec =
      opts
      |> Enum.into(%{})
      |> Map.merge(%{name: name, type: :item, place_in: container.id})

    create!(spec)
  end

  @doc """
  Create an NPC and place it in `container`. Sets `type: :npc`, `template: :npc` by default.
  Opts: `:description`, `:verbs`, `:properties`, `:template`.
  """
  @spec npc!(struct(), String.t(), keyword()) :: struct()
  def npc!(container, name, opts \\ []) do
    spec =
      opts
      |> Enum.into(%{})
      |> Map.merge(%{name: name, type: :npc, place_in: container.id})

    spec = Map.put_new(spec, :template, :npc)
    create!(spec)
  end

  @doc """
  Create a player object. Sets `type: :player`, `template: :pc` by default.

  Player creation is an account-lifecycle concern, not a world mutation — this
  helper exists for seeding, session initialisation, and tests. Verbs must not
  call it.

  Opts: `:description`, `:verbs`, `:properties`, `:template`, `:place_in`.
  """
  @spec player!(String.t(), keyword()) :: struct()
  def player!(name, opts \\ []) do
    spec = opts |> Enum.into(%{}) |> Map.merge(%{name: name, type: :player})
    spec = Map.put_new(spec, :template, :pc)
    create!(spec)
  end

  ## Internal

  defp plan_all(specs) do
    Enum.reduce_while(specs, {:ok, []}, fn spec, {:ok, acc} ->
      with {:ok, resolved} <- resolve_spec(spec),
           {:ok, plan} <- plan(resolved) do
        {:cont, {:ok, acc ++ [plan]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp resolve_spec(%{template: ref} = spec) when not is_nil(ref) and not is_struct(ref) do
    # Resolve atom or id to %Object{}, then derive type if needed
    with {:ok, generic_obj} <- resolve_generic_ref(ref),
         {:ok, type} <- derive_type(spec, generic_obj) do
      {:ok, spec |> Map.put(:template, generic_obj) |> Map.put(:type, type)}
    end
  end

  defp resolve_spec(%{template: %Object{}} = spec) do
    with {:ok, type} <- derive_type(spec, spec.template) do
      {:ok, Map.put(spec, :type, type)}
    end
  end

  defp resolve_spec(spec) do
    # No template — type must be explicit
    case Map.get(spec, :type) do
      nil -> {:error, :type_required}
      _type -> {:ok, spec}
    end
  end

  defp resolve_generic_ref(atom) when is_atom(atom) do
    case Map.get(@generic_names, atom) do
      nil -> {:error, {:unknown_generic_ref, atom}}
      name -> find_generic_by_name(name)
    end
  end

  defp resolve_generic_ref(id) when is_binary(id) do
    case LineCore.Object.get(id) do
      nil -> {:error, {:generic_not_found, id}}
      obj -> {:ok, obj}
    end
  end

  defp find_generic_by_name(name) do
    import Ecto.Query

    case Repo.one(
           from(o in Object,
             where: o.name == ^name and o.type == :generic and is_nil(o.deleted_at),
             limit: 1
           )
         ) do
      nil -> {:error, {:generic_not_found, name}}
      obj -> {:ok, obj}
    end
  end

  defp derive_type(%{type: type}, _generic_obj) when not is_nil(type), do: {:ok, type}

  defp derive_type(_spec, generic_obj) do
    case LineCore.Object.get_property(generic_obj.id, "instance_type") do
      nil ->
        {:error, :abstract_generic}

      type_str when is_binary(type_str) ->
        case type_str do
          "room" -> {:ok, :room}
          "item" -> {:ok, :item}
          "npc" -> {:ok, :npc}
          "player" -> {:ok, :player}
          other -> {:error, {:unknown_instance_type, other}}
        end
    end
  end

  defp validate_template_resolved(nil), do: :ok
  defp validate_template_resolved(%Object{}), do: :ok

  defp validate_template_resolved(other),
    do: {:error, {:template_not_resolved, other}}

  defp validate_name(""), do: {:error, :name_empty}

  defp validate_name(name)
       when is_binary(name) and byte_size(name) >= 1 and byte_size(name) <= 120,
       do: {:ok, name}

  defp validate_name(name) when is_binary(name), do: {:error, :name_too_long}
  defp validate_name(_), do: {:error, :name_invalid}

  defp fetch_type(%{type: type}) when not is_nil(type), do: {:ok, type}
  defp fetch_type(_), do: {:error, :type_required}

  defp apply_events(events) do
    multi =
      Enum.reduce(events, Multi.new(), fn event, acc ->
        add_to_multi(acc, event)
      end)

    case Repo.transaction(multi) do
      {:ok, _} -> {:ok, :applied}
      {:error, _key, reason, _changes} -> {:error, reason}
    end
  end

  defp add_to_multi(multi, {:create_object, attrs}) do
    Multi.insert(
      multi,
      {:create_object, make_ref()},
      Object.changeset(%Object{}, attrs)
    )
  end

  defp add_to_multi(multi, {:set_property, object_id, key, value}) do
    stored = if is_map(value), do: value, else: %{"v" => value}

    Multi.insert(
      multi,
      {:set_property, object_id, key, make_ref()},
      Property.changeset(%Property{}, %{object_id: object_id, key: key, value: stored}),
      on_conflict: [set: [value: stored, updated_at: DateTime.utc_now()]],
      conflict_target: [:object_id, :key]
    )
  end

  defp add_to_multi(multi, {:relate, from_id, to_id, rel_type}) do
    Multi.insert(
      multi,
      {:relate, from_id, to_id, rel_type, make_ref()},
      Relationship.changeset(%Relationship{}, %{from_id: from_id, to_id: to_id, type: rel_type})
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
