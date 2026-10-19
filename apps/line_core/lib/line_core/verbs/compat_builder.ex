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

  def resolve_any(ctx, name) do
    normalized = name |> String.trim() |> String.downcase()

    case normalized do
      "me" ->
        ctx.actor

      "self" ->
        ctx.actor

      "here" ->
        ctx.room

      _ ->
        archetype(normalized) || Resolver.visible(ctx, name) || Object.find_global_by_name(name)
    end
  end

  def resolve_owned(ctx, name) do
    object = resolve_any(ctx, name)

    cond do
      is_nil(object) -> {:error, :not_found}
      Object.owns?(ctx.actor.id, object.id) -> {:ok, object}
      true -> {:error, :permission_denied}
    end
  end

  def resolve_mutable(ctx, name) do
    object = resolve_any(ctx, name)

    cond do
      is_nil(object) -> {:error, :not_found}
      object.id == ctx.actor.id -> {:ok, object}
      Object.owns?(ctx.actor.id, object.id) -> {:ok, object}
      true -> {:error, :permission_denied}
    end
  end

  def archetype("$root"), do: Archetypes.get(:root)
  def archetype("$thing"), do: Archetypes.get(:item)
  def archetype("$item"), do: Archetypes.get(:item)
  def archetype("$container"), do: Archetypes.get(:container)
  def archetype("$corpse"), do: Archetypes.get(:corpse)
  def archetype("$wieldable"), do: Archetypes.get(:wieldable)
  def archetype("$weapon"), do: Archetypes.get(:weapon)
  def archetype("$clothing"), do: Archetypes.get(:clothing)
  def archetype("$room"), do: Archetypes.get(:room)
  def archetype("$exit"), do: Archetypes.get(:exit)
  def archetype("$motile"), do: Archetypes.get(:motile)
  def archetype("$mob"), do: Archetypes.get(:mob)
  def archetype("$pc"), do: Archetypes.get(:pc)
  def archetype("$npc"), do: Archetypes.get(:npc)
  def archetype("$mod"), do: Archetypes.get(:mod)
  def archetype("$immobile"), do: Archetypes.get(:immobile)
  def archetype("$skill"), do: Archetypes.get(:skill)
  def archetype("$verb"), do: Archetypes.get(:verb)
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
  def execute(ctx, [parent_name, name_spec]) do
    with :ok <- Builder.require(ctx.actor),
         parent when not is_nil(parent) <- Builder.archetype(parent_name) do
      [name | aliases] =
        name_spec
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      ref = {:builder_create, ctx.actor.id, name}

      alias_event =
        if aliases == [],
          do: [],
          else: [{:set_property, {:created, ref}, "aliases", aliases}]

      {:ok,
       [
         {:create_object, ref, %{type: :item, name: name, parent_id: parent.id}},
         {:relate, ctx.actor.id, {:created, ref}, :contains},
         {:relate, ctx.actor.id, {:created, ref}, :owns}
       ] ++
         alias_event ++
         [{:notify_actor, "Created #{name} as a child of #{parent.name}."}]}
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
         {:create_object, ref, %{type: :room, name: String.trim(name), parent_id: parent.id}},
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
  def execute(ctx, []), do: audit(ctx, ctx.actor)

  def execute(ctx, [name]) do
    with :ok <- Builder.require(ctx.actor),
         target when not is_nil(target) <- Builder.resolve_any(ctx, name) do
      audit(ctx, target)
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp audit(ctx, target) do
    with :ok <- Builder.require(ctx.actor) do
      owned = Object.owned(target.id)

      text =
        case owned do
          [] ->
            "#{target.name} owns no objects."

          _ ->
            "Objects owned by #{target.name}:\n" <>
              Enum.map_join(owned, "\n", &"  #{&1.name} [#{&1.id}]")
        end

      {:ok, [{:notify_actor, text}]}
    end
  end
end

