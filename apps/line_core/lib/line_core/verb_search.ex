defmodule LineCore.VerbSearch do
  @moduledoc """
  MOO verb search over actor, room, direct object, and indirect object.

  Each origin walks its inheritance chain. The first matching attached verb
  wins. The special argument specifier "this" refers to the search origin,
  not the archetype object on which the inherited verb is defined.
  """

  alias LineCore.{Object, Resolver, VerbInvocation, VerbRegistry, VerbStore}
  alias LineCore.Verb.Context

  def resolve(actor_id, command) do
    with {:ok, actor} <- fetch_actor(actor_id),
         {:ok, room} <- fetch_room(actor) do
      contents = Object.contents(room.id)

      base_context = %Context{
        actor: actor,
        room: room,
        room_contents: contents,
        dobj: nil,
        iobj: nil,
        command: command.raw,
        now: DateTime.utc_now()
      }

      dobj = resolve_object(base_context, command.dobjstr)
      iobj = resolve_object(base_context, command.iobjstr)
      context = %{base_context | dobj: dobj, iobj: iobj}

      origins =
        [actor, room, dobj, iobj]
        |> Enum.reject(&is_nil/1)

      case find_first(origins, command, dobj, iobj) do
        nil ->
          {:error, :no_matching_verb}

        %{verb: verb} = match ->
          definition = VerbStore.definition(verb)

          case VerbRegistry.resolve(definition.module) do
            {:ok, module} ->
              {:ok,
               Map.merge(match, %{
                 verb_name: definition.name,
                 module: module,
                 args: VerbInvocation.args(definition, command),
                 context: context,
                 command: command
               })}

            :error ->
              {:error, :invalid_verb_implementation}
          end
      end
    end
  end

  defp find_first(origins, command, dobj, iobj) do
    Enum.find_value(origins, fn origin ->
      [origin | Object.ancestors(origin.id)]
      |> Enum.find_value(fn defined_on ->
        VerbStore.attached(defined_on.id)
        |> Enum.find_value(fn verb ->
          definition = VerbStore.definition(verb)

          if matches?(definition, command, origin, dobj, iobj) do
            %{verb: verb, origin: origin, defined_on: defined_on}
          end
        end)
      end)
    end)
  end

  defp matches?(definition, command, origin, dobj, iobj) do
    name_matches?(definition, command.verb) and
      object_spec_matches?(definition.dobj, dobj, origin) and
      prep_matches?(definition.prep, command.prepstr) and
      object_spec_matches?(definition.iobj, iobj, origin)
  end

  defp name_matches?(definition, typed) do
    typed = String.downcase(typed || "")
    canonical = String.downcase(definition.name || "")
    aliases = Enum.map(definition.aliases || [], &String.downcase/1)
    typed == canonical or typed in aliases
  end

  defp object_spec_matches?("none", object, _origin), do: is_nil(object)
  defp object_spec_matches?("any", _object, _origin), do: true

  defp object_spec_matches?("this", object, origin) do
    not is_nil(object) and object.id == origin.id
  end

  defp object_spec_matches?(_, _object, _origin), do: false

  defp prep_matches?("any", _prep), do: true
  defp prep_matches?("none", prep), do: is_nil(prep)
  defp prep_matches?(expected, prep), do: expected == prep

  defp resolve_object(_context, nil), do: nil
  defp resolve_object(context, text), do: Resolver.visible(context, text)

  defp fetch_actor(actor_id) do
    case Object.get(actor_id) do
      nil -> {:error, :actor_not_found}
      actor -> {:ok, actor}
    end
  end

  defp fetch_room(actor) do
    case Object.container_of(actor.id) do
      nil -> {:error, :actor_not_in_room}
      room -> {:ok, room}
    end
  end
end
