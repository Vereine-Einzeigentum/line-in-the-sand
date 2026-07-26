defmodule LineCore.Dispatcher do
  @moduledoc """
  Takes a parsed command, finds the actor and room, looks up the verb,
  calls execute/2, applies returned events transactionally, and broadcasts
  notifications via PubSub.

  This is the only place side effects from verbs happen. Verbs are pure;
  everything that touches the DB or the network goes through here.

  Every successful dispatch is also recorded in the append-only journal
  (`LineCore.Journal`) inside the same transaction, capturing the raw command,
  resolved verb/args, and the full event list.

  ## Event types

  Persistent (applied via Ecto.Multi):
  - `{:set_property, object_id, key, value}`
  - `{:delete_property, object_id, key}`
  - `{:move, object_id, container_id, rel_type}` — moves an object, deleting prior relationships *of the same type*
  - `{:relate, from_id, to_id, rel_type}` — adds a relationship
  - `{:unrelate, from_id, to_id, rel_type}` — removes a relationship
  - `{:create_object, attrs}`
  - `{:delete_object, object_id}` — soft delete

  Notification (broadcast via PubSub, no DB impact):
  - `{:notify_actor, msg}`
  - `{:notify_room, msg}` / `{:notify_room, msg, opts}` (opts: `except: [...]`)
  - `{:notify_object, object_id, msg}` — direct message to any object via actor topic
  - `{:broadcast_channel, channel, msg}`
  """

  alias LineCore.{Object, Repo}
  alias LineCore.Schemas.{Object, Property, Relationship}
  alias LineCore.Verb.Context
  alias Ecto.Multi

  def dispatch(actor_id, verb_module, args, raw_command) do
    with {:ok, actor} <- fetch_actor(actor_id),
         {:ok, room} <- fetch_room(actor),
         contents = LineCore.Object.contents(room.id),
         :ok <- check_requirements(actor, verb_module),
         context = build_context(actor, room, contents, raw_command),
         {:ok, events} <- verb_module.execute(context, args),
         {:ok, _result} <- apply_events(events, context, verb_module, args, raw_command) do
      broadcast_events(events, context)
      :ok
    end
  end

  defp fetch_actor(actor_id) do
    case LineCore.Object.get(actor_id) do
      nil -> {:error, :actor_not_found}
      actor -> {:ok, actor}
    end
  end

  defp fetch_room(actor) do
    case LineCore.Object.container_of(actor.id) do
      nil -> {:error, :actor_not_in_room}
      room -> {:ok, room}
    end
  end

  defp build_context(actor, room, contents, raw_command) do
    %Context{
      actor: actor,
      room: room,
      room_contents: contents,
      command: raw_command,
      now: DateTime.utc_now()
    }
  end

  defp check_requirements(actor, verb_module) do
    if function_exported?(verb_module, :requirements, 0) do
      reqs = verb_module.requirements()

      unmet =
        Enum.filter(reqs, fn {key, min} ->
          (LineCore.Object.get_property(actor.id, to_string(key)) || 0) < min
        end)

      case unmet do
        [] -> :ok
        _ -> {:error, {:insufficient_skill, unmet}}
      end
    else
      :ok
    end
  end

  defp apply_events(events, context, verb_module, args, raw_command) do
    events
    |> Enum.reduce(Multi.new(), fn event, multi ->
      apply_event_to_multi(multi, event, context)
    end)
    |> LineCore.Journal.record(context, verb_module, args, events, raw_command)
    |> Repo.transaction()
  end

  defp apply_event_to_multi(multi, {:set_property, object_id, key, value}, _ctx) do
    stored = if is_map(value), do: value, else: %{"v" => value}

    Multi.insert(
      multi,
      {:set_property, object_id, key, make_ref()},
      %Property{}
      |> Property.changeset(%{object_id: object_id, key: key, value: stored}),
      on_conflict: [set: [value: stored, updated_at: DateTime.utc_now()]],
      conflict_target: [:object_id, :key]
    )
  end

  defp apply_event_to_multi(multi, {:delete_property, object_id, key}, _ctx) do
    import Ecto.Query

    Multi.delete_all(
      multi,
      {:delete_property, object_id, key, make_ref()},
      from(p in Property, where: p.object_id == ^object_id and p.key == ^key)
    )
  end

  defp apply_event_to_multi(multi, {:move, object_id, to_container_id, rel_type}, _ctx) do
    import Ecto.Query

    multi
    |> Multi.delete_all(
      {:remove_old_container, object_id, make_ref()},
      from(r in Relationship, where: r.to_id == ^object_id and r.type == ^rel_type)
    )
    |> Multi.insert(
      {:move, object_id, to_container_id, make_ref()},
      %Relationship{}
      |> Relationship.changeset(%{
        from_id: to_container_id,
        to_id: object_id,
        type: rel_type
      })
    )
  end

  defp apply_event_to_multi(multi, {:relate, from_id, to_id, rel_type}, _ctx) do
    Multi.insert(
      multi,
      {:relate, from_id, to_id, rel_type, make_ref()},
      %Relationship{}
      |> Relationship.changeset(%{from_id: from_id, to_id: to_id, type: rel_type})
    )
  end

  defp apply_event_to_multi(multi, {:unrelate, from_id, to_id, rel_type}, _ctx) do
    import Ecto.Query

    Multi.delete_all(
      multi,
      {:unrelate, from_id, to_id, rel_type, make_ref()},
      from(r in Relationship,
        where: r.from_id == ^from_id and r.to_id == ^to_id and r.type == ^rel_type
      )
    )
  end

  defp apply_event_to_multi(multi, {:create_object, attrs}, _ctx) do
    Multi.insert(multi, {:create_object, make_ref()}, Object.changeset(%Object{}, attrs))
  end

  defp apply_event_to_multi(multi, {:delete_object, object_id}, _ctx) do
    import Ecto.Query

    multi
    |> Multi.run({:check_delete, object_id, make_ref()}, fn _repo, _changes ->
      case LineCore.Object.get(object_id) do
        %{type: :player} -> {:error, :cannot_delete_player}
        _ -> {:ok, :ok}
      end
    end)
    |> Multi.update_all(
      {:delete_object, object_id, make_ref()},
      from(o in Object, where: o.id == ^object_id),
      set: [deleted_at: DateTime.utc_now()]
    )
  end

  defp apply_event_to_multi(multi, {:notify_actor, _}, _ctx), do: multi
  defp apply_event_to_multi(multi, {:notify_room, _, _}, _ctx), do: multi
  defp apply_event_to_multi(multi, {:notify_room, _}, _ctx), do: multi
  defp apply_event_to_multi(multi, {:notify_object, _, _}, _ctx), do: multi
  defp apply_event_to_multi(multi, {:broadcast_channel, _, _}, _ctx), do: multi

  defp broadcast_events(events, context) do
    Enum.each(events, fn event -> broadcast_event(event, context) end)
  end

  defp broadcast_event({:notify_actor, msg}, ctx) do
    LineCore.PubSub.broadcast({:actor, ctx.actor.id}, {:msg, msg})
  end

  defp broadcast_event({:notify_room, msg, opts}, ctx) do
    except = Keyword.get(opts, :except, [])
    LineCore.PubSub.broadcast({:room, ctx.room.id}, {:room_msg, msg, except})
  end

  defp broadcast_event({:notify_room, msg}, ctx) do
    LineCore.PubSub.broadcast({:room, ctx.room.id}, {:room_msg, msg, []})
  end

  defp broadcast_event({:notify_object, object_id, msg}, _ctx) do
    LineCore.PubSub.broadcast({:actor, object_id}, {:msg, msg})
  end

  defp broadcast_event({:broadcast_channel, channel, msg}, _ctx) do
    LineCore.PubSub.broadcast({:channel, channel}, {:channel_msg, channel, msg})
  end

  defp broadcast_event(_, _), do: :ok
end
