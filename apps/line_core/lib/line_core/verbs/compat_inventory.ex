defmodule LineCore.Verbs.Give do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, [_object, _recipient]) do
    item = ctx.dobj
    recipient = ctx.iobj

    cond do
      is_nil(item) or is_nil(recipient) ->
        {:error, :not_found}

      not directly_contained_by?(item.id, ctx.actor.id) ->
        {:error, :not_in_inventory}

      true ->
        detach =
          ctx.actor.id
          |> Object.equipped()
          |> Enum.filter(fn {_type, object} -> object.id == item.id end)
          |> Enum.map(fn {type, object} -> {:unrelate, ctx.actor.id, object.id, type} end)

        {:ok,
         detach ++
           [
             {:move, item.id, recipient.id, :contains},
             {:notify_actor, "You give the #{item.name} to #{recipient.name}."},
             {:notify_object, recipient.id, "#{ctx.actor.name} gives you the #{item.name}."},
             {:notify_room, "#{ctx.actor.name} gives #{recipient.name} the #{item.name}.",
              except: [ctx.actor.id, recipient.id]}
           ]}
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

defmodule LineCore.Verbs.Unwield do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, [_name]) do
    item = ctx.dobj

    matches =
      ctx.actor.id
      |> Object.equipped()
      |> Enum.filter(fn {type, object} ->
        type in [:wields_main, :wields_off] and item && object.id == item.id
      end)

    case matches do
      [] ->
        {:error, :not_wielded}

      _ ->
        events =
          Enum.map(matches, fn {type, object} ->
            {:unrelate, ctx.actor.id, object.id, type}
          end)

        {:ok, events ++ [{:notify_actor, "You stop wielding the #{item.name}."}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.Wear do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, [_name]) do
    item = ctx.dobj

    cond do
      is_nil(item) ->
        {:error, :not_found}

      Object.container_of(item.id) == nil or Object.container_of(item.id).id != ctx.actor.id ->
        {:error, :not_in_inventory}

      Enum.any?(Object.related_by(ctx.actor.id, :wears), &(&1.id == item.id)) ->
        {:error, :already_wearing}

      true ->
        {:ok,
         [
           {:relate, ctx.actor.id, item.id, :wears},
           {:notify_actor, "You put on the #{item.name}."},
           {:notify_room, "#{ctx.actor.name} puts on the #{item.name}.", except: [ctx.actor.id]}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.RemoveWear do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, [_name]) do
    item = ctx.dobj

    if item && Enum.any?(Object.related_by(ctx.actor.id, :wears), &(&1.id == item.id)) do
      {:ok,
       [
         {:unrelate, ctx.actor.id, item.id, :wears},
         {:notify_actor, "You remove the #{item.name}."},
         {:notify_room, "#{ctx.actor.name} removes the #{item.name}.", except: [ctx.actor.id]}
       ]}
    else
      {:error, :not_wearing}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.Open do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, [_name]) do
    object = ctx.dobj

    cond do
      is_nil(object) -> {:error, :not_found}
      Object.get_property(object.id, "locked", false) == true -> {:error, :container_locked}
      Object.get_property(object.id, "open", true) == true -> {:error, :already_open}
      true ->
        {:ok,
         [
           {:set_property, object.id, "open", true},
           {:notify_actor, "You open the #{object.name}."},
           {:notify_room, "#{ctx.actor.name} opens the #{object.name}.", except: [ctx.actor.id]}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.Close do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, [_name]) do
    object = ctx.dobj

    cond do
      is_nil(object) -> {:error, :not_found}
      Object.get_property(object.id, "open", true) == false -> {:error, :already_closed}
      true ->
        {:ok,
         [
           {:set_property, object.id, "open", false},
           {:notify_actor, "You close the #{object.name}."},
           {:notify_room, "#{ctx.actor.name} closes the #{object.name}.", except: [ctx.actor.id]}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.Lock do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, _args) do
    object = ctx.dobj
    key = ctx.iobj

    with {:ok, object} <- present(object),
         :ok <- closed(object),
         :ok <- keyed_for(object, key),
         :ok <- carried(ctx.actor.id, key) do
      {:ok,
       [
         {:set_property, object.id, "locked", true},
         {:notify_actor, "You lock the #{object.name}."}
       ]}
    end
  end

  defp present(nil), do: {:error, :not_found}
  defp present(object), do: {:ok, object}

  defp closed(object) do
    if Object.get_property(object.id, "open", true), do: {:error, :container_open}, else: :ok
  end

  defp keyed_for(object, nil) do
    if Object.get_property(object.id, "key_id"), do: {:error, :key_required}, else: {:error, :no_key_defined}
  end

  defp keyed_for(object, key) do
    if Object.get_property(object.id, "key_id") == key.id, do: :ok, else: {:error, :wrong_key}
  end

  defp carried(actor_id, key) do
    case Object.container_of(key.id) do
      %{id: ^actor_id} -> :ok
      _ -> {:error, :key_not_carried}
    end
  end
end

defmodule LineCore.Verbs.Unlock do
  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, _args) do
    object = ctx.dobj
    key = ctx.iobj

    with {:ok, object} <- present(object),
         :ok <- keyed_for(object, key),
         :ok <- carried(ctx.actor.id, key) do
      {:ok,
       [
         {:set_property, object.id, "locked", false},
         {:notify_actor, "You unlock the #{object.name}."}
       ]}
    end
  end

  defp present(nil), do: {:error, :not_found}
  defp present(object), do: {:ok, object}

  defp keyed_for(object, nil) do
    if Object.get_property(object.id, "key_id"), do: {:error, :key_required}, else: {:error, :no_key_defined}
  end

  defp keyed_for(object, key) do
    if Object.get_property(object.id, "key_id") == key.id, do: :ok, else: {:error, :wrong_key}
  end

  defp carried(actor_id, key) do
    case Object.container_of(key.id) do
      %{id: ^actor_id} -> :ok
      _ -> {:error, :key_not_carried}
    end
  end
end
