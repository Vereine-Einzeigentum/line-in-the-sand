defmodule LineCore.Renderer do
  @moduledoc """
  Turns an Object into the five-section display format Handler specified:

      <objName>
      <Description with word wrap>
      <Visible attachments — armor, weapons, decals>
      <Where it is>
      <Anything happening to it>

  Each section can be one or more lines; missing sections collapse to nothing.
  Word-wrap is applied to description text.

  Description resolution order:
    1. `custom_description` property (set via `desc me as ...`)
    2. The `description` column on the object (set at creation time)
    3. Nothing rendered if neither is set

  Used by look/examine verbs and by room-entry rendering.
  """

  alias LineCore.Object

  @wrap_width 78

  @doc """
  Render an object in the standard five-section format.

  Returns a list of lines.
  """
  def render(object) do
    [
      render_name(object),
      render_description(object),
      render_attachments(object),
      render_location(object),
      render_state(object)
    ]
    |> Enum.reject(&match?([], &1))
    |> List.flatten()
  end

  defp render_name(%{name: name}), do: [name]

  defp render_description(object) do
    desc =
      case Object.get_property(object.id, "custom_description") do
        nil ->
          object.description

        custom when is_binary(custom) and byte_size(custom) > 0 ->
          custom

        _ ->
          object.description
      end

    case desc do
      nil -> []
      "" -> []
      text -> word_wrap(text, @wrap_width)
    end
  end

  defp render_attachments(%{id: id, type: :player}), do: wielded_and_worn(id)
  defp render_attachments(%{id: id, type: :npc}), do: wielded_and_worn(id)
  defp render_attachments(_), do: []

  defp wielded_and_worn(object_id) do
    object_id
    |> Object.equipped()
    |> Enum.map(fn
      {:wields_main, o} -> "Wielding #{o.name} in main hand."
      {:wields_off, o} -> "Wielding #{o.name} in off hand."
      {:wears, o} -> "Wearing #{o.name}."
    end)
  end

  defp render_location(%{id: id}) do
    case Object.get_property(id, "location_phrase") do
      nil -> []
      phrase -> [phrase]
    end
  end

  defp render_state(%{id: id}) do
    case Object.get_property(id, "active_state") do
      nil -> []
      state -> [state]
    end
  end

  defp word_wrap(text, width) do
    text
    |> String.split(~r/\R/)
    |> Enum.flat_map(&wrap_line(&1, width))
  end

  defp wrap_line("", _), do: [""]

  defp wrap_line(line, width) do
    line
    |> String.split(" ")
    |> Enum.reduce([""], fn word, [current | rest] ->
      cond do
        current == "" ->
          [word | rest]

        String.length(current) + 1 + String.length(word) <= width ->
          [current <> " " <> word | rest]

        true ->
          [word, current | rest]
      end
    end)
    |> Enum.reverse()
  end
end
