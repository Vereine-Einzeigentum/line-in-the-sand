defmodule LineCore.Verbs.Who do
  @moduledoc """
  `who` — list players currently online (OOC).
  `who <player>` — return online status for a named player (OOC).

  Reads from `LineCore.Presence`, but the caller is always included in their
  own `who` result. This makes the command correct during the small window
  before websocket presence registration completes and for non-websocket
  dispatchers such as tests/admin tooling.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Object, Presence}

  @impl true
  def execute(ctx, []) do
    online_ids =
      [ctx.actor.id | Presence.online_player_ids()]
      |> Enum.uniq()

    names =
      online_ids
      |> Enum.map(&Object.get/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.name)
      |> Enum.sort()

    line =
      case names do
        [] -> "[OOC] No one is online."
        _ -> "[OOC] Online (#{length(names)}): " <> Enum.join(names, ", ")
      end

    {:ok, [{:notify_actor, line}]}
  end

  def execute(_ctx, [name]) do
    target = Object.find_player_by_name(name)

    line =
      cond do
        target == nil ->
          "[OOC] No player by that name."

        Presence.online?(target.id) ->
          "[OOC] #{target.name} is online."

        true ->
          "[OOC] #{target.name} is offline."
      end

    {:ok, [{:notify_actor, line}]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
