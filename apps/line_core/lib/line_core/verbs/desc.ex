defmodule LineCore.Verbs.Desc do
  @moduledoc """
  `desc me as <description>` / `describe me as <description>` — set the actor's
  own description (what other players see via `look <player>`).

  The description is stored as a property `custom_description`. The Renderer
  reads this property first and falls back to the schema's `description`
  column. This avoids needing a new dispatcher event type.

  `desc <object> as <description>` — Phase 1+ (requires ownership tracking),
  not implemented in 0.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Object, Resolver}

  @impl true
  def execute(_ctx, []), do: {:error, :desc_what}

  def execute(ctx, [description]) when is_binary(description) do
    trimmed = String.trim(description)

    if trimmed == "" do
      {:error, :empty_description}
    else
      {:ok,
       [
         {:set_property, ctx.actor.id, "custom_description", trimmed},
         {:notify_actor, "You set your description."}
       ]}
    end
  end

  def execute(ctx, [object_name, description]) do
    object = Resolver.visible(ctx, object_name)
    trimmed = String.trim(description)

    cond do
      is_nil(object) ->
        {:error, :not_found}

      not Object.owns?(ctx.actor.id, object.id) ->
        {:error, :permission_denied}

      trimmed == "" ->
        {:error, :empty_description}

      true ->
        {:ok,
         [
           {:set_property, object.id, "custom_description", trimmed},
           {:notify_actor, "You set #{object.name}'s description."}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
