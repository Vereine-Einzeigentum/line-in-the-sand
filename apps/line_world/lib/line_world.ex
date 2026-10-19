defmodule LineWorld do
  @moduledoc """
  Enactment authority for semantic consequences. No logic adapter writes world state.
  `enact/2` re-evaluates policy inside the dispatcher's transaction; callers
  cannot submit an old approval or executable events. Deferred proposals must
  be resubmitted explicitly.
  """
  alias LineCore.{Archetypes, Consequence, Dispatcher, ItemSpec, Object}
  alias LineWorld.Decision

  def decide(consequence, ctx) do
    base = %Decision{
      status: :reject,
      reason: :invalid_consequence,
      consequence: consequence,
      actor_id: ctx.actor.id
    }

    with :ok <- Consequence.validate(consequence),
         :ok <- authorized(ctx.actor.id) do
      parent = Archetypes.get(:item)

      cond do
        MapSet.size(consequence.spec.unknown) > 0 ->
          %{
            base
            | status: :defer,
              reason: {:unresolved_fields, Enum.sort(consequence.spec.unknown)}
          }

        display_fields(consequence.spec) != :ok ->
          %{base | reason: :invalid_item_display}

        is_nil(parent) ->
          %{base | status: :defer, reason: :item_archetype_unavailable}

        true ->
          %{base | status: :enact, reason: :prerequisites_met, parent_id: parent.id}
      end
    else
      {:error, reason} -> %{base | reason: reason}
    end
  end

  def enact(actor_id, consequence) do
    Dispatcher.dispatch_transactional(
      actor_id,
      LineWorld.Enactment,
      [consequence],
      "semantic enactment"
    )
  end

  defp authorized(actor_id) do
    if Object.get_property(actor_id, "can_materialize_items", false) == true or
         Object.get_property(actor_id, "admin", false) == true,
       do: :ok,
       else: {:error, :not_authorized}
  end

  defp display_fields(spec) do
    name = ItemSpec.get(spec, "name")
    description = ItemSpec.get(spec, "description", "")

    if is_binary(name) and String.length(name) in 1..120 and String.trim(name) != "" and
         is_binary(description) and byte_size(description) <= 4096,
       do: :ok,
       else: {:error, :invalid_item_display}
  end
end
