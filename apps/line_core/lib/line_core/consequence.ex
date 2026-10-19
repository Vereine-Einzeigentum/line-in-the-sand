defmodule LineCore.Consequence do
  @moduledoc "An inert semantic proposal. It carries evidence, never executable events."
  alias LineCore.ItemSpec

  @enforce_keys [:kind, :spec, :provenance]
  defstruct [:kind, :spec, :provenance]

  @type t :: %__MODULE__{kind: :materialize_item, spec: ItemSpec.t(), provenance: map()}

  def validate(%__MODULE__{
        kind: :materialize_item,
        spec: spec,
        provenance: provenance
      }) do
    with :ok <- validate_provenance(provenance), do: ItemSpec.validate(spec)
  end

  def validate(_), do: {:error, :invalid_consequence}

  def validate_provenance(%{"source" => source, "reference" => reference} = provenance)
      when is_binary(source) and byte_size(source) in 1..120 and
             is_binary(reference) and byte_size(reference) in 1..512 and map_size(provenance) == 2 do
    :ok
  end

  def validate_provenance(_), do: {:error, :invalid_provenance}
end
