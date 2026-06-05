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

  def execute(_ctx, [_object, _description]) do
    {:error, :owned_object_desc_not_yet_implemented}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
