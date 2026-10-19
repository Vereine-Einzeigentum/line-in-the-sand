defmodule LineMl.Backend do
  @moduledoc """
  Trusted, configured inference adapter. Responses contain only semantic
  additions, never replacement assertions, executable modules, or world events.
  The boundary validates every response; implementing this behaviour alone is
  not a guarantee of correctness. Adapters run with a bounded lifetime.
  """
  @callback complete(LineMl.Request.t()) ::
              {:ok, %{derived: map(), solved: map()}} | {:error, term()}
end
