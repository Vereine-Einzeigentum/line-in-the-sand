defmodule LineCore.ContainmentTest do
  @moduledoc """
  Containment is about to stop being one level deep.

  A vehicle is a container with rooms inside it, and a clone vat is the same
  shape. That makes the containment chain a real graph walk rather than a
  single hop — and a graph walk with no cycle guard has no base case.
  """

  use ExUnit.Case, async: false

  alias LineCore.{Dispatcher, Object, Repo, TestHarness}

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.JournalEntry)
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    :ok
  end

  describe "container_chain/1" do
    test "walks enclosing containers innermost first" do
      room = TestHarness.spawn_room("Hub")
      crate = TestHarness.spawn_item_in(room, "crate")
      tin = TestHarness.spawn_item_in(crate, "tin")

      assert Object.container_chain(tin.id) == [crate.id, room.id]
      assert Object.container_chain(crate.id) == [room.id]
      assert Object.container_chain(room.id) == []
    end

    test "tolerates a cycle already present in the graph" do
      room = TestHarness.spawn_room("Hub")
      a = TestHarness.spawn_item_in(room, "a")
      b = TestHarness.spawn_item_in(a, "b")

      # Force a cycle behind the guard's back, the way bad data would arrive.
      Object.unrelate(room.id, a.id, :contains)
      {:ok, _} = Object.relate(b.id, a.id, :contains)

      # Degrades to a finite list rather than hanging.
      assert is_list(Object.container_chain(a.id))
      assert length(Object.container_chain(a.id)) <= 16
    end
  end

  describe "would_cycle?/3" do
    test "an object cannot contain itself" do
      room = TestHarness.spawn_room("Hub")
      crate = TestHarness.spawn_item_in(room, "crate")

      assert Object.would_cycle?(crate.id, crate.id)
    end

    test "an object cannot be moved into something it already contains" do
      room = TestHarness.spawn_room("Hub")
      truck = TestHarness.spawn_item_in(room, "truck")
      trailer = TestHarness.spawn_item_in(truck, "trailer")

      assert Object.would_cycle?(truck.id, trailer.id)
      refute Object.would_cycle?(trailer.id, room.id)
    end

    test "nesting depth does not matter" do
      room = TestHarness.spawn_room("Hub")
      a = TestHarness.spawn_item_in(room, "a")
      b = TestHarness.spawn_item_in(a, "b")
      c = TestHarness.spawn_item_in(b, "c")

      assert Object.would_cycle?(a.id, c.id)
    end
  end

  describe "Object.move/3" do
    test "refuses a self-move" do
      room = TestHarness.spawn_room("Hub")
      crate = TestHarness.spawn_item_in(room, "crate")

      assert {:error, :containment_cycle} = Object.move(crate.id, crate.id)
    end

    test "refuses driving a vehicle into its own trailer" do
      room = TestHarness.spawn_room("Hub")
      truck = TestHarness.spawn_item_in(room, "truck")
      trailer = TestHarness.spawn_item_in(truck, "trailer")

      assert {:error, :containment_cycle} = Object.move(truck.id, trailer.id)

      # The truck is where it was, and the chain still terminates.
      assert %{id: room_id} = Object.container_of(truck.id)
      assert room_id == room.id
      assert Object.container_chain(trailer.id) == [truck.id, room.id]
    end

    test "permits an ordinary move" do
      room = TestHarness.spawn_room("Hub")
      other = TestHarness.spawn_room("Yard")
      crate = TestHarness.spawn_item_in(room, "crate")

      assert {:ok, _} = Object.move(crate.id, other.id)
      assert %{id: id} = Object.container_of(crate.id)
      assert id == other.id
    end
  end

  describe "the dispatcher refuses cycles too" do
    test "a :move event that would cycle fails the transaction" do
      room = TestHarness.spawn_room("Hub")
      truck = TestHarness.spawn_item_in(room, "truck")
      trailer = TestHarness.spawn_item_in(truck, "trailer")

      result =
        Ecto.Multi.new()
        |> Dispatcher.apply_to_multi([{:move, truck.id, trailer.id, :contains}])
        |> Repo.transaction()

      assert {:error, _op, :containment_cycle, _changes} = result

      # Nothing moved.
      assert %{id: room_id} = Object.container_of(truck.id)
      assert room_id == room.id
    end

    test "an ordinary :move event still applies" do
      room = TestHarness.spawn_room("Hub")
      yard = TestHarness.spawn_room("Yard")
      crate = TestHarness.spawn_item_in(room, "crate")

      assert {:ok, _} =
               Ecto.Multi.new()
               |> Dispatcher.apply_to_multi([{:move, crate.id, yard.id, :contains}])
               |> Repo.transaction()

      assert %{id: id} = Object.container_of(crate.id)
      assert id == yard.id
    end
  end
end
