defmodule LineCore.Presence do
  @moduledoc """
  Tracks which players currently have an active session (HTTP playtest or
  websocket).

  Backed by a unique Registry keyed on player_id. Sessions register on start
  and the Registry entry vanishes automatically when the session process exits.

  This is the source of truth for the `who` verb. PlaytestSession registers
  itself in `init/1`; the websocket GameChannel (STEP 7) will do the same.
  """

  @registry LineCore.Presence.Registry

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry)
  end

  @doc """
  Register the calling process as the active session for `player_id`.

  Returns `{:ok, pid}` on success, `{:error, {:already_registered, pid}}` if
  the player is already online.
  """
  def register(player_id, metadata \\ %{}) do
    Registry.register(@registry, player_id, metadata)
  end

  @doc "Unregister the calling process from the player_id."
  def unregister(player_id) do
    Registry.unregister(@registry, player_id)
  end

  @doc "Is the given player_id currently online?"
  def online?(player_id) do
    case Registry.lookup(@registry, player_id) do
      [] -> false
      [_] -> true
    end
  end

  @doc "List all currently online player_ids."
  def online_player_ids do
    Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc "Metadata associated with an online player_id, or nil."
  def metadata(player_id) do
    case Registry.lookup(@registry, player_id) do
      [{_pid, meta}] -> meta
      [] -> nil
    end
  end

  @doc "Count of online players."
  def count, do: Registry.count(@registry)
end
