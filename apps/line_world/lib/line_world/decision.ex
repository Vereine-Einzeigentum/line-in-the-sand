defmodule LineWorld.Decision do
  @moduledoc "World authority's decision and the reason for it; not an executable event."
  @enforce_keys [:status, :reason, :consequence, :actor_id]
  defstruct [:status, :reason, :consequence, :actor_id, :parent_id]
end
