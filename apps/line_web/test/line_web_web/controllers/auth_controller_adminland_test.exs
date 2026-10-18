defmodule LineWebWeb.AuthControllerAdminlandTest do
  use LineWebWeb.ConnCase, async: false

  alias LineCore.{Object, Repo}

  setup do
    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    :ok
  end

  test "successful admin login loads the admin into adminland", %{conn: conn} do
    {:ok, elsewhere} = Object.create(:room, "Elsewhere")
    {:ok, admin} = Object.create(:player, "admin")
    {:ok, _} = Object.relate(elsewhere.id, admin.id, :contains)
    {:ok, _} = Object.set_property(admin.id, "admin", true)
    {:ok, _} = Object.set_property(admin.id, "password_hash", Bcrypt.hash_pwd_salt("correct horse"))

    conn = post(conn, "/api/login", %{"name" => "admin", "password" => "correct horse"})

    assert %{"player_id" => player_id, "token" => token} = json_response(conn, 200)
    assert player_id == admin.id
    assert is_binary(token)

    assert %{name: "ADMINLAND"} = Object.container_of(admin.id)
  end

  test "ordinary player login preserves their current room", %{conn: conn} do
    {:ok, room} = Object.create(:room, "Player Room")
    {:ok, player} = Object.create(:player, "player")
    {:ok, _} = Object.relate(room.id, player.id, :contains)
    {:ok, _} = Object.set_property(player.id, "password_hash", Bcrypt.hash_pwd_salt("correct horse"))

    conn = post(conn, "/api/login", %{"name" => "player", "password" => "correct horse"})

    assert %{"player_id" => player_id} = json_response(conn, 200)
    assert player_id == player.id
    assert %{id: room_id} = Object.container_of(player.id)
    assert room_id == room.id
  end
end
