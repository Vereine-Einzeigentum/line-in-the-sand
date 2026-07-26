defmodule LineCore.Genesis do
  @moduledoc """
  The one supported way to bring an object into the graph.

  Sits between `LineCore.Object` (graph primitives) and everything that needs
  to *make* something. Before this module, twelve call sites hand-assembled
  objects out of `Object.create/3` plus a trailing sequence of `relate` and
  `set_property` calls — none of them setting `parent_id`, all of them
  non-atomic. Both problems are structural, and both are fixed here.

  ## plan/1 is the load-bearing half

  `plan/1` pre-generates the object's UUID with `Ecto.UUID.generate/0` and
  threads it through the `:create_object` attrs *and* every `:relate` and
  `:set_property` event that follows. That is what dissolves the "reference an
  object that does not exist yet" ordering problem **without changing the
  dispatcher at all** — no new event shapes, no forward-reference resolution in
  `apply_event_to_multi/3`. The only companion change is `:id` becoming
  castable in `LineCore.Schemas.Object.changeset/2`.

  The returned event list is an ordinary one. A verb may splice it straight
  into its own `{:ok, events}` and the dispatcher will apply it transactionally
  alongside everything else the verb decided.

  ### On purity

  `plan/1` performs **no writes and no broadcasts** — that is the invariant
  this codebase means by "pure", and it holds exactly. It does perform *reads*:
  resolving a `t:generic_ref/0` atom to its generic's id, and reading
  `instance_type` off the template to derive a type, both require the database.
  This is the same latitude `LineCore.Combat.damage_events/3` and
  `LineCore.Verbs.Look` already take. A spec that names its `:type` outright
  and passes no atom template needs no reads at all, which is why the
  event-shape tests can run without a sandbox checkout.

  ## Type is decided at the call site, never inherited from `:generic`

  A generic is `:generic` by construction, so inheriting a template's own type
  is always wrong. Resolution order:

  1. A purpose-shaped helper fixes it (`item!/3` → `:item`, `npc!/3` → `:npc`).
  2. A raw spec may state `:type`; explicit always wins.
  3. Otherwise it resolves from an `instance_type` property on the template,
     via the ancestor walk `Object.get_property/2` already performs.
  4. Only concrete generics declare `instance_type`. The abstract intermediates
     — `Generic Thing`, `Generic Mob`, `Generic Human`, `Generic Agent` — leave
     it unset, so deriving a type from one is a hard `:abstract_generic` error
     rather than a silent wrong answer.

  ## Players are not world mutations

  `plan/1` refuses `type: :player` with `:player_creation_forbidden`. Player
  creation is an account-lifecycle concern; a verb must not be able to conjure
  one. `player!/2` is the deliberate, impure door, and it is not reachable from
  the event layer.

  ## Examples

      Genesis.room!("District One: Safehouse", description: "A concrete cube.")

      Genesis.item!(scrap_zone, "bent crowbar",
        template: :weapon,
        description: "Steel crowbar, bent at the hook.",
        properties: %{scrap_value: 15, damage: 18}
      )

  The crowbar derives from `Generic Weapon`, so it inherits `wield`/`unwield`
  through `effective_verbs/1` without anyone listing them.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias LineCore.{Dispatcher, Object, Repo}
  alias LineCore.Schemas.Object, as: ObjSchema

  @type id :: binary()

  @typedoc """
  How to name the generic an object derives from: a well-known atom, a raw
  object id, or an already-loaded object.
  """
  @type generic_ref :: atom() | id() | ObjSchema.t()

  @typedoc """
  Provenance — who or what brought this object into the world. Recorded for
  attribution, **not** as a licence to delete.
  """
  @type source :: :seed | :hand | :generated | :playtest | :player

  @type spec :: %{
          required(:name) => String.t(),
          optional(:type) => ObjSchema.object_type(),
          optional(:template) => generic_ref(),
          optional(:description) => String.t(),
          optional(:verbs) => [String.t()],
          optional(:properties) => %{(String.t() | atom()) => term()},
          optional(:place_in) => id(),
          optional(:source) => source()
        }

  @type plan_result :: %{id: id(), events: [tuple()]}

  # Atoms are typo-proof in a way name strings are not. The raw-id escape hatch
  # keeps one-off generics to a single argument.
  @generics %{
    room: "Generic Room",
    thing: "Generic Thing",
    weapon: "Generic Weapon",
    scrap: "Generic Scrap",
    mob: "Generic Mob",
    human: "Generic Human",
    npc: "Generic NPC",
    pc: "Generic PC",
    agent: "Generic Agent",
    operator: "Generic Operator",
    supervisor: "Generic Supervisor",
    representative: "Generic Representative",
    handler: "Generic Handler",
    director: "Generic Director",
    shareholder: "Generic Shareholder"
  }

  # Whitelist rather than String.to_existing_atom/1: instance_type arrives from
  # JSONB, which is to say from data, and data does not get to mint atoms.
  @instance_types %{
    "player" => :player,
    "room" => :room,
    "item" => :item,
    "npc" => :npc,
    "exit" => :exit,
    "generic" => :generic
  }

  @object_types [:player, :room, :item, :npc, :exit, :generic]
  @sources [:seed, :hand, :generated, :playtest, :player]

  @doc "The atom → generic-name table `t:generic_ref/0` resolves against."
  @spec generic_names() :: %{atom() => String.t()}
  def generic_names, do: @generics

  ## Plan

  @doc """
  Describe the object a spec asks for: the id it *will* have, and the ordered
  events that materialise it.

  Pure in the sense that matters — emits events rather than performing writes,
  so the result is embeddable in a verb's `{:ok, events}`. See the module doc
  on what reads it does perform.

  Refuses `type: :player`; use `player!/2`.
  """
  @spec plan(spec()) :: {:ok, plan_result()} | {:error, term()}
  def plan(spec), do: plan(spec, [])

  @doc false
  # `allow_player: true` is the private door player!/2 goes through. It is not
  # part of the public contract precisely so the event layer cannot find it.
  @spec plan(spec(), keyword()) :: {:ok, plan_result()} | {:error, term()}
  def plan(spec, opts) when is_map(spec) and is_list(opts) do
    with {:ok, name} <- fetch_name(spec),
         {:ok, template_id} <- resolve_template(Map.get(spec, :template)),
         {:ok, type} <- resolve_type(spec, template_id),
         :ok <- permit_type(type, opts),
         {:ok, source} <- resolve_source(spec),
         {:ok, properties} <- normalize_properties(Map.get(spec, :properties, %{})),
         :ok <- validate_place_in(Map.get(spec, :place_in)) do
      id = Ecto.UUID.generate()

      attrs =
        %{id: id, type: type, name: name}
        |> maybe_put(:description, Map.get(spec, :description))
        |> maybe_put(:verbs, Map.get(spec, :verbs))
        |> maybe_put(:parent_id, template_id)

      events =
        [{:create_object, attrs}] ++
          place_events(id, Map.get(spec, :place_in)) ++
          property_events(id, properties) ++
          [{:set_property, id, "source", to_string(source)}]

      {:ok, %{id: id, events: events}}
    end
  end

  def plan(spec, _opts), do: {:error, {:invalid_spec, spec}}

  ## Create

  @doc """
  Plan a spec and apply it in one transaction. Returns the created object.

  Impure convenience for callers outside the dispatcher pipeline — seeds,
  sessions, tests. Inside a verb, use `plan/1` and return the events.
  """
  @spec create(spec()) :: {:ok, ObjSchema.t()} | {:error, term()}
  def create(spec), do: create(spec, [])

  @doc false
  @spec create(spec(), keyword()) :: {:ok, ObjSchema.t()} | {:error, term()}
  def create(spec, opts) do
    with {:ok, plan} <- plan(spec, opts),
         {:ok, [object]} <- materialise([plan]) do
      {:ok, object}
    end
  end

  @doc "Like `create/1`, but raises on error."
  @spec create!(spec()) :: ObjSchema.t()
  def create!(spec), do: create!(spec, [])

  @doc false
  @spec create!(spec(), keyword()) :: ObjSchema.t()
  def create!(spec, opts) do
    case create(spec, opts) do
      {:ok, object} -> object
      {:error, reason} -> raise ArgumentError, "genesis failed: #{inspect(reason)}"
    end
  end

  @doc """
  Create many objects in a single all-or-nothing transaction.

  For scenes and faction rosters. Every spec is planned first, so a bad spec
  fails the batch before anything is written.

  Specs cannot reference *each other's* pre-generated ids — each is planned
  independently. Build a parent with `create/1` first and pass its id as
  `:place_in` or `:template`.
  """
  @spec create_many([spec()]) :: {:ok, [ObjSchema.t()]} | {:error, term()}
  def create_many(specs) when is_list(specs) do
    specs
    |> Enum.reduce_while({:ok, []}, fn spec, {:ok, acc} ->
      case plan(spec) do
        {:ok, plan} -> {:cont, {:ok, [plan | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      {:ok, reversed} -> reversed |> Enum.reverse() |> materialise()
    end
  end

  defp materialise(plans) do
    multi =
      Enum.reduce(plans, Multi.new(), fn plan, acc ->
        Dispatcher.apply_to_multi(acc, plan.events)
      end)

    case Repo.transaction(multi) do
      {:ok, _changes} ->
        {:ok, Enum.map(plans, fn plan -> Object.get!(plan.id) end)}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  ## Readable helpers
  #
  # World content is the artefact humans maintain, and it will outgrow engine
  # code. These exist so a seed file reads like world-building rather than
  # configuration. Each fixes the type, which is why passing an abstract
  # template to one of them is fine — nothing is being inferred.

  @doc "Create a room. Derives from `Generic Room` unless told otherwise."
  @spec room!(String.t(), keyword()) :: ObjSchema.t()
  def room!(name, opts \\ []) do
    opts |> to_spec(name) |> Map.put_new(:template, :room) |> Map.put(:type, :room) |> create!()
  end

  @doc """
  Create an item inside `container`. Derives from `Generic Thing` unless told
  otherwise — pass `template: :weapon` or `template: :scrap` for the ones that
  should inherit those verbs.
  """
  @spec item!(ObjSchema.t() | id() | nil, String.t(), keyword()) :: ObjSchema.t()
  def item!(container, name, opts \\ []) do
    opts
    |> to_spec(name)
    |> Map.put_new(:template, :thing)
    |> Map.put(:type, :item)
    |> place(container)
    |> create!()
  end

  @doc "Create an NPC inside `container`. Derives from `Generic NPC` unless told otherwise."
  @spec npc!(ObjSchema.t() | id() | nil, String.t(), keyword()) :: ObjSchema.t()
  def npc!(container, name, opts \\ []) do
    opts
    |> to_spec(name)
    |> Map.put_new(:template, :npc)
    |> Map.put(:type, :npc)
    |> place(container)
    |> create!()
  end

  @doc """
  Create a player. Derives from `Generic PC` unless told otherwise.

  Together with `player!/2`, the only way to make a `:player`. Deliberately
  absent from the event layer — see the module doc.
  """
  @spec player(String.t(), keyword()) :: {:ok, ObjSchema.t()} | {:error, term()}
  def player(name, opts \\ []) do
    opts |> player_spec(name) |> create(allow_player: true)
  end

  @doc "Like `player/2`, but raises on error."
  @spec player!(String.t(), keyword()) :: ObjSchema.t()
  def player!(name, opts \\ []) do
    opts |> player_spec(name) |> create!(allow_player: true)
  end

  defp player_spec(opts, name) do
    opts
    |> to_spec(name)
    |> Map.put_new(:template, :pc)
    |> Map.put(:type, :player)
  end

  ## Spec assembly

  defp to_spec(opts, name) when is_list(opts) do
    opts |> Map.new() |> Map.put(:name, name)
  end

  defp to_spec(opts, name) when is_map(opts), do: Map.put(opts, :name, name)

  defp place(spec, nil), do: spec
  defp place(spec, %ObjSchema{id: id}), do: Map.put(spec, :place_in, id)
  defp place(spec, id) when is_binary(id), do: Map.put(spec, :place_in, id)

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  ## Resolution

  defp fetch_name(spec) do
    case Map.get(spec, :name) do
      name when is_binary(name) ->
        trimmed = String.trim(name)
        if trimmed == "", do: {:error, :blank_name}, else: {:ok, trimmed}

      nil ->
        {:error, :missing_name}

      other ->
        {:error, {:invalid_name, other}}
    end
  end

  defp resolve_template(nil), do: {:ok, nil}
  defp resolve_template(%ObjSchema{id: id}), do: {:ok, id}

  defp resolve_template(ref) when is_atom(ref) do
    case Map.fetch(@generics, ref) do
      :error ->
        {:error, {:unknown_generic, ref}}

      {:ok, name} ->
        case find_generic(name) do
          nil -> {:error, {:generic_not_seeded, ref}}
          generic -> {:ok, generic.id}
        end
    end
  end

  defp resolve_template(ref) when is_binary(ref) do
    case Object.get(ref) do
      nil -> {:error, {:generic_not_found, ref}}
      object -> {:ok, object.id}
    end
  end

  defp resolve_template(other), do: {:error, {:invalid_template, other}}

  defp find_generic(name) do
    from(o in ObjSchema,
      where: o.name == ^name and o.type == :generic and is_nil(o.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end

  defp resolve_type(spec, template_id) do
    case Map.get(spec, :type) do
      nil ->
        derive_type(template_id)

      type when type in @object_types ->
        {:ok, type}

      other ->
        {:error, {:unknown_type, other}}
    end
  end

  # No template means nothing to derive from — the caller has to say.
  defp derive_type(nil), do: {:error, :missing_type}

  defp derive_type(template_id) do
    case Object.get_property(template_id, "instance_type") do
      nil ->
        {:error, :abstract_generic}

      raw ->
        case Map.fetch(@instance_types, to_string(raw)) do
          {:ok, type} -> {:ok, type}
          :error -> {:error, {:unknown_instance_type, raw}}
        end
    end
  end

  defp permit_type(:player, opts) do
    if Keyword.get(opts, :allow_player, false) do
      :ok
    else
      {:error, :player_creation_forbidden}
    end
  end

  defp permit_type(_type, _opts), do: :ok

  defp resolve_source(spec) do
    case Map.get(spec, :source, :hand) do
      source when source in @sources -> {:ok, source}
      other -> {:error, {:unknown_source, other}}
    end
  end

  defp validate_place_in(nil), do: :ok
  defp validate_place_in(id) when is_binary(id), do: :ok
  defp validate_place_in(other), do: {:error, {:invalid_place_in, other}}

  # Sorted so a plan's event list is deterministic and therefore assertable.
  defp normalize_properties(properties) when is_map(properties) do
    normalized =
      properties
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Enum.sort_by(&elem(&1, 0))

    case Enum.find(normalized, fn {key, _} -> key == "" end) do
      nil -> {:ok, normalized}
      _ -> {:error, :blank_property_key}
    end
  end

  defp normalize_properties(other), do: {:error, {:invalid_properties, other}}

  ## Event assembly

  defp place_events(_id, nil), do: []
  defp place_events(id, container_id), do: [{:relate, container_id, id, :contains}]

  defp property_events(id, properties) do
    Enum.map(properties, fn {key, value} -> {:set_property, id, key, value} end)
  end
end
