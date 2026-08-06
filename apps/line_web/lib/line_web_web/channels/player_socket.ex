defmodule LineWebWeb.PlayerSocket do
  use Phoenix.Socket

  channel "player:*", LineWebWeb.PlayerChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(
           LineWebWeb.Endpoint,
           LineWebWeb.Endpoint.player_auth_salt(),
           token,
           max_age: 86_400 * 30
         ) do
      {:ok, player_id} when is_binary(player_id) ->
        {:ok, assign(socket, :player_id, player_id)}

      _ ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "player_socket:#{socket.assigns.player_id}"
end
