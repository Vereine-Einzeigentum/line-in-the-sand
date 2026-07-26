# 01 — Game Design Invariants

Hard rules. Not suggestions. Not "consider." If you are an AI agent or a human
contributor, these are non-negotiable. Violating any of them means your work
gets reverted.

---

## DO

- **Everything is an object.** Players, rooms, items, NPCs, exits, skills, verbs
  — all objects in one table, one namespace, one graph. An object's type comes
  from what it descends from, not from an enum column.

- **Verbs are objects.** A verb is an object attached to another object. Verb
  behavior comes from an Elixir module reference on the verb object, but the verb
  itself is a first-class object with properties that can customize behavior.
  System verbs (parser builtins) may bypass this for bootstrapping, but all
  game verbs live on objects.

- **Verbs are pure.** `execute/2` reads context, returns events. No database
  writes. No broadcasts. No `Repo` calls. No side effects. The dispatcher is the
  only place side effects happen. This is load-bearing — it makes verbs testable,
  composable, and auditable.

- **Inheritance is a real tree.** Every object has a parent (except `$root`).
  Properties and verbs inherit down the tree. A child can override anything its
  parent defines. This is prototype-based inheritance, like JavaScript's prototype
  chain, not class-based inheritance.

- **Containment is separate from inheritance.** "Object A is a child of Object B"
  (inheritance) is a completely different relationship from "Object A is inside
  Object B" (containment). These are two independent hierarchies. Never confuse
  them. Never store them in the same relationship type.

- **The dispatcher owns all side effects.** Persistence (database writes) and
  notification (PubSub broadcasts) happen in the dispatcher and nowhere else.
  Verbs emit events. The dispatcher applies them. This is the transaction
  boundary.

- **Atomic transactions.** All persistent events from one verb execution are
  applied in a single `Ecto.Multi` transaction. All succeed or all fail. No
  partial state.

- **Soft deletes only.** Objects are never hard-deleted. `deleted_at` gets set.
  The row stays. Audit integrity depends on this.

- **UUIDs everywhere.** All object IDs are `binary_id` (UUID). No integer IDs.
  No sequential IDs. Objects are addressed by UUID.

- **Properties are JSONB-wrapped.** Scalar values stored as `%{"v" => value}`.
  Always use `Object.get_property/2,3` and `set_property/3`. Never read
  `Property.value` directly.

- **Zero-warning builds.** `mix compile --warnings-as-errors` must pass clean.
  No exceptions. No "it's just a warning."

- **`mix format` before commit.** Always.

- **Dependencies flow downward.** `line_shared` < `line_core` < `line_web`.
  `line_world` and `line_ml` depend on `line_core` and `line_shared`. Never make
  a lower app depend on a higher one.

---

## DO NOT

- **Do not hardcode object types as enums.** The current `type` column
  (`:player | :room | :item | :npc | :exit`) is a transitional artifact. Type
  comes from ancestry — "this object descends from `$room`, therefore it is a
  room." The enum will be removed. Do not add values to it. Do not branch logic
  on it in new code.

- **Do not hardcode verb lists.** The current `verbs` string-list column on
  objects and the `@verb_map` in the Parser are transitional. Verbs are objects.
  Verb dispatch walks the object tree. Do not add entries to `@verb_map` for new
  game verbs — wire them as verb objects instead.

- **Do not put side effects in verbs.** No `Repo.insert`. No `Repo.update`. No
  `PubSub.broadcast`. No `IO.puts`. Verbs return events. Period.

- **Do not conflate inheritance and containment.** "Parent" means prototype
  ancestor. "Container" means spatial location. A sword's parent is `$wieldable`.
  A sword's container is the player carrying it. These are different
  relationships stored differently.

- **Do not make skills a hardcoded list.** Skills are objects descended from a
  generic `$skill` object. There are 19 of them in the current canon. There could
  be more. They are created by the seed, not by an enum or a module list.

- **Do not add GPL/AGPL dependencies.** All current deps are MIT/Apache-2.0.
  Keep it that way.

- **Do not add a frontend build pipeline** (esbuild, webpack, etc.) without
  explicit permission. The omission is deliberate. Static CSS is served from
  `priv/static/assets/`.

- **Do not create "helper" abstractions prematurely.** Three similar lines of
  code are better than a premature abstraction. Build what the task requires.

- **Do not write verbs that query for derived data they could compute.** If a
  verb needs to know something, compute it from the context or read properties.
  Don't run Ecto queries inside verb `execute/2`.

- **Do not skip the dispatcher.** All game actions go through
  `Dispatcher.dispatch/4`. No shortcutting around it to "just update the
  database." The dispatcher is the audit trail, the transaction boundary, and
  the broadcast point.

---

## ARCHITECTURE AT A GLANCE

```
Player types "attack fence" into client
        |
        v
    [ Parser ]  — resolves "attack" to a verb, "fence" to args
        |
        v
    [ Dispatcher ]
        |
        +---> builds read-only Context (actor, room, room_contents)
        +---> checks verb requirements (skill gates)
        +---> calls verb_module.execute(context, args)
        |           |
        |           v
        |     [ Verb ]  — pure function, returns {:ok, [events]}
        |           |
        |           v
        +---> applies persistent events (Ecto.Multi transaction)
        +---> broadcasts notification events (PubSub)
        |
        v
    Player sees "You attack the fence."
    Room sees "Tester attacks the fence."
```

This flow is the spine. Every feature, every verb, every interaction goes
through it. The verb is the only place game logic lives. The dispatcher is the
only place state changes. The parser is the only entry point.
