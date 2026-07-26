defmodule LineCore.Verbs.Look do
  @moduledoc """
  `look` — describe the current room and what's in it.
  `look <target>` — describe a specific object.

  Pure: produces notify events, no state changes.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Object, Renderer}

  @impl true
  def execute(ctx, []) do
    # Bare look: describe the room.
    lines =
      Renderer.render(ctx.room) ++
        [""] ++
        exits_line(ctx.room) ++
        [""] ++
        contents_lines(ctx)

    {:ok, [{:notify_actor, Enum.join(lines, "\n")}]}
  end

  def execute(ctx, [target_name]) do
    case find_target(ctx, target_name) do
      nil ->
        {:error, :not_found}

      target ->
        {:ok, [{:notify_actor, Enum.join(Renderer.render(target), "\n")}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Helpers

  defp exits_line(room) do
    case Object.exits(room.id) do
      [] -> ["No obvious exits."]
      exits -> ["Exits: " <> Enum.map_join(exits, ", ", fn {dir, _} -> dir end)]
    end
  end

  defp contents_lines(ctx) do
    ctx.room_contents
    |> Enum.reject(&(&1.id == ctx.actor.id))
    |> Enum.map(fn o -> "You see: #{o.name}." <> state_suffix(o) end)
  end

  # An unattended body is still in the room and still worth describing as one.
  # `active_state` is the general mechanism — a session marks a player offline
  # with it, and anything else that wants a standing condition can use it too.
  defp state_suffix(object) do
    case Object.get_property(object.id, "active_state") do
      nil -> ""
      state -> " (#{state})"
    end
  end

  defp find_target(ctx, name) do
    name_down = String.downcase(name)

    # Search room contents first, then actor's inventory.
    in_room =
      Enum.find(ctx.room_contents, fn o ->
        String.downcase(o.name) == name_down or
          String.contains?(String.downcase(o.name), name_down)
      end)

    if in_room do
      in_room
    else
      ctx.actor.id
      |> Object.contents()
      |> Enum.find(fn o ->
        String.downcase(o.name) == name_down or
          String.contains?(String.downcase(o.name), name_down)
      end)
    end
  end
end
