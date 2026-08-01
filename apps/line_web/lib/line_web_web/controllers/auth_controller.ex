defmodule LineWebWeb.AuthController do
  use Phoenix.Controller, formats: [:json]

  alias LineCore.Object
  alias LineWebWeb.Endpoint

  @min_password 8
  @max_name 32
  @min_name 2

  def register(conn, %{"name" => name, "password" => password})
      when is_binary(name) and is_binary(password) do
    name = String.trim(name)

    cond do
      String.length(name) < @min_name or String.length(name) > @max_name ->
        json_error(conn, 400, "name must be 2-32 characters")

      String.length(password) < @min_password ->
        json_error(conn, 400, "password must be at least 8 characters")

      Object.find_player_by_name(name) != nil ->
        json_error(conn, 409, "name taken")

      true ->
        hash = Bcrypt.hash_pwd_salt(password)

        case Object.create(:player, name) do
          {:ok, player} ->
            Object.set_property(player.id, "password_hash", hash)
            token = sign_token(player.id)
            json(conn, %{token: token, player_id: player.id})

          {:error, _reason} ->
            json_error(conn, 500, "could not create player")
        end
    end
  end

  def register(conn, _), do: json_error(conn, 400, "name and password required")

  def login(conn, %{"name" => name, "password" => password})
      when is_binary(name) and is_binary(password) do
    name = String.trim(name)

    case Object.find_player_by_name(name) do
      %{id: player_id} ->
        hash = Object.get_property(player_id, "password_hash")

        if is_binary(hash) and Bcrypt.verify_pass(password, hash) do
          token = sign_token(player_id)
          json(conn, %{token: token, player_id: player_id})
        else
          login_failed(conn)
        end

      nil ->
        Bcrypt.no_user_verify()
        login_failed(conn)
    end
  end

  def login(conn, _), do: json_error(conn, 400, "name and password required")

  defp login_failed(conn) do
    json_error(conn, 401,
      "if you forgot your account info, email admin@example.com from the account you registered with")
  end

  defp sign_token(player_id) do
    Phoenix.Token.sign(Endpoint, Endpoint.player_auth_salt(), player_id)
  end

  defp json_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end
end
