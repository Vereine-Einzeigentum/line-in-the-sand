defmodule LineCore.Archetypes do
  @moduledoc """
  Canonical object inheritance spine for LINE.

  The compatibility type column remains during alpha, but capability and
  behavior flow through this parent tree.
  """

  import Ecto.Query

  alias LineCore.{Object, Repo, VerbStore}
  alias LineCore.Schemas.Object, as: ObjSchema

  @legacy_item_parent_marker "migration:item_parent_v1"

  @skill_defs [
    {"$blade", "grit", "shade", "combat", "vigor"},
    {"$brawl", "iron", "grit", "combat", "vigor"},
    {"$barrel", "wit", "grit", "combat", "rigor"},
    {"$surge", "wire", "wit", "combat", "rigor"},
    {"$venom", "shade", "face", "combat", "rigor"},
    {"$evade", "shade", "vigor", "dodge", nil},
    {"$slip", "shade", "wit", "dodge", nil},
    {"$spoof", "wire", "face", "hacking", nil},
    {"$entry", "wire", "grit", "hacking", nil},
    {"$trace", "wire", "shade", "hacking", nil},
    {"$prowl", "shade", "grit", "stealth", nil},
    {"$cover", "face", "rigor", "stealth", nil},
    {"$medic", "iron", "rigor", "medical", nil},
    {"$flash", "wit", "wire", "craft", nil},
    {"$forge", "wit", "rigor", "craft", nil},
    {"$rig", "wit", "iron", "craft", nil},
    {"$scrap_skill", "rigor", "vigor", "craft", nil},
    {"$hustle", "vigor", "face", "social", nil},
    {"$menace", "iron", "face", "social", nil}
  ]

  @names %{
    root: "$root",
    room: "$room",
    exit: "$exit",
    motile: "$motile",
    mob: "$mob",
    pc: "$pc",
    npc: "$npc",
    mod: "$mod",
    immobile: "$immobile",
    item: "$item",
    container: "$container",
    corpse: "$corpse",
    wieldable: "$wieldable",
    weapon: "$weapon",
    clothing: "$clothing",
    skill: "$skill",
    verb: "$verb"
  }

  def seed do
    root = ensure!(:root, nil)
    room = ensure!(:room, root.id)
    exit = ensure!(:exit, root.id)

    motile = ensure!(:motile, root.id)
    mob = ensure!(:mob, motile.id)
    pc = ensure!(:pc, mob.id)
    npc = ensure!(:npc, mob.id)
    mod = ensure!(:mod, motile.id)

    immobile = ensure!(:immobile, root.id)

    item = ensure!(:item, root.id)
    container = ensure!(:container, item.id)
    corpse = ensure!(:corpse, container.id)
    wieldable = ensure!(:wieldable, item.id)
    weapon = ensure!(:weapon, wieldable.id)
    clothing = ensure!(:clothing, item.id)

    skill = ensure!(:skill, root.id)
    seed_skills!(skill)
    verb = ensure!(:verb, root.id)

    tree = %{
      root: root,
      room: room,
      exit: exit,
      motile: motile,
      mob: mob,
      pc: pc,
      npc: npc,
      mod: mod,
      immobile: immobile,
      item: item,
      container: container,
      corpse: corpse,
      wieldable: wieldable,
      weapon: weapon,
      clothing: clothing,
      skill: skill,
      verb: verb
    }

    install_verbs!(tree)
    tree
  end

  def adopt_existing(tree \\ seed()) do
    from(o in ObjSchema, where: is_nil(o.deleted_at))
    |> Repo.all()
    |> Enum.each(fn object ->
      unless reserved?(object) do
        desired = desired_parent_id(object, tree)

        cond do
          is_nil(desired) ->
            :ok

          is_nil(object.parent_id) ->
            set_parent!(object, desired)

          object.type == :player and
              Object.get_property(object.id, "admin") == true and
              object.parent_id == tree.pc.id ->
            set_parent!(object, tree.mod.id)

          true ->
            :ok
        end
      end
    end)

    :ok
  end

  @doc """
  One-time alpha data migration for objects created while every :item defaulted
  directly to $wieldable.

  Once complete, the root marker prevents later explicitly-wieldable objects
  from being demoted on subsequent deploys.
  """
  def normalize_legacy_item_parents(tree \\ seed()) do
    if Object.get_local_property(tree.root.id, @legacy_item_parent_marker) == true do
      :ok
    else
      from(o in ObjSchema,
        where:
          o.type == :item and
            o.parent_id == ^tree.wieldable.id and
            is_nil(o.deleted_at) and
            not like(o.name, "$%")
      )
      |> Repo.all()
      |> Enum.each(&set_parent!(&1, tree.item.id))

      {:ok, _} =
        Object.set_property(tree.root.id, @legacy_item_parent_marker, true)

      :ok
    end
  end

  def default_parent_id(type) do
    key =
      case type do
        :room -> :room
        :exit -> :exit
        :player -> :pc
        :npc -> :npc
        :item -> :item
        _ -> nil
      end

    if key do
      case find(Map.fetch!(@names, key)) do
        nil -> nil
        object -> object.id
      end
    end
  end

  def get(key) when is_atom(key), do: find(Map.fetch!(@names, key))

  defp ensure!(key, parent_id) do
    name = Map.fetch!(@names, key)

    object =
      case find(name) do
        nil ->
          {:ok, created} = Object.create(:item, name, %{parent_id: parent_id})
          created

        existing ->
          if existing.parent_id == parent_id do
            existing
          else
            set_parent!(existing, parent_id)
          end
      end

    {:ok, _} = Object.set_property(object.id, "archetype", true)
    Object.get!(object.id)
  end

  defp find(name) do
    from(o in ObjSchema,
      where: o.name == ^name and is_nil(o.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end

  defp set_parent!(object, parent_id) do
    object
    |> ObjSchema.changeset(%{parent_id: parent_id})
    |> Repo.update!()
  end

  defp reserved?(object) do
    String.starts_with?(object.name, "$")
  end

  defp desired_parent_id(object, tree) do
    case object.type do
      :room ->
        tree.room.id

      :exit ->
        tree.exit.id

      :player ->
        if Object.get_property(object.id, "admin") == true,
          do: tree.mod.id,
          else: tree.pc.id

      :npc ->
        tree.npc.id

      :item ->
        tree.item.id

      _ ->
        nil
    end
  end

  defp seed_skills!(skill_root) do
    Enum.each(@skill_defs, fn {name, stat_a, stat_b, category, speed} ->
      skill =
        case find(name) do
          nil ->
            {:ok, created} = Object.create(:item, name, %{parent_id: skill_root.id})
            created

          existing ->
            if existing.parent_id == skill_root.id,
              do: existing,
              else: set_parent!(existing, skill_root.id)
        end

      {:ok, _} = Object.set_property(skill.id, "stat_a", stat_a)
      {:ok, _} = Object.set_property(skill.id, "stat_b", stat_b)
      {:ok, _} = Object.set_property(skill.id, "category", category)

      if speed do
        {:ok, _} = Object.set_property(skill.id, "attack_speed_stat", speed)
      end
    end)

    :ok
  end

  defp install_verbs!(tree) do
    definitions = [
      {tree.root, %{name: "look", aliases: ["l"], module: "look", dobj: "any", prep: "any", iobj: "any", arg_mode: "target_optional"}},
      {tree.root, %{name: "examine", aliases: ["ex", "exam", "x"], module: "examine", dobj: "any", prep: "any", iobj: "any", arg_mode: "target_required"}},
      {tree.root, %{name: "get", aliases: ["grab", "gather", "pickup", "take"], module: "get", dobj: "any", prep: "none", iobj: "none", arg_mode: "target_required"}},
      {tree.root, %{name: "drop", aliases: ["leave", "discard", "throw"], module: "drop", dobj: "any", prep: "none", iobj: "none", arg_mode: "target_required"}},
      {tree.root, %{name: "say", aliases: [], module: "say", dobj: "any", prep: "any", iobj: "any", arg_mode: "rest"}},
      {tree.root, %{name: "emote", aliases: [], module: "emote", dobj: "any", prep: "any", iobj: "any", arg_mode: "rest"}},

      {tree.room, %{name: "go", aliases: ["move"], module: "go", dobj: "none", prep: "none", iobj: "none", arg_mode: "rest"}},

      {tree.motile, %{name: "inventory", aliases: ["inv", "i"], module: "inventory", dobj: "none", prep: "none", iobj: "none", arg_mode: "none"}},
      {tree.motile, %{name: "score", aliases: ["sc", "stats"], module: "score", dobj: "none", prep: "none", iobj: "none", arg_mode: "none"}},
      {tree.motile, %{name: "skills", aliases: ["sk"], module: "skills", dobj: "none", prep: "none", iobj: "none", arg_mode: "none"}},
      {tree.motile, %{name: "gear", aliases: ["eq", "equipment"], module: "gear", dobj: "none", prep: "none", iobj: "none", arg_mode: "none"}},
      {tree.motile, %{name: "home", aliases: [], module: "home", dobj: "none", prep: "none", iobj: "none", arg_mode: "none"}},
      {tree.motile, %{name: "@sethome", aliases: [], module: "sethome", dobj: "none", prep: "none", iobj: "none", arg_mode: "none"}},
      {tree.motile, %{name: "map", aliases: ["lmap"], module: "map", dobj: "none", prep: "none", iobj: "none", arg_mode: "none"}},
      {tree.motile, %{name: "exits", aliases: [], module: "exits", dobj: "none", prep: "none", iobj: "none", arg_mode: "none"}},
      {tree.motile, %{name: "give", aliases: ["hand"], module: "give", dobj: "any", prep: "to", iobj: "this", arg_mode: "object_pair"}},
      {tree.motile, %{name: "whisper", aliases: [], module: "whisper", dobj: "any", prep: "to", iobj: "this", arg_mode: "object_pair"}},

      {tree.mob, %{name: "attack", aliases: ["kill", "k", "hit", "stab", "slash", "shoot", "punch"], module: "attack", dobj: "this", prep: "any", iobj: "any", arg_mode: "target_required"}},

      {tree.item, %{name: "scrap", aliases: ["salvage"], module: "scrap", dobj: "this", prep: "none", iobj: "none", arg_mode: "target_required"}},

      {tree.container, %{name: "get", aliases: ["grab", "gather", "pickup", "take", "remove"], module: "get", dobj: "any", prep: "from", iobj: "this", arg_mode: "container_get"}},
      {tree.container, %{name: "put", aliases: ["place", "insert"], module: "put", dobj: "any", prep: "in", iobj: "this", arg_mode: "container_put"}},
      {tree.container, %{name: "open", aliases: [], module: "open", dobj: "this", prep: "none", iobj: "none", arg_mode: "target_required"}},
      {tree.container, %{name: "close", aliases: [], module: "close", dobj: "this", prep: "none", iobj: "none", arg_mode: "target_required"}},
      {tree.container, %{name: "lock", aliases: [], module: "lock", dobj: "this", prep: "with", iobj: "any", arg_mode: "object_pair"}},
      {tree.container, %{name: "unlock", aliases: [], module: "unlock", dobj: "this", prep: "with", iobj: "any", arg_mode: "object_pair"}},

      {tree.wieldable, %{name: "wield", aliases: ["hold", "equip"], module: "wield", dobj: "this", prep: "none", iobj: "none", arg_mode: "wield"}},
      {tree.wieldable, %{name: "unwield", aliases: ["stow"], module: "unwield", dobj: "this", prep: "none", iobj: "none", arg_mode: "target_required"}},

      {tree.clothing, %{name: "wear", aliases: [], module: "wear", dobj: "this", prep: "none", iobj: "none", arg_mode: "target_required"}},
      {tree.clothing, %{name: "remove", aliases: [], module: "remove_wear", dobj: "this", prep: "none", iobj: "none", arg_mode: "target_required"}},

      {tree.npc, %{name: "sell", aliases: ["fence"], module: "sell", dobj: "any", prep: "any", iobj: "this", arg_mode: "sell"}}
    ]

    Enum.each(definitions, fn {owner, definition} ->
      {:ok, _} = VerbStore.attach(owner.id, tree.verb.id, definition)
    end)

    :ok
  end
end
