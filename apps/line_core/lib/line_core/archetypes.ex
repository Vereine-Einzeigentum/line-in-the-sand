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

  def adopt_existing(tree \ seed()) do
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
  def normalize_legacy_item_parents(tree \ seed()) do
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

  defp install_verbs!(tree) do
    definitions = [
      {tree.root, %{name: "look", aliases: ["l"], module: "look", dobj: "any", prep: "any", iobj: "any", arg_mode: "target_optional"}},
      {tree.root, %{name: "examine", aliases: ["ex", "x"], module: "examine", dobj: "any", prep: "any", iobj: "any", arg_mode: "target_required"}},
      {tree.root, %{name: "get", aliases: ["grab", "gather", "pickup", "take"], module: "get", dobj: "any", prep: "any", iobj: "any", arg_mode: "target_required"}},
      {tree.root, %{name: "drop", aliases: ["leave", "put", "discard"], module: "drop", dobj: "any", prep: "any", iobj: "any", arg_mode: "target_required"}},
      {tree.root, %{name: "say", aliases: [], module: "say", dobj: "any", prep: "any", iobj: "any", arg_mode: "rest"}},
      {tree.room, %{name: "go", aliases: ["move"], module: "go", dobj: "none", prep: "none", iobj: "none", arg_mode: "rest"}},
      {tree.motile, %{name: "inventory", aliases: ["inv", "i"], module: "inventory", dobj: "none", prep: "none", iobj: "none", arg_mode: "none"}},
      {tree.mob, %{name: "attack", aliases: ["kill", "k", "hit", "stab", "slash", "shoot", "punch"], module: "attack", dobj: "this", prep: "any", iobj: "any", arg_mode: "target_required"}},
      {tree.item, %{name: "scrap", aliases: ["salvage"], module: "scrap", dobj: "this", prep: "none", iobj: "none", arg_mode: "target_required"}},
      {tree.wieldable, %{name: "wield", aliases: ["hold", "equip"], module: "wield", dobj: "this", prep: "none", iobj: "none", arg_mode: "wield"}},
      {tree.npc, %{name: "sell", aliases: ["fence"], module: "sell", dobj: "any", prep: "any", iobj: "this", arg_mode: "sell"}}
    ]

    Enum.each(definitions, fn {owner, definition} ->
      {:ok, _} = VerbStore.attach(owner.id, tree.verb.id, definition)
    end)

    :ok
  end
end
