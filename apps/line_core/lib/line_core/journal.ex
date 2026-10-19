defmodule LineCore.Journal do
  @moduledoc """
  Durable observations, ordered per actor under the same lock as dispatch.
  Records are not executable events or behavioral labels. Export retries reuse
  stable IDs; repeated game commands remain separate actions.
  """
  import Ecto.Query
  alias LineCore.{Repo, Object}
  alias LineCore.Journal.Entry

  @doc false
  def lock_actor(actor_id) do
    Repo.one(
      from(o in LineCore.Schemas.Object,
        where: o.id == ^actor_id and is_nil(o.deleted_at),
        lock: "FOR UPDATE"
      )
    )
  end

  @doc "Start a transport session. LOGIN means observed connection, not inferred return."
  def open_session(actor_id, source) when source in [:game_channel, :player_channel] do
    Repo.transaction(fn ->
      if is_nil(lock_actor(actor_id)), do: Repo.rollback(:actor_not_found)
      session_id = Ecto.UUID.generate()

      append_locked(actor_id, "LOGIN", "observed", %{"source" => to_string(source)},
        session_id: session_id,
        opening: true
      )

      session_id
    end)
  end

  @doc "Idempotent observed disconnect. Never infers QUIT or abandonment."
  def close_session(actor_id, session_id) when is_binary(session_id) do
    Repo.transaction(fn ->
      if is_nil(lock_actor(actor_id)), do: Repo.rollback(:actor_not_found)

      case session_tail(actor_id, session_id) do
        nil ->
          Repo.rollback(:invalid_play_session)

        %{event_type: "DISCONNECT"} ->
          :ok

        _ ->
          append_locked(actor_id, "DISCONNECT", "observed", %{}, session_id: session_id)
          :ok
      end
    end)
  end

  @doc false
  def validate_session(actor_id, opts) do
    case Keyword.get(opts, :session_id) do
      nil ->
        :ok

      id when is_binary(id) ->
        with {:ok, _} <- Ecto.UUID.cast(id),
             %Entry{event_type: type} <- session_tail(actor_id, id),
             true <- type != "DISCONNECT" do
          :ok
        else
          _ -> {:error, :invalid_play_session}
        end

      _ ->
        {:error, :invalid_play_session}
    end
  end

  @doc false
  def append_locked(actor_id, type, outcome, data, opts \\ []) do
    unless Repo.in_transaction?(), do: raise("journal writes require the actor transaction")

    previous =
      Repo.one(
        from(e in Entry, where: e.actor_id == ^actor_id, order_by: [desc: e.position], limit: 1)
      )

    session_id = Keyword.get(opts, :session_id)
    session_previous = if session_id, do: session_tail(actor_id, session_id)

    unless Keyword.get(opts, :opening, false) do
      case validate_session(actor_id, opts) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end

    now = DateTime.utc_now()

    location_id =
      case Object.container_of(actor_id) do
        nil -> nil
        room -> room.id
      end

    Repo.insert!(%Entry{
      actor_id: actor_id,
      position: if(previous, do: previous.position + 1, else: 1),
      event_type: type,
      outcome: outcome,
      occurred_at: now,
      elapsed_us: elapsed(now, previous),
      session_id: session_id,
      session_position:
        if(session_id,
          do: if(session_previous, do: session_previous.session_position + 1, else: 1)
        ),
      session_elapsed_us: elapsed(now, session_previous),
      location_id: Keyword.get(opts, :location_id, location_id),
      target_id: Keyword.get(opts, :target_id),
      data: data
    })
  end

  @doc "Read a bounded, repeatable page in one actor's committed order. Cursor is position."
  def export(actor_id, after_position \\ 0, limit \\ 1000)
      when is_integer(after_position) and after_position >= 0 and
             is_integer(limit) and limit in 1..1000 do
    Repo.all(
      from(e in Entry,
        where: e.actor_id == ^actor_id and e.position > ^after_position,
        order_by: e.position,
        limit: ^limit
      )
    )
    |> Enum.map(fn entry ->
      entry
      |> Map.from_struct()
      |> Map.delete(:__meta__)
      |> Map.update!(:occurred_at, &DateTime.to_iso8601/1)
    end)
  end

  defp session_tail(actor_id, session_id) do
    Repo.one(
      from(e in Entry,
        where: e.actor_id == ^actor_id and e.session_id == ^session_id,
        order_by: [desc: e.position],
        limit: 1
      )
    )
  end

  # Wall-clock rollback must not fabricate a positive duration.
  defp elapsed(_, nil), do: nil

  defp elapsed(now, previous) do
    delta = DateTime.diff(now, previous.occurred_at, :microsecond)
    if delta >= 0, do: delta
  end
end
