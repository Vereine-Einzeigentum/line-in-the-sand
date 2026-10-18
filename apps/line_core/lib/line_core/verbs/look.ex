defmodule LineCore.Verbs.Look do
  @moduledoc """
  `look` — describe the current room and what's in it.
  `look <target>` — describe a specific object.

  Direct-object resolution recognizes `self`/`me`, `here`, the current
  room by name, objects in the room, and objects in the actor's inventory.

  Pure: produces notify events, no state changes.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Object, Renderer}

  @impl true
  def execute(ctx, []) do
    {:ok, [{:notify_actor, room_description(ctx.room, ctx.actor.id)}]}
  end

  def execute(ctx, [target_name]) do
    case resolve_target(ctx, target_name) do
      nil ->
        {:error, :not_found}

      target ->
        {:ok, [{:notify_actor, Enum.join(Renderer.render(target), "\n")}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  @doc "Render a full room view for the given viewer. Used by Go for auto-look."
  def room_description(room, viewer_id) do
    contents = Object.contents(room.id)
    others = Enum.reject(contents, &(&1.id == viewer_id))

    lines =
      Renderer.render(room) ++
        [""] ++
        exits_line(room) ++
        [""] ++
        contents_lines(others)

    Enum.join(lines, "\n")
  end

  ## Helpers

  defp resolve_target(ctx, target_name) when is_binary(target_name) do
    normalized = target_name |> String.trim() |> String.downcase()

    case normalized do
      "self" ->
        ctx.actor

      "me" ->
        ctx.actor

      "here" ->
        ctx.room

      _ ->
        Object.find_by_name([ctx.room], target_name) ||
          Object.find_by_name(ctx.room_contents, target_name) ||
          Object.find_by_name(Object.contents(ctx.actor.id), target_name)
    end
  end

  defp exits_line(room) do
    case Object.exits(room.id) do
      [] -> ["No obvious exits."]
      exits -> ["Exits: " <> Enum.map_join(exits, ", ", fn {dir, _} -> dir end)]
    end
  end

  defp contents_lines([]), do: []

  defp contents_lines(objs) do
    Enum.map(objs, fn o -> "You see: #{o.name}." end)
  end
end
