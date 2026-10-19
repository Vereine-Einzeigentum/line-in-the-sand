defmodule LineCore.ArchetypesTest do
  use ExUnit.Case, async: false

  alias LineCore.{Archetypes, Object, Repo}

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

  test "seeds the canonical inheritance spine idempotently" do
    first = Archetypes.seed()
    second = Archetypes.seed()

    assert first.root.id == second.root.id

    assert first.room.parent_id == first.root.id
    assert first.exit.parent_id == first.root.id

    assert first.motile.parent_id == first.root.id
    assert first.mob.parent_id == first.motile.id
    assert first.pc.parent_id == first.mob.id
    assert first.npc.parent_id == first.mob.id
    assert first.mod.parent_id == first.motile.id
    assert first.mod.parent_id != first.mob.id

    assert first.item.parent_id == first.root.id
    assert first.container.parent_id == first.item.id
    assert first.corpse.parent_id == first.container.id
    assert first.wieldable.parent_id == first.item.id
    assert first.weapon.parent_id == first.wieldable.id
    assert first.clothing.parent_id == first.item.id

    assert first.verb.parent_id == first.root.id
  end

  test "generic items default to item, not wieldable" do
    tree = Archetypes.seed()
    {:ok, cup} = Object.create(:item, "coffee cup")

    assert cup.parent_id == tree.item.id
    refute Object.descendant_of?(cup.id, tree.wieldable.id)
  end

  test "corpse is a container and individual corpses can carry lock state" do
    tree = Archetypes.seed()
    {:ok, _} = Object.set_property(tree.container.id, "contains_objects", true)

    {:ok, robot_corpse} =
      Object.create(:item, "dead security bot", %{parent_id: tree.corpse.id})

    {:ok, _} = Object.set_property(robot_corpse.id, "locked", true)

    assert Object.descendant_of?(robot_corpse.id, tree.corpse.id)
    assert Object.descendant_of?(robot_corpse.id, tree.container.id)
    assert Object.descendant_of?(robot_corpse.id, tree.item.id)
    assert Object.get_property(robot_corpse.id, "contains_objects") == true
    assert Object.get_property(robot_corpse.id, "locked") == true
  end

  test "adopts existing world objects without confusing containment with inheritance" do
    tree = Archetypes.seed()
    {:ok, room} = Object.create(:room, "Unparented Room", %{parent_id: nil})
    {:ok, player} = Object.create(:player, "Unparented PC", %{parent_id: nil})
    {:ok, item} = Object.create(:item, "Unparented Item", %{parent_id: nil})
    {:ok, _} = Object.relate(room.id, player.id, :contains)
    {:ok, _} = Object.relate(player.id, item.id, :contains)

    :ok = Archetypes.adopt_existing(tree)

    assert Object.get(room.id).parent_id == tree.room.id
    assert Object.get(player.id).parent_id == tree.pc.id
    assert Object.get(item.id).parent_id == tree.item.id
    assert Object.container_of(player.id).id == room.id
    assert Object.container_of(item.id).id == player.id
  end

  test "admin players are adopted under mod, not pc" do
    tree = Archetypes.seed()
    {:ok, admin} = Object.create(:player, "Admin", %{parent_id: nil})
    {:ok, _} = Object.set_property(admin.id, "admin", true)

    :ok = Archetypes.adopt_existing(tree)

    assert Object.get(admin.id).parent_id == tree.mod.id
  end

  test "legacy direct wieldable items are normalized once" do
    tree = Archetypes.seed()

    {:ok, legacy} =
      Object.create(:item, "legacy wrench", %{parent_id: tree.wieldable.id})

    :ok = Archetypes.normalize_legacy_item_parents(tree)
    assert Object.get(legacy.id).parent_id == tree.item.id

    {:ok, explicit} =
      Object.create(:item, "explicit baton", %{parent_id: tree.wieldable.id})

    :ok = Archetypes.normalize_legacy_item_parents(tree)
    assert Object.get(explicit.id).parent_id == tree.wieldable.id
  end
end
