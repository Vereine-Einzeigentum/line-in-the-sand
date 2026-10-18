defmodule LineCore.BootstrapAdminTest do
  use ExUnit.Case, async: false

  alias LineCore.{BootstrapAdmin, Object, Repo}

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

  test "creates a privileged admin login without conflating role with object type" do
    assert {:ok, {:created, admin}} =
             BootstrapAdmin.ensure("admin", "initial-secret", email: "admin@example.test")

    assert admin.type == :player
    assert Object.get_property(admin.id, "account_role") == "admin"
    assert Object.get_property(admin.id, "admin") == true
    assert Object.get_property(admin.id, "email") == "admin@example.test"

    hash = Object.get_property(admin.id, "password_hash")
    assert is_binary(hash)
    assert Bcrypt.verify_pass("initial-secret", hash)
  end

  test "is idempotent and does not reset an existing admin password" do
    assert {:ok, {:created, admin}} = BootstrapAdmin.ensure("admin", "first-secret")

    original_hash = Object.get_property(admin.id, "password_hash")
    assert Bcrypt.verify_pass("first-secret", original_hash)

    assert {:ok, {:existing, same_admin}} =
             BootstrapAdmin.ensure("admin", "replacement-secret")

    assert same_admin.id == admin.id

    current_hash = Object.get_property(admin.id, "password_hash")
    assert current_hash == original_hash
    assert Bcrypt.verify_pass("first-secret", current_hash)
    refute Bcrypt.verify_pass("replacement-secret", current_hash)
  end

  test "places a newly bootstrapped admin in the requested starting room" do
    {:ok, room} = Object.create(:room, "Bootstrap Safehouse")

    assert {:ok, {:created, admin}} =
             BootstrapAdmin.ensure("admin", "initial-secret", starting_room_id: room.id)

    assert %{id: room_id} = Object.container_of(admin.id)
    assert room_id == room.id
  end

  test "does not teleport an existing admin on a later bootstrap" do
    {:ok, first_room} = Object.create(:room, "First Room")
    {:ok, second_room} = Object.create(:room, "Second Room")

    assert {:ok, {:created, admin}} =
             BootstrapAdmin.ensure("admin", "initial-secret", starting_room_id: first_room.id)

    assert {:ok, _} = Object.move(admin.id, second_room.id)

    assert {:ok, {:existing, _admin}} =
             BootstrapAdmin.ensure("admin", "replacement-secret", starting_room_id: first_room.id)

    assert %{id: room_id} = Object.container_of(admin.id)
    assert room_id == second_room.id
  end

  test "bootstrap_from_env skips cleanly when bootstrap credentials are absent" do
    old_name = System.get_env("ADMIN_BOOTSTRAP_NAME")
    old_password = System.get_env("ADMIN_BOOTSTRAP_PASSWORD")

    System.delete_env("ADMIN_BOOTSTRAP_NAME")
    System.delete_env("ADMIN_BOOTSTRAP_PASSWORD")

    on_exit(fn ->
      restore_env("ADMIN_BOOTSTRAP_NAME", old_name)
      restore_env("ADMIN_BOOTSTRAP_PASSWORD", old_password)
    end)

    assert :skip == BootstrapAdmin.bootstrap_from_env()
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
