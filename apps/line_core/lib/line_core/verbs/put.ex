defmodule LineCore.Verbs.Put do
  @moduledoc """
  `put <object> in <container>` — move a directly carried object into an
  accessible container.

  The container capability comes from inherited verb dispatch. This module
  only implements the mechanical consequence once dispatch has selected it.
  """

  @behaviour LineCore.Verb

  alias LineCore.{Container, Object}

  @impl true
  def execute(_ctx, []), do: {:error, :put_what}
  def execute(_ctx, [_object]), do: {:error, :put_where}

  def execute(ctx, ["all", _container_name]) do
    container = ctx.iobj

    cond do
      is_nil(container) ->
        {:error, :not_found}

      true ->
        with :ok <- Container.accessible?(container.id) do
          items =
            ctx.actor.id
            |> Object.contents()
            |> Enum.filter(&(&1.type == :item))
            |> Enum.reject(&(&1.id == container.id))

          case items do
            [] ->
              {:error, :not_in_inventory}

            _ ->
              equipped = Object.equipped(ctx.actor.id)

              detach =
                equipped
                |> Enum.filter(fn {_type, object} -> Enum.any?(items, &(&1.id == object.id)) end)
                |> Enum.map(fn {type, object} -> {:unrelate, ctx.actor.id, object.id, type} end)

              moves = Enum.map(items, &{:move, &1.id, container.id, :contains})
              names = Enum.map_join(items, ", ", & &1.name)

              {:ok,
               detach ++
                 moves ++
                 [
                   {:notify_actor, "You put in the #{container.name}: #{names}."},
                   {:notify_room, "#{ctx.actor.name} puts several things in the #{container.name}.",
                    except: [ctx.actor.id]}
                 ]}
          end
        end
    end
  end

  def execute(ctx, [_object_name, _container_name]) do
    item = ctx.dobj
    container = ctx.iobj

    cond do
      is_nil(item) ->
        {:error, :not_found}

      is_nil(container) ->
        {:error, :not_found}

      not directly_contained_by?(item.id, ctx.actor.id) ->
        {:error, :not_in_inventory}

      Container.would_cycle?(item.id, container.id) ->
        {:error, :containment_cycle}

      true ->
        with :ok <- Container.accessible?(container.id) do
          detach =
            ctx.actor.id
            |> Object.equipped()
            |> Enum.filter(fn {_type, object} -> object.id == item.id end)
            |> Enum.map(fn {type, object} -> {:unrelate, ctx.actor.id, object.id, type} end)

          {:ok,
           detach ++
           [
             {:move, item.id, container.id, :contains},
             {:notify_actor, "You put the #{item.name} in the #{container.name}."},
             {:notify_room, "#{ctx.actor.name} puts something in the #{container.name}.",
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
