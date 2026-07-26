defmodule LineWebWeb.PlaytestControllerRawTest do
  use LineWebWeb.ConnCase, async: false

  alias LineCore.{Object, Repo, TestHarness}

  @playtest_token "test-token-raw"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    System.put_env("PLAYTEST_TOKEN", @playtest_token)
    LineCore.Seed.Generics.seed()

    on_exit(fn ->
      System.delete_env("PLAYTEST_TOKEN")
      System.delete_env("PLAYTEST_STARTING_ROOM_ID")
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    :ok
  end

  defp auth(conn),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> @playtest_token)

  test "POST /cmd with raw form dispatches via parser", %{conn: conn} do
    room = TestHarness.spawn_room("Hub", "A small room.")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    conn = auth(conn) |> post("/api/playtest/sessions/#{token}/cmd", %{raw: "look"})

    body = json_response(conn, 200)
    assert body["status"] == "dispatched"

    Process.sleep(50)

    conn2 = auth(build_conn()) |> get("/api/playtest/sessions/#{token}/feed")
    body2 = json_response(conn2, 200)
    assert body2["count"] >= 1
    assert Enum.any?(body2["messages"], &(&1["text"] =~ "Hub"))
  end

  test "POST /cmd with raw bare direction routes to Go", %{conn: conn} do
    a = TestHarness.spawn_room("A")
    b = TestHarness.spawn_room("B", "Room B description.")
    TestHarness.connect_rooms(a, b, "north")
    {:ok, token} = LineCore.PlaytestSession.create(a.id)

    conn = auth(conn) |> post("/api/playtest/sessions/#{token}/cmd", %{raw: "n"})
    assert json_response(conn, 200)["status"] == "dispatched"

    Process.sleep(50)

    {:ok, info} = LineCore.PlaytestSession.info(token)
    container = Object.container_of(info.player_id)
    assert container.id == b.id
  end

  test "POST /cmd with raw empty string returns 400", %{conn: conn} do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    conn = auth(conn) |> post("/api/playtest/sessions/#{token}/cmd", %{raw: ""})
    assert json_response(conn, 400)["error"] =~ "empty"
  end

  test "POST /cmd with raw unknown verb returns 400", %{conn: conn} do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    conn = auth(conn) |> post("/api/playtest/sessions/#{token}/cmd", %{raw: "blarg"})
    assert json_response(conn, 400)["error"] =~ "unknown verb"
  end

  test "POST /cmd with neither raw nor verb returns 400", %{conn: conn} do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    conn = auth(conn) |> post("/api/playtest/sessions/#{token}/cmd", %{nothing: "useful"})
    assert json_response(conn, 400)["error"] =~ "raw"
  end

  test "POST /cmd with quote-prefix say works through raw", %{conn: conn} do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    conn = auth(conn) |> post("/api/playtest/sessions/#{token}/cmd", %{raw: ~s("hello there)})
    assert json_response(conn, 200)["status"] == "dispatched"

    Process.sleep(50)
    conn2 = auth(build_conn()) |> get("/api/playtest/sessions/#{token}/feed")
    body = json_response(conn2, 200)
    assert Enum.any?(body["messages"], fn m -> m["text"] =~ ~s("hello there") end)
  end
end
