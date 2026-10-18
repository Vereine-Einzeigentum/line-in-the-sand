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