defmodule LineCore.Verbs.BuilderClasses do
  @behaviour LineCore.Verb

  alias LineCore.{Archetypes, Builder, Object}

  @impl true
  def execute(ctx, []) do
    with :ok <- Builder.require(ctx.actor) do
      classes =
        Archetypes.get(:root)
        |> descendants()
        |> Enum.filter(&(Object.get_property(&1.id, "archetype", false) == true))
        |> Enum.map(& &1.name)
        |> Enum.sort()

      {:ok, [{:notify_actor, "Classes: " <> Enum.join(classes, ", ")}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp descendants(object) do
    children = Object.children(object.id)
    children ++ Enum.flat_map(children, &descendants/1)
  end
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

  alias LineCore.Builder

  @impl true
  def execute(ctx, [object_name, destination_name]) do
    with :ok <- Builder.require(ctx.actor),
         {:ok, object} <- Builder.resolve_mutable(ctx, object_name),
         destination when not is_nil(destination) <- Builder.resolve_any(ctx, destination_name) do
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

defmodule LineCore.Verbs.BuilderOpen do
  @behaviour LineCore.Verb

  @impl true
  def execute(ctx, [exit_spec, destination_name]) do
    case LineCore.Verbs.BuilderDig.execute(ctx, [exit_spec, destination_name]) do
      {:ok, events} ->
        events =
          Enum.map(events, fn
            {:notify_actor, message} ->
              {:notify_actor, String.replace_prefix(message, "Dug exit", "Opened exit")}

            event ->
              event
          end)

        {:ok, events}

      other ->
        other
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderInspect do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [name]) do
    with :ok <- Builder.require(ctx.actor),
         object when not is_nil(object) <- Builder.resolve_any(ctx, name) do
      parent = Object.parent(object.id)
      container = Object.container_of(object.id)

      lines = [
        "#{object.name} [#{object.id}]",
        "Parent: #{if(parent, do: parent.name, else: "none")}",
        "Container: #{if(container, do: container.name, else: "none")}",
        "Children: #{length(Object.children(object.id))}",
        "Contents: #{length(Object.contents(object.id))}"
      ]

      {:ok, [{:notify_actor, Enum.join(lines, "\n")}]}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderContents do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [name]) do
    with :ok <- Builder.require(ctx.actor),
         object when not is_nil(object) <- Builder.resolve_any(ctx, name) do
      contents = Object.contents(object.id)

      text =
        case contents do
          [] ->
            "#{object.name} contains nothing."

          _ ->
            "#{object.name} contains:\n" <>
              Enum.map_join(contents, "\n", &"  #{&1.name} [#{&1.id}]")
        end

      {:ok, [{:notify_actor, text}]}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderParents do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [name]) do
    with :ok <- Builder.require(ctx.actor),
         object when not is_nil(object) <- Builder.resolve_any(ctx, name) do
      chain = Object.ancestors(object.id)

      text =
        case chain do
          [] -> "#{object.name} has no parent."
          _ -> "Parents of #{object.name}: " <> Enum.map_join(chain, " -> ", & &1.name)
        end

      {:ok, [{:notify_actor, text}]}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderKids do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [name]) do
    with :ok <- Builder.require(ctx.actor),
         object when not is_nil(object) <- Builder.resolve_any(ctx, name) do
      kids = Object.children(object.id)

      text =
        case kids do
          [] ->
            "#{object.name} has no children."

          _ ->
            "Children of #{object.name}:\n" <>
              Enum.map_join(kids, "\n", &"  #{&1.name} [#{&1.id}]")
        end

      {:ok, [{:notify_actor, text}]}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderProperties do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [name]) do
    with :ok <- Builder.require(ctx.actor),
         object when not is_nil(object) <- Builder.resolve_any(ctx, name) do
      properties =
        object.id
        |> Object.properties()
        |> Enum.sort_by(fn {key, _value} -> key end)

      text =
        case properties do
          [] ->
            "#{object.name} has no local properties."

          _ ->
            "Properties on #{object.name}:\n" <>
              Enum.map_join(properties, "\n", fn {key, value} ->
                "  #{key} = #{inspect(value)}"
              end)
        end

      {:ok, [{:notify_actor, text}]}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderVerbs do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object, VerbStore}

  @impl true
  def execute(ctx, [name]) do
    with :ok <- Builder.require(ctx.actor),
         object when not is_nil(object) <- Builder.resolve_any(ctx, name) do
      entries =
        [object | Object.ancestors(object.id)]
        |> Enum.flat_map(fn owner ->
          owner.id
          |> VerbStore.attached()
          |> Enum.map(fn verb ->
            definition = VerbStore.definition(verb)
            {definition.name, owner.name, definition}
          end)
        end)
        |> Enum.uniq_by(fn {name, _owner, _definition} -> name end)
        |> Enum.sort_by(fn {name, _owner, _definition} -> name end)

      text =
        case entries do
          [] ->
            "#{object.name} has no effective verbs."

          _ ->
            "Verbs on #{object.name}:\n" <>
              Enum.map_join(entries, "\n", fn {verb_name, owner_name, definition} ->
                aliases =
                  case definition.aliases do
                    [] -> ""
                    list -> " [" <> Enum.join(list, ", ") <> "]"
                  end

                "  #{verb_name}#{aliases} <- #{owner_name}"
              end)
        end

      {:ok, [{:notify_actor, text}]}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderChparent do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [spec]) do
    case Regex.run(~r/^(.+?)\s+to\s+(.+)$/i, spec) do
      [_, object_name, parent_name] ->
        with :ok <- Builder.require(ctx.actor),
             {:ok, object} <- Builder.resolve_owned(ctx, String.trim(object_name)),
             parent when not is_nil(parent) <- Builder.resolve_any(ctx, String.trim(parent_name)),
             :ok <- cycle_check(object, parent) do
          {:ok,
           [
             {:update_object, object.id, %{parent_id: parent.id}},
             {:notify_actor, "Changed parent of #{object.name} to #{parent.name}."}
           ]}
        else
          nil -> {:error, :not_found}
          {:error, _} = error -> error
        end

      _ ->
        {:error, :bad_args}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp cycle_check(object, parent) do
    if object.id == parent.id or Object.descendant_of?(parent.id, object.id),
      do: {:error, :inheritance_cycle},
      else: :ok
  end
