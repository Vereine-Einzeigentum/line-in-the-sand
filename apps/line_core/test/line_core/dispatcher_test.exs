defmodule LineCore.DispatcherTest do
  use ExUnit.Case, async: false

  alias LineCore.{Dispatcher, Object, PubSub, Repo}

  defmodule TestVerb do
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

  test "all three event types apply correctly in one dispatch" do
    {:ok, room} = Object.create(:room, "Test Room")
    {:ok, alice} = Object.create(:player, "Alice")
    {:ok, bob} = Object.create(:player, "Bob")
    {:ok, item} = Object.create(:item, "Crate")

    Object.relate(room.id, alice.id, :contains)
    Object.relate(room.id, bob.id, :contains)
    Object.relate(room.id, item.id, :contains)

    PubSub.subscribe({:actor, alice.id})
    PubSub.subscribe({:actor, bob.id})
    PubSub.subscribe({:room, room.id})

    assert :ok = Dispatcher.dispatch(alice.id, TestVerb, [item.id], "mark crate")

    # Property was set
    assert Object.get_property(item.id, "marked") == true

    # Alice received her direct message
    assert_receive {:msg, "You mark the object."}, 500

    # Room broadcast with except list
    assert_receive {:room_msg, "Alice marks something.", except}, 500
    assert alice.id in except
  end

  test "transactional failure rolls back all events" do
    {:ok, room} = Object.create(:room, "Test Room")
    {:ok, player} = Object.create(:player, "Player")
    Object.relate(room.id, player.id, :contains)

    defmodule BadVerb do
      @behaviour LineCore.Verb

      @impl true
      def execute(_ctx, _args) do
        {:ok,
         [
           {:set_property, "00000000-0000-0000-0000-000000000000", "test", "value"}
         ]}
      end
    end

    # Dispatch with a bogus object_id should fail the Multi
    result = Dispatcher.dispatch(player.id, BadVerb, [], "bad")

    refute match?(:ok, result)
  end

  test "verb returning error short-circuits dispatch" do
    {:ok, room} = Object.create(:room, "Test Room")
    {:ok, player} = Object.create(:player, "Player")
    Object.relate(room.id, player.id, :contains)

    defmodule FailVerb do
      @behaviour LineCore.Verb

      @impl true
      def execute(_ctx, _args), do: {:error, :nope}
    end

    PubSub.subscribe({:actor, player.id})

    assert {:error, :nope} = Dispatcher.dispatch(player.id, FailVerb, [], "fail")

    # No broadcast should have happened
    refute_receive {:msg, _}, 100
  end
end
