defmodule LineCore.EventPlanTest do
  use ExUnit.Case, async: true
  alias LineCore.EventPlan

  @parent "00000000-0000-0000-0000-000000000001"

  defp create do
    %{
      id: :create,
      requires: [],
      event:
        {:create_object, :item,
         %{type: :item, name: "impossible flute", description: "", parent_id: @parent}}
    }
  end

  defp store(deps \\ [:create]) do
    %{
      id: :store,
      requires: deps,
      event:
        {:set_property, {:created, :item}, "semantic_spec",
         LineCore.ItemSpec.to_map(LineCore.ItemSpec.new(["Flute"]))}
    }
  end

  test "dependencies determine execution order even when nodes arrive reversed" do
    assert {:ok, [create_event, store_event]} = EventPlan.compile([store(), create()])
    assert create_event == create().event
    assert store_event == store().event
  end

  test "an incidental list order cannot substitute for a creation dependency" do
    assert {:error, {:invalid_event, :store}} = EventPlan.compile([create(), store([])])
  end

  test "rejects missing, duplicated, and cyclic graph nodes" do
    assert {:error, :invalid_dependencies} = EventPlan.compile([store()])
    assert {:error, :invalid_dependencies} = EventPlan.compile([create(), create()])

    assert {:error, :cyclic_dependencies} =
             EventPlan.compile([%{create() | requires: [:store]}, store()])
  end

  test "does not admit arbitrary world mutations or duplicate created references" do
    assert {:error, {:invalid_event, :bad}} =
             EventPlan.compile([
               %{id: :bad, requires: [], event: {:set_property, @parent, "admin", true}}
             ])

    assert {:error, {:invalid_event, :second}} =
             EventPlan.compile([
               create(),
               %{create() | id: :second, requires: [:create]}
             ])
  end

  test "invalid object fields and unresolved references are rejected before execution" do
    assert {:error, {:invalid_event, :bad}} =
             EventPlan.compile([
               %{
                 id: :bad,
                 requires: [],
                 event: {:relate, @parent, {:created, :missing}, :contains}
               }
             ])

    bad = %{create() | event: {:create_object, :item, %{type: :item}}}
    assert {:error, {:invalid_event, :create}} = EventPlan.compile([bad])
  end
end
