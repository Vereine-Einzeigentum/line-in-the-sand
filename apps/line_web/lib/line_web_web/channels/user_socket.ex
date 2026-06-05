defmodule LineWebWeb.UserSocket do
  @moduledoc """
  Phoenix Socket for game connections.

  Authentication for Phase 0: a `player_id` (UUID) is passed in connect params.
  Server verifies the player exists and is a `:player`-type object. No password
  yet — Phase 0 is closed playtest with trusted testers.

  Phase 1+ will add proper auth (signed tokens, password+username, or OAuth).

  Channels:
  - `game:<player_id>` — joined by the owning player only; receives all
    notifications for that actor and the room they're in.
  """

  use Phoenix.Socket

  channel "game:*", LineWebWeb.GameChannel

  @impl true
  def connect(%{"player_id" => player_id}, socket, _connect_info) do
    case verify_player(player_id) do
      {:ok, player} ->
        {:ok, assign(socket, :player_id, player.id) |> assign(:player, player)}

      :error ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "player_socket:#{socket.assigns.player_id}"

  defp verify_player(player_id) when is_binary(player_id) do
    case LineCore.Object.get(player_id) do
      %{type: :player} = player -> {:ok, player}
      _ -> :error
    end
  end

  defp verify_player(_), do: :error
end