end

defmodule LineCore.Verbs.BuilderSet do
  @behaviour LineCore.Verb

  alias LineCore.Builder

  @impl true
  def execute(ctx, [spec]) do
    case Regex.run(~r/^(.+)\.([A-Za-z0-9_:-]+)\s+(?:to|=)\s+(.+)$/i, spec) do
      [_, object_name, key, raw_value] ->
        with :ok <- Builder.require(ctx.actor),
             {:ok, object} <- Builder.resolve_mutable(ctx, String.trim(object_name)) do
          value = parse_value(raw_value)

          {:ok,
           [
             {:set_property, object.id, key, value},
             {:notify_actor, "Set #{object.name}.#{key} = #{inspect(value)}."}
           ]}
        end

      _ ->
        {:error, :bad_args}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp parse_value(raw) do
    value = String.trim(raw)

    cond do
      String.downcase(value) == "true" ->
        true

      String.downcase(value) == "false" ->
        false

      String.downcase(value) in ["nil", "null", "none"] ->
        nil

      Regex.match?(~r/^-?\d+$/, value) ->
        String.to_integer(value)

      Regex.match?(~r/^-?\d+\.\d+$/, value) ->
        String.to_float(value)

      String.starts_with?(value, ~s(")) and String.ends_with?(value, ~s(")) ->
        value |> String.trim_leading(~s(")) |> String.trim_trailing(~s("))

      true ->
        value
    end
  end
end

