defmodule LineCore.ItemSpecTest do
  use ExUnit.Case, async: true

  alias LineCore.ItemSpec

  @asserted %{
    "action" => "auto",
    "mag_type" => "drum",
    "capacity" => 1000,
    "sights" => "aim_assist",
    "powered" => false
  }

  test "storage round trips tiers and reads false or completed facts literally" do
    {:ok, spec} =
      ItemSpec.new(["Flute"], %{"powered" => false}, unknown: ["name"])
      |> ItemSpec.put_solved("name", "thunder flute")

    assert {:ok, ^spec} = ItemSpec.from_map(ItemSpec.to_map(spec))
    assert ItemSpec.get(spec, "powered", true) == false
    assert ItemSpec.get(spec, "name") == "thunder flute"
  end

  test "derived and solved tiers cannot contradict each other or rewrite their own facts" do
    {:ok, spec} = ItemSpec.new(["Thing"]) |> ItemSpec.put_derived("mass", 12)
    assert {:error, {:semantic_conflict, "mass", 12, 13}} = ItemSpec.put_solved(spec, "mass", 13)
    assert {:error, {:semantic_conflict, "mass", 12, 14}} = ItemSpec.put_derived(spec, "mass", 14)
  end

  test "portable boundary rejects executable terms and forged conflicting tiers" do
    assert :ok = ItemSpec.validate(ItemSpec.new(["Impossible"], @asserted))

    assert {:error, :invalid_facts} =
             ItemSpec.validate(ItemSpec.new(["Thing"], %{"effect" => fn -> :ok end}))

    spec = %{ItemSpec.new(["Thing"], %{"mass" => 12}) | solved: %{"mass" => 13}}
    assert {:error, :conflicting_facts} = ItemSpec.validate(spec)
    spec = %{ItemSpec.new(["Thing"]) | derived: %{"mass" => 12}, unknown: MapSet.new(["mass"])}
    assert {:error, :resolved_field_marked_unknown} = ItemSpec.validate(spec)
  end

  test "preserves an absurd generated weapon literally" do
    spec =
      ItemSpec.new(
        ["Weapon", "Gun", "Pistol"],
        @asserted,
        unknown: ["mass"]
      )

    assert spec.lineage == ["Weapon", "Gun", "Pistol"]
    assert spec.asserted == @asserted
    assert spec.derived == %{}
    assert spec.solved == %{}
    assert MapSet.equal?(spec.unknown, MapSet.new(["mass"]))
  end

  test "a solved value fills an unresolved field without rewriting assertions" do
    spec =
      ItemSpec.new(
        ["Weapon", "Gun", "Pistol"],
        @asserted,
        unknown: ["mass"]
      )

    assert {:ok, solved} = ItemSpec.put_solved(spec, "mass", 38.2)

    assert solved.asserted == @asserted
    assert solved.solved == %{"mass" => 38.2}
    refute MapSet.member?(solved.unknown, "mass")
  end

  test "a derived value can resolve an unknown field" do
    spec = ItemSpec.new(["Weapon", "Gun"], %{}, unknown: ["loaded_mass"])

    assert {:ok, derived} = ItemSpec.put_derived(spec, "loaded_mass", 41.7)

    assert derived.derived == %{"loaded_mass" => 41.7}
    refute MapSet.member?(derived.unknown, "loaded_mass")
  end

  test "derived or solved facts cannot silently contradict an asserted fact" do
    spec = ItemSpec.new(["Weapon", "Gun", "Pistol"], @asserted)

    assert {:error, {:asserted_conflict, "capacity", 1000, 30}} =
             ItemSpec.put_derived(spec, "capacity", 30)

    assert {:error, {:asserted_conflict, "powered", false, true}} =
             ItemSpec.put_solved(spec, "powered", true)
  end

  test "reasserting the same value is a no-op rather than duplicate provenance" do
    spec = ItemSpec.new(["Weapon", "Gun", "Pistol"], @asserted)

    assert {:ok, ^spec} = ItemSpec.put_derived(spec, "capacity", 1000)
    assert {:ok, ^spec} = ItemSpec.put_solved(spec, "powered", false)
  end

  test "fact export is deterministic and preserves semantic tiers" do
    spec =
      ItemSpec.new(
        ["Weapon", "Gun", "Pistol"],
        @asserted,
        unknown: ["mass"]
      )

    {:ok, spec} = ItemSpec.put_derived(spec, "fire_class", "machine_pistol")
    {:ok, spec} = ItemSpec.put_solved(spec, "mass", 38.2)

    assert ItemSpec.facts(spec) == [
             {:lineage, 0, "Weapon"},
             {:lineage, 1, "Gun"},
             {:lineage, 2, "Pistol"},
             {:asserted, "action", "auto"},
             {:asserted, "capacity", 1000},
             {:asserted, "mag_type", "drum"},
             {:asserted, "powered", false},
             {:asserted, "sights", "aim_assist"},
             {:derived, "fire_class", "machine_pistol"},
             {:solved, "mass", 38.2}
           ]
  end
end
