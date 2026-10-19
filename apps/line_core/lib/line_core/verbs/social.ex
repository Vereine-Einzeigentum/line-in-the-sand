defmodule LineCore.Verbs.Social do
  @moduledoc """
  Executes sanctioned textual socials selected by the leading-dot namespace.

  Socials are canonical text only. They do not apply game effects.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Resolver, Socials}

  @impl true
  def execute(_ctx, []), do: {:error, :social_what}

  def execute(ctx, [name]) when is_binary(name) do
    with {:ok, social} <- fetch_social(name) do
      emit(social, ctx, nil)
    end
  end

  def execute(ctx, [name, target_name]) when is_binary(name) and is_binary(target_name) do
    with {:ok, social} <- fetch_social(name),
         target when not is_nil(target) <- Resolver.visible(ctx, target_name) do
      emit(social, ctx, target)
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp fetch_social(name) do
    case Socials.fetch(name) do
      {:ok, social} -> {:ok, social}
      :error -> {:error, :unknown_social}
    end
  end

  defp emit(social, ctx, target) do
    {actor_text, room_text} = Socials.render(social, ctx.actor, target)

    {:ok,
     [
       {:notify_actor, actor_text},
       {:notify_room, room_text, except: [ctx.actor.id]}
     ]}
  end
end
