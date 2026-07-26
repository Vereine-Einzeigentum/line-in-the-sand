# 03 — Inheritance

How properties and verbs flow from parent to child in the object tree.

---

## Two hierarchies — never confuse them

| Hierarchy | Meaning | Relationship | Example |
|-----------|---------|-------------|---------|
| **Inheritance** | "is a kind of" | `parent_id` on the object | A knife is a kind of `$wieldable` |
| **Containment** | "is inside of" | containment relationship | A knife is inside a player's inventory |

These are completely independent. A knife's parent is `$wieldable` (inheritance).
A knife's container is the player carrying it (containment). Changing where a
knife is does not change what kind of thing it is.

See `05-containment.md` for the spatial model.

---

## Property inheritance

Properties are key-value pairs on objects. When an object doesn't define a
property, the value comes from its parent. This creates a chain of defaults.

### Read resolution

To read property `key` on object `X`:

1. Check if `X` has a local value for `key`.
2. If not, check `X`'s parent.
3. If not, check the grandparent.
4. Continue up to `$root`.
5. If nobody defines it, return `nil` (or a provided default).

### Write behavior: always local

Writing a property **always creates or updates a local value on the target
object**. It never writes to a parent. This is copy-on-write semantics — the
first write to an inherited property creates a local override.

This is simpler than LambdaMOO's `TYPE_CLEAR` system where property slots are
pre-allocated on descendants. In LINE, there are no pre-allocated slots.
Properties exist on an object only if they've been explicitly set on that object
or if the object defines them as defaults.

### Consequences

- Changing a property on `$wieldable` immediately affects all wieldable objects
  that haven't overridden that property.
- Setting a property on a specific knife creates a local value. The parent's
  value is unaffected.
- Deleting a local property override re-exposes the inherited value from the
  parent chain.

---

## Verb inheritance

Verbs are objects attached to other objects. When resolving which verb to execute,
the engine walks up the inheritance tree.

### Verb objects

A verb object is a child of `$verb` (or a sub-archetype) with:

- **`name`** — the verb name (what the player types)
- **A module reference property** — points to the Elixir module that implements
  the behavior
- **Argument specifiers** — what kind of direct object, preposition, and indirect
  object this verb expects (see `04-verb-dispatch.md`)
- **Customization properties** — any properties that modify the verb's behavior
  for the specific object it's attached to

### Resolution

To find a verb on an object:

1. Check if the object has a verb object with the matching name.
2. If not, check the object's parent.
3. Continue up to `$root`.
4. First match wins.

A child object can override a parent's verb by attaching a verb object with the
same name. This is analogous to method overriding in OOP.

### System verbs

Some verbs are system-level and bypass the object tree entirely. These are
registered in the parser and dispatched directly to Elixir modules. Examples:
`who`, `help`, `quit`. System verbs exist for bootstrapping and out-of-character
commands that don't belong on in-world objects.

Game verbs — verbs that affect the world — live on objects.

---

## Ancestry queries

Since type comes from ancestry, the system needs efficient ancestry checks:

- **"Is X a room?"** — Does X descend from `$room`?
- **"Is X wieldable?"** — Does X descend from `$wieldable`?
- **"What type is X?"** — Walk up X's parent chain until you hit a well-known
  archetype.

Implementation options (to be decided):

1. **Walk the parent chain at query time.** Simple, correct, potentially slow
   for deep trees.
2. **Materialized path / closure table.** Precomputed ancestry for fast `IS A`
   queries. More complex to maintain.
3. **Cached archetype tag.** Denormalized column updated on reparenting. Fast
   reads, must be kept in sync.

The choice affects performance but not correctness. All three give the same
answers. Start simple (option 1), optimize if needed.
