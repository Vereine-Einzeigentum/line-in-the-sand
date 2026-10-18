defmodule LineCore.ItemSpec do
  @moduledoc """
  Pure semantic specification for generated items.

  A spec deliberately separates what generation asserted from what LINE later
  derives or solves. This allows an item synthesizer to be absurd without giving
  it authority to invent mechanical consequences or silently rewriting its own
  claims.

  `lineage` is ordered and open-ended. `asserted` values are immutable inputs.
  `unknown` names fields that were intentionally left unresolved. `derived` and
  `solved` are independent semantic tiers populated after generation.
  """

  @enforce_keys [:lineage, :asserted, :unknown]
  defstruct lineage: [],
            asserted: %{},
            unknown: MapSet.new(),
            derived: %{},
            solved: %{}

  @type key :: term()
  @type value :: term()

  @type t :: %__MODULE__{
          lineage: [term()],
          asserted: %{optional(key()) => value()},
          unknown: MapSet.t(key()),
          derived: %{optional(key()) => value()},
          solved: %{optional(key()) => value()}
        }

  @doc """
  Builds a partial generated-item specification.

  Fields named in both `asserted` and `unknown` are treated as asserted: an
  explicit generated value is stronger than an unresolved-field marker.
  """
  @spec new([term()], map(), keyword()) :: t()
  def new(lineage, asserted \\ %{}, opts \\ [])
      when is_list(lineage) and is_map(asserted) and is_list(opts) do
    asserted_keys = Map.keys(asserted) |> MapSet.new()

    unknown =
      opts
      |> Keyword.get(:unknown, [])
      |> MapSet.new()
      |> MapSet.difference(asserted_keys)

    %__MODULE__{
      lineage: lineage,
      asserted: asserted,
      unknown: unknown
    }
  end

  @doc """
  Adds a fact derived from existing semantics.

  A derived value may fill an unresolved field, but it cannot silently replace
  a contradictory asserted value.
  """
  @spec put_derived(t(), key(), value()) ::
          {:ok, t()} | {:error, {:asserted_conflict, key(), value(), value()}}
  def put_derived(%__MODULE__{} = spec, key, value) do
    put_semantic(spec, :derived, key, value)
  end

  @doc """
  Adds a fact supplied by a constraint/solver pass.

  A solved value may fill an unresolved field, but it cannot silently replace
  a contradictory asserted value.
  """
  @spec put_solved(t(), key(), value()) ::
          {:ok, t()} | {:error, {:asserted_conflict, key(), value(), value()}}
  def put_solved(%__MODULE__{} = spec, key, value) do
    put_semantic(spec, :solved, key, value)
  end

  @doc """
  Exports the specification as deterministic tagged facts.

  The tags preserve semantic tier so future Prolog/Datalog/CLP adapters do not
  have to infer provenance from a flattened property map.
  """
  @spec facts(t()) :: [tuple()]
  def facts(%__MODULE__{} = spec) do
    lineage =
      spec.lineage
      |> Enum.with_index()
      |> Enum.map(fn {node, index} -> {:lineage, index, node} end)

    lineage ++
      map_facts(:asserted, spec.asserted) ++
      unknown_facts(spec.unknown) ++
      map_facts(:derived, spec.derived) ++
      map_facts(:solved, spec.solved)
  end

  defp put_semantic(%__MODULE__{} = spec, tier, key, value)
       when tier in [:derived, :solved] do
    case Map.fetch(spec.asserted, key) do
      {:ok, ^value} ->
        {:ok, spec}

      {:ok, asserted_value} ->
        {:error, {:asserted_conflict, key, asserted_value, value}}

      :error ->
        updated =
          spec
          |> Map.update!(tier, &Map.put(&1, key, value))
          |> Map.update!(:unknown, &MapSet.delete(&1, key))

        {:ok, updated}
    end
  end

  defp map_facts(tag, map) do
    map
    |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key) end)
    |> Enum.map(fn {key, value} -> {tag, key, value} end)
  end

  defp unknown_facts(unknown) do
    unknown
    |> Enum.sort_by(&:erlang.term_to_binary/1)
    |> Enum.map(&{:unknown, &1})
  end
end
