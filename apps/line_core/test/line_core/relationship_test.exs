defmodule LineCore.RelationshipTest do
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

  test "exits with directions are queryable" do
    {:ok, a} = Object.create(:room, "Room A")
    {:ok, b} = Object.create(:room, "Room B")
    {:ok, c} = Object.create(:room, "Room C")

    Object.relate(a.id, b.id, :exit_to, %{"direction" => "north"})
    Object.relate(b.id, a.id, :exit_to, %{"direction" => "south"})
    Object.relate(b.id, c.id, :exit_to, %{"direction" => "east"})

    a_exits = Object.exits(a.id)
    assert length(a_exits) == 1
    assert {"north", %{id: b_id}} = hd(a_exits)
    assert b_id == b.id

    b_exits = Object.exits(b.id)
    assert length(b_exits) == 2
  end

  test "exit resolution handles direction aliases" do
    {:ok, a} = Object.create(:room, "Room A")
    {:ok, b} = Object.create(:room, "Room B")

    Object.relate(a.id, b.id, :exit_to, %{"direction" => "north"})

    # Both "n" and "north" should resolve
    assert %{id: id1} = Object.resolve_exit(a.id, "n")
    assert id1 == b.id

    assert %{id: id2} = Object.resolve_exit(a.id, "north")
    assert id2 == b.id

    assert %{id: id3} = Object.resolve_exit(a.id, "NORTH")
    assert id3 == b.id

    # Nonexistent direction returns nil
    assert nil == Object.resolve_exit(a.id, "south")
  end

  test "contents query returns objects in container" do
    {:ok, room} = Object.create(:room, "Test Room")
    {:ok, item1} = Object.create(:item, "Knife")
    {:ok, item2} = Object.create(:item, "Rope")
    {:ok, npc} = Object.create(:npc, "Stranger")

    Object.relate(room.id, item1.id, :contains)
    Object.relate(room.id, item2.id, :contains)
    Object.relate(room.id, npc.id, :contains)

    contents = Object.contents(room.id)

    assert length(contents) == 3
    names = Enum.map(contents, & &1.name) |> Enum.sort()
    assert names == ["Knife", "Rope", "Stranger"]
  end

  test "move atomically changes container" do
    {:ok, room_a} = Object.create(:room, "Room A")
    {:ok, room_b} = Object.create(:room, "Room B")
    {:ok, player} = Object.create(:player, "Player")

    Object.relate(room_a.id, player.id, :contains)
    assert %{id: a_id} = Object.container_of(player.id)
    assert a_id == room_a.id

    {:ok, _} = Object.move(player.id, room_b.id)

    assert %{id: b_id} = Object.container_of(player.id)
    assert b_id == room_b.id

    # Player should no longer be in room_a
    refute Enum.any?(Object.contents(room_a.id), &(&1.id == player.id))
    assert Enum.any?(Object.contents(room_b.id), &(&1.id == player.id))
  end

  test "soft-deleted objects don't appear in queries" do
    {:ok, room} = Object.create(:room, "Test Room")
    {:ok, item} = Object.create(:item, "Doomed Item")
    Object.relate(room.id, item.id, :contains)

    assert length(Object.contents(room.id)) == 1

    Repo.update!(LineCore.Schemas.Object.changeset(item, %{deleted_at: DateTime.utc_now()}))

    assert Object.contents(room.id) == []
    assert Object.get(item.id) == nil
  end
end
