defmodule LineCore.Builder do
  @moduledoc false

  alias LineCore.{Archetypes, Object, Resolver}

  def allowed?(actor) do
    case Archetypes.get(:mod) do
      nil -> false
      mod -> actor.id == mod.id or Object.descendant_of?(actor.id, mod.id)
    end
  end

  def require(actor) do
    if allowed?(actor), do: :ok, else: {:error, :permission_denied}
  end

  def resolve_owned(ctx, name) do
    object = Resolver.visible(ctx, name)

    cond do
      is_nil(object) -> {:error, :not_found}
      Object.owns?(ctx.actor.id, object.id) -> {:ok, object}
      true -> {:error, :permission_denied}
    end
  end

  def archetype("$thing"), do: Archetypes.get(:item)
  def archetype("$item"), do: Archetypes.get(:item)
  def archetype("$container"), do: Archetypes.get(:container)
  def archetype("$wieldable"), do: Archetypes.get(:wieldable)
  def archetype("$weapon"), do: Archetypes.get(:weapon)
  def archetype("$clothing"), do: Archetypes.get(:clothing)
  def archetype("$room"), do: Archetypes.get(:room)
  def archetype(_), do: nil
end

defmodule LineCore.Verbs.Rename do
  @behaviour LineCore.Verb

  alias LineCore.{Object, Resolver}

  @impl true
  def execute(_ctx, []), do: {:error, :rename_what}

  def execute(ctx, [target_name, new_name]) do
    target =
      case String.downcase(String.trim(target_name)) do
        "me" -> ctx.actor
        "self" -> ctx.actor
        _ -> Resolver.visible(ctx, target_name)
      end

    cond do
      is_nil(target) ->
        {:error, :not_found}

      target.id != ctx.actor.id and not Object.owns?(ctx.actor.id, target.id) ->
        {:error, :permission_denied}

      String.trim(new_name) == "" ->
        {:error, :empty_name}

      true ->
        {:ok,
         [
           {:update_object, target.id, %{name: String.trim(new_name)}},
           {:notify_actor, "Renamed #{target.name} to #{String.trim(new_name)}."}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderCreate do
  @behaviour LineCore.Verb

  alias LineCore.Builder

  @impl true
  def execute(ctx, [parent_name, name]) do
    with :ok <- Builder.require(ctx.actor),
         parent when not is_nil(parent) <- Builder.archetype(parent_name) do
      ref = {:builder_create, ctx.actor.id, name}

      {:ok,
       [
         {:create_object, ref,
          %{type: :item, name: String.trim(name), parent_id: parent.id}},
         {:relate, ctx.actor.id, {:created, ref}, :contains},
         {:relate, ctx.actor.id, {:created, ref}, :owns},
         {:notify_actor, "Created #{String.trim(name)} as a child of #{parent.name}."}
       ]}
    else
      nil -> {:error, :unknown_class}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderDig do
  @behaviour LineCore.Verb

  alias LineCore.{Archetypes, Builder, Object}

  @impl true
  def execute(ctx, [name]) do
    with :ok <- Builder.require(ctx.actor) do
      parent = Archetypes.get(:room)
      ref = {:builder_room, ctx.actor.id, name}

      {:ok,
       [
         {:create_object, ref,
          %{type: :room, name: String.trim(name), parent_id: parent.id}},
         {:relate, ctx.actor.id, {:created, ref}, :owns},
         {:notify_actor, "Dug room #{String.trim(name)}."}
       ]}
    end
  end

  def execute(ctx, [exit_spec, destination_name]) do
    with :ok <- Builder.require(ctx.actor),
         nil <- Object.resolve_exit(ctx.room.id, exit_spec),
         destination when not is_nil(destination) <- Object.find_global_by_name(destination_name),
         true <- room?(destination) do
      canonical = Object.canonicalize_direction(exit_spec)
      exit_parent = Archetypes.get(:exit)
      ref = {:builder_exit, ctx.actor.id, ctx.room.id, canonical}

      {:ok,
       [
         {:create_object, ref,
          %{
            type: :exit,
            name: "#{canonical} exit to #{destination.name}",
            parent_id: exit_parent.id
          }},
         {:set_property, {:created, ref}, "direction", canonical},
         {:set_property, {:created, ref}, "destination_id", destination.id},
         {:relate, ctx.room.id, {:created, ref}, :contains},
         {:relate, ctx.actor.id, {:created, ref}, :owns},
         {:relate, ctx.room.id, destination.id, :exit_to, %{"direction" => canonical}},
         {:notify_actor, "Dug exit #{canonical} to #{destination.name}."}
       ]}
    else
      %{} -> {:error, :exit_exists}
      nil -> {:error, :destination_not_found}
      false -> {:error, :destination_not_room}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp room?(object) do
    case Archetypes.get(:room) do
      nil -> false
      room -> object.id == room.id or Object.descendant_of?(object.id, room.id)
    end
  end
end

defmodule LineCore.Verbs.BuilderCount do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, []) do
    with :ok <- Builder.require(ctx.actor) do
      count = length(Object.owned(ctx.actor.id))
      noun = if count == 1, do: "object", else: "objects"
      {:ok, [{:notify_actor, "You own #{count} #{noun}."}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderAudit do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, []) do
    with :ok <- Builder.require(ctx.actor) do
      owned = Object.owned(ctx.actor.id)

      text =
        case owned do
          [] -> "You own no objects."
          _ -> "Owned objects:\n" <> Enum.map_join(owned, "\n", &"  #{&1.name} [#{&1.id}]")
        end

      {:ok, [{:notify_actor, text}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderClasses do
  @behaviour LineCore.Verb

  alias LineCore.{Archetypes, Builder, Object}

  @impl true
  def execute(ctx, []) do
    with :ok <- Builder.require(ctx.actor) do
      classes =
        Archetypes.get(:root).id
        |> Object.children()
        |> Enum.filter(&(Object.get_property(&1.id, "archetype", false) == true))
        |> Enum.map(& &1.name)
        |> Enum.sort()

      {:ok, [{:notify_actor, "Classes: " <> Enum.join(classes, ", ")}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderQuota do
  @behaviour LineCore.Verb

  alias LineCore.Builder

  @impl true
  def execute(ctx, []) do
    with :ok <- Builder.require(ctx.actor) do
      {:ok, [{:notify_actor, "Build quota: unrestricted for moderators."}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderMove do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Resolver}

  @impl true
  def execute(ctx, [object_name, destination_name]) do
    with :ok <- Builder.require(ctx.actor),
         {:ok, object} <- Builder.resolve_owned(ctx, object_name),
         destination when not is_nil(destination) <- Resolver.visible(ctx, destination_name) do
      {:ok,
       [
         {:move, object.id, destination.id, :contains},
         {:notify_actor, "Moved #{object.name} to #{destination.name}."}
       ]}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderRecycle do
  @behaviour LineCore.Verb

  alias LineCore.Builder

  @impl true
  def execute(ctx, [object_name]) do
    with :ok <- Builder.require(ctx.actor),
         {:ok, object} <- Builder.resolve_owned(ctx, object_name) do
      {:ok,
       [
         {:delete_object, object.id},
         {:notify_actor, "Recycled #{object.name}."}
       ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
