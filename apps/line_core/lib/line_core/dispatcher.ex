defmodule LineCore.Dispatcher do
  @moduledoc """
  Takes a parsed command, finds the actor and room, looks up the verb,
  calls execute/2, applies returned events transactionally, and broadcasts
  notifications via PubSub.

  This is the only place side effects from verbs happen. Verbs are pure;
  everything that touches the DB or the network goes through here.

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

  alias LineCore.Repo
  alias LineCore.Schemas.{Object, Property, Relationship}
  alias LineCore.Verb.Context
  alias Ecto.Multi

  def dispatch(actor_id, verb_module, args, raw_command) do
    dispatch_resolved(actor_id, verb_module, args, raw_command, nil, nil)
  end

  def dispatch_resolved(actor_id, verb_module, args, raw_command, dobj, iobj) do
    with {:ok, actor} <- fetch_actor(actor_id),
         {:ok, room} <- fetch_room(actor),
         contents = LineCore.Object.contents(room.id),
         :ok <- check_requirements(actor, verb_module),
         context = build_context(actor, room, contents, raw_command, dobj, iobj),
         {:ok, events} <- verb_module.execute(context, args),
         {:ok, _result} <- apply_events(events, context) do
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

  defp build_context(actor, room, contents, raw_command, dobj, iobj) do
    %Context{
      actor: actor,
      room: room,
      room_contents: contents,
      dobj: dobj,
      iobj: iobj,
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

  defp apply_events(events, context) do
    events
    |> Enum.reduce(Multi.new(), fn event, multi ->
      apply_event_to_multi(multi, event, context)
    end)
    |> Repo.transaction()
  end

  defp apply_event_to_multi(multi, {:set_property, object_ref, key, value}, _ctx) do
    stored = if is_map(value), do: value, else: %{"v" => value}

    if created_ref?(object_ref) do
      Multi.run(
        multi,
        {:set_property, object_ref, key, make_ref()},
        fn repo, changes ->
          object_id = resolve_object_ref!(object_ref, changes)

          %Property{}
          |> Property.changeset(%{object_id: object_id, key: key, value: stored})
          |> repo.insert(
            on_conflict: [set: [value: stored, updated_at: DateTime.utc_now()]],
            conflict_target: [:object_id, :key]
          )
        end
      )
    else
      Multi.insert(
        multi,
        {:set_property, object_ref, key, make_ref()},
        %Property{}
        |> Property.changeset(%{object_id: object_ref, key: key, value: stored}),
        on_conflict: [set: [value: stored, updated_at: DateTime.utc_now()]],
        conflict_target: [:object_id, :key]
      )
    end
  end

  defp apply_event_to_multi(multi, {:delete_property, object_id, key}, _ctx) do
    import Ecto.Query

    Multi.delete_all(
      multi,
      {:delete_property, object_id, key, make_ref()},
      from(p in Property, where: p.object_id == ^object_id and p.key == ^key)
    )
  end

  defp apply_event_to_multi(multi, {:move, object_ref, container_ref, rel_type}, _ctx) do
    import Ecto.Query

    if created_ref?(object_ref) or created_ref?(container_ref) do
      Multi.run(
        multi,
        {:move, object_ref, container_ref, make_ref()},
        fn repo, changes ->
          object_id = resolve_object_ref!(object_ref, changes)
          to_container_id = resolve_object_ref!(container_ref, changes)

          repo.delete_all(
            from(r in Relationship, where: r.to_id == ^object_id and r.type == ^rel_type)
          )

          %Relationship{}
          |> Relationship.changeset(%{
            from_id: to_container_id,
            to_id: object_id,
            type: rel_type
          })
          |> repo.insert()
        end
      )
    else
      multi
      |> Multi.delete_all(
        {:remove_old_container, object_ref, make_ref()},
        from(r in Relationship, where: r.to_id == ^object_ref and r.type == ^rel_type)
      )
      |> Multi.insert(
        {:move, object_ref, container_ref, make_ref()},
        %Relationship{}
        |> Relationship.changeset(%{
          from_id: container_ref,
          to_id: object_ref,
          type: rel_type
        })
      )
    end
  end

  defp apply_event_to_multi(multi, {:relate, from_ref, to_ref, rel_type}, _ctx) do
    if created_ref?(from_ref) or created_ref?(to_ref) do
      Multi.run(
        multi,
        {:relate, from_ref, to_ref, rel_type, make_ref()},
        fn repo, changes ->
          from_id = resolve_object_ref!(from_ref, changes)
          to_id = resolve_object_ref!(to_ref, changes)

          %Relationship{}
          |> Relationship.changeset(%{from_id: from_id, to_id: to_id, type: rel_type})
          |> repo.insert()
        end
      )
    else
      Multi.insert(
        multi,
        {:relate, from_ref, to_ref, rel_type, make_ref()},
        %Relationship{}
        |> Relationship.changeset(%{from_id: from_ref, to_id: to_ref, type: rel_type})
      )
    end
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

  defp apply_event_to_multi(multi, {:create_object, ref, attrs}, _ctx) do
    Multi.insert(multi, {:create_object, ref}, Object.changeset(%Object{}, attrs))
  end

  defp apply_event_to_multi(multi, {:create_object, attrs}, _ctx) do
    Multi.insert(multi, {:create_object, make_ref()}, Object.changeset(%Object{}, attrs))
  end

  defp apply_event_to_multi(multi, {:update_object, object_id, attrs}, _ctx) do
    Multi.update(
      multi,
      {:update_object, object_id, make_ref()},
      Object.changeset(LineCore.Object.get!(object_id), attrs)
    )
  end

  defp apply_event_to_multi(multi, {:delete_object, object_id}, _ctx) do
    import Ecto.Query

    Multi.update_all(
      multi,
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

  defp created_ref?({:created, _ref}), do: true
  defp created_ref?(_), do: false

  defp resolve_object_ref!({:created, ref}, changes) do
    changes
    |> Map.fetch!({:create_object, ref})
    |> Map.fetch!(:id)
  end

  defp resolve_object_ref!(id, _changes), do: id
end
