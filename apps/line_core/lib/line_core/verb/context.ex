defmodule LineCore.Verb.Context do
  @moduledoc """
  Read-only context passed to every verb execution.

  Built by the dispatcher from the actor's current state and the room they're
  in. Verbs receive this context and produce events; the context itself is
  never mutated by a verb.

  ## Fields

  - `:actor` — the Object performing the verb (player or NPC)
  - `:room` — the Object representing the room the actor is in
  - `:room_contents` — the list of Objects currently in the room
                       (includes other players, NPCs, items, exits)
  - `:command` — the original raw command string (for logging/debugging)
  - `:now` — DateTime of dispatch, so verbs that depend on time
              (cooldowns, day/night) use a consistent reference
  """

  alias LineCore.Schemas.Object

  @type t :: %__MODULE__{
          actor: Object.t(),
          room: Object.t(),
          room_contents: [Object.t()],
          command: String.t(),
          now: DateTime.t()
        }

  defstruct [:actor, :room, :room_contents, :command, :now]
end
