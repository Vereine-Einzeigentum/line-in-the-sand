defmodule LineCore.Journal do
  @moduledoc """
  Append-only gameplay journal.

  `record/6` adds one `JournalEntry` insert to the dispatcher's `Ecto.Multi`,
  so the entry commits atomically with the events it describes — the journal
  and the world can never disagree.

  Everything a future model needs is captured per dispatch:

  - `raw` — the natural-language command as typed
  - `verb` / `args` — what the parser resolved it to
  - `events` — the full event list the verb emitted (persistent and
    notification alike; notifications are world flavor a model should see)

  Event tuples are serialized to JSONB-safe maps: `{:set_property, id, "hp", 3}`
  becomes `%{"type" => "set_property", "args" => [id, "hp", 3]}`. Atoms become
  strings, keyword lists become maps, tuples become lists. `nil`/booleans pass
  through unchanged.
  """

  alias Ecto.Multi
  alias LineCore.Schemas.JournalEntry

  @doc """
  Append a journal insert to `multi` recording this dispatch.
  """
  def record(multi, context, verb_module, args, events, raw) do
    changeset =
      JournalEntry.changeset(%JournalEntry{}, %{
        actor_id: context.actor.id,
        room_id: context.room.id,
        verb: verb_name(verb_module),
        raw: raw,
        args: %{"v" => serialize(args)},
        events: %{"v" => Enum.map(events, &serialize_event/1)}
      })

    Multi.insert(multi, :journal_entry, changeset)
  end

  @doc """
  The journal name for a verb module: `LineCore.Verbs.Get` → `"get"`.
  """
  def verb_name(verb_module) do
    verb_module |> Module.split() |> List.last() |> Macro.underscore()
  end

  @doc """
  Serialize one event tuple to a `%{"type" => ..., "args" => [...]}` map.
  """
  def serialize_event(event) when is_tuple(event) do
    [type | rest] = Tuple.to_list(event)
    %{"type" => to_string(type), "args" => serialize(rest)}
  end

  @doc """
  Make an arbitrary event payload JSONB-safe.
  """
  def serialize(term)

  def serialize(term) when is_atom(term) do
    if term in [nil, true, false], do: term, else: to_string(term)
  end

  def serialize(term) when is_tuple(term), do: term |> Tuple.to_list() |> serialize()

  def serialize(term) when is_list(term) do
    if Keyword.keyword?(term) do
      Map.new(term, fn {k, v} -> {to_string(k), serialize(v)} end)
    else
      Enum.map(term, &serialize/1)
    end
  end

  def serialize(term) when is_map(term) and not is_struct(term) do
    Map.new(term, fn {k, v} -> {serialize_key(k), serialize(v)} end)
  end

  def serialize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def serialize(term), do: term

  defp serialize_key(k) when is_binary(k), do: k
  defp serialize_key(k), do: to_string(k)
end
