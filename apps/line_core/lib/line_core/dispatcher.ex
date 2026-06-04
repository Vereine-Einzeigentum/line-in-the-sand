defmodule LineCore.Dispatcher do
  @moduledoc """
  Takes a parsed command, finds the actor and room, looks up the verb,
  calls execute/2, applies returned events transactionally, and broadcasts
  notifications via PubSub.

  This is the only place side effects from verbs happen. Verbs are pure;
  everything that touches the DB or the network goes through here.
  """

  alias LineCore.{Object, Repo}
  alias LineCore.Schemas.{Object, Property, Relationship}
  alias LineCore.Verb.Context
  alias Ecto.Multi

  @doc """
  Dispatch a parsed command.

  `actor_id`: the player or NPC performing the action
  `verb_module`: the module implementing LineCore.Verb behaviour
  `args`: parsed args from the command parser
  `raw_command`: original command string (for logging)
  """
  def dispatch(actor_id, verb_module, args, raw_command) do
    with {:ok, actor} <- fetch_actor(actor_id),
         {:ok, room} <- fetch_room(actor),
         contents = LineCore.Object.contents(room.id),
         :ok <- check_requirements(actor, verb_module),
         context = build_context(actor, room, contents, raw_command),
         {:ok, events} <- verb_module.execute(context, args),
         {:ok, _result} <- apply_events(events, context) do
      broadcast_events(events, context)
      :ok
    end
  end

  ## Actor/room resolution

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

  ## Requirements check

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

  ## Event application — transactional

  defp apply_events(events, context) do
    events
    |> Enum.reduce(Multi.new(), fn event, multi ->
      apply_event_to_multi(multi, event, context)
    end)
    |> Repo.transaction()
  end

  defp apply_event_to_multi(multi, {:set_property, object_id, key, value}, _ctx) do
    stored = if is_map(value), do: value, else: %{"v" => value}

    Multi.insert(multi, {:set_property, object_id, key},
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
      {:delete_property, object_id, key},
      from(p in Property, where: p.object_id == ^object_id and p.key == ^key)
    )
  end

  defp apply_event_to_multi(multi, {:move, object_id, to_container_id, rel_type}, _ctx) do
    import Ecto.Query

    multi
    |> Multi.delete_all(
      {:remove_old_container, object_id},
      from(r in Relationship, where: r.to_id == ^object_id and r.type == ^rel_type)
    )
    |> Multi.insert({:move, object_id, to_container_id},
      %Relationship{}
      |> Relationship.changeset(%{
        from_id: to_container_id,
        to_id: object_id,
        type: rel_type
      })
    )
  end

  defp apply_event_to_multi(multi, {:create_object, attrs}, _ctx) do
    Multi.insert(multi, {:create_object, make_ref()}, Object.changeset(%Object{}, attrs))
  end

  defp apply_event_to_multi(multi, {:delete_object, object_id}, _ctx) do
    Multi.update(
      multi,
      {:delete_object, object_id},
      Object.changeset(%Object{id: object_id}, %{deleted_at: DateTime.utc_now()})
    )
  end

  # Notify events have no DB impact; they get broadcast in broadcast_events/2.
  defp apply_event_to_multi(multi, {:notify_actor, _}, _ctx), do: multi
  defp apply_event_to_multi(multi, {:notify_room, _, _}, _ctx), do: multi
  defp apply_event_to_multi(multi, {:notify_room, _}, _ctx), do: multi
  defp apply_event_to_multi(multi, {:notify_object, _, _}, _ctx), do: multi
  defp apply_event_to_multi(multi, {:broadcast_channel, _, _}, _ctx), do: multi

  ## Event broadcasting via PubSub

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
