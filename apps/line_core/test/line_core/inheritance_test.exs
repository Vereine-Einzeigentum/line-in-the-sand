defmodule LineCore.InheritanceTest do
  use ExUnit.Case, async: false

  alias LineCore.{Object, Repo}

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

  test "child reads an inherited property from its parent" do
    {:ok, parent} = Object.create(:item, "$wieldable")
    {:ok, child} = Object.create(:item, "knife", %{parent_id: parent.id})
    {:ok, _} = Object.set_property(parent.id, "grip", "one_hand")

    assert Object.get_property(child.id, "grip") == "one_hand"
    assert Object.get_local_property(child.id, "grip") == nil
  end

  test "local property overrides inherited value without mutating parent" do
    {:ok, parent} = Object.create(:item, "$weapon")
    {:ok, child} = Object.create(:item, "odd pistol", %{parent_id: parent.id})
    {:ok, _} = Object.set_property(parent.id, "damage_class", "standard")
    {:ok, _} = Object.set_property(child.id, "damage_class", "absurd")

    assert Object.get_property(child.id, "damage_class") == "absurd"
    assert Object.get_property(parent.id, "damage_class") == "standard"
  end

  test "changing a parent default immediately changes descendants without local overrides" do
    {:ok, parent} = Object.create(:item, "$container")
    {:ok, child} = Object.create(:item, "crate", %{parent_id: parent.id})

    {:ok, _} = Object.set_property(parent.id, "sealed", false)
    assert Object.get_property(child.id, "sealed") == false

    {:ok, _} = Object.set_property(parent.id, "sealed", true)
    assert Object.get_property(child.id, "sealed") == true
  end

  test "inheritance and containment are independent" do
    {:ok, prototype} = Object.create(:item, "$weapon")
    {:ok, room} = Object.create(:room, "Store Room")
    {:ok, pistol} = Object.create(:item, "pistol", %{parent_id: prototype.id})
    {:ok, _} = Object.relate(room.id, pistol.id, :contains)

    assert %{id: parent_id} = Object.parent(pistol.id)
    assert parent_id == prototype.id

    assert %{id: container_id} = Object.container_of(pistol.id)
    assert container_id == room.id
  end

  test "ancestry walks the parent chain and supports is-a queries" do
    {:ok, root} = Object.create(:item, "$root")
    {:ok, weapon} = Object.create(:item, "$weapon", %{parent_id: root.id})
    {:ok, pistol} = Object.create(:item, "$pistol", %{parent_id: weapon.id})

    assert Enum.map(Object.ancestors(pistol.id), & &1.id) == [weapon.id, root.id]
    assert Object.descendant_of?(pistol.id, weapon.id)
    assert Object.descendant_of?(pistol.id, root.id)
    refute Object.descendant_of?(root.id, pistol.id)
  end
end
