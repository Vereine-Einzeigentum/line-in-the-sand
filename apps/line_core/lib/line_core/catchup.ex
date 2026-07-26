defmodule LineCore.Catchup do
  @moduledoc """
  The online/offline transition, and what the world owes you when you return.

  Persistent bodies create a problem the old ephemeral ones did not have. Death
  emits `{:notify_object, victim_id, "Everything goes dark..."}`, which
  publishes to a PubSub topic. If nobody is subscribed — because nobody is
  driving that body — the message evaporates. The player logs in at the
  safehouse, poorer, with an empty inventory, and no account of what happened.

  The journal already holds the answer. Every dispatch writes a
  `journal_entries` row containing the full event list, `notify_object` events
  included, so this is a catch-up *read* rather than new bookkeeping.

  ## Ownership

  This module owns two properties:

  - `active_state` — set while offline, cleared on return. `LineCore.Renderer`
    renders it on examine and `LineCore.Verbs.Look` appends it in room
    contents, so an unattended body reads as unattended.
  - `last_seen_at` — an ISO 8601 timestamp, the low-water mark `digest/1`
    replays from.
  """

  import Ecto.Query

  alias LineCore.{Object, Repo}
  alias LineCore.Schemas.JournalEntry

  @offline_state "Unattended. Breathing, but nobody home."

  # A returning player wants to know what happened, not to read a transcript of
  # a fortnight. Older entries stay in the journal; they are simply not replayed.
  @max_entries 50

  @doc "The phrase an unattended body is described with."
  def offline_state, do: @offline_state

  ## Transitions

  @doc """
  Mark a body as being driven again: clears `active_state` so it stops
  rendering as unattended.

  Deletes rather than blanks the property, so anything the prototype chain has
  to say about `active_state` becomes visible again instead of being shadowed
  by a null.
  """
  def mark_online(player_id) do
    Object.delete_property(player_id, "active_state")
    :ok
  end

  @doc """
  Mark a body as unattended, stamping the moment it was left.

  Returns `:ok` even if the object is gone — a caller tearing down a connection
  has nothing useful to do with a failure here.
  """
  def mark_offline(player_id, now \\ DateTime.utc_now()) do
    case Object.get(player_id) do
      nil ->
        :ok

      _player ->
        Object.set_property(player_id, "active_state", @offline_state)
        Object.set_property(player_id, "last_seen_at", DateTime.to_iso8601(now))
        :ok
    end
  end

  @doc "When this body was last left unattended, or nil if it never has been."
  def last_seen_at(player_id) do
    with raw when is_binary(raw) <- Object.get_property(player_id, "last_seen_at"),
         {:ok, datetime, _offset} <- DateTime.from_iso8601(raw) do
      datetime
    else
      _ -> nil
    end
  end

  ## Catch-up

  @doc """
  A "while you were away" digest for a returning player, as a list of lines.

  Empty when the player has never been away or nothing addressed to them
  happened while they were. The caller decides how to deliver it.
  """
  def digest(player_id) do
    case last_seen_at(player_id) do
      nil ->
        []

      since ->
        case missed_messages(player_id, since) do
          [] -> []
          messages -> ["While you were away:" | Enum.map(messages, &("  " <> &1))]
        end
    end
  end

  @doc """
  Messages addressed to this player by dispatches recorded after `since`.

  Reads `notify_object` events naming the player out of the journal — exactly
  the messages that were published to an actor topic with no subscriber.
  """
  def missed_messages(player_id, %DateTime{} = since, limit \\ @max_entries) do
    from(j in JournalEntry,
      where: j.inserted_at > ^since,
      where: fragment("(? -> 'v') @> ?::text::jsonb", j.events, ^references(player_id)),
      order_by: [asc: j.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.flat_map(&addressed_to(&1, player_id))
  end

  # JSONB containment: "does the event array contain an element whose args
  # include this id". Array containment is subset-based and recursive, so this
  # matches the id in any argument position. Same fragment idiom as
  # `Object.exits/1`.
  #
  # The cast is `::text::jsonb`, not `::jsonb`, and the difference is load
  # bearing. A bare `::jsonb` makes Postgres report the parameter's type as
  # jsonb, at which point Postgrex JSON-encodes the string it is given — so an
  # already-encoded `[{"args": [...]}]` arrives as a JSON *string* rather than
  # an array, and containment silently returns false instead of erroring.
  # Going through text says plainly which side does the encoding.
  defp references(player_id), do: Jason.encode!([%{"args" => [player_id]}])

  defp addressed_to(%JournalEntry{events: %{"v" => events}}, player_id)
       when is_list(events) do
    Enum.flat_map(events, fn
      %{"type" => "notify_object", "args" => [^player_id, message]} -> [message]
      _ -> []
    end)
  end

  defp addressed_to(_entry, _player_id), do: []
end
