defmodule LineCore.Verbs.Emote do
  @moduledoc """
  Free-form textual pose.

  `:text` is social text only. It does not resolve or execute actions named
  inside the text and therefore cannot produce mechanical effects.
  """

  @behaviour LineCore.Verb

  @impl true
  def execute(_ctx, []), do: {:error, :emote_what}

  def execute(ctx, [text]) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:error, :emote_what}

      pose ->
        line = "#{ctx.actor.name} #{pose}"

        {:ok,
         [
           {:notify_actor, line},
           {:notify_room, line, except: [ctx.actor.id]}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
