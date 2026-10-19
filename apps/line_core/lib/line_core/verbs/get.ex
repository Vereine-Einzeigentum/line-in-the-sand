defmodule LineCore.Verbs.Get do
  @moduledoc """
  `get <item>` picks an item up from the current room.

  `get <item> from <container>` is selected through the target container's
  inherited verb and moves a direct child of that container into inventory.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Container, Object}

  @impl true
  def execute(_ctx, []), do: {:error, :get_what}

  def execute(ctx, ["all"]) do
    items =
      ctx.room_contents
      |> Enum.reject(&(&1.id == ctx.actor.id))
      |> Enum.filter(&(&1.type == :item))

    case items do
      [] ->
        {:error, :not_found}

      _ ->
        moves = Enum.map(items, &{:move, &1.id, ctx.actor.id, :contains})
        names = Enum.map_join(items, ", ", & &1.name)

        {:ok,
         moves ++
           [
             {:notify_actor, "You pick up: #{names}."},
             {:notify_room, "#{ctx.actor.name} picks up several things.", except: [ctx.actor.id]}
           ]}
    end
  end

  def execute(ctx, [name]) do
    candidate =
      ctx.room_contents
      |> Enum.reject(&(&1.id == ctx.actor.id))
      |> Enum.filter(&(&1.type == :item))
      |> Object.find_by_name(name)

    case candidate do
      nil ->
        {:error, :not_found}

      item ->
        {:ok,
         [
           {:move, item.id, ctx.actor.id, :contains},
           {:notify_actor, "You pick up the #{item.name}."},
           {:notify_room, "#{ctx.actor.name} picks up the #{item.name}.", except: [ctx.actor.id]}
         ]}
    end
  end

  def execute(ctx, ["all", _container_name]) do
    container = ctx.iobj

    cond do
      is_nil(container) ->
        {:error, :not_found}

      true ->
        with :ok <- Container.accessible?(container.id) do
          items =
            container.id
            |> Object.contents()
            |> Enum.filter(&(&1.type == :item))

          case items do
            [] ->
              {:error, :not_found}

            _ ->
              moves = Enum.map(items, &{:move, &1.id, ctx.actor.id, :contains})
              names = Enum.map_join(items, ", ", & &1.name)

              {:ok,
               moves ++
                 [
                   {:notify_actor, "You take from the #{container.name}: #{names}."},
                   {:notify_room,
                    "#{ctx.actor.name} takes several things from the #{container.name}.",
                    except: [ctx.actor.id]}
                 ]}
          end
        end
    end
  end

  def execute(ctx, [_item_name, _container_name]) do
    item = ctx.dobj
    container = ctx.iobj

    cond do
      is_nil(item) ->
        {:error, :not_found}

      is_nil(container) ->
        {:error, :not_found}

      not directly_contained_by?(item.id, container.id) ->
        {:error, :not_in_container}

      true ->
        with :ok <- Container.accessible?(container.id) do
          {:ok,
           [
             {:move, item.id, ctx.actor.id, :contains},
             {:notify_actor, "You take the #{item.name} from the #{container.name}."},
             {:notify_room, "#{ctx.actor.name} takes something from the #{container.name}.",
              except: [ctx.actor.id]}
           ]}
        end
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp directly_contained_by?(object_id, container_id) do
    case Object.container_of(object_id) do
      %{id: ^container_id} -> true
      _ -> false
    end
  end
end
