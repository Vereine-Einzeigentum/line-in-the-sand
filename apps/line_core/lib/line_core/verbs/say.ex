defmodule LineCore.Verbs.Say do
  @moduledoc """
  `say <message>` or `"<message>` — speak aloud to everyone in the current
  room.

  Broadcasts to the room. The actor sees a confirmation; everyone else in
  the room hears the speech with the actor's name.
  """

  @behaviour LineCore.Verb

  @impl true
  def execute(_ctx, []), do: {:error, :say_what}

  def execute(ctx, [message]) when is_binary(message) do
    trimmed = String.trim(message)

    if trimmed == "" do
      {:error, :say_what}
    else
      {:ok,
       [
         {:notify_actor, "You say, \"#{trimmed}\""},
         {:notify_room, "#{ctx.actor.name} says, \"#{trimmed}\"", except: [ctx.actor.id]}
       ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
