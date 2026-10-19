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
          {:ok, t()}
          | {:error, {:asserted_conflict | :semantic_conflict, key(), value(), value()}}
  def put_derived(%__MODULE__{} = spec, key, value) do
    put_semantic(spec, :derived, key, value)
  end

  @doc """
  Adds a fact supplied by a constraint/solver pass.

  A solved value may fill an unresolved field, but it cannot silently replace
  a contradictory asserted value.
  """
  @spec put_solved(t(), key(), value()) ::
          {:ok, t()}
          | {:error, {:asserted_conflict | :semantic_conflict, key(), value(), value()}}
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

  @doc "Validate the portable, bounded representation accepted at external boundaries."
  def validate(%__MODULE__{} = spec) do
    tiers = [spec.asserted, spec.derived, spec.solved]

    cond do
      not is_list(spec.lineage) or spec.lineage == [] or
          not Enum.all?(spec.lineage, &field?/1) ->
        {:error, :invalid_lineage}

      not Enum.all?(tiers, &json?/1) or not Enum.all?(tiers, &is_map/1) ->
        {:error, :invalid_facts}

      not is_struct(spec.unknown, MapSet) or not Enum.all?(spec.unknown, &field?/1) ->
        {:error, :invalid_unknown_fields}

      conflicting?(tiers) ->
        {:error, :conflicting_facts}

      Enum.any?(tiers, fn tier -> Enum.any?(Map.keys(tier), &MapSet.member?(spec.unknown, &1)) end) ->
        {:error, :resolved_field_marked_unknown}

      :erlang.external_size(spec) > 65_536 ->
        {:error, :spec_too_large}

      true ->
        :ok
    end
  end

  def validate(_), do: {:error, :invalid_spec}

  @doc "Read a fact without flattening or changing its provenance tiers."
  def get(%__MODULE__{} = spec, key, default \\ nil) do
    Enum.reduce_while([spec.asserted, spec.derived, spec.solved], default, fn tier, _ ->
      case Map.fetch(tier, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, default}
      end
    end)
  end

  @doc "Lossless JSON-compatible storage; semantic tiers remain separate."
  def to_map(%__MODULE__{} = spec) do
    %{
      "lineage" => spec.lineage,
      "asserted" => spec.asserted,
      "unknown" => Enum.sort(spec.unknown),
      "derived" => spec.derived,
      "solved" => spec.solved
    }
  end

  @doc "Restore a stored specification without collapsing its semantic tiers."
  def from_map(
        %{
          "lineage" => lineage,
          "asserted" => asserted,
          "unknown" => unknown,
          "derived" => derived,
          "solved" => solved
        } = data
      )
      when map_size(data) == 5 and is_list(unknown) do
    spec = %__MODULE__{
      lineage: lineage,
      asserted: asserted,
      unknown: MapSet.new(unknown),
      derived: derived,
      solved: solved
    }

    with :ok <- validate(spec), do: {:ok, spec}
  end

  def from_map(_), do: {:error, :invalid_spec}

  defp field?(value), do: is_binary(value) and byte_size(value) in 1..120

  defp json?(value, depth \\ 0)
  defp json?(_, depth) when depth > 16, do: false

  defp json?(value, _)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: true

  defp json?(value, depth) when is_list(value), do: Enum.all?(value, &json?(&1, depth + 1))

  defp json?(value, depth) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, item} -> field?(key) and json?(item, depth + 1) end)
  end

  defp json?(_, _), do: false

  defp conflicting?(tiers) do
    tiers
    |> Enum.flat_map(&Map.to_list/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.any?(fn {_key, values} -> length(Enum.uniq(values)) > 1 end)
  end

  defp put_semantic(%__MODULE__{} = spec, tier, key, value)
       when tier in [:derived, :solved] do
    case Map.fetch(spec.asserted, key) do
      {:ok, ^value} ->
        {:ok, spec}

      {:ok, asserted_value} ->
        {:error, {:asserted_conflict, key, asserted_value, value}}

      :error ->
        existing = Enum.find([spec.derived, spec.solved], &Map.has_key?(&1, key))

        if existing && Map.fetch!(existing, key) !== value do
          {:error, {:semantic_conflict, key, Map.fetch!(existing, key), value}}
        else
          updated =
            spec
            |> Map.update!(tier, &Map.put(&1, key, value))
            |> Map.update!(:unknown, &MapSet.delete(&1, key))

          {:ok, updated}
        end
    end
  end

  defp map_facts(tag, map) do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> {tag, key, value} end)
  end

  defp unknown_facts(unknown) do
    unknown
    |> Enum.sort()
    |> Enum.map(&{:unknown, &1})
  end
end
