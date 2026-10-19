defmodule LineCore.Verbs.SetHome do
  @behaviour LineCore.Verb

  @impl true
  def execute(ctx, []) do
    {:ok,
     [
       {:set_property, ctx.actor.id, "home_room_id", ctx.room.id},
       {:notify_actor, "Home set to #{ctx.room.name}."}
     ]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.Home do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, []) do
    case Object.get_property(ctx.actor.id, "home_room_id") do
      nil ->
        {:error, :home_not_set}

      room_id ->
        case Object.get(room_id) do
          nil ->
            {:error, :home_not_found}

          room ->
            {:ok,
             [
               {:move, ctx.actor.id, room.id, :contains},
               {:notify_actor, "You return home to #{room.name}."}
             ]}
        end
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.Whisper do
  @behaviour LineCore.Verb

  @impl true
  def execute(ctx, [message, _target]) do
    target = ctx.iobj
    message = strip_quotes(message)

    cond do
      is_nil(target) ->
        {:error, :not_found}

      String.trim(message) == "" ->
        {:error, :whisper_what}

      true ->
        {:ok,
         [
           {:notify_actor, ~s(You whisper "#{message}" to #{target.name}.)},
           {:notify_object, target.id, ~s(#{ctx.actor.name} whispers "#{message}" to you.)}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp strip_quotes(value) do
    value
    |> String.trim()
    |> String.trim_leading(~s("))
    |> String.trim_trailing(~s("))
  end
end

defmodule LineCore.Verbs.Page do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(_ctx, []), do: {:error, :page_who}
  def execute(_ctx, [_target]), do: {:error, :page_what}

  def execute(ctx, [target_name, message]) do
    case Object.find_player_by_name(target_name) do
      nil ->
        {:error, :no_such_player}

      target ->
        text = String.trim(message)

        if text == "" do
          {:error, :page_what}
        else
          {:ok,
           [
             {:notify_actor, "You page #{target.name}: #{text}"},
             {:notify_object, target.id, "[page from #{ctx.actor.name}] #{text}"}
           ]}
        end
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.WhereIs do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(_ctx, []), do: {:error, :whereis_who}

  def execute(_ctx, [name]) do
    case Object.find_player_by_name(name) do
      nil ->
        {:error, :no_such_player}

      target ->
        place =
          case Object.container_of(target.id) do
            nil -> "nowhere"
            room -> room.name
          end

        {:ok, [{:notify_actor, "#{target.name} is in #{place}."}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
