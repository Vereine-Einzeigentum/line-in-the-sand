defmodule LineCore.WorldCommand do
  @moduledoc """
  Parser output for an in-world MOO command.

  The parser preserves strings; object resolution happens later against the
  actor's current world state.
  """

  defstruct [:verb, :argstr, :dobjstr, :prepstr, :iobjstr, :modifier, :raw]

  @type t :: %__MODULE__{
          verb: String.t(),
          argstr: String.t() | nil,
          dobjstr: String.t() | nil,
          prepstr: String.t() | nil,
          iobjstr: String.t() | nil,
          modifier: String.t() | nil,
          raw: String.t()
        }
end
