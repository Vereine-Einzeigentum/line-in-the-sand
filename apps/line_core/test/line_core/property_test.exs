defmodule LineCore.PropertyTest do
  use ExUnit.Case, async: false

  alias LineCore.Object
  alias LineCore.Repo

  setup do
    # Sandbox-style cleanup
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)
    :ok
  end

  test "scalar values round-trip through JSONB" do
    {:ok, obj} = Object.create(:item, "Test Item")

    Object.set_property(obj.id, "hp", 50)
    Object.set_property(obj.id, "name_alt", "Spare Knife")
    Object.set_property(obj.id, "broken", true)
    Object.set_property(obj.id, "weight", 1.5)

    assert Object.get_property(obj.id, "hp") == 50
    assert Object.get_property(obj.id, "name_alt") == "Spare Knife"
    assert Object.get_property(obj.id, "broken") == true
    assert Object.get_property(obj.id, "weight") == 1.5
  end

  test "map values round-trip without unwrapping" do
    {:ok, obj} = Object.create(:item, "Test Item")

    complex = %{"damage" => 8, "type" => "piercing", "tags" => ["sharp", "metal"]}
    Object.set_property(obj.id, "weapon_stats", complex)

    assert Object.get_property(obj.id, "weapon_stats") == complex
  end

  test "upsert replaces existing value" do
    {:ok, obj} = Object.create(:item, "Test Item")

    Object.set_property(obj.id, "hp", 50)
    Object.set_property(obj.id, "hp", 25)

    assert Object.get_property(obj.id, "hp") == 25
  end

  test "missing property returns nil or default" do
    {:ok, obj} = Object.create(:item, "Test Item")

    assert Object.get_property(obj.id, "nonexistent") == nil
    assert Object.get_property(obj.id, "nonexistent", 0) == 0
  end

  test "properties/1 returns all as a map" do
    {:ok, obj} = Object.create(:player, "Player")

    Object.set_property(obj.id, "hp", 50)
    Object.set_property(obj.id, "stat_wire", 3)
    Object.set_property(obj.id, "stat_iron", 5)

    props = Object.properties(obj.id)

    assert props["hp"] == 50
    assert props["stat_wire"] == 3
    assert props["stat_iron"] == 5
  end
end
