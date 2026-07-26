defmodule LineWebWeb.GameChannel do
  @moduledoc """
  Primary game channel.

  Joining `game:<player_id>` subscribes the channel to the player's PubSub
  topics (`{:actor, player_id}` and `{:room, current_room_id}`) and registers
  the player in `LineCore.Presence`. The channel forwards all received messages
  to the client.

  Client sends commands as `"command"` events with `%{"raw" => "look"}` payload.
  The channel routes them through `LineCore.Parser` and dispatches via
  `LineCore.Dispatcher`.

  On the wire, the client receives:
    - `"msg"` event with `%{text: "..."}` for direct actor notifications
    - `"room_msg"` event with `%{text: "..."}` for room broadcasts
    - `"channel_msg"` event with `%{channel: "...", text: "..."}` for channels
    - `"error"` event with `%{reason: "..."}` for command failures
  """

  use Phoenix.Channel

  alias LineCore.{Catchup, Dispatcher, Object, Parser, Presence, PubSub}

  ## Join

  @impl true
  def join("game:" <> requested_player_id, _payload, socket) do
    if requested_player_id == socket.assigns.player_id do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "player_id mismatch"}}
    end
  end

  ## After-join setup: subscriptions + presence registration

  @impl true
  def handle_info(:after_join, socket) do
    player_id = socket.assigns.player_id

    # Subscribe to actor topic
    PubSub.subscribe({:actor, player_id})

    # Subscribe to current room topic
    socket =
      case Object.container_of(player_id) do
        nil ->
          socket

        room ->
          PubSub.subscribe({:room, room.id})
          assign(socket, :current_room_id, room.id)
      end

    # Register as online
    Presence.register(player_id, %{source: :websocket, joined_at: DateTime.utc_now()})

    # Somebody is driving this body again. Tell them what it lived through
    # while they were not — the notifications sent to an actor topic with no
    # subscriber are recoverable from the journal, and only from there.
    case Catchup.digest(player_id) do
      [] -> :ok
      lines -> push(socket, "msg", %{text: Enum.join(lines, "\n")})
    end

    Catchup.mark_online(player_id)

    {:noreply, socket}
  end

  # Forward PubSub-delivered messages to the client over the socket.

  def handle_info({:msg, text}, socket) do
    push(socket, "msg", %{text: text})
    {:noreply, socket}
  end

  def handle_info({:room_msg, text, except}, socket) do
    if socket.assigns.player_id in except do
      {:noreply, socket}
    else
      push(socket, "room_msg", %{text: text})
      {:noreply, socket}
    end
  end

  def handle_info({:channel_msg, channel, text}, socket) do
    push(socket, "channel_msg", %{channel: to_string(channel), text: text})
    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  ## Incoming commands from client

  @impl true
  def handle_in("command", %{"raw" => raw}, socket) when is_binary(raw) do
    case Parser.parse(raw) do
      {:ok, verb_module, args} ->
        case Dispatcher.dispatch(socket.assigns.player_id, verb_module, args, raw) do
          :ok ->
            # If the verb was Go, we may have moved rooms — re-subscribe.
            socket = maybe_resubscribe_room(socket, verb_module)
            {:reply, {:ok, %{status: "dispatched"}}, socket}

          {:error, reason} ->
            push(socket, "error", %{reason: format_reason(reason)})
            {:reply, {:error, %{reason: format_reason(reason)}}, socket}
        end

      {:empty, _} ->
        push(socket, "error", %{reason: "empty command"})
        {:reply, {:error, %{reason: "empty command"}}, socket}

      {:unknown, verb, _} ->
        push(socket, "error", %{reason: "unknown verb: #{verb}"})
        {:reply, {:error, %{reason: "unknown verb: #{verb}"}}, socket}
    end
  end

  def handle_in("command", _payload, socket) do
    push(socket, "error", %{reason: "missing 'raw' field"})
    {:reply, {:error, %{reason: "missing 'raw' field"}}, socket}
  end

  ## Termination — unregister presence

  @impl true
  def terminate(_reason, socket) do
    player_id = socket.assigns[:player_id]

    if player_id do
      Presence.unregister(player_id)
      PubSub.unsubscribe({:actor, player_id})

      case socket.assigns[:current_room_id] do
        nil -> :ok
        room_id -> PubSub.unsubscribe({:room, room_id})
      end

      # The connection ends; the body does not. It stays where it was standing,
      # marked unattended, and remains a legal target while it is.
      Catchup.mark_offline(player_id)
    end

    :ok
  end

  ## Helpers

  defp maybe_resubscribe_room(socket, LineCore.Verbs.Go) do
    player_id = socket.assigns.player_id
    new_room = Object.container_of(player_id)

    case {socket.assigns[:current_room_id], new_room} do
      {old, %{id: new_id}} when old != new_id ->
        if old, do: PubSub.unsubscribe({:room, old})
        PubSub.subscribe({:room, new_id})
        assign(socket, :current_room_id, new_id)

      _ ->
        socket
    end
  end

  defp maybe_resubscribe_room(socket, _verb), do: socket

  defp format_reason(reason) when is_atom(reason), do: to_string(reason)
  defp format_reason({tag, _detail}) when is_atom(tag), do: to_string(tag)
  defp format_reason(other), do: inspect(other)
end
