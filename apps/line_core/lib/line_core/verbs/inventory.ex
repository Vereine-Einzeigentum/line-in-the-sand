defmodule LineCore.Verbs.Inventory do
  @moduledoc """
  `inventory` / `inv` / `i` — list what the actor is carrying.

  Shows items contained directly by the actor. Wielded and worn items are
  shown separately for clarity.
  """

  @behaviour LineCore.Verb

  alias LineCore.Repo
  alias LineCore.Schemas.Relationship
  import Ecto.Query

  @impl true
  def execute(ctx, []) do
    items = list_items(ctx.actor.id)
    wielded = list_relations(ctx.actor.id, [:wields_main, :wields_off])
    worn = list_relations(ctx.actor.id, [:wears])

    lines =
      cond do
        items == [] and wielded == [] and worn == [] ->
          ["You aren't carrying anything."]

        true ->
          carried_section(items) ++
            wielded_section(wielded) ++
            worn_section(worn)
      end

    {:ok, [{:notify_actor, Enum.join(lines, "\n")}]}
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Helpers

  defp list_items(actor_id) do
    actor_id
    |> LineCore.Object.contents()
    |> Enum.filter(&(&1.type == :item))
  end

  defp list_relations(actor_id, types) do
    from(o in LineCore.Schemas.Object,
      join: r in Relationship,
      on: r.to_id == o.id,
      where: r.from_id == ^actor_id and r.type in ^types and is_nil(o.deleted_at),
      select: {r.type, o.name}
    )
    |> Repo.all()
  end

  defp carried_section([]), do: []

  defp carried_section(items) do
    ["You are carrying:"] ++ Enum.map(items, fn i -> "  - #{i.name}" end)
  end

  defp wielded_section([]), do: []

  defp wielded_section(items) do
    Enum.map(items, fn
      {:wields_main, name} -> "Wielding in main hand: #{name}"
      {:wields_off, name} -> "Wielding in off hand: #{name}"
    end)
  end

  defp worn_section([]), do: []

  defp worn_section(items) do
    Enum.map(items, fn {:wears, name} -> "Wearing: #{name}" end)
  end
end
