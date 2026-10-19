defmodule LineCore.EventPlan do
  @moduledoc """
  Validates and orders the event graphs used by semantic enactment.
  The alpha vocabulary is intentionally limited to item creation, containment,
  semantic properties, and actor notifications. Ordinary verbs keep their
  existing event vocabulary. Created references must have explicit dependencies.
  """

  def compile(nodes) when is_list(nodes) and length(nodes) in 1..64 do
    if Enum.all?(nodes, &node?/1) do
      ids = Enum.map(nodes, & &1.id)

      if length(Enum.uniq(ids)) == length(ids) and
           Enum.all?(nodes, fn node -> Enum.all?(node.requires, &(&1 in ids)) end) do
        order(nodes, %{}, %{}, [])
      else
        {:error, :invalid_dependencies}
      end
    else
      {:error, :invalid_event_node}
    end
  end

  def compile(_), do: {:error, :invalid_event_plan}

  defp node?(%{id: id, requires: deps, event: _} = node) do
    map_size(node) == 3 and (is_atom(id) or is_binary(id)) and is_list(deps)
  end

  defp node?(_), do: false

  defp order([], _done, _created, events), do: {:ok, Enum.reverse(events)}

  defp order(nodes, done, created, events) do
    case Enum.find(nodes, fn node -> Enum.all?(node.requires, &Map.has_key?(done, &1)) end) do
      nil ->
        {:error, :cyclic_dependencies}

      node ->
        ancestors =
          Enum.reduce(node.requires, MapSet.new(node.requires), fn id, acc ->
            MapSet.union(acc, Map.fetch!(done, id))
          end)

        case validate_event(node.event, ancestors, created) do
          {:ok, new_ref} ->
            created = if new_ref, do: Map.put(created, new_ref, node.id), else: created

            order(List.delete(nodes, node), Map.put(done, node.id, ancestors), created, [
              node.event | events
            ])

          :error ->
            {:error, {:invalid_event, node.id}}
        end
    end
  end

  defp validate_event({:create_object, ref, attrs}, _ancestors, created)
       when is_map(attrs) and (is_atom(ref) or is_binary(ref)) do
    valid =
      ref not in [nil, false] and not Map.has_key?(created, ref) and
        Enum.sort(Map.keys(attrs)) == Enum.sort([:type, :name, :description, :parent_id]) and
        attrs.type == :item and is_binary(attrs.name) and String.length(attrs.name) in 1..120 and
        is_binary(attrs.description) and byte_size(attrs.description) <= 4096 and
        uuid?(attrs.parent_id)

    if valid, do: {:ok, ref}, else: :error
  end

  defp validate_event({:set_property, ref, key, value}, ancestors, created)
       when key in ["semantic_spec", "semantic_provenance"] and is_map(value) do
    valid =
      case key do
        "semantic_spec" -> match?({:ok, _}, LineCore.ItemSpec.from_map(value))
        "semantic_provenance" -> LineCore.Consequence.validate_provenance(value) == :ok
      end

    if valid and reference?(ref, ancestors, created), do: {:ok, nil}, else: :error
  end

  defp validate_event({:relate, from, to, :contains}, ancestors, created) do
    if reference?(from, ancestors, created) and reference?(to, ancestors, created),
      do: {:ok, nil},
      else: :error
  end

  defp validate_event({:notify_actor, text}, _, _)
       when is_binary(text) and byte_size(text) <= 4096,
       do: {:ok, nil}

  defp validate_event(_, _, _), do: :error

  defp reference?({:created, ref}, ancestors, created) do
    case Map.fetch(created, ref) do
      {:ok, node_id} -> MapSet.member?(ancestors, node_id)
      :error -> false
    end
  end

  defp reference?(id, _, _), do: uuid?(id)

  defp uuid?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))
end
