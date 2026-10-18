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
    assert first.motile.parent_id == first.root.id
    assert first.mob.parent_id == first.motile.id
    assert first.pc.parent_id == first.mob.id
    assert first.npc.parent_id == first.mob.id
    assert first.mod.parent_id == first.motile.id
    assert first.mod.parent_id != first.mob.id
    assert first.wieldable.parent_id == first.root.id
    assert first.verb.parent_id == first.root.id
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
    assert Object.get(item.id).parent_id == tree.wieldable.id
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
end