defmodule LineCore.Verbs.BuilderClear do
  @behaviour LineCore.Verb

  alias LineCore.Builder

  @impl true
  def execute(ctx, [spec]) do
    case Regex.run(~r/^(.+)\.([A-Za-z0-9_:-]+)$/i, String.trim(spec)) do
      [_, object_name, key] ->
        with :ok <- Builder.require(ctx.actor),
             {:ok, object} <- Builder.resolve_mutable(ctx, String.trim(object_name)) do
          {:ok,
           [
             {:delete_property, object.id, key},
             {:notify_actor, "Cleared #{object.name}.#{key}."}
           ]}
        end

      _ ->
        {:error, :bad_args}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderLink do
  @behaviour LineCore.Verb

  alias LineCore.{Archetypes, Builder, Object}

  @impl true
  def execute(ctx, [exit_name, destination_name]) do
    with :ok <- Builder.require(ctx.actor),
         {:ok, exit} <- Builder.resolve_owned(ctx, exit_name),
         :ok <- ensure_exit(exit),
         source when not is_nil(source) <- Object.container_of(exit.id),
         destination when not is_nil(destination) <- Builder.resolve_any(ctx, destination_name),
         :ok <- ensure_room(destination),
         direction when is_binary(direction) <- Object.get_property(exit.id, "direction") do
      old_destination_id = Object.get_property(exit.id, "destination_id")

      unlink =
        if is_binary(old_destination_id),
          do: [{:unrelate, source.id, old_destination_id, :exit_to}],
          else: []

      {:ok,
       unlink ++
         [
           {:set_property, exit.id, "destination_id", destination.id},
           {:relate, source.id, destination.id, :exit_to, %{"direction" => direction}},
           {:notify_actor, "Linked #{exit.name} to #{destination.name}."}
         ]}
    else
      nil -> {:error, :not_found}
      false -> {:error, :exit_has_no_direction}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp ensure_exit(object) do
    root = Archetypes.get(:exit)

    if root && (object.id == root.id or Object.descendant_of?(object.id, root.id)),
      do: :ok,
      else: {:error, :not_an_exit}
  end

  defp ensure_room(object) do
    root = Archetypes.get(:room)

    if root && (object.id == root.id or Object.descendant_of?(object.id, root.id)),
      do: :ok,
      else: {:error, :destination_not_room}
  end
end

defmodule LineCore.Verbs.BuilderUnlink do
  @behaviour LineCore.Verb

  alias LineCore.{Archetypes, Builder, Object}

  @impl true
  def execute(ctx, [exit_name]) do
    with :ok <- Builder.require(ctx.actor),
         {:ok, exit} <- Builder.resolve_owned(ctx, String.trim(exit_name)),
         :ok <- ensure_exit(exit),
         source when not is_nil(source) <- Object.container_of(exit.id),
         destination_id when is_binary(destination_id) <-
           Object.get_property(exit.id, "destination_id") do
      {:ok,
       [
         {:unrelate, source.id, destination_id, :exit_to},
         {:delete_property, exit.id, "destination_id"},
         {:notify_actor, "Unlinked #{exit.name}."}
       ]}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_linked}
      {:error, _} = error -> error
      _ -> {:error, :not_linked}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp ensure_exit(object) do
    root = Archetypes.get(:exit)

    if root && (object.id == root.id or Object.descendant_of?(object.id, root.id)),
      do: :ok,
      else: {:error, :not_an_exit}
  end
end

