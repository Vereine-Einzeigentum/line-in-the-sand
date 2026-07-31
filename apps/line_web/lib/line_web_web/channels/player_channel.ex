defmodule LineWebWeb.PlayerChannel do
  use Phoenix.Channel

  alias LineCore.{Dispatcher, Object, PubSub}

  @impl true
  def join("player:" <> player_id, _payload, socket) do
    if player_id == socket.assigns.player_id do
      case Object.get(player_id) do
        nil ->
          {:error, %{reason: "player_not_found"}}

        _player ->
          :ok = PubSub.subscribe({:actor, player_id})

          case Object.container_of(player_id) do
            %{id: room_id} ->
              :ok = PubSub.subscribe({:room, room_id})
              {:ok, assign(socket, :room_id, room_id)}

            nil ->
              {:ok, assign(socket, :room_id, nil)}
          end
      end
    else
      {:error, %{reason: "topic_mismatch"}}
    end
  end

  @impl true
  def handle_in("cmd", %{"raw" => raw}, socket) when is_binary(raw) do
    case LineCore.Parser.parse(raw) do
      {:ok, verb_module, args} ->
        result =
          Dispatcher.dispatch(
            socket.assigns.player_id,
            verb_module,
            args,
            raw
          )

        case result do
          :ok ->
            socket = maybe_resubscribe_room(socket)
            {:reply, :ok, socket}

          {:error, reason} ->
            push(socket, "system", %{
              text: error_text(reason),
              kind: "error"
            })
            {:reply, {:error, %{reason: to_string(reason)}}, socket}
        end

      {:empty, _} ->
        {:reply, :ok, socket}

      {:unknown, verb, _} ->
        push(socket, "system", %{
          text: "Huh?",
          kind: "error"
        })
        {:reply, {:error, %{reason: "unknown_verb: #{verb}"}}, socket}
    end
  end

  @impl true
  def handle_info({:msg, text}, socket) do
    push(socket, "msg", %{text: text})
    {:noreply, socket}
  end

  def handle_info({:room_msg, text, except}, socket) do
    if socket.assigns.player_id in except do
      {:noreply, socket}
    else
      push(socket, "room_msg", %{text: text, except: except})
      {:noreply, socket}
    end
  end

  def handle_info({:system, payload}, socket) when is_map(payload) do
    push(socket, "system", payload)
    {:noreply, socket}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp maybe_resubscribe_room(socket) do
    new_room_id =
      case Object.container_of(socket.assigns.player_id) do
        %{id: id} -> id
        nil -> nil
      end

    if new_room_id == socket.assigns.room_id do
      socket
    else
      if socket.assigns.room_id, do: PubSub.unsubscribe({:room, socket.assigns.room_id})
      if new_room_id, do: :ok = PubSub.subscribe({:room, new_room_id})
      assign(socket, :room_id, new_room_id)
    end
  end

  defp error_text(:actor_not_found), do: "You don't seem to exist."
  defp error_text(:actor_not_in_room), do: "You're nowhere."
  defp error_text(:no_exit), do: "You can't go that way."
  defp error_text(:not_here), do: "You don't see that here."
  defp error_text(reason), do: "Error: #{reason}"
end
