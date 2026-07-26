defmodule LineCore.PlaytestSession do
  @moduledoc """
  Manages ephemeral playtest sessions.

  Each session has:
  - A unique token (used as auth + identifier)
  - A player object in the world
  - A GenServer process that subscribes to the player's actor and room topics
    and accumulates messages in a bounded queue

  The HTTP layer creates sessions, dispatches commands through them, and reads
  the accumulated message queue for SSE/long-poll delivery.

  Sessions auto-expire after fifteen minutes of no activity, overridable with
  the `:playtest_idle_timeout` application env.

  ## The session is ephemeral; the player is not

  Ending a session — by `terminate/1`, by idle expiry, by the process dying —
  releases connection-scoped resources only. The player object stays in the
  world, marked offline, exactly where it was standing. It remains visible in
  `look`, and it remains a legal target: an unattended body can be attacked and
  killed, which is what gives persistence stakes rather than making it scenery.

  What happened while nobody was driving is recoverable — the journal recorded
  it, and `LineCore.Catchup` reads it back on reconnect.
  """

  use GenServer
  require Logger

  alias LineCore.{Catchup, Genesis, PubSub}

  @default_idle_timeout :timer.minutes(15)
  @max_queue_size 200

  defstruct [:token, :player_id, :room_id, :queue, :created_at, :last_activity]

  ## Public API

  @doc "Create a new playtest session with an ephemeral player in the given starting room."
  def create(starting_room_id, opts \\ []) do
    token = generate_token()
    name = Keyword.get(opts, :name, "Playtester-#{String.slice(token, 0, 6)}")

    case GenServer.start(__MODULE__, {token, starting_room_id, name}, name: via(token)) do
      {:ok, _pid} ->
        {:ok, token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get session info (player_id, room_id, age)."
  def info(token) do
    GenServer.call(via(token), :info)
  catch
    :exit, _ -> {:error, :no_session}
  end

  @doc "Dispatch a command on behalf of the session's player."
  def dispatch_command(token, verb_module, args, raw_command) do
    GenServer.call(via(token), {:dispatch, verb_module, args, raw_command})
  catch
    :exit, _ -> {:error, :no_session}
  end

  @doc "Pull queued messages. Returns up to `limit` messages and removes them from the queue."
  def pull_messages(token, limit \\ 50) do
    GenServer.call(via(token), {:pull, limit})
  catch
    :exit, _ -> {:error, :no_session}
  end

  @doc "End the session. The player object stays in the world, marked offline."
  def terminate(token) do
    GenServer.call(via(token), :terminate)
  catch
    :exit, _ -> {:error, :no_session}
  end

  @doc "Check if a session exists for the given token."
  def exists?(token) do
    case Registry.lookup(LineCore.PlaytestRegistry, token) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  ## GenServer callbacks

  @impl true
  def init({token, starting_room_id, name}) do
    # One transaction: the player is created, placed and given its properties,
    # or none of it happened. The old sequence created the player, then related
    # it in a second call, with a compensating `unrelate` that could not undo
    # the player it was compensating for.
    case Genesis.player(name, source: :playtest, place_in: starting_room_id) do
      {:ok, player} ->
        Catchup.mark_online(player.id)

        PubSub.subscribe({:actor, player.id})
        PubSub.subscribe({:room, starting_room_id})

        state = %__MODULE__{
          token: token,
          player_id: player.id,
          room_id: starting_room_id,
          queue: :queue.new(),
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }

        {:ok, state, idle_timeout()}

      error ->
        {:stop, {:player_create_failed, error}}
    end
  end

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      token: state.token,
      player_id: state.player_id,
      room_id: state.room_id,
      created_at: state.created_at,
      queue_size: :queue.len(state.queue)
    }

    {:reply, {:ok, info}, touch(state), idle_timeout()}
  end

  def handle_call({:dispatch, verb_module, args, raw}, _from, state) do
    result = LineCore.Dispatcher.dispatch(state.player_id, verb_module, args, raw)
    {:reply, result, touch(state), idle_timeout()}
  end

  def handle_call({:pull, limit}, _from, state) do
    {pulled, remaining} = take_n(state.queue, limit, [])
    {:reply, {:ok, pulled}, %{state | queue: remaining}, idle_timeout()}
  end

  def handle_call(:terminate, _from, state) do
    cleanup(state)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:msg, _} = msg, state) do
    {:noreply, enqueue(state, msg), idle_timeout()}
  end

  def handle_info({:room_msg, _msg, except} = full, state) do
    if state.player_id in except do
      {:noreply, state, idle_timeout()}
    else
      {:noreply, enqueue(state, full), idle_timeout()}
    end
  end

  def handle_info({:channel_msg, _, _} = msg, state) do
    {:noreply, enqueue(state, msg), idle_timeout()}
  end

  def handle_info(:timeout, state) do
    Logger.info("playtest session #{state.token} idle-expired")
    cleanup(state)
    {:stop, :normal, state}
  end

  def handle_info(_, state) do
    {:noreply, state, idle_timeout()}
  end

  ## Helpers

  # Configurable so idle expiry is a testable path rather than a fifteen-minute
  # one. Production never sets it.
  defp idle_timeout do
    Application.get_env(:line_core, :playtest_idle_timeout, @default_idle_timeout)
  end

  defp via(token), do: {:via, Registry, {LineCore.PlaytestRegistry, token}}

  defp generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end

  defp touch(state), do: %{state | last_activity: DateTime.utc_now()}

  defp enqueue(state, msg) do
    q = :queue.in(msg, state.queue)

    q =
      if :queue.len(q) > @max_queue_size do
        {_, q2} = :queue.out(q)
        q2
      else
        q
      end

    %{state | queue: q}
  end

  defp take_n(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp take_n(queue, n, acc) do
    case :queue.out(queue) do
      {{:value, msg}, rest} -> take_n(rest, n - 1, [msg | acc])
      {:empty, _} -> {Enum.reverse(acc), queue}
    end
  end

  # Ending a session tears down connection-scoped resources — this process, its
  # subscriptions, its queue — and nothing else. The body stays in its room.
  #
  # It used to soft-delete the player, which destroyed a character because a
  # *connection* ended. Persistent bodies are the intended model: a logged-out
  # PC is structurally identical to an NPC standing in the same room, and is
  # just as visible, just as attackable.
  defp cleanup(state) do
    PubSub.unsubscribe({:actor, state.player_id})
    PubSub.unsubscribe({:room, state.room_id})

    Catchup.mark_offline(state.player_id)
  end
end
