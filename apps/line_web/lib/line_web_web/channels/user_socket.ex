defmodule LineWebWeb.UserSocket do
  @moduledoc """
  Phoenix Socket for game connections.

  Authentication: connect params carry a signed `token` from
  `LineWebWeb.PlayerToken`, which the server verifies before resolving the
  player it names. Raw player UUIDs are **not** accepted — they are identifiers,
  not credentials (see `LineWebWeb.PlayerToken` for why that distinction
  matters now that the journal records every actor id).

  Tokens are minted by whatever authenticates the player; in Phase 0 that is
  the playtest API, which returns a `socket_token` alongside the session.
  Phase 1+ can issue them from a real account flow without changing this
  module.

  Channels:
  - `game:<player_id>` — joined by the owning player only; receives all
    notifications for that actor and the room they're in.
  """

  use Phoenix.Socket

  alias LineWebWeb.PlayerToken

  channel "game:*", LineWebWeb.GameChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    with {:ok, player_id} <- PlayerToken.verify(token),
         {:ok, player} <- verify_player(player_id) do
      {:ok, assign(socket, :player_id, player.id) |> assign(:player, player)}
    else
      _ -> :error
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
