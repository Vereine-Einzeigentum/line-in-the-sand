defmodule LineCore.Verbs.Emote do
  @moduledoc """
  `emote <action>` / `me <action>` / `:<action>` — perform a non-verbal action visible to the room.

  Broadcasts to the entire room (including the actor) with the format "<Name> <action>".
  """

  @behaviour LineCore.Verb

  @impl true
  def execute(_ctx, []), do: {:error, :emote_what}

  def execute(ctx, [message]) when is_binary(message) do
    trimmed = String.trim(message)

    if trimmed == "" do
      {:error, :emote_what}
    else
      {:ok,
       [
         {:notify_room, "#{ctx.actor.name} #{trimmed}"}
       ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
