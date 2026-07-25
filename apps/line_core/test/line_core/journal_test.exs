defmodule LineCore.JournalTest do
  use ExUnit.Case, async: false

  alias LineCore.{Dispatcher, Journal, Object, Repo}
  alias LineCore.Schemas.JournalEntry

  defmodule MarkVerb do
    @behaviour LineCore.Verb

    @impl true
    def execute(ctx, [target_id]) do
      {:ok,
       [
         {:set_property, target_id, "marked", true},
         {:notify_actor, "You mark the object."},
         {:notify_room, "#{ctx.actor.name} marks something.", except: [ctx.actor.id]}
       ]}
    end
  end

  defmodule FailVerb do
    @behaviour LineCore.Verb

    @impl true
    def execute(_ctx, _args), do: {:error, :nope}
  end

  defmodule BadVerb do
    @behaviour LineCore.Verb

    @impl true
    def execute(_ctx, _args) do
      {:ok, [{:set_property, "00000000-0000-0000-0000-000000000000", "test", "value"}]}
    end
  end

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.delete_all(JournalEntry)
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    :ok
  end

  test "a successful dispatch writes one journal entry with the full event list" do
    {:ok, room} = Object.create(:room, "Test Room")
    {:ok, alice} = Object.create(:player, "Alice")
    {:ok, item} = Object.create(:item, "Crate")
    Object.relate(room.id, alice.id, :contains)
    Object.relate(room.id, item.id, :contains)

    assert :ok = Dispatcher.dispatch(alice.id, MarkVerb, [item.id], "mark crate")

    assert [entry] = Repo.all(JournalEntry)
    assert entry.actor_id == alice.id
    assert entry.room_id == room.id
    assert entry.verb == "mark_verb"
    assert entry.raw == "mark crate"
    assert entry.args == %{"v" => [item.id]}

    assert %{"v" => [set_prop, notify_actor, notify_room]} = entry.events
    assert set_prop == %{"type" => "set_property", "args" => [item.id, "marked", true]}
    assert notify_actor == %{"type" => "notify_actor", "args" => ["You mark the object."]}

    assert notify_room == %{
             "type" => "notify_room",
             "args" => ["Alice marks something.", %{"except" => [alice.id]}]
           }
  end

  test "a verb error writes no journal entry" do
    {:ok, room} = Object.create(:room, "Test Room")
    {:ok, player} = Object.create(:player, "Player")
    Object.relate(room.id, player.id, :contains)

    assert {:error, :nope} = Dispatcher.dispatch(player.id, FailVerb, [], "fail")
    assert Repo.all(JournalEntry) == []
  end

  test "a failed transaction rolls back the journal entry with the events" do
    {:ok, room} = Object.create(:room, "Test Room")
    {:ok, player} = Object.create(:player, "Player")
    Object.relate(room.id, player.id, :contains)

    result = Dispatcher.dispatch(player.id, BadVerb, [], "bad")

    refute match?(:ok, result)
    assert Repo.all(JournalEntry) == []
  end

  test "journal entries preserve dispatch order" do
    {:ok, room} = Object.create(:room, "Test Room")
    {:ok, alice} = Object.create(:player, "Alice")
    {:ok, item} = Object.create(:item, "Crate")
    Object.relate(room.id, alice.id, :contains)
    Object.relate(room.id, item.id, :contains)

    assert :ok = Dispatcher.dispatch(alice.id, MarkVerb, [item.id], "first")
    assert :ok = Dispatcher.dispatch(alice.id, MarkVerb, [item.id], "second")

    import Ecto.Query
    raws = Repo.all(from(j in JournalEntry, order_by: j.id, select: j.raw))
    assert raws == ["first", "second"]
  end

  test "serialize/1 makes event payloads JSONB-safe" do
    assert Journal.serialize(:contains) == "contains"
    assert Journal.serialize(nil) == nil
    assert Journal.serialize(true) == true
    assert Journal.serialize(except: ["abc"]) == %{"except" => ["abc"]}
    assert Journal.serialize({:a, 1}) == ["a", 1]
    assert Journal.serialize(%{hp: 3}) == %{"hp" => 3}
  end

  test "verb_name/1 derives journal names from modules" do
    assert Journal.verb_name(LineCore.Verbs.Get) == "get"
    assert Journal.verb_name(LineCore.Verbs.Look) == "look"
  end
end
