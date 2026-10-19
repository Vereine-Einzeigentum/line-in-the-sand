defmodule LineMl.Request do
  @moduledoc "A bounded request to complete an existing item specification."
  alias LineCore.ItemSpec
  @enforce_keys [:id, :spec, :instruction]
  defstruct [:id, :spec, :instruction]
  @type t :: %__MODULE__{id: String.t(), spec: ItemSpec.t(), instruction: String.t()}

  def validate(%__MODULE__{id: id, spec: spec, instruction: instruction})
      when is_binary(id) and byte_size(id) in 1..120 and
             is_binary(instruction) and byte_size(instruction) in 1..4096,
      do: ItemSpec.validate(spec)

  def validate(_), do: {:error, :invalid_request}
end
