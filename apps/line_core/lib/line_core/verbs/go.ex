defmodule LineCore.Verbs.Go do
  @moduledoc """
  `go <direction>` or bare `<direction>` — move through an exit.

  Resolves the direction against the room's exit relationships, moves the
  actor to the destination room, broadcasts departure to the old room and
  arrival to the new room. Renders the destination room automatically.
  """

  @behaviour LineCore.Verb

  alias LineCore.Object
  alias LineCore.Verbs.Look

  @impl true
  def execute(_ctx, []) do
    {:error, :no_direction}
  end

  def execute(ctx, [direction]) do
    case Object.resolve_exit(ctx.room.id, direction) do
      nil ->
        {:error, :no_such_exit}

      dest_room ->
        with :ok <- traversable_exit(ctx.room.id, direction) do
          canonical = Object.canonicalize_direction(direction)
          actor_name = ctx.actor.name
          room_view = Look.room_description(dest_room, ctx.actor.id)

          {:ok,
           [
             {:notify_room, "#{actor_name} leaves #{canonical}.", except: [ctx.actor.id]},
             {:move, ctx.actor.id, dest_room.id, :contains},
             {:notify_actor, "You walk #{canonical}.\n\n" <> room_view}
           ]}
        end
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp traversable_exit(room_id, direction) do
    case Object.resolve_exit_object(room_id, direction) do
      nil ->
        :ok

      exit ->
        cond do
          Object.get_property(exit.id, "locked", false) == true ->
            {:error, :exit_locked}

          Object.get_property(exit.id, "open", true) == false ->
            {:error, :exit_closed}

          true ->
            :ok
        end
    end
  end

end
