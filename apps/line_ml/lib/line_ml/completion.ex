defmodule LineMl.Completion do
  @moduledoc "Validated completion and its source, ready for the logic boundary."
  @enforce_keys [:spec, :provenance]
  defstruct [:spec, :provenance]
end
