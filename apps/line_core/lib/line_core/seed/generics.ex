defmodule LineCore.Seed.Generics do
  @moduledoc """
  The prototype root of the world: a mother object and the generics that derive
  from it.

  This is the MOO idiom. You do not build a room from nothing; you derive one
  from the generic room, which already knows what rooms are like. Anything a
  descendant does not define resolves upward, so changing a generic changes
  every object descended from it — including objects an object model generates
  later, which is the point: a generated NPC should inherit NPC-ness rather
  than mint every property from scratch.

  ## The tree

      The Line  (the mother object)
      ├── Generic Room
      ├── Generic Thing
      │   ├── Generic Weapon
      │   └── Generic Scrap
      └── Generic Mob
          ├── Generic Human
          │   ├── Generic NPC
          │   └── Generic PC
          └── Generic Agent
              └── Generic Operator
                  ├── Generic Supervisor ── Generic Representative
                  └── Generic Handler ──── Generic Director ──── Generic Shareholder

  **NPC and PC split at Human** so the only real difference — whether someone
  is driving it — sits at the leaf. A logged-out PC is then structurally
  identical to an NPC standing in the same room, which is what makes persistent
  bodies the default rather than a special case. Non-human creatures descend
  from `Generic Mob` directly.

  **Staff branch at Mob**, not at Human: staff are of the building, not of the
  residents. The corporate ladder is also the permission ladder, and it costs
  nothing to enforce — `Object.effective_verbs/1` already unions verbs *up* the
  chain, so an Operator will inherit every Agent verb and a Director every
  Handler verb automatically. The ladder is seeded as structure; it grants no
  verbs yet, because the moderation and production verbs it would grant do not
  exist. Listing names for unimplemented verbs would put dead strings in the
  database.

  ## `instance_type` and abstract generics

  Only *concrete* generics declare an `instance_type` property. It is what
  `LineCore.Genesis` reads to decide what type an object derived from this
  generic should be — necessary because a generic is always `:generic` itself,
  so inheriting the template's own type is always wrong.

  `Generic Thing`, `Generic Mob`, `Generic Human` and `Generic Agent` leave it
  unset on purpose. Deriving a type from one of them is a hard
  `:abstract_generic` error rather than a silent wrong answer.

  ## Defaults and the mechanics canon

  Property defaults follow `mechanics.md`, the single source of truth for
  health bars, core stats and chargen attributes. `Generic Mob` carries the
  three health bars and all eight chargen attributes; `Generic PC` carries the
  four core stats.

  Two deliberate gaps, so the data does not overstate what the engine does:

  - The canon's *derivations* are not implemented. HP pool scales off Iron and
    Fatigue capacity off Vigor; here they are flat defaults. Nothing yet reads
    Fatigue or Stress at all.
  - The nineteen skills are **not** stored. Canon defines a skill total as the
    sum of two chargen attributes, so storing totals would duplicate derived
    state. `skill_scrap_xp` is unrelated — that is experience, not a total.

  Starting attribute values are a provisional flat baseline; canon specifies
  the attributes but not chargen's opening spread.

  Idempotent, keyed on the mother object's name.
  """

  alias LineCore.Genesis
  alias LineCore.Schemas.Object, as: ObjSchema

  @mother "The Line"

  # Declarative so the shape of the world is readable as a shape. Each entry is
  # {key, parent_key, name, spec-fragment}; order matters only in that a parent
  # must appear before its children.
  @tree [
    {:mother, nil, @mother,
     %{
       description:
         "The building itself. Everything in THE LINE descends from this, whether it knows it or not.",
       verbs: ["look", "examine"]
     }},

    # -- Places ------------------------------------------------------------
    {:room, :mother, "Generic Room",
     %{
       description: "A space with edges and ways out.",
       verbs: ["go"],
       properties: %{"instance_type" => "room"}
     }},

    # -- Things ------------------------------------------------------------
    {:thing, :mother, "Generic Thing",
     %{
       description: "An object with mass, salvage value, and a history.",
       verbs: ["get", "drop", "give"]
     }},
    {:weapon, :thing, "Generic Weapon",
     %{
       description: "A thing shaped, or repurposed, for damage.",
       verbs: ["wield", "unwield"],
       properties: %{"instance_type" => "item", "damage" => 3}
     }},
    {:scrap, :thing, "Generic Scrap",
     %{
       description: "Material worth more taken apart than whole.",
       verbs: ["scrap", "sell"],
       properties: %{"instance_type" => "item", "scrap_value" => 5}
     }},

    # -- Living things -----------------------------------------------------
    {:mob, :mother, "Generic Mob",
     %{
       description: "Something alive enough to be hurt.",
       verbs: ["say", "emote", "attack"],
       properties: %{
         # Three health bars (mechanics.md). HP is the only one combat reads
         # today; Fatigue and Stress are seeded so the shape is right, not
         # because anything consumes them yet.
         "hp_current" => 20,
         "hp_max" => 20,
         "fatigue_current" => 20,
         "fatigue_max" => 20,
         "stress_current" => 0,
         "stress_max" => 100,

         # The eight chargen attributes — three opposition pairs plus the two
         # independent axes. Flat baseline pending chargen.
         "stat_wire" => 1,
         "stat_shade" => 1,
         "stat_grit" => 1,
         "stat_face" => 1,
         "stat_wit" => 1,
         "stat_iron" => 1,
         "stat_rigor" => 1,
         "stat_vigor" => 1
       }
     }},
    {:human, :mob, "Generic Human",
     %{description: "Born in THE LINE, or brought here early enough that it makes no difference."}},
    {:npc, :human, "Generic NPC",
     %{
       description: "Someone who lives here and was not summoned by a login.",
       properties: %{"instance_type" => "npc"}
     }},
    {:pc, :human, "Generic PC",
     %{
       description: "A resident of THE LINE, restored more times than they admit.",
       verbs: ["inventory", "score", "who", "help", "desc", "text"],
       properties: %{
         "instance_type" => "player",

         # A PC is sturdier than a baseline Mob. 50 is what `LineCore.Combat`
         # already documents as the player HP model and falls back to, so the
         # generic and the fallback now agree instead of contradicting each
         # other — which they quietly did for as long as nothing descended
         # from the generics.
         "hp_current" => 50,
         "hp_max" => 50,

         # The four core stats (mechanics.md). Money is two currencies;
         # Signal is an up/down pair whose average gates advancement.
         "dirham" => 0,
         "yuan" => 0,
         "faction_rep" => 0,
         "social_clout" => 0,
         "signal_up" => 0,
         "signal_down" => 0
       }
     }},

    # -- Staff -------------------------------------------------------------
    # Of the building, not of the residents. Structure only for now: capability
    # is granted by position in this tree once effective_verbs/1 has a consumer.
    {:agent, :mob, "Generic Agent",
     %{description: "Not a resident. Something the building runs."}},
    {:operator, :agent, "Generic Operator",
     %{
       description: "An agent with a post and a remit.",
       properties: %{"instance_type" => "npc"}
     }},
    {:supervisor, :operator, "Generic Supervisor",
     %{description: "Watches the floor. Moderation ladder, first rung."}},
    {:representative, :supervisor, "Generic Representative",
     %{description: "Speaks for the floor to whoever is above it."}},
    {:handler, :operator, "Generic Handler",
     %{description: "Runs production. Where the work actually gets assigned."}},
    {:director, :handler, "Generic Director", %{description: "Sets what production is for."}},
    {:shareholder, :director, "Generic Shareholder",
     %{description: "Owns the outcome. Rarely on the floor."}}
  ]

  @doc "Seed the prototype chain. Returns a map of generic key => object."
  def seed do
    case find(@mother) do
      nil -> do_seed()
      _mother -> collect()
    end
  end

  @doc "The mother object, or nil before seeding."
  def mother, do: find(@mother)

  @doc "The declarative tree, as {key, parent_key, name, spec} tuples."
  def tree, do: @tree

  defp do_seed do
    Enum.reduce(@tree, %{}, fn {key, parent_key, name, fragment}, acc ->
      spec =
        fragment
        |> Map.merge(%{name: name, type: :generic, source: :seed})
        |> put_template(parent_key, acc)

      Map.put(acc, key, Genesis.create!(spec))
    end)
  end

  defp put_template(spec, nil, _acc), do: spec

  defp put_template(spec, parent_key, acc) do
    Map.put(spec, :template, Map.fetch!(acc, parent_key).id)
  end

  defp collect do
    Map.new(@tree, fn {key, _parent, name, _fragment} -> {key, find(name)} end)
  end

  defp find(name) do
    import Ecto.Query

    from(o in ObjSchema,
      where: o.name == ^name and o.type == :generic and is_nil(o.deleted_at),
      limit: 1
    )
    |> LineCore.Repo.one()
  end
end
