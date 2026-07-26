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

  # A spec that names its type and passes no atom template needs no reads at
  # all, which is what lets these assert on event shape alone.
  describe "plan/1 — event shape" do
    test "describes an object as one ordered event list" do
      {:ok, %{id: id, events: events}} =
        Genesis.plan(%{name: "a bent nail", type: :item, source: :hand})

      assert [{:create_object, attrs}, {:set_property, ^id, "source", "hand"}] = events
      assert attrs.id == id
      assert attrs.type == :item
      assert attrs.name == "a bent nail"
    end

    test "pre-generates the id and threads it through every later event" do
      {:ok, %{id: id, events: events}} =
        Genesis.plan(%{
          name: "twisted pipe",
          type: :item,
          place_in: "11111111-1111-1111-1111-111111111111",
          properties: %{scrap_value: 12, tag: "scrap"}
        })

      assert {:ok, _} = Ecto.UUID.cast(id)

      # Every event that has to name the object names the same id — which is
      # the whole reason the id is generated before anything is written.
      assert [
               {:create_object, %{id: ^id}},
               {:relate, "11111111-1111-1111-1111-111111111111", ^id, :contains},
               {:set_property, ^id, "scrap_value", 12},
               {:set_property, ^id, "tag", "scrap"},
               {:set_property, ^id, "source", "hand"}
             ] = events
    end

    test "property events are ordered deterministically" do
      spec = %{name: "x", type: :item, properties: %{zeta: 1, alpha: 2, mid: 3}}

      {:ok, %{events: first}} = Genesis.plan(spec)
      {:ok, %{events: second}} = Genesis.plan(spec)

      keys = fn events ->
        for {:set_property, _id, key, _v} <- events, key != "source", do: key
      end

      assert keys.(first) == ["alpha", "mid", "zeta"]
      assert keys.(first) == keys.(second)
    end

    test "omits a placement event when nothing places it" do
      {:ok, %{events: events}} = Genesis.plan(%{name: "loose bolt", type: :item})

      refute Enum.any?(events, &match?({:relate, _, _, _}, &1))
    end

    test "a plan is embeddable in a verb's event list" do
      {:ok, %{events: events}} = Genesis.plan(%{name: "spark", type: :item})

      # No event a verb may not emit; nothing here is a write or a broadcast.
      for event <- events do
        assert elem(event, 0) in [:create_object, :relate, :set_property]
      end
    end
  end

  describe "plan/1 — refusals" do
    test "refuses to conjure a player" do
      assert {:error, :player_creation_forbidden} =
               Genesis.plan(%{name: "Interloper", type: :player})
    end

    test "refuses a nameless or blank object" do
      assert {:error, :missing_name} = Genesis.plan(%{type: :item})
      assert {:error, :blank_name} = Genesis.plan(%{name: "   ", type: :item})
    end

    test "refuses a type it does not recognise" do
      assert {:error, {:unknown_type, :vehicle}} =
               Genesis.plan(%{name: "car", type: :vehicle})
    end

    test "refuses an unknown provenance" do
      assert {:error, {:unknown_source, :vibes}} =
               Genesis.plan(%{name: "x", type: :item, source: :vibes})
    end

    test "refuses to guess a type with nothing to derive it from" do
      assert {:error, :missing_type} = Genesis.plan(%{name: "x"})
    end

    test "refuses an unknown generic" do
      assert {:error, {:unknown_generic, :dragon}} =
               Genesis.plan(%{name: "x", template: :dragon})
    end
  end

  describe "type resolution" do
    setup do
      %{generics: Generics.seed()}
    end

    test "derives type from the template's instance_type" do
      {:ok, %{events: [{:create_object, attrs} | _]}} =
        Genesis.plan(%{name: "a grey rat", template: :npc})

      assert attrs.type == :npc
    end

    test "an explicit type always wins over the template's" do
      {:ok, %{events: [{:create_object, attrs} | _]}} =
        Genesis.plan(%{name: "a prop rat", template: :npc, type: :item})

      assert attrs.type == :item
    end

    test "never inherits :generic from the template it derives from", %{generics: g} do
      # The bug this replaces: spawn_from/3 defaulted to the generic's own
      # type, and a generic is :generic by construction.
      assert g.pc.type == :generic

      {:ok, %{events: [{:create_object, attrs} | _]}} =
        Genesis.plan(%{name: "Someone", template: :npc})

      refute attrs.type == :generic
    end

    test "refuses to derive a type from an abstract generic" do
      for abstract <- [:thing, :mob, :human, :agent] do
        assert {:error, :abstract_generic} =
                 Genesis.plan(%{name: "vague", template: abstract}),
               "expected #{abstract} to be abstract"
      end
    end

    test "an abstract generic is still usable when the type is stated" do
      {:ok, %{events: [{:create_object, attrs} | _]}} =
        Genesis.plan(%{name: "a crate", template: :thing, type: :item})

      assert attrs.type == :item
    end
  end

  describe "create/1" do
    setup do
      %{generics: Generics.seed()}
    end

    test "sets parent_id, writes properties as rows, and places the object" do
      room = Genesis.room!("Hub")

      {:ok, item} =
        Genesis.create(%{
          name: "bent crowbar",
          template: :weapon,
          place_in: room.id,
          properties: %{"damage" => 18}
        })

      assert item.type == :item
      refute is_nil(item.parent_id)

      assert Object.own_property(item.id, "damage") == 18
      assert %{id: room_id} = Object.container_of(item.id)
      assert room_id == room.id
    end

    test "records provenance" do
      {:ok, item} = Genesis.create(%{name: "shard", type: :item, source: :generated})

      assert Object.own_property(item.id, "source") == "generated"
    end

    test "defaults provenance to :hand" do
      {:ok, item} = Genesis.create(%{name: "shard", type: :item})

      assert Object.own_property(item.id, "source") == "hand"
    end

    test "a failure rolls the object row back with everything else" do
      before = Repo.aggregate(LineCore.Schemas.Object, :count)

      # A placement naming a container that does not exist violates the
      # relationship's foreign key, failing the transaction after the object
      # insert has already been staged.
      assert {:error, _reason} =
               Genesis.create(%{
                 name: "orphan",
                 type: :item,
                 place_in: Ecto.UUID.generate()
               })

      assert Repo.aggregate(LineCore.Schemas.Object, :count) == before
    end

    test "create!/1 raises rather than returning an error" do
      assert_raise ArgumentError, ~r/genesis failed/, fn ->
        Genesis.create!(%{name: "nope", type: :player})
      end
    end
  end

  describe "create_many/1" do
    setup do
      %{generics: Generics.seed()}
    end

    test "creates every spec in one transaction" do
      {:ok, [a, b, c]} =
        Genesis.create_many([
          %{name: "one", type: :item},
          %{name: "two", type: :item},
          %{name: "three", type: :item}
        ])

      assert Enum.map([a, b, c], & &1.name) == ["one", "two", "three"]
    end

    test "one bad spec fails the batch before anything is written" do
      before = Repo.aggregate(LineCore.Schemas.Object, :count)

      assert {:error, :player_creation_forbidden} =
               Genesis.create_many([
                 %{name: "fine", type: :item},
                 %{name: "Interloper", type: :player}
               ])

      assert Repo.aggregate(LineCore.Schemas.Object, :count) == before
    end
  end

  describe "helpers" do
    setup do
      %{generics: Generics.seed()}
    end

    test "room!/2 derives from Generic Room", %{generics: g} do
      room = Genesis.room!("Hub", description: "A cube.")

      assert room.type == :room
      assert room.parent_id == g.room.id
      assert room.description == "A cube."
    end

    test "item!/3 places the item and derives from Generic Thing", %{generics: g} do
      room = Genesis.room!("Hub")
      item = Genesis.item!(room, "a rag")

      assert item.type == :item
      assert item.parent_id == g.thing.id
      assert %{id: room_id} = Object.container_of(item.id)
      assert room_id == room.id
    end

    test "npc!/3 places the NPC and derives from Generic NPC", %{generics: g} do
      room = Genesis.room!("Hub")
      npc = Genesis.npc!(room, "Hamid")

      assert npc.type == :npc
      assert npc.parent_id == g.npc.id
    end

    test "player!/2 is the only door to a :player", %{generics: g} do
      player = Genesis.player!("Tester")

      assert player.type == :player
      assert player.parent_id == g.pc.id
    end

    test "helpers accept a raw container id" do
      room = Genesis.room!("Hub")
      item = Genesis.item!(room.id, "a rag")

      assert %{id: room_id} = Object.container_of(item.id)
      assert room_id == room.id
    end
  end

  # The point of all of it: inheritance reaching content a player can touch.
  describe "inheritance reaches real content" do
    setup do
      %{generics: Generics.seed()}
    end

    test "a weapon-derived item can be wielded without listing the verb" do
      room = Genesis.room!("Hub")

      crowbar =
        Genesis.item!(room, "bent crowbar", template: :weapon, properties: %{"damage" => 18})

      assert crowbar.verbs == []
      assert "wield" in Object.effective_verbs(crowbar.id)
      assert "unwield" in Object.effective_verbs(crowbar.id)
    end

    test "a scrap-derived item inherits a scrap value it never set" do
      room = Genesis.room!("Hub")
      junk = Genesis.item!(room, "twisted pipe", template: :scrap)

      assert Object.own_property(junk.id, "scrap_value") == nil
      assert Object.get_property(junk.id, "scrap_value") == 5
      assert "scrap" in Object.effective_verbs(junk.id)
    end

    test "editing a generic changes content already in the world" do
      room = Genesis.room!("Hub")
      junk = Genesis.item!(room, "twisted pipe", template: :scrap)
      generics = Generics.seed()

      Object.set_property(generics.scrap.id, "scrap_value", 99)

      assert Object.get_property(junk.id, "scrap_value") == 99
    end

    test "an object's own value still shadows the generic's" do
      room = Genesis.room!("Hub")

      junk =
        Genesis.item!(room, "shattered display",
          template: :scrap,
          properties: %{"scrap_value" => 18}
        )

      assert Object.get_property(junk.id, "scrap_value") == 18
    end
  end
end
