defmodule LineCore.JournalTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias LineCore.{Dispatcher, Journal, Object, PubSub, Repo}
  alias LineCore.Journal.Entry

  defmodule Increment do
    @behaviour LineCore.Verb
    def execute(ctx, _) do
      value = Object.get_property(ctx.actor.id, "count", 0) + 1
      {:ok, [{:set_property, ctx.actor.id, "count", value}, {:notify_actor, "counted"}]}
    end
  end

  defmodule Broken do
    @behaviour LineCore.Verb
    def execute(ctx, _) do
      {:ok,
       [
         {:set_property, ctx.actor.id, "count", 99},
         {:set_property, "00000000-0000-0000-0000-000000000000", "invalid", true},
         {:notify_actor, "must not arrive"}
       ]}
    end
  end

  defmodule Refuse do
    @behaviour LineCore.Verb
    def execute(_, _), do: {:error, {:denied, "private diagnostic payload"}}
  end

  setup tags do
    # Concurrent workers need committed fixtures and independent transactions.
    Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: !tags[:unboxed])
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    {:ok, room} = Object.create(:room, "Journal room")
    {:ok, actor} = Object.create(:player, "Journal player")
    Object.relate(room.id, actor.id, :contains)
    PubSub.subscribe({:actor, actor.id})

    on_exit(fn ->
      Repo.delete_all(from(e in Entry, where: e.actor_id == ^actor.id))
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    %{actor: actor, room: room}
  end

  test "successful commands journal structured effects and unknown context explicitly", ctx do
    assert :ok = Dispatcher.dispatch(ctx.actor.id, Increment, [], "raw secret")

    assert [%{position: 1, schema_version: 1, outcome: "applied"} = entry] =
             Journal.export(ctx.actor.id)

    assert entry.location_id == ctx.room.id
    assert entry.session_id == nil
    assert entry.faction_id == nil
    assert entry.content_id == nil
    assert entry.elapsed_us == nil
    assert entry.data["effects"] |> hd() |> Map.get("value") == 1
    refute Jason.encode!(entry) =~ "raw secret"
    assert_receive {:msg, "counted"}
  end

  test "late event failure rolls back mutation and success history", ctx do
    assert {:error, _} = Dispatcher.dispatch(ctx.actor.id, Broken, [], "broken")
    assert Object.get_property(ctx.actor.id, "count") == nil
    assert Journal.export(ctx.actor.id) == []
    refute_receive {:msg, _}
  end

  test "journal persistence failure rolls back game state and notifications", ctx do
    # Fault injection at the last write in the same transaction.
    Repo.query!(
      "ALTER TABLE play_journal ADD CONSTRAINT journal_fault CHECK (actor_id <> '#{ctx.actor.id}')"
    )

    try do
      assert_raise Ecto.ConstraintError, fn ->
        Dispatcher.dispatch(ctx.actor.id, Increment, [], "increment")
      end

      assert Object.get_property(ctx.actor.id, "count") == nil
      assert Journal.export(ctx.actor.id) == []
      refute_receive {:msg, _}
    after
      Repo.query!("ALTER TABLE play_journal DROP CONSTRAINT journal_fault")
    end
  end

  test "refusals are diagnostic outcomes without invented gameplay effects", ctx do
    assert {:error, {:denied, _}} = Dispatcher.dispatch(ctx.actor.id, Refuse, [], "refuse")
    assert [%{outcome: "rejected", data: data}] = Journal.export(ctx.actor.id)
    assert data["reason"] == "denied"
    refute Map.has_key?(data, "effects")
    refute Jason.encode!(data) =~ "private"
  end

  test "session intervals, disconnect idempotence, and reconnect stay explicit", ctx do
    assert {:ok, first} = Journal.open_session(ctx.actor.id, :game_channel)
    assert :ok = Dispatcher.dispatch(ctx.actor.id, Increment, [], "increment", session_id: first)
    assert {:ok, :ok} = Journal.close_session(ctx.actor.id, first)
    assert {:ok, :ok} = Journal.close_session(ctx.actor.id, first)
    assert {:ok, second} = Journal.open_session(ctx.actor.id, :player_channel)
    assert first != second
    entries = Journal.export(ctx.actor.id)
    assert Enum.map(entries, & &1.event_type) == ["LOGIN", "COMMAND", "DISCONNECT", "LOGIN"]
    assert Enum.map(entries, & &1.session_position) == [1, 2, 3, 1]
    assert Enum.at(entries, 1).session_elapsed_us >= 0
    assert Enum.at(entries, 3).session_elapsed_us == nil
    assert Enum.at(entries, 3).elapsed_us >= 0
    refute Jason.encode!(entries) =~ "QUIT"
  end

  test "closed, unknown, or another actor's sessions cannot authorize a dispatch", ctx do
    {:ok, id} = Journal.open_session(ctx.actor.id, :game_channel)
    {:ok, other} = Object.create(:player, "Other")
    Object.relate(ctx.room.id, other.id, :contains)

    assert {:error, :invalid_play_session} =
             Dispatcher.dispatch(other.id, Increment, [], "x", session_id: id)

    Journal.close_session(ctx.actor.id, id)

    for session <- [id, Ecto.UUID.generate(), "malformed"] do
      assert {:error, :invalid_play_session} =
               Dispatcher.dispatch(ctx.actor.id, Increment, [], "x", session_id: session)
    end

    assert Object.get_property(ctx.actor.id, "count") == nil
    assert Object.get_property(other.id, "count") == nil
  end

  @tag :unboxed
  test "concurrent commands share committed actor order and cannot lose read-modify-write", ctx do
    tasks =
      for _ <- 1..6,
          do: Task.async(fn -> Dispatcher.dispatch(ctx.actor.id, Increment, [], "increment") end)

    assert Enum.map(tasks, &Task.await/1) == List.duplicate(:ok, 6)
    assert Object.get_property(ctx.actor.id, "count") == 6
    entries = Journal.export(ctx.actor.id)
    assert Enum.map(entries, & &1.position) == Enum.to_list(1..6)
    assert Enum.map(entries, &hd(&1.data["effects"])["value"]) == Enum.to_list(1..6)
  end

  test "paged export is repeatable and repeated commands remain distinct", ctx do
    for _ <- 1..3, do: Dispatcher.dispatch(ctx.actor.id, Increment, [], "same command")
    page = Journal.export(ctx.actor.id, 0, 2)
    assert page == Journal.export(ctx.actor.id, 0, 2)
    rest = Journal.export(ctx.actor.id, List.last(page).position, 2)
    assert Enum.map(page ++ rest, & &1.position) == [1, 2, 3]
    assert length(Enum.uniq_by(page ++ rest, & &1.id)) == 3
  end

  test "ordinary dispatch refuses an outer transaction before publishing", ctx do
    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               assert {:error, :nested_enactment} =
                        Dispatcher.dispatch(ctx.actor.id, Increment, [], "x")

               Repo.rollback(:cancelled)
             end)

    assert Journal.export(ctx.actor.id) == []
    refute_receive {:msg, _}
  end
end
