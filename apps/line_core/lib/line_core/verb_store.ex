defmodule LineCore.VerbStore do
  @moduledoc """
  Persistent verb definitions attached to world objects.

  Verb definitions are objects under $verb. The has_verb relationship expresses
  attachment; inheritance of the owner determines effective availability.
  """

  import Ecto.Query

  alias LineCore.{Object, Repo}
  alias LineCore.Schemas.Object, as: ObjSchema

  @fields [
    {"name", :name},
    {"aliases", :aliases},
    {"module", :module},
    {"dobj", :dobj},
    {"prep", :prep},
    {"iobj", :iobj},
    {"arg_mode", :arg_mode}
  ]

  def attach(owner_id, verb_parent_id, attrs) when is_map(attrs) do
    name = Map.get(attrs, :name) || Map.get(attrs, "name")
    object_name = "$verb:" <> owner_id <> ":" <> to_string(name)

    with true <- is_binary(name) and name != "",
         {:ok, verb} <- ensure_verb_object(object_name, verb_parent_id),
         :ok <- write_definition(verb.id, attrs),
         :ok <- ensure_attachment(owner_id, verb.id) do
      {:ok, Object.get!(verb.id)}
    else
      false -> {:error, :invalid_verb_name}
      {:error, _} = error -> error
    end
  end

  def attached(owner_id), do: Object.related_by(owner_id, :has_verb)

  def definition(verb) do
    %{
      name: Object.get_local_property(verb.id, "verb:name"),
      aliases: Object.get_local_property(verb.id, "verb:aliases") || [],
      module: Object.get_local_property(verb.id, "verb:module"),
      dobj: Object.get_local_property(verb.id, "verb:dobj") || "none",
      prep: Object.get_local_property(verb.id, "verb:prep") || "none",
      iobj: Object.get_local_property(verb.id, "verb:iobj") || "none",
      arg_mode: Object.get_local_property(verb.id, "verb:arg_mode") || "none"
    }
  end

  defp ensure_verb_object(name, parent_id) do
    case from(o in ObjSchema,
           where: o.name == ^name and is_nil(o.deleted_at),
           limit: 1
         )
         |> Repo.one() do
      nil -> Object.create(:item, name, %{parent_id: parent_id})
      verb -> {:ok, verb}
    end
  end

  defp write_definition(verb_id, attrs) do
    Enum.reduce_while(@fields, :ok, fn {key, atom_key}, :ok ->
      value = Map.get(attrs, atom_key) || Map.get(attrs, key)
      value = if key == "aliases" and is_nil(value), do: [], else: value

      if is_nil(value) do
        {:cont, :ok}
      else
        case Object.set_property(verb_id, "verb:" <> key, value) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end
    end)
  end

  defp ensure_attachment(owner_id, verb_id) do
    if Enum.any?(attached(owner_id), &(&1.id == verb_id)) do
      :ok
    else
      case Object.relate(owner_id, verb_id, :has_verb) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
