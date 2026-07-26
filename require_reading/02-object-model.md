# 02 — Object Model

This is a MOO. Everything is an object.

---

## What "everything is an object" means

There is one `objects` table. Every entity in the game — every room, every
player, every NPC, every sword, every exit, every skill, every verb — is a row
in that table. Objects are identified by UUID. Objects have properties (key-value
pairs in JSONB). Objects have relationships to other objects.

There are no separate tables for rooms, items, or players. There is no `rooms`
table. There is no `items` table. An object's identity comes from **what it
descends from** in the inheritance tree.

---

## The inheritance tree

Every object has a parent (except `$root`). The parent determines what kind of
thing the object is. Properties and verbs are inherited from parent to child.

### MOO convention: the `$` prefix

In classic MOO (LambdaMOO, HellCore), generic/prototype objects are referenced
with `$` notation: `$room`, `$thing`, `$player`. In LINE IN THE SAND, these are
Elixir-native names with MOO equivalents noted.

### The tree

```
$root                          # The root object. Seeded row. Everything descends from this.
|
+-- $room                      # Generic room. Rooms are containers.
|                               # MOO equivalent: $room (#3 in HellCore)
|
+-- $exit                       # Generic exit. Exists in source room AND destination room.
|                               # MOO equivalent: $exit
|
+-- $motile                    # Things that move. The mobility archetype.
|   |
|   +-- $mob                   # Mobile entity with agency (can act, has stats).
|   |   |
|   |   +-- $human             # Human mob. Has chargen attributes.
|   |       |
|   |       +-- $pc            # Player character. Connectable by a human.
|   |       |                   # MOO equivalent: $player (#6 in HellCore)
|   |       |
|   |       +-- $npc           # Non-player character. AI-driven.
|   |
|   +-- $mod                   # Moderator. Has motility + admin privileges.
|                               # Parallel to $mob, not descended from it.
|
+-- $immobile                  # Things that don't move. Furniture, terminals, fixtures.
|
+-- $wieldable                 # Things that can be wielded. Weapons, tools.
|
+-- $skill                     # Generic skill. 19 descendants, one per skill.
|   |
|   +-- $blade                 # Grit + Shade, attack speed: Vigor
|   +-- $brawl                 # Iron + Grit, attack speed: Vigor
|   +-- $barrel                # Wit + Grit, attack speed: Rigor
|   +-- $surge                 # Wire + Wit, attack speed: Rigor
|   +-- $venom                 # Shade + Face, attack speed: Rigor
|   +-- $evade                 # Shade + Vigor
|   +-- $slip                  # Shade + Wit
|   +-- $spoof                 # Wire + Face
|   +-- $entry                 # Wire + Grit
|   +-- $trace                 # Wire + Shade
|   +-- $prowl                 # Shade + Grit
|   +-- $cover                 # Face + Rigor
|   +-- $medic                 # Iron + Rigor
|   +-- $flash                 # Wit + Wire
|   +-- $forge                 # Wit + Rigor
|   +-- $rig                   # Wit + Iron
|   +-- $scrap_skill           # Rigor + Vigor (disambiguated from the scrap verb)
|   +-- $hustle                # Vigor + Face
|   +-- $menace                # Iron + Face
|
+-- (other archetypes as needed — not a closed set)
```

### Key points

- **`$root` is a seeded database row.** It has a fixed well-known ID. Code knows
  about it. Everything chains up to it.

- **`$room` is its own archetype.** It sits at the top level, parallel to
  `$motile`, `$immobile`, etc. Rooms are not "immobile objects" — they are a
  fundamentally different kind of thing.

- **`$mod` is parallel to `$mob`, not descended from it.** Both are under
  `$motile`. A mod has motility (moves around the world) and admin privileges,
  but is not a mob in the game-mechanics sense.

- **`$exit` is a full object.** Exits have properties (direction, lock state).
  A door between two rooms means the exit object exists in both rooms
  simultaneously (multi-containment — see `05-containment.md`).

- **Skills are objects.** The 19 skills in the canon are objects descended from
  `$skill`. They are not an enum. They are not a hardcoded list. They are seeded
  into the database. New skills can be added by creating a new child of `$skill`.

- **The tree is open.** The archetypes listed here are not exhaustive. New
  top-level archetypes or sub-archetypes can be added. The system does not
  assume a closed set.

---

## Object identity

An object's "type" is determined by its ancestry. To ask "is this a room?" you
check whether the object descends from `$room`. To ask "is this a weapon?" you
check whether it descends from `$wieldable`.

The current codebase has a `type` enum column (`:player | :room | :item | :npc |
:exit`). This is transitional and will be removed. New code should not branch
on this enum. Use ancestry queries instead.

---

## Object structure (current schema + planned changes)

Each object has:

- **`id`** — UUID, primary key
- **`name`** — string, 1-120 chars
- **`description`** — string, default text description
- **`parent_id`** — UUID, foreign key to parent object (the inheritance link)
- **`deleted_at`** — soft delete timestamp
- **Properties** — key-value pairs in the `object_properties` table (JSONB values)
- **Relationships** — directed edges in the `object_relationships` table

The `type` enum and `verbs` string list are transitional fields that will be
dropped once ancestry-based type resolution and verb-as-object dispatch are
implemented.

---

## Naming convention

| LINE name | MOO equivalent | Notes |
|-----------|---------------|-------|
| `$root` | `#0` / System Object | Seeded row, well-known ID |
| `$room` | `$room` / `#3` | Generic room prototype |
| `$pc` | `$player` / `#6` | Player character prototype |
| `$npc` | (no standard) | Non-player character |
| `$mob` | (no standard) | Mobile entity with agency |
| `$wieldable` | `$thing` (partial) | Wieldable objects |
| `$immobile` | `$thing` (partial) | Non-mobile objects |
| `$exit` | `$exit` | Exit object |
| `$skill` | (no standard) | LINE-specific |

In code, these are referenced by well-known UUIDs stored as module attributes
or application config, similar to how HellCore stores `$room = #0.room`.
