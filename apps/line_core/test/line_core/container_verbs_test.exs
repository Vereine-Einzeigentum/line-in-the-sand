defmodule LineCore.ContainerVerbsTest do
  use ExUnit.Case, async: false

  alias LineCore.{Archetypes, CommandRouter, Object, Repo, TestHarness}

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    tree = Archetypes.seed()
    room = TestHarness.spawn_room("Morgue")
    player = TestHarness.spawn_player_in(room, "Alice")

    {:ok, corpse} =
      Object.create(:item, "corpse of Bob", %{parent_id: tree.corpse.id})

    {:ok, _} = Object.relate(room.id, corpse.id, :contains)

    {:ok, coin} = Object.create(:item, "bent coin")
    {:ok, _} = Object.relate(player.id, coin.id, :contains)

    {:ok, tree: tree, room: room, player: player, corpse: corpse, coin: coin}
  end

  test "put moves a carried object into a container through inherited container verb", ctx do
    assert :ok = CommandRouter.dispatch(ctx.player.id, "put bent coin in corpse")

    assert Object.container_of(ctx.coin.id).id == ctx.corpse.id
    TestHarness.assert_msg(~r/put the bent coin in the corpse of Bob/i)
  end

  test "get from resolves an object nested inside the indirect container", ctx do
    :ok = Object.move(ctx.coin.id, ctx.corpse.id)

    assert :ok = CommandRouter.dispatch(ctx.player.id, "get bent coin from corpse")

    assert Object.container_of(ctx.coin.id).id == ctx.player.id
    TestHarness.assert_msg(~r/take the bent coin from the corpse of Bob/i)
  end

  test "ordinary items do not acquire container verbs", ctx do
    {:ok, rock} = Object.create(:item, "rock")
    {:ok, _} = Object.relate(ctx.room.id, rock.id, :contains)

    assert {:error, :unknown_verb} =
             CommandRouter.dispatch(ctx.player.id, "put bent coin in rock")

    assert Object.container_of(ctx.coin.id).id == ctx.player.id
  end

  test "a robot corpse can be locally locked without a special corpse subsystem", ctx do
    {:ok, robot_corpse} =
      Object.create(:item, "corpse of service bot", %{parent_id: ctx.tree.corpse.id})

    {:ok, _} = Object.relate(ctx.room.id, robot_corpse.id, :contains)
    {:ok, _} = Object.set_property(robot_corpse.id, "locked", true)
    :ok = Object.move(ctx.coin.id, robot_corpse.id)

    assert {:error, :container_locked} =
             CommandRouter.dispatch(ctx.player.id, "get bent coin from service bot")

    assert Object.container_of(ctx.coin.id).id == robot_corpse.id
  end

  test "containment cycles are rejected", ctx do
    {:ok, bag} =
      Object.create(:item, "bag", %{parent_id: ctx.tree.container.id})

    {:ok, _} = Object.relate(ctx.player.id, bag.id, :contains)
    :ok = Object.move(ctx.corpse.id, bag.id)

    assert {:error, :containment_cycle} =
             CommandRouter.dispatch(ctx.player.id, "put bag in corpse")

    assert Object.container_of(bag.id).id == ctx.player.id
  end
end
