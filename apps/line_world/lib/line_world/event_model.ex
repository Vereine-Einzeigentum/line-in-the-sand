defmodule LineWorld.EventModel do
  @moduledoc """
  Mechanical realization of approved consequences. This is where semantic
  intent becomes an executable event graph. Unknown consequence kinds fail closed.
  Semantic lineage stays literal data; it is never interpreted as an Elixir
  module or automatically promoted into administrative or combat properties.
  """
  alias LineCore.{Consequence, EventPlan, ItemSpec}
  alias LineWorld.Decision

  def build(%Decision{status: :reject, reason: reason}), do: {:error, {:rejected, reason}}
  def build(%Decision{status: :defer, reason: reason}), do: {:error, {:deferred, reason}}

  def build(
        %Decision{status: :enact, consequence: %Consequence{kind: :materialize_item} = c} =
          decision
      ) do
    with :ok <- Consequence.validate(c),
         true <- MapSet.size(c.spec.unknown) == 0 do
      attrs = %{
        type: :item,
        name: ItemSpec.get(c.spec, "name"),
        description: ItemSpec.get(c.spec, "description", ""),
        parent_id: decision.parent_id
      }

      EventPlan.compile([
        %{id: :create, requires: [], event: {:create_object, :item, attrs}},
        %{
          id: :spec,
          requires: [:create],
          event: {:set_property, {:created, :item}, "semantic_spec", ItemSpec.to_map(c.spec)}
        },
        %{
          id: :provenance,
          requires: [:create],
          event: {:set_property, {:created, :item}, "semantic_provenance", c.provenance}
        },
        %{
          id: :contain,
          requires: [:spec, :provenance],
          event: {:relate, decision.actor_id, {:created, :item}, :contains}
        },
        %{
          id: :notice,
          requires: [:contain],
          event: {:notify_actor, "An item materializes in your inventory."}
        }
      ])
    else
      false -> {:error, :incomplete_spec}
      error -> error
    end
  end

  def build(_), do: {:error, :invalid_decision}
end