defmodule LineCore.Verbs.BuilderAddAlias do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [spec]) do
    case Regex.run(~r/^(.+?)\s+to\s+(.+)$/i, spec) do
      [_, alias_name, object_name] ->
        with :ok <- Builder.require(ctx.actor),
             {:ok, object} <- Builder.resolve_mutable(ctx, String.trim(object_name)) do
          alias_name = String.trim(alias_name)
          aliases = Object.get_local_property(object.id, "aliases") || []
          aliases = Enum.uniq(aliases ++ [alias_name])

          {:ok,
           [
             {:set_property, object.id, "aliases", aliases},
             {:notify_actor, "Added alias #{alias_name} to #{object.name}."}
           ]}
        end

      _ ->
        {:error, :bad_args}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderRmAlias do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [spec]) do
    case Regex.run(~r/^(.+?)\s+from\s+(.+)$/i, spec) do
      [_, alias_name, object_name] ->
        with :ok <- Builder.require(ctx.actor),
             {:ok, object} <- Builder.resolve_mutable(ctx, String.trim(object_name)) do
          alias_name = String.trim(alias_name)
          aliases = Object.get_local_property(object.id, "aliases") || []
          kept = Enum.reject(aliases, &(String.downcase(&1) == String.downcase(alias_name)))

          {:ok,
           [
             {:set_property, object.id, "aliases", kept},
             {:notify_actor, "Removed alias #{alias_name} from #{object.name}."}
           ]}
        end

      _ ->
        {:error, :bad_args}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderAliases do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [name]) do
    with :ok <- Builder.require(ctx.actor),
         object when not is_nil(object) <- Builder.resolve_any(ctx, name) do
      aliases = Object.get_property(object.id, "aliases", [])

      text =
        case aliases do
          [] -> "Aliases for #{object.name}: none."
          _ -> "Aliases for #{object.name}: " <> Enum.join(aliases, ", ")
        end

      {:ok, [{:notify_actor, text}]}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderProperty do
  @behaviour LineCore.Verb

  alias LineCore.Builder

  @impl true
  def execute(ctx, [spec]) do
    case Regex.run(~r/^(.+?):([A-Za-z0-9_:-]+)\s+(.+)$/i, spec) do
      [_, object_name, key, raw_value] ->
        with :ok <- Builder.require(ctx.actor),
             {:ok, object} <- Builder.resolve_mutable(ctx, String.trim(object_name)) do
          value = parse_value(raw_value)

          {:ok,
           [
             {:set_property, object.id, key, value},
             {:notify_actor, "Set property #{object.name}:#{key} = #{inspect(value)}."}
           ]}
        end

      _ ->
        {:error, :bad_args}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp parse_value(raw) do
    value = String.trim(raw)

    cond do
      String.downcase(value) == "true" ->
        true

      String.downcase(value) == "false" ->
        false

      String.downcase(value) in ["nil", "null", "none"] ->
        nil

      Regex.match?(~r/^-?\d+$/, value) ->
        String.to_integer(value)

      Regex.match?(~r/^-?\d+\.\d+$/, value) ->
        String.to_float(value)

      String.starts_with?(value, ~s(")) and String.ends_with?(value, ~s(")) ->
        value |> String.trim_leading(~s(")) |> String.trim_trailing(~s("))

      true ->
        value
    end
  end
end

defmodule LineCore.Verbs.BuilderRmProperty do
  @behaviour LineCore.Verb

  alias LineCore.Builder

  @impl true
  def execute(ctx, [spec]) do
    case Regex.run(~r/^(.+?):([A-Za-z0-9_:-]+)$/i, String.trim(spec)) do
      [_, object_name, key] ->
        with :ok <- Builder.require(ctx.actor),
             {:ok, object} <- Builder.resolve_mutable(ctx, String.trim(object_name)) do
          {:ok,
           [
             {:delete_property, object.id, key},
             {:notify_actor, "Removed property #{object.name}:#{key}."}
           ]}
        end

      _ ->
        {:error, :bad_args}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end

defmodule LineCore.Verbs.BuilderEject do
  @behaviour LineCore.Verb

  alias LineCore.{Builder, Object}

  @impl true
  def execute(ctx, [spec]) when is_binary(spec) do
    with :ok <- Builder.require(ctx.actor),
         {:ok, target_name, source} <- parse_target_and_source(ctx, spec),
         target when not is_nil(target) <-
           Object.find_by_name(Object.contents(source.id), target_name) do
      events =
        case valid_home(target) do
          nil ->
            [{:unrelate, source.id, target.id, :contains}]

          home ->
            [{:move, target.id, home.id, :contains}]
        end

      notices =
        [
          {:notify_actor, "You eject #{target.name} from #{source.name}."},
          {:notify_room, "#{ctx.actor.name} ejects #{target.name} from #{source.name}.",
           except: [ctx.actor.id, target.id]}
        ] ++
          if target.id == ctx.actor.id do
            []
          else
            [{:notify_object, target.id, "You have been ejected from #{source.name}."}]
          end

      {:ok, events ++ notices}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  defp parse_target_and_source(ctx, spec) do
    trimmed = String.trim(spec)

    case Regex.run(~r/^(.+?)\s+from\s+(.+)$/i, trimmed) do
      [_, target_name, source_name] ->
        case Builder.resolve_any(ctx, String.trim(source_name)) do
          nil -> {:error, :not_found}
          source -> {:ok, String.trim(target_name), source}
        end

      _ ->
        if trimmed == "" do
          {:error, :bad_args}
        else
          {:ok, trimmed, ctx.room}
        end
    end
  end

  defp valid_home(target) do
    case Object.get_property(target.id, "home_room_id") do
      id when is_binary(id) -> Object.get(id)
      _ -> nil
    end
  end
end
