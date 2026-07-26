# 04 — Verb Dispatch

How player input becomes action. Resolution order. Argument matching.

---

## The dispatch pipeline

```
Raw input: "put sword in chest"
     |
     v
[ Parser ] -----> verb: "put", dobjstr: "sword", prep: "in", iobjstr: "chest"
     |
     v
[ Object resolution ] --> dobj: <sword object>, iobj: <chest object>
     |
     v
[ Verb search ] -----> walks objects in order, finds matching verb
     |
     v
[ Dispatcher ] ------> builds context, calls execute/2, applies events
```

---

## Step 1: Parsing

The parser splits raw input into:

- **verb** — the first word (or a recognized alias)
- **dobjstr** — direct object string (what you're acting on)
- **prepstr** — the preposition ("in", "on", "at", "to", "with", etc.)
- **iobjstr** — indirect object string (the secondary target)

Special cases:
- `"` as first character is a shortcut for `say`
- A bare direction word (`north`, `n`, etc.) is a shortcut for `go`

---

## Step 2: Object resolution

The parser resolves `dobjstr` and `iobjstr` to actual objects by searching:

1. **Player's inventory** (objects contained by the player)
2. **Room contents** (objects contained by the player's current room)
3. Special words: `"me"` / `"self"` = the player, `"here"` = the room

Resolution is case-insensitive substring matching. If ambiguous, the first
match wins. If no match, the object reference is `nil`.

---

## Step 3: Verb search — the critical part

This is where MOO dispatch differs from a MUD. There is no central command
table. The engine searches for a matching verb **on objects**, in this order:

### Search order

1. **The player** (and the player's parent chain)
2. **The room** (and the room's parent chain)
3. **The direct object** (and its parent chain)
4. **The indirect object** (and its parent chain)
5. **Fallback: the room's `huh` verb** (unrecognized command handler)

For each object, the search walks up the inheritance chain (object → parent →
grandparent → ... → `$root`) looking for a verb whose name and argument
specifiers match the parsed input.

**The first match across all objects wins.** Once a matching verb is found, the
search stops.

### Argument specifiers

Each verb object has three argument specifiers that control when it matches:

| Specifier | Values | Meaning |
|-----------|--------|---------|
| **dobj** (direct object) | `none`, `any`, `this` | What direct object this verb expects |
| **prep** (preposition) | `none`, `any`, or a specific preposition | What preposition this verb expects |
| **iobj** (indirect object) | `none`, `any`, `this` | What indirect object this verb expects |

The special value `this` means "this verb only matches when the object it's
defined on IS the direct/indirect object in the command." This is how a sword's
`wield` verb only fires when you type `wield sword`, not `wield hat`.

### Match examples

A `wield` verb on `$wieldable` with specifiers `dobj: this, prep: none, iobj: none`:
- `wield sword` — player search (no match) → room search (no match) →
  dobj search: sword → sword's parent `$wieldable` → has `wield` with
  `dobj: this` → sword IS the dobj → **MATCH**
- `wield hat` — hat is not a descendant of `$wieldable`, so when searching
  the hat's parent chain, no `wield` verb is found → no match

A `put` verb on `$container` with specifiers `dobj: any, prep: "in", iobj: this`:
- `put sword in chest` — chest descends from `$container` → has `put` with
  `iobj: this` → chest IS the iobj → **MATCH**

A `look` verb on `$root` with specifiers `dobj: any, prep: none, iobj: none`:
- `look` — player search → player's parent chain → eventually `$root` → has
  `look` with `dobj: any` → **MATCH**

---

## Step 4: Execution

Once a verb is found, the dispatcher:

1. Builds a read-only `Context` struct with: actor, room, room_contents,
   resolved dobj, resolved iobj, the raw command, and the current timestamp.
2. Checks the verb's `requirements/0` callback (skill/stat gates).
3. Calls `verb_module.execute(context, args)`.
4. The verb returns `{:ok, [events]}` or `{:error, reason}`.
5. On success, persistent events are applied in one `Ecto.Multi` transaction.
6. Notification events are broadcast via PubSub.

---

## System verbs vs game verbs

| Type | Where they live | Dispatch | Examples |
|------|----------------|----------|----------|
| **System verbs** | Parser registry | Direct module call | `who`, `help`, `quit` |
| **Game verbs** | On objects in the tree | Object tree search | `look`, `get`, `wield`, `attack` |

System verbs are out-of-character commands that don't interact with the world
model. They bypass the object tree search and dispatch directly to an Elixir
module. Keep the system verb list small — most verbs should be game verbs on
objects.

---

## Verb context variables

When a verb executes, it has access to:

| Variable | Type | Meaning |
|----------|------|---------|
| `actor` | Object | The player/mob who issued the command |
| `room` | Object | The room the actor is in |
| `room_contents` | [Object] | Everything in the room |
| `dobj` | Object \| nil | The resolved direct object |
| `iobj` | Object \| nil | The resolved indirect object |
| `command` | String | The raw input string |
| `now` | DateTime | Current timestamp |

---

## Transitional state

The current codebase uses a hardcoded `@verb_map` in the Parser that maps
strings directly to Elixir modules. This is the Phase 0 bootstrap. The target
architecture is the object-tree search described above.

Migration path:
1. System verbs stay in the parser registry.
2. Game verbs move onto objects as verb objects are implemented.
3. The parser's verb map shrinks as verbs move to objects.
4. Eventually the parser only handles system verbs and delegates everything
   else to the object tree search.
