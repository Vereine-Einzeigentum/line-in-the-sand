defmodule LineCore.Verbs.Inventory do
  @moduledoc """
  `inventory` / `inv` / `i` — list what the actor is carrying.

  Shows items contained directly by the actor. Wielded and worn items are
  shown separately for clarity.
  """

  @behaviour LineCore.Verb

  alias LineCore.Object

  @impl true
  def execute(ctx, []) do
    items =
      ctx.actor.id
      |> Object.contents()
      |> Enum.filter(&(&1.type == :item))

    equipped = Object.equipped(ctx.actor.id)
    wielded = Enum.filter(equipped, fn {t, _} -> t in [:wields_main, :wields_off] end)
    worn = Enum.filter(equipped, fn {t, _} -> t == :wears end)

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

  defp carried_section([]), do: []

  defp carried_section(items) do
    ["You are carrying:"] ++ Enum.map(items, fn i -> "  - #{i.name}" end)
  end

  defp wielded_section([]), do: []

  defp wielded_section(items) do
    Enum.map(items, fn
      {:wields_main, o} -> "Wielding in main hand: #{o.name}"
      {:wields_off, o} -> "Wielding in off hand: #{o.name}"
    end)
  end

  defp worn_section([]), do: []

  defp worn_section(items) do
    Enum.map(items, fn {:wears, o} -> "Wearing: #{o.name}" end)
  end
end
