defmodule LineWebWeb.PlaytestController do
  @moduledoc """
  HTTP API for playtest sessions.

  Endpoints:

      POST   /api/playtest/sessions               — create session
      GET    /api/playtest/sessions/:token        — session info
      POST   /api/playtest/sessions/:token/cmd    — dispatch command
      GET    /api/playtest/sessions/:token/feed   — pull queued messages
      DELETE /api/playtest/sessions/:token        — terminate session

  All endpoints require `Authorization: Bearer <PLAYTEST_TOKEN>` header.
  `PLAYTEST_TOKEN` is set via env var; if unset, the API is disabled and
  all requests return 503.

  Command formats accepted by /cmd:

    1. Raw form (preferred for agentic playtest):
       `{"raw": "look at fence"}`
       Goes through LineCore.Parser. Single source of truth for input parsing.

    2. Pre-parsed form (for programmatic clients that bypass the parser):
       `{"verb": "look", "args": ["fence"]}`
       Looks up verb directly in the parser's verb map.
  """

  use LineWebWeb, :controller

  alias LineCore.{Parser, PlaytestSession}

  ## Plug pipeline

  plug :require_playtest_token
  plug :require_session when action in [:show, :command, :feed, :delete]

  ## Actions

  def create(conn, params) do
    starting_room_id = Map.get(params, "starting_room_id") || default_starting_room()
    name = Map.get(params, "name")

    opts = if name, do: [name: name], else: []

    case PlaytestSession.create(starting_room_id, opts) do
      {:ok, token} ->
        {:ok, info} = PlaytestSession.info(token)

        conn
        |> put_status(:created)
        |> json(%{
          token: token,
          player_id: info.player_id,
          room_id: info.room_id,
          created_at: info.created_at
        })

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

  def show(conn, _params) do
    token = conn.assigns.session_token
    {:ok, info} = PlaytestSession.info(token)
    json(conn, info)
  end

  def command(conn, %{"raw" => raw} = _params) when is_binary(raw) do
    token = conn.assigns.session_token

    case Parser.parse(raw) do
      {:ok, verb_module, args} ->
        dispatch_and_respond(conn, token, verb_module, args, raw)

      {:empty, _} ->
        conn |> put_status(:bad_request) |> json(%{error: "empty command"})

      {:unknown, verb, _input} ->
        conn |> put_status(:bad_request) |> json(%{error: "unknown verb: #{verb}"})
    end
  end

  def command(conn, %{"verb" => verb} = params) do
    token = conn.assigns.session_token
    args = Map.get(params, "args", [])
    raw = "#{verb} #{Enum.join(args, " ")}" |> String.trim()

    case lookup_verb(verb) do
      {:ok, verb_module} ->
        dispatch_and_respond(conn, token, verb_module, args, raw)

      :error ->
        conn |> put_status(:bad_request) |> json(%{error: "unknown verb: #{verb}"})
    end
  end

  def command(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "request must include either 'raw' or 'verb' field"})
  end

  def feed(conn, params) do
    token = conn.assigns.session_token
    limit = params |> Map.get("limit", "50") |> String.to_integer()

    {:ok, messages} = PlaytestSession.pull_messages(token, limit)

    formatted =
      Enum.map(messages, fn
        {:msg, m} -> %{type: "msg", text: m}
        {:room_msg, m, _except} -> %{type: "room_msg", text: m}
        {:channel_msg, ch, m} -> %{type: "channel", channel: to_string(ch), text: m}
      end)

    json(conn, %{messages: formatted, count: length(formatted)})
  end

  def delete(conn, _params) do
    token = conn.assigns.session_token

    case PlaytestSession.terminate(token) do
      :ok -> json(conn, %{status: "terminated"})
      {:error, reason} -> conn |> put_status(:not_found) |> json(%{error: inspect(reason)})
    end
  end

  ## Plugs

  defp require_playtest_token(conn, _) do
    expected = System.get_env("PLAYTEST_TOKEN")

    cond do
      is_nil(expected) or expected == "" ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "playtest API disabled (PLAYTEST_TOKEN not set)"})
        |> halt()

      bearer_token(conn) != expected ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"}) |> halt()

      true ->
        conn
    end
  end

  defp require_session(conn, _) do
    token = conn.path_params["token"]

    if PlaytestSession.exists?(token) do
      assign(conn, :session_token, token)
    else
      conn |> put_status(:not_found) |> json(%{error: "session not found"}) |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  ## Verb resolution from pre-parsed form

  defp lookup_verb(verb) when is_binary(verb) do
    case Map.get(Parser.verb_map(), String.downcase(verb)) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  defp dispatch_and_respond(conn, token, verb_module, args, raw) do
    case PlaytestSession.dispatch_command(token, verb_module, args, raw) do
      :ok ->
        json(conn, %{status: "dispatched", verb: inspect(verb_module), args: args})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

  defp default_starting_room do
    case System.get_env("PLAYTEST_STARTING_ROOM_ID") do
      nil -> raise "PLAYTEST_STARTING_ROOM_ID env var must be set for playtest sessions"
      id -> id
    end
  end
end
