defmodule LineWorld.Logic do
  @moduledoc """
  Engine-neutral logic boundary: facts in, inert consequences out.
  Adapters cannot supply event lists. This deterministic implementation proposes
  materialization; world policy separately decides whether and when it happens.
  """
  alias LineCore.{Consequence, ItemSpec}

  @callback derive(ItemSpec.t(), map()) :: {:ok, [Consequence.t()]} | {:error, term()}

  def derive(spec, provenance) do
    consequence = %Consequence{kind: :materialize_item, spec: spec, provenance: provenance}

    with :ok <- Consequence.validate(consequence) do
      {:ok, [consequence]}
    end
  end
end
