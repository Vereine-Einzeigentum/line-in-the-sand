defmodule LineCore.Verbs.Who do
  @moduledoc """
  `who` — list players currently online (OOC).
  `who <player>` — return online status for a named player (OOC).

  Reads from `LineCore.Presence`. The output is marked OOC since it
  references real-world session state, not in-world knowledge. Phase 1+
  may add an in-world matrix/directory system for diegetic profiles.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Object, Presence}

  @impl true
  def execute(_ctx, []) do
    online_ids = Presence.online_player_ids()

    lines =
      case online_ids do
        [] ->
          ["[OOC] No one else is online."]

        ids ->
          names =
            ids
            |> Enum.map(&Object.get/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.map(& &1.name)
            |> Enum.sort()

          ["[OOC] Online (#{length(names)}): " <> Enum.join(names, ", ")]
      end

    {:ok, [{:notify_actor, Enum.join(lines, "\n")}]}
  end

  def execute(_ctx, [name]) do
    target = find_player_by_name(name)

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

  ## Helpers

  defp find_player_by_name(name) do
    import Ecto.Query
    alias LineCore.{Repo}
    alias LineCore.Schemas.Object

    name_down = String.downcase(name)

    from(o in Object,
      where:
        o.type == :player and
          fragment("lower(?)", o.name) == ^name_down and
          is_nil(o.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end
end
