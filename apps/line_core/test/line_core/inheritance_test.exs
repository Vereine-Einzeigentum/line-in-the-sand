defmodule LineCore.InheritanceTest do
  use ExUnit.Case, async: false

  alias LineCore.{Object, Repo}
  alias LineCore.Seed.Generics

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

  describe "lineage" do
    test "walks the prototype chain nearest-first" do
      {:ok, root} = Object.create(:generic, "Root")
      {:ok, mid} = Object.create(:generic, "Mid", %{parent_id: root.id})
      {:ok, leaf} = Object.create(:item, "Leaf", %{parent_id: mid.id})

      assert Object.ancestors(leaf.id) == [mid.id, root.id]
      assert Object.lineage(leaf.id) == [leaf.id, mid.id, root.id]
      assert Object.ancestors(root.id) == []
    end

    test "a soft-deleted ancestor still supplies inherited values" do
      {:ok, generic} = Object.create(:generic, "Generic Crate")
      Object.set_property(generic.id, "capacity", 9)
      {:ok, crate} = Object.create(:item, "Crate", %{parent_id: generic.id})

      generic.id
      |> Object.get()
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
      |> Repo.update()

      # Deleting a generic must not silently strip every descendant's defaults.
      assert Object.get_property(crate.id, "capacity") == 9
    end
  end

  describe "property inheritance" do
    setup do
      {:ok, generic} = Object.create(:generic, "Generic Blade")
      Object.set_property(generic.id, "damage", 3)
      Object.set_property(generic.id, "material", "steel")
      {:ok, knife} = Object.create(:item, "knife", %{parent_id: generic.id})
      %{generic: generic, knife: knife}
    end

    test "inherits when not defined locally", %{knife: knife} do
      assert Object.get_property(knife.id, "damage") == 3
      assert Object.get_property(knife.id, "material") == "steel"
    end

    test "own value shadows the inherited one", %{knife: knife} do
      Object.set_property(knife.id, "damage", 7)

      assert Object.get_property(knife.id, "damage") == 7
      assert Object.own_property(knife.id, "damage") == 7
      assert Object.get_property(knife.id, "material") == "steel"
    end

    test "own_property/2 does not inherit", %{knife: knife} do
      assert Object.own_property(knife.id, "damage") == nil
    end

    test "changing the generic changes every descendant", %{generic: generic, knife: knife} do
      Object.set_property(generic.id, "damage", 11)
      assert Object.get_property(knife.id, "damage") == 11
    end

    test "nearest ancestor wins across a longer chain" do
      {:ok, a} = Object.create(:generic, "A")
      Object.set_property(a.id, "tone", "far")
      {:ok, b} = Object.create(:generic, "B", %{parent_id: a.id})
      Object.set_property(b.id, "tone", "near")
      {:ok, c} = Object.create(:item, "C", %{parent_id: b.id})

      assert Object.get_property(c.id, "tone") == "near"
    end

    test "defaults still apply when nothing in the chain defines the key", %{knife: knife} do
      assert Object.get_property(knife.id, "nonexistent", :fallback) == :fallback
    end

    test "properties/1 merges the chain, own values winning", %{generic: g, knife: knife} do
      Object.set_property(knife.id, "damage", 7)
      Object.set_property(knife.id, "edge", "chipped")

      props = Object.properties(knife.id)

      assert props["damage"] == 7
      assert props["material"] == "steel"
      assert props["edge"] == "chipped"
      assert Object.own_properties(knife.id) == %{"damage" => 7, "edge" => "chipped"}
      assert Object.properties(g.id) == %{"damage" => 3, "material" => "steel"}
    end
  end

  describe "verb inheritance" do
    test "effective verbs union the chain" do
      {:ok, root} = Object.create(:generic, "Root", %{verbs: ["look"]})
      {:ok, mid} = Object.create(:generic, "Mid", %{parent_id: root.id, verbs: ["get", "look"]})
      {:ok, leaf} = Object.create(:item, "Leaf", %{parent_id: mid.id, verbs: ["scrap"]})

      verbs = Object.effective_verbs(leaf.id)

      assert Enum.sort(verbs) == ["get", "look", "scrap"]
    end
  end

  describe "cycle safety" do
    test "an object cannot be its own parent" do
      {:ok, a} = Object.create(:generic, "A")

      assert {:error, :self_parent} = Object.set_parent(a.id, a.id)
    end

    test "a descendant cannot become its own ancestor's parent" do
      {:ok, a} = Object.create(:generic, "A")
      {:ok, b} = Object.create(:generic, "B", %{parent_id: a.id})
      {:ok, c} = Object.create(:generic, "C", %{parent_id: b.id})

      assert {:error, :cycle} = Object.set_parent(a.id, c.id)
    end

    test "set_parent/2 reparents and can clear" do
      {:ok, a} = Object.create(:generic, "A")
      Object.set_property(a.id, "k", "from-a")
      {:ok, b} = Object.create(:generic, "B")
      Object.set_property(b.id, "k", "from-b")
      {:ok, leaf} = Object.create(:item, "Leaf", %{parent_id: a.id})

      assert Object.get_property(leaf.id, "k") == "from-a"

      {:ok, _} = Object.set_parent(leaf.id, b.id)
      assert Object.get_property(leaf.id, "k") == "from-b"

      {:ok, _} = Object.set_parent(leaf.id, nil)
      assert Object.get_property(leaf.id, "k") == nil
    end
  end

  describe "spawn_from/3" do
    test "derives an object that inherits type and properties" do
      {:ok, generic} = Object.create(:generic, "Generic Rat", %{verbs: ["attack"]})
      Object.set_property(generic.id, "hp_max", 4)

      {:ok, rat} = Object.spawn_from(generic.id, "a grey rat", %{type: :npc})

      assert rat.type == :npc
      assert rat.parent_id == generic.id
      assert Object.get_property(rat.id, "hp_max") == 4
      assert "attack" in Object.effective_verbs(rat.id)
    end

    test "reports a missing generic" do
      assert {:error, :generic_not_found} =
               Object.spawn_from(Ecto.UUID.generate(), "orphan")
    end
  end

  describe "generics seed" do
    test "is idempotent and wires the chain" do
      first = Generics.seed()
      second = Generics.seed()

      assert first.mother.id == second.mother.id
      assert first.pc.id == second.pc.id

      # PC derives from Human derives from Mob derives from the mother.
      assert Object.ancestors(first.pc.id) == [
               first.human.id,
               first.mob.id,
               first.mother.id
             ]
    end

    test "a spawned player inherits combat defaults and verbs" do
      g = Generics.seed()

      {:ok, player} = Object.spawn_from(g.pc.id, "Tester", %{type: :player})

      assert Object.get_property(player.id, "hp_max") == 20
      assert Object.get_property(player.id, "dirham") == 0

      verbs = Object.effective_verbs(player.id)
      assert "attack" in verbs
      assert "score" in verbs
      assert "look" in verbs
    end

    test "leaf generics declare instance_type; abstract generics do not" do
      g = Generics.seed()

      assert Object.get_property(g.pc.id, "instance_type") == "player"
      assert Object.get_property(g.npc.id, "instance_type") == "npc"
      assert Object.get_property(g.room.id, "instance_type") == "room"
      assert Object.get_property(g.weapon.id, "instance_type") == "item"
      assert Object.get_property(g.scrap.id, "instance_type") == "item"

      # Abstract intermediates have no instance_type
      assert Object.get_property(g.mob.id, "instance_type") == nil
      assert Object.get_property(g.human.id, "instance_type") == nil
      assert Object.get_property(g.thing.id, "instance_type") == nil
    end

    test "generics stay out of containment and so never render in a room" do
      g = Generics.seed()

      assert Object.container_of(g.mother.id) == nil
      assert Object.container_of(g.pc.id) == nil
    end
  end
end
