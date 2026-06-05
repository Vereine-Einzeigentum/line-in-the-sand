defmodule LineCore.Verbs.Examine do
  @moduledoc """
  `examine <target>` / `ex <target>` / `x <target>` — detailed look at a
  specific object. Requires a target (unlike `look`, which can be bare).

  Uses the full Renderer output, including attachments and active state,
  which can be more detailed than `look <target>`.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Object, Renderer}

  @impl true
  def execute(_ctx, []), do: {:error, :examine_what}

  def execute(ctx, [target_name]) do
    case find_target(ctx, target_name) do
      nil ->
        {:error, :not_found}

      target ->
        lines = Renderer.render(target)
        {:ok, [{:notify_actor, Enum.join(lines, "\n")}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Helpers — same search logic as Look

  defp find_target(ctx, name) do
    name_down = String.downcase(name)

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
