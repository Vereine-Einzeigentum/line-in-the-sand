defmodule LineCore.Verbs.Look do
  @moduledoc """
  `look` — describe the current room and what's in it.
  `look <target>` — describe a specific object.

  Direct-object resolution uses the shared visible-object resolver.

  Pure: produces notify events, no state changes.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Container, Object, Renderer, Resolver}

  @impl true
  def execute(ctx, []) do
    {:ok, [{:notify_actor, room_description(ctx.room, ctx.actor.id)}]}
  end

  def execute(ctx, [target_name]) do
    if looking_inside?(ctx) and ctx.iobj do
      look_inside(ctx.iobj)
    else
      case ctx.dobj || Resolver.visible(ctx, target_name) do
        nil ->
          {:error, :not_found}

        target ->
          {:ok, [{:notify_actor, Enum.join(Renderer.render(target), "\n")}]}
      end
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

  defp looking_inside?(ctx) do
    ctx.iobj != nil and
      Regex.match?(~r/^\s*(look|l)\s+in(?:side)?\b/i, ctx.command || "")
  end

  defp look_inside(container) do
    with :ok <- Container.accessible?(container.id) do
      contents = Object.contents(container.id)

      text =
        case contents do
          [] ->
            "The #{container.name} is empty."

          objects ->
            "Inside the #{container.name}:\n" <>
              Enum.map_join(objects, "\n", &"  #{&1.name}")
        end

      {:ok, [{:notify_actor, text}]}
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
