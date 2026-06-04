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

  Used by look/examine verbs and by room-entry rendering.
  """

  alias LineCore.Object

  @wrap_width 78

  @doc """
  Render an object in the standard five-section format.

  Returns a list of lines; clients can join with newlines or render
  per-line with their own styling.
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

  defp render_description(%{description: nil}), do: []
  defp render_description(%{description: ""}), do: []

  defp render_description(%{description: desc}) do
    word_wrap(desc, @wrap_width)
  end

  defp render_attachments(%{id: id, type: :player}) do
    attachments = wielded_and_worn(id)
    if attachments == [], do: [], else: attachments
  end

  defp render_attachments(%{id: id, type: :npc}) do
    attachments = wielded_and_worn(id)
    if attachments == [], do: [], else: attachments
  end

  defp render_attachments(_), do: []

  defp wielded_and_worn(object_id) do
    import Ecto.Query
    alias LineCore.Repo
    alias LineCore.Schemas.Relationship

    from(o in LineCore.Schemas.Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where:
        r.from_id == ^object_id and
          r.type in [:wields_main, :wields_off, :wears] and
          is_nil(o.deleted_at),
      select: {r.type, o.name}
    )
    |> Repo.all()
    |> Enum.map(fn
      {:wields_main, name} -> "Wielding #{name} in main hand."
      {:wields_off, name} -> "Wielding #{name} in off hand."
      {:wears, name} -> "Wearing #{name}."
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

  ## Word-wrap

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
