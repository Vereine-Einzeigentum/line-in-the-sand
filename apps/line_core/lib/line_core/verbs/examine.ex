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
    target =
      Object.find_by_name(ctx.room_contents, target_name) ||
        Object.find_by_name(Object.contents(ctx.actor.id), target_name)

    case target do
      nil ->
        {:error, :not_found}

      target ->
        lines = Renderer.render(target)
        {:ok, [{:notify_actor, Enum.join(lines, "\n")}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
