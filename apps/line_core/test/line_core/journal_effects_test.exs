defmodule LineCore.Journal.EffectsTest do
  use ExUnit.Case, async: true
  alias LineCore.Journal.Effects

  test "projects mechanics and resolves generated identities without text or secrets" do
    events = [
      {:create_object, :box, %{name: "private name"}},
      {:set_property, {:created, :box}, "password_hash", "secret hash"},
      {:set_property, {:created, :box}, "hp", 12},
      {:move, {:created, :box}, "room-id", :contains},
      {:notify_actor, "private message"},
      {:notify_room, "private chat", except: ["actor-id"]}
    ]

    projected = Effects.project(events, %{{:create_object, :box} => %{id: "box-id"}})
    assert Enum.map(projected, & &1["index"]) == Enum.to_list(0..5)
    assert Enum.at(projected, 1)["value_omitted"]
    assert Enum.at(projected, 2)["value"] == 12
    assert Enum.at(projected, 3)["object_id"] == "box-id"
    encoded = Jason.encode!(projected)
    refute encoded =~ "private"
    refute encoded =~ "secret hash"
  end

  test "anonymous creates acquire stable internal references before execution" do
    [event] = Effects.prepare([{:create_object, %{name: "box"}}])
    assert {:create_object, {:journal, 0}, _} = event

    assert [%{"object_id" => "new-id"}] =
             Effects.project([event], %{{:create_object, {:journal, 0}} => %{id: "new-id"}})
  end
end
