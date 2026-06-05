defmodule LineCore.Verbs.Go do
  @moduledoc """
  `go <direction>` or bare `<direction>` — move through an exit.

  Resolves the direction against the room's exit relationships, moves the
  actor to the destination room, broadcasts departure to the old room and
  arrival to the new room.
  """

  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(_ctx, []) do
    {:error, :no_direction}
  end

  def execute(ctx, [direction]) do
    case Object.resolve_exit(ctx.room.id, direction) do
      nil ->
        {:error, :no_such_exit}

      dest_room ->
        canonical = Object.canonicalize_direction(direction)
        actor_name = ctx.actor.name

        {:ok,
         [
           # Broadcast departure to old room (everyone except the mover)
           {:notify_room, "#{actor_name} leaves #{canonical}.", except: [ctx.actor.id]},

           # Move the actor
           {:move, ctx.actor.id, dest_room.id, :contains},

           # Notify the actor — they'll see the new room via a look downstream
           # (post-move hook will fire a Look. For now, tell them where they are.)
           {:notify_actor, "You walk #{canonical}."}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
