defmodule LineCore.GenesisTest do
  use ExUnit.Case, async: false

  alias LineCore.{Genesis, Object, Repo}
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

  ## plan/1 — pure, no DB needed for pre-resolved specs

  describe "plan/1" do
    test "returns a pre-generated UUID and event list" do
      {:ok, %{id: id, events: events}} =
        Genesis.plan(%{name: "a crate", type: :item})

      assert is_binary(id)
      assert {:ok, _} = Ecto.UUID.cast(id)
      assert [{:create_object, attrs} | _] = events
      assert attrs.id == id
      assert attrs.type == :item
      assert attrs.name == "a crate"
    end

    test "includes a :create_object event with all provided schema fields" do
      {:ok, weapon} = Object.create(:generic, "Blade Generic")

      {:ok, %{events: events}} =
        Genesis.plan(%{
          name: "rusty knife",
          type: :item,
          template: weapon,
          description: "Chipped at the edge.",
          verbs: ["get"]
        })

      [{:create_object, attrs} | _] = events
      assert attrs.name == "rusty knife"
      assert attrs.description == "Chipped at the edge."
      assert attrs.verbs == ["get"]
      assert attrs.parent_id == weapon.id
    end

    test "emits :set_property events for each property" do
      {:ok, %{id: id, events: events}} =
        Genesis.plan(%{
          name: "pipe",
          type: :item,
          properties: %{scrap_value: 12, tag: "scrap"}
        })

      prop_events = Enum.filter(events, &match?({:set_property, _, _, _}, &1))
      assert length(prop_events) == 2

      assert {:set_property, ^id, "scrap_value", 12} in prop_events
      assert {:set_property, ^id, "tag", "scrap"} in prop_events
    end

    test "emits a :relate event when place_in is provided" do
      {:ok, room} = Object.create(:room, "Hub")

      {:ok, %{id: id, events: events}} =
        Genesis.plan(%{name: "thing", type: :item, place_in: room.id})

      assert {:relate, room.id, ^id, :contains} in events
    end

    test "property keys are stringified" do
      {:ok, %{id: id, events: events}} =
        Genesis.plan(%{name: "x", type: :item, properties: %{damage: 5}})

      assert {:set_property, ^id, "damage", 5} in events
    end

    test "returns error when name is missing" do
      assert {:error, {:missing_required_field, :name}} = Genesis.plan(%{type: :item})
    end

    test "returns error when name is empty" do
      assert {:error, :name_empty} = Genesis.plan(%{name: "", type: :item})
    end

    test "returns error when type is missing" do
      assert {:error, :type_required} = Genesis.plan(%{name: "thing"})
    end

    test "returns error when template is an unresolved atom" do
      assert {:error, {:template_not_resolved, :weapon}} =
               Genesis.plan(%{name: "thing", type: :item, template: :weapon})
    end
  end

  ## create/1 — integration tests with DB

  describe "create/1 — no template" do
    test "creates an object with the given type and name" do
      {:ok, obj} = Genesis.create(%{name: "a box", type: :item})

      assert obj.type == :item
      assert obj.name == "a box"
      assert obj.parent_id == nil
    end

    test "sets properties atomically with the object" do
      {:ok, obj} = Genesis.create(%{name: "pipe", type: :item, properties: %{scrap_value: 15}})

      assert Object.get_property(obj.id, "scrap_value") == 15
    end

    test "places object in container when place_in is given" do
      {:ok, room} = Object.create(:room, "Hub")

      {:ok, obj} = Genesis.create(%{name: "crate", type: :item, place_in: room.id})

      assert %{id: ^room.id} = Object.container_of(obj.id)
    end

    test "all-or-nothing: invalid place_in rolls back the object too" do
      fake_room_id = Ecto.UUID.generate()

      assert {:error, _} =
               Genesis.create(%{name: "ghost", type: :item, place_in: fake_room_id})

      # Object must not exist — the transaction rolled back
      assert [] = Repo.all(LineCore.Schemas.Object)
    end
  end

  describe "create/1 — with atom template (requires seeded generics)" do
    setup do
      Generics.seed()
      :ok
    end

    test "resolves :weapon template and sets parent_id" do
      {:ok, knife} = Genesis.create(%{name: "rusty knife", template: :weapon})

      weapon_generic = Object.get(knife.parent_id)
      assert weapon_generic.name == "Weapon"
      assert knife.type == :item
    end

    test "inherits damage default from Weapon generic" do
      {:ok, knife} = Genesis.create(%{name: "rusty knife", template: :weapon})

      assert Object.get_property(knife.id, "damage") == 3
    end

    test "own property shadows the inherited generic default" do
      {:ok, crowbar} =
        Genesis.create(%{name: "crowbar", template: :weapon, properties: %{damage: 18}})

      assert Object.get_property(crowbar.id, "damage") == 18
    end

    test "type derived from instance_type when not stated" do
      # :scrap has instance_type "item"
      {:ok, obj} = Genesis.create(%{name: "wire", template: :scrap})
      assert obj.type == :item
    end

    test "explicit type wins over instance_type" do
      # Force a different type (unusual but must not silently ignore it)
      {:ok, obj} = Genesis.create(%{name: "x", type: :item, template: :room})
      assert obj.type == :item
    end

    test "abstract generic returns :abstract_generic error" do
      # :mob has no instance_type — spawning from it is forbidden
      assert {:error, :abstract_generic} = Genesis.create(%{name: "creature", template: :mob})
    end

    test "unknown atom returns error" do
      assert {:error, {:unknown_generic_ref, :dragon}} =
               Genesis.create(%{name: "dragon", template: :dragon})
    end

    test "a seeded crowbar has wield via effective_verbs/1" do
      {:ok, crowbar} =
        Genesis.create(%{name: "bent crowbar", template: :weapon, properties: %{damage: 18}})

      verbs = Object.effective_verbs(crowbar.id)
      assert "wield" in verbs
      assert "unwield" in verbs
    end

    test "a spawned PC has hp_max without setting it" do
      {:ok, player} = Genesis.create(%{name: "Tester", template: :pc})

      assert Object.get_property(player.id, "hp_max") == 20
      assert Object.get_property(player.id, "dirham") == 0
    end
  end

  ## create!/1

  describe "create!/1" do
    test "returns the object on success" do
      obj = Genesis.create!(%{name: "thing", type: :item})
      assert obj.type == :item
    end

    test "raises on error" do
      assert_raise RuntimeError, ~r/Genesis.create! failed/, fn ->
        Genesis.create!(%{type: :item})
      end
    end
  end

  ## create_many/1

  describe "create_many/1" do
    test "creates multiple objects in one transaction" do
      {:ok, [a, b]} =
        Genesis.create_many([
          %{name: "Alpha", type: :item},
          %{name: "Beta", type: :item}
        ])

      assert a.name == "Alpha"
      assert b.name == "Beta"
      assert Object.get(a.id) != nil
      assert Object.get(b.id) != nil
    end

    test "rolls back all objects if one fails" do
      initial_count = Repo.aggregate(LineCore.Schemas.Object, :count)

      fake_room_id = Ecto.UUID.generate()

      result =
        Genesis.create_many([
          %{name: "Good", type: :item},
          %{name: "Bad", type: :item, place_in: fake_room_id}
        ])

      assert {:error, _} = result
      assert Repo.aggregate(LineCore.Schemas.Object, :count) == initial_count
    end
  end

  ## Readable helpers

  describe "room!/2" do
    setup do
      Generics.seed()
      :ok
    end

    test "creates a room with type: :room and template: :room" do
      room = Genesis.room!("Lobby", description: "A concrete antechamber.")
      assert room.type == :room
      assert room.name == "Lobby"
      assert room.description == "A concrete antechamber."
      # parent_id should point to the Room generic
      assert room.parent_id != nil
    end

    test "inherits go verb from Room generic" do
      room = Genesis.room!("Test Room")
      assert "go" in Object.effective_verbs(room.id)
    end
  end

  describe "item!/3" do
    test "creates an item placed in the given container" do
      {:ok, room} = Object.create(:room, "Hub")
      item = Genesis.item!(room, "scrap heap", description: "A pile of junk.")

      assert item.type == :item
      assert item.name == "scrap heap"
      assert %{id: room_id} = Object.container_of(item.id)
      assert room_id == room.id
    end

    test "with template: :weapon inherits wield verb" do
      Generics.seed()
      {:ok, room} = Object.create(:room, "Hub")
      weapon = Genesis.item!(room, "pipe", template: :weapon, properties: %{damage: 7})

      assert "wield" in Object.effective_verbs(weapon.id)
      assert Object.get_property(weapon.id, "damage") == 7
    end
  end

  describe "npc!/3" do
    setup do
      Generics.seed()
      :ok
    end

    test "creates an NPC placed in the given container" do
      {:ok, room} = Object.create(:room, "Shop")
      npc = Genesis.npc!(room, "Hamid", description: "A fence.")

      assert npc.type == :npc
      assert npc.name == "Hamid"
      assert %{id: room_id} = Object.container_of(npc.id)
      assert room_id == room.id
    end

    test "inherits attack verb from Mob via ancestry" do
      {:ok, room} = Object.create(:room, "Hub")
      npc = Genesis.npc!(room, "Guard")
      assert "attack" in Object.effective_verbs(npc.id)
    end
  end

  describe "player!/2" do
    setup do
      Generics.seed()
      :ok
    end

    test "creates a player with type: :player and PC template" do
      player = Genesis.player!("Alice")
      assert player.type == :player
      assert player.name == "Alice"
    end

    test "inherits hp_max and dirham from PC ancestry" do
      player = Genesis.player!("Bob")
      assert Object.get_property(player.id, "hp_max") == 20
      assert Object.get_property(player.id, "dirham") == 0
    end

    test "can be placed in a room via place_in opt" do
      {:ok, room} = Object.create(:room, "Spawn")
      player = Genesis.player!("Charlie", place_in: room.id)

      assert %{id: room_id} = Object.container_of(player.id)
      assert room_id == room.id
    end
  end
end
