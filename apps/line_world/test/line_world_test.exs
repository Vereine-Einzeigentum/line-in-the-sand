defmodule LineWorldTest do
  use ExUnit.Case, async: false
  alias LineCore.{Archetypes, Dispatcher, ItemSpec, Object, PubSub, Repo}
  alias LineWorld.{EventModel, Logic}

  defmodule BrokenDestination do
    @behaviour LineCore.Verb
    def execute(ctx, [consequence]) do
      decision = LineWorld.decide(consequence, ctx)
      EventModel.build(%{decision | actor_id: "00000000-0000-0000-0000-000000000000"})
    end
  end

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    Archetypes.seed()
    {:ok, room} = Object.create(:room, "Workshop")
    {:ok, actor} = Object.create(:player, "Maker")
    {:ok, _} = Object.relate(room.id, actor.id, :contains)
    {:ok, _} = Object.set_property(actor.id, "can_materialize_items", true)
    PubSub.subscribe({:actor, actor.id})

    spec =
      ItemSpec.new(["Weapon", "Flute", "Weather"], %{
        "name" => "a thunder flute",
        "powered" => false,
        "capacity" => 1000,
        "admin" => true
      })

    provenance = %{"source" => "test:completion", "reference" => "request-1"}
    {:ok, [consequence]} = Logic.derive(spec, provenance)
    %{actor: actor, spec: spec, consequence: consequence, provenance: provenance}
  end

  test "logic produces an inert proposal and enactment persists literal semantics", ctx do
    assert Object.contents(ctx.actor.id) == []
    assert :ok = LineWorld.enact(ctx.actor.id, ctx.consequence)
    assert [item] = Object.contents(ctx.actor.id)
    assert item.parent_id == Archetypes.get(:item).id
    assert item.name == "a thunder flute"
    assert Object.get_property(item.id, "semantic_spec") == ItemSpec.to_map(ctx.spec)
    assert Object.get_property(item.id, "semantic_provenance") == ctx.provenance
    assert Object.get_property(item.id, "admin") == nil
    assert_receive {:msg, "An item materializes in your inventory."}
  end

  test "unresolved fields defer without creating an item or publishing success", ctx do
    partial = %{ctx.spec | unknown: MapSet.new(["mass"])}
    {:ok, [proposal]} = Logic.derive(partial, ctx.provenance)

    assert {:error, {:deferred, {:unresolved_fields, ["mass"]}}} =
             LineWorld.enact(ctx.actor.id, proposal)

    assert Object.contents(ctx.actor.id) == []
    refute_receive {:msg, _}

    {:ok, completed} = ItemSpec.put_solved(partial, "mass", 12)
    {:ok, [proposal]} = Logic.derive(completed, ctx.provenance)
    assert :ok = LineWorld.enact(ctx.actor.id, proposal)
  end

  test "authorization is rechecked at execution, not inherited from a proposal", ctx do
    {:ok, _} = Object.set_property(ctx.actor.id, "can_materialize_items", false)
    assert {:error, {:rejected, :not_authorized}} = LineWorld.enact(ctx.actor.id, ctx.consequence)
    assert Object.contents(ctx.actor.id) == []
    refute_receive {:msg, _}
  end

  test "an unresolved display name can be completed without moving it into asserted facts", ctx do
    spec = ItemSpec.new(["Flute"], %{}, unknown: ["name"])
    {:ok, [proposal]} = Logic.derive(spec, ctx.provenance)

    assert {:error, {:deferred, {:unresolved_fields, ["name"]}}} =
             LineWorld.enact(ctx.actor.id, proposal)

    {:ok, spec} = ItemSpec.put_solved(spec, "name", "completed flute")
    {:ok, [proposal]} = Logic.derive(spec, ctx.provenance)
    assert :ok = LineWorld.enact(ctx.actor.id, proposal)
    assert [item] = Object.contents(ctx.actor.id)
    assert item.name == "completed flute"
    assert Object.get_property(item.id, "semantic_spec")["asserted"] == %{}
  end

  test "forged conflicting semantics and executable payloads are rejected", ctx do
    conflict = %{ctx.spec | solved: %{"capacity" => 30}}
    assert {:error, :conflicting_facts} = Logic.derive(conflict, ctx.provenance)

    assert {:error, {:rejected, :conflicting_facts}} =
             LineWorld.enact(ctx.actor.id, %{ctx.consequence | spec: conflict})

    assert {:error, {:rejected, :invalid_consequence}} =
             LineWorld.enact(ctx.actor.id, %{
               events: [{:set_property, ctx.actor.id, "admin", true}]
             })

    refute_receive {:msg, _}
  end

  test "a late database failure rolls back creation and suppresses notifications", ctx do
    before = Repo.aggregate(LineCore.Schemas.Object, :count)

    assert {:error, _} =
             Dispatcher.dispatch_transactional(
               ctx.actor.id,
               BrokenDestination,
               [ctx.consequence],
               "fault injection"
             )

    assert Repo.aggregate(LineCore.Schemas.Object, :count) == before
    assert Object.contents(ctx.actor.id) == []
    refute_receive {:msg, _}
  end

  test "Event Model refuses both non-enacted decisions and raw event lists", ctx do
    rejected = %LineWorld.Decision{
      status: :reject,
      reason: :denied,
      actor_id: ctx.actor.id,
      consequence: ctx.consequence
    }

    assert {:error, {:rejected, :denied}} = EventModel.build(rejected)
    assert {:error, :invalid_decision} = EventModel.build([{:notify_actor, "pretend"}])
  end

  test "an outer transaction cannot cause premature success notifications", ctx do
    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               assert {:error, :nested_enactment} = LineWorld.enact(ctx.actor.id, ctx.consequence)
               Repo.rollback(:cancelled)
             end)

    assert Object.contents(ctx.actor.id) == []
    refute_receive {:msg, _}
  end
end
