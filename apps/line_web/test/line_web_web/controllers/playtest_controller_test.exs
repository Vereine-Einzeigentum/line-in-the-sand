defmodule LineWebWeb.PlaytestControllerTest do
  use LineWebWeb.ConnCase, async: false

  alias LineCore.{Object, Repo, TestHarness}

  @playtest_token "test-token-do-not-use-in-prod"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    # Set env var for the duration of the test
    System.put_env("PLAYTEST_TOKEN", @playtest_token)

    on_exit(fn ->
      System.delete_env("PLAYTEST_TOKEN")
      System.delete_env("PLAYTEST_STARTING_ROOM_ID")
      Repo.delete_all(LineCore.Schemas.Property)
      Repo.delete_all(LineCore.Schemas.Relationship)
      Repo.delete_all(LineCore.Schemas.Object)
    end)

    :ok
  end

  defp auth(conn) do
    Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> @playtest_token)
  end

  test "503 when PLAYTEST_TOKEN env var is unset", %{conn: conn} do
    System.delete_env("PLAYTEST_TOKEN")

    conn = post(conn, "/api/playtest/sessions", %{})

    assert json_response(conn, 503)["error"] =~ "disabled"
  end

  test "401 when no bearer token is provided", %{conn: conn} do
    conn = post(conn, "/api/playtest/sessions", %{})
    assert json_response(conn, 401)["error"] =~ "invalid"
  end

  test "401 when bearer token is wrong", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer wrong-token")
      |> post("/api/playtest/sessions", %{})

    assert json_response(conn, 401)["error"] =~ "invalid"
  end

  test "POST /sessions creates a session with provided starting room", %{conn: conn} do
    room = TestHarness.spawn_room("Hub")

    conn = auth(conn) |> post("/api/playtest/sessions", %{starting_room_id: room.id})

    body = json_response(conn, 201)
    assert body["token"]
    assert body["player_id"]
    assert body["room_id"] == room.id
  end

  test "GET /sessions/:token returns session info", %{conn: conn} do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    conn = auth(conn) |> get("/api/playtest/sessions/#{token}")

    body = json_response(conn, 200)
    assert body["token"] == token
    assert body["room_id"] == room.id
  end

  test "POST /sessions/:token/cmd dispatches a look", %{conn: conn} do
    room = TestHarness.spawn_room("Hub", "A small room.")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    conn = auth(conn) |> post("/api/playtest/sessions/#{token}/cmd", %{verb: "look", args: []})

    body = json_response(conn, 200)
    assert body["status"] == "dispatched"
  end

  test "GET /sessions/:token/feed returns queued messages", %{conn: conn} do
    room = TestHarness.spawn_room("Bazaar", "Crowded.")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    # Dispatch a command to produce queued events
    LineCore.PlaytestSession.dispatch_command(token, LineCore.Verbs.Look, [], "look")
    Process.sleep(50)

    conn = auth(conn) |> get("/api/playtest/sessions/#{token}/feed")

    body = json_response(conn, 200)
    assert body["count"] >= 1
    assert Enum.any?(body["messages"], &(&1["type"] == "msg" and &1["text"] =~ "Bazaar"))
  end

  test "DELETE /sessions/:token terminates the session", %{conn: conn} do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    conn = auth(conn) |> delete("/api/playtest/sessions/#{token}")
    assert json_response(conn, 200)["status"] == "terminated"

    refute LineCore.PlaytestSession.exists?(token)
  end

  test "404 on unknown session token", %{conn: conn} do
    conn = auth(conn) |> get("/api/playtest/sessions/no-such-token")
    assert json_response(conn, 404)["error"] =~ "not found"
  end

  test "400 on unknown verb", %{conn: conn} do
    room = TestHarness.spawn_room("Hub")
    {:ok, token} = LineCore.PlaytestSession.create(room.id)

    conn = auth(conn) |> post("/api/playtest/sessions/#{token}/cmd", %{verb: "nonexistent"})

    assert json_response(conn, 400)["error"] =~ "unknown verb"
  end
end
