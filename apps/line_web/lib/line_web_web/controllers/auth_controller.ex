defmodule LineWebWeb.AuthController do
  use Phoenix.Controller, formats: [:json]

  alias LineCore.{Object, Repo}
  alias LineWebWeb.Endpoint

  @max_name 32
  @min_name 2
  @temp_pass_length 16

  # POST /api/request  —  request <name> for <email>
  def request_account(conn, %{"name" => name, "email" => email})
      when is_binary(name) and is_binary(email) do
    name = String.trim(name)
    email = String.trim(email)

    cond do
      String.length(name) < @min_name or String.length(name) > @max_name ->
        json_error(conn, 400, "name must be #{@min_name}-#{@max_name} characters")

      not String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/) ->
        json_error(conn, 400, "invalid email")

      Object.find_player_by_name(name) != nil ->
        json_error(conn, 409, "name taken")

      true ->
        temp_pass = generate_temp_password()
        hash = Bcrypt.hash_pwd_salt(temp_pass)

        case create_player_atomic(name, email, hash) do
          {:ok, _player} ->
            LineWeb.AccountEmail.temp_password(email, name, temp_pass)
            |> LineWeb.Mailer.deliver()

            json(conn, %{ok: true})

          {:error, _reason} ->
            json_error(conn, 500, "could not create player")
        end
    end
  end

  def request_account(conn, _), do: json_error(conn, 400, "name and email required")

  # POST /api/login
  def login(conn, %{"name" => name, "password" => password})
      when is_binary(name) and is_binary(password) do
    name = String.trim(name)

    case Object.find_player_by_name(name) do
      %{id: player_id} ->
        hash = Object.get_property(player_id, "password_hash")

        if is_binary(hash) and Bcrypt.verify_pass(password, hash) do
          token = sign_token(player_id)
          must_change = Object.get_property(player_id, "temp_password") == true

          json(conn, %{
            token: token,
            player_id: player_id,
            must_change_password: must_change
          })
        else
          login_failed(conn)
        end

      nil ->
        Bcrypt.no_user_verify()
        login_failed(conn)
    end
  end

  def login(conn, _), do: json_error(conn, 400, "name and password required")

  defp create_player_atomic(name, email, hash) do
    Repo.transaction(fn ->
      case Object.create(:player, name) do
        {:ok, player} ->
          Object.set_property(player.id, "password_hash", hash)
          Object.set_property(player.id, "email", email)
          Object.set_property(player.id, "temp_password", true)
          player

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp login_failed(conn) do
    json_error(conn, 401,
      "if you forgot your account info, email admin@example.com from the account you registered with")
  end

  defp generate_temp_password do
    :crypto.strong_rand_bytes(@temp_pass_length) |> Base.url_encode64(padding: false)
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
