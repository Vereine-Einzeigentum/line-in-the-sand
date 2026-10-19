defmodule LineCore.ObjectVerbDispatchTest do
  use ExUnit.Case, async: false

  alias LineCore.{Archetypes, CommandRouter, Parser, Repo, TestHarness, VerbSearch}

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    tree = Archetypes.seed()
    {:ok, tree: tree}
  end

  test "ordinary game verbs are no longer parser-registry commands" do
    map = Parser.verb_map()

    refute Map.has_key?(map, "look")
    refute Map.has_key?(map, "get")
    refute Map.has_key?(map, "wield")
    refute Map.has_key?(map, "attack")

    assert Map.has_key?(map, "who")
    assert Map.has_key?(map, "@password")
  end

  test "look is found through actor ancestry on root", %{tree: tree} do
    room = TestHarness.spawn_room("Hub")
    player = TestHarness.spawn_player_in(room, "Alice")
    :ok = Archetypes.adopt_existing(tree)

    assert :ok = CommandRouter.dispatch(player.id, "look self")
    TestHarness.assert_msg(~r/Alice/)
  end

  test "wield is found on direct object's wieldable ancestry", %{tree: tree} do
    room = TestHarness.spawn_room("Hub")
    player = TestHarness.spawn_player_in(room, "Alice")
    knife =
      TestHarness.spawn_item_in(player, "knife", %{parent_id: tree.weapon.id})

    :ok = Archetypes.adopt_existing(tree)

    assert {:ok, command} = Parser.parse_world("wield knife")
    assert {:ok, match} = VerbSearch.resolve(player.id, command)

    assert match.origin.id == knife.id
    assert match.defined_on.id == tree.wieldable.id
    assert match.verb_name == "wield"
  end

  test "generic items do not inherit wield, but do inherit scrap", %{tree: tree} do
    room = TestHarness.spawn_room("Hub")
    player = TestHarness.spawn_player_in(room, "Alice")
    cup = TestHarness.spawn_item_in(player, "coffee cup")

    assert cup.parent_id == tree.item.id

    assert {:ok, wield_command} = Parser.parse_world("wield coffee cup")
    assert {:error, :no_matching_verb} = VerbSearch.resolve(player.id, wield_command)

    assert {:ok, scrap_command} = Parser.parse_world("scrap coffee cup")
    assert {:ok, scrap_match} = VerbSearch.resolve(player.id, scrap_command)
    assert scrap_match.origin.id == cup.id
    assert scrap_match.defined_on.id == tree.item.id
    assert scrap_match.verb_name == "scrap"
  end

  test "verb search order prefers actor before room before direct object", %{tree: tree} do
    room = TestHarness.spawn_room("Hub")
    player = TestHarness.spawn_player_in(room, "Alice")
    item = TestHarness.spawn_item_in(room, "switch")
    :ok = Archetypes.adopt_existing(tree)

    {:ok, actor_verb} =
      LineCore.VerbStore.attach(player.id, tree.verb.id, %{
        name: "probe",
        module: "look",
        dobj: "any",
        prep: "none",
        iobj: "none",
        arg_mode: "target_optional"
      })

    {:ok, _room_verb} =
      LineCore.VerbStore.attach(room.id, tree.verb.id, %{
        name: "probe",
        module: "look",
        dobj: "any",
        prep: "none",
        iobj: "none",
        arg_mode: "target_optional"
      })

    {:ok, _object_verb} =
      LineCore.VerbStore.attach(item.id, tree.verb.id, %{
        name: "probe",
        module: "look",
        dobj: "this",
        prep: "none",
        iobj: "none",
        arg_mode: "target_optional"
      })

    assert {:ok, command} = Parser.parse_world("probe switch")
    assert {:ok, match} = VerbSearch.resolve(player.id, command)
    assert match.verb.id == actor_verb.id
    assert match.origin.id == player.id
  end

  test "aliases live on verb objects rather than the parser map", %{tree: tree} do
    room = TestHarness.spawn_room("Hub")
    player = TestHarness.spawn_player_in(room, "Alice")
    :ok = Archetypes.adopt_existing(tree)

    assert {:ok, command} = Parser.parse_world("l self")
    assert {:ok, match} = VerbSearch.resolve(player.id, command)
    assert match.verb_name == "look"
    assert match.defined_on.id == tree.root.id
  end
  test "ordinary verb names support two-character MOO abbreviation while dot socials bypass it" do
    room = TestHarness.spawn_room("Hub")
    alice = TestHarness.spawn_player_in(room, "Alice")
    bob = TestHarness.spawn_player_in(room, "Bob")

    assert {:ok, command} = Parser.parse_world("hi Bob")
    assert {:ok, match} = VerbSearch.resolve(alice.id, command)
    assert match.verb_name == "attack"
    assert match.context.dobj.id == bob.id

    assert {:ok, LineCore.Verbs.Social, ["hi"]} = Parser.parse(".hi")
  end
end
