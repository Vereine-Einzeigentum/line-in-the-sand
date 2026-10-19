defmodule LineCore.Journal.Effects do
  @moduledoc """
  Non-executable, structured projections of applied mechanical events.
  Text, arbitrary property values, and notification bodies are deliberately omitted.
  """

  def prepare(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn
      {{:create_object, attrs}, index} -> {:create_object, {:journal, index}, attrs}
      {event, _index} -> event
    end)
  end

  def project(events, changes) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {event, index} ->
      Map.put(project_event(event, changes), "index", index)
    end)
  end

  defp project_event({:set_property, ref, key, value}, changes) do
    base = %{"type" => "SET_PROPERTY", "object_id" => resolve(ref, changes), "key" => key}

    if is_number(value) or is_boolean(value) or is_nil(value),
      do: Map.put(base, "value", value),
      else: Map.put(base, "value_omitted", true)
  end

  defp project_event({:delete_property, id, key}, _) do
    %{"type" => "DELETE_PROPERTY", "object_id" => id, "key" => key}
  end

  defp project_event({:move, ref, container, rel}, changes) do
    %{
      "type" => "MOVE",
      "object_id" => resolve(ref, changes),
      "container_id" => resolve(container, changes),
      "relation" => to_string(rel)
    }
  end

  defp project_event({:relate, from, to, rel, _metadata}, changes),
    do: project_event({:relate, from, to, rel}, changes)

  defp project_event({op, from, to, rel}, changes) when op in [:relate, :unrelate] do
    %{
      "type" => op |> to_string() |> String.upcase(),
      "from_id" => resolve(from, changes),
      "to_id" => resolve(to, changes),
      "relation" => to_string(rel)
    }
  end

  defp project_event({:create_object, ref, _attrs}, changes) do
    %{"type" => "CREATE_OBJECT", "object_id" => resolve({:created, ref}, changes)}
  end

  defp project_event({:update_object, id, _attrs}, _) do
    %{"type" => "UPDATE_OBJECT", "object_id" => id, "values_omitted" => true}
  end

  defp project_event({:delete_object, id}, _),
    do: %{"type" => "DELETE_OBJECT", "object_id" => id}

  defp project_event({:notify_object, id, _}, _),
    do: %{"type" => "NOTIFY_OBJECT", "object_id" => id}

  defp project_event(event, _)
       when elem(event, 0) in [:notify_actor, :notify_room, :broadcast_channel] do
    %{"type" => event |> elem(0) |> to_string() |> String.upcase()}
  end

  defp resolve({:created, ref}, changes), do: Map.fetch!(changes, {:create_object, ref}).id
  defp resolve(id, _), do: id
end
