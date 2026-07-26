defmodule LineCore.PubSub do
  @moduledoc """
  Broadcast channel for room/actor/channel events.

  Wraps Phoenix.PubSub with typed topics:

  - `{:room, room_id}`    — broadcast to everyone in a room
  - `{:actor, actor_id}`  — message to a single actor
  - `{:channel, name}`    — broadcast to a named channel (gang, faction, ooc)

  Subscribers receive `{:msg, message}`, `{:room_msg, message, except_ids}`,
  or `{:channel_msg, channel, message}` depending on the topic.

  Phoenix Channels in `:line_web` subscribe to these topics and forward
  messages to connected clients.
  """

  @pubsub LineCore.PubSub.Bus

  def child_spec(_opts) do
    Phoenix.PubSub.child_spec(name: @pubsub)
  end

  def subscribe({:room, room_id}), do: Phoenix.PubSub.subscribe(@pubsub, "room:#{room_id}")
  def subscribe({:actor, actor_id}), do: Phoenix.PubSub.subscribe(@pubsub, "actor:#{actor_id}")
  def subscribe({:channel, name}), do: Phoenix.PubSub.subscribe(@pubsub, "channel:#{name}")

  def unsubscribe({:room, room_id}), do: Phoenix.PubSub.unsubscribe(@pubsub, "room:#{room_id}")
  def unsubscribe({:actor, actor_id}), do: Phoenix.PubSub.unsubscribe(@pubsub, "actor:#{actor_id}")
  def unsubscribe({:channel, name}), do: Phoenix.PubSub.unsubscribe(@pubsub, "channel:#{name}")

  def broadcast({:room, room_id}, msg) do
    Phoenix.PubSub.broadcast(@pubsub, "room:#{room_id}", msg)
  end

  def broadcast({:actor, actor_id}, msg) do
    Phoenix.PubSub.broadcast(@pubsub, "actor:#{actor_id}", msg)
  end

  def broadcast({:channel, name}, msg) do
    Phoenix.PubSub.broadcast(@pubsub, "channel:#{name}", msg)
  end
end
