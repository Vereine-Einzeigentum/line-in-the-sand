defmodule LineCore.AdminlandTest do
  use ExUnit.Case, async: false

  alias LineCore.{Adminland, Object, Repo}

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    :ok
  end

  test "adminland is one isolated room and seeds idempotently" do
    assert {:ok, room} = Adminland.ensure()
    assert room.type == :room
    assert room.name == "ADMINLAND"
    assert Object.get_property(room.id, "admin_only") == true
    assert Object.get_property(room.id, "system_space") == true
    assert Object.get_property(room.id, "map_tile") == "adminland"
    assert Object.exits(room.id) == []

    assert {:ok, same_room} = Adminland.ensure()
    assert same_room.id == room.id
  end

  test "loads admins into adminland" do
    {:ok, ordinary_room} = Object.create(:room, "Ordinary Room")
    {:ok, admin} = Object.create(:player, "admin")
    {:ok, _} = Object.relate(ordinary_room.id, admin.id, :contains)
    {:ok, _} = Object.set_property(admin.id, "admin", true)

    assert {:ok, adminland} = Adminland.load_if_admin(admin.id)
    assert %{id: room_id} = Object.container_of(admin.id)
    assert room_id == adminland.id
  end

  test "does not move ordinary players" do
    {:ok, ordinary_room} = Object.create(:room, "Ordinary Room")
    {:ok, player} = Object.create(:player, "player")
    {:ok, _} = Object.relate(ordinary_room.id, player.id, :contains)

    assert :not_admin == Adminland.load_if_admin(player.id)
    assert %{id: room_id} = Object.container_of(player.id)
    assert room_id == ordinary_room.id
  end
end
