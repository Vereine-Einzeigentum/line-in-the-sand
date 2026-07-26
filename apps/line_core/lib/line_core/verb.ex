defmodule LineCore.Verb do
  @moduledoc """
  Behaviour for mechanical verbs.

  A verb is a pure function from (context, args) to a list of events.
  Pure means: no side effects, no DB writes, no broadcasts. The verb
  decides what *should* happen; the dispatcher applies the events
  transactionally and broadcasts to the room.

  This separation makes verbs trivially testable (call execute/2, inspect
  the event list) and makes side effects uniform (every verb's events go
  through the same Multi-backed applier).

  ## Example

      defmodule LineCore.Verbs.Get do
        @behaviour LineCore.Verb

        @impl true
        def execute(ctx, [item_name]) do
          case Room.find_item(ctx.room, item_name) do
            {:ok, item} ->
              if can_carry?(ctx.actor, item) do
                {:ok, [
                  {:move, item.id, ctx.actor.id, :contains},
                  {:notify_actor, "You pick up the \#{item.name}."},
                  {:notify_room, "\#{ctx.actor.name} picks up the \#{item.name}.",
                    except: [ctx.actor.id]}
                ]}
              else
                {:error, :too_heavy}
              end

            :error ->
              {:error, :not_found}
          end
        end
      end
  """

  alias LineCore.Verb.Context

  @typedoc """
  Events that a verb can produce. Applied by the dispatcher in order.
  """
  @type event ::
          {:set_property, object_id :: binary(), key :: String.t(), value :: term()}
          | {:delete_property, object_id :: binary(), key :: String.t()}
          | {:move, object_id :: binary(), to_container_id :: binary(), rel_type :: atom()}
          | {:force_move, object_id :: binary(), to_container_id :: binary(), rel_type :: atom()}
          | {:create_object, attrs :: map()}
          | {:delete_object, object_id :: binary()}
          | {:notify_actor, message :: String.t()}
          | {:notify_room, message :: String.t(), opts :: keyword()}
          | {:notify_object, object_id :: binary(), message :: String.t()}
          | {:broadcast_channel, channel :: atom(), message :: String.t()}

  @type result :: {:ok, [event()]} | {:error, atom() | String.t()}

  @doc """
  Execute the verb with the given context and parsed arguments.

  Must be pure — no DB writes, no broadcasts, no side effects. Return events
  describing what should happen; the dispatcher does the rest.
  """
  @callback execute(context :: Context.t(), args :: list()) :: result()

  @doc """
  The minimum stat/skill requirements to attempt this verb.

  Returns a list of `{stat_or_skill, minimum_value}` pairs. The dispatcher
  checks these before calling execute/2 and rejects with `:insufficient_skill`
  if any are unmet.

  Default: no requirements. Override for verbs gated by skills.
  """
  @callback requirements() :: [{atom(), integer()}]

  @optional_callbacks [requirements: 0]
end
