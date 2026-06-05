defmodule LineCore.Verbs.Text do
  @moduledoc """
  `text <player> <message>` / `txt <player> <message>` / `tell <player> <message>` —
  private message to a player by name, anywhere in the world.

  Looks up the player by name (case-insensitive exact match preferred,
  substring fallback). Delivers via the `{:actor, target_id}` PubSub topic
  so the recipient sees it regardless of which room they're in.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Repo}
  alias LineCore.Schemas.Object
  import Ecto.Query

  @impl true
  def execute(_ctx, []), do: {:error, :text_who}
  def execute(_ctx, [_target]), do: {:error, :text_what}

  def execute(ctx, [target_name, message]) when is_binary(target_name) and is_binary(message) do
    trimmed = String.trim(message)

    cond do
      trimmed == "" ->
        {:error, :text_what}

      true ->
        case find_player(target_name, ctx.actor.id) do
          nil ->
            {:error, :no_such_player}

          target ->
            actor_line = "You text #{target.name}: \"#{trimmed}\""
            target_line = "[txt from #{ctx.actor.name}]: #{trimmed}"

            {:ok,
             [
               {:notify_actor, actor_line},
               {:notify_object, target.id, target_line}
             ]}
        end
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Helpers

  defp find_player(name, exclude_id) do
    name_down = String.downcase(name)

    # Exact match first
    exact =
      from(o in Object,
        where:
          o.type == :player and
            fragment("lower(?)", o.name) == ^name_down and
            o.id != ^exclude_id and
            is_nil(o.deleted_at),
        limit: 1
      )
      |> Repo.one()

    if exact do
      exact
    else
      # Substring fallback
      from(o in Object,
        where:
          o.type == :player and
            fragment("lower(?)", o.name) |> like(^"%#{name_down}%") and
            o.id != ^exclude_id and
            is_nil(o.deleted_at),
        limit: 1
      )
      |> Repo.one()
    end
  end
end
