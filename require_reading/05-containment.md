# 05 — Containment

The spatial model. How objects exist in the world.

---

## Containment is not inheritance

Read this again: **containment is not inheritance.**

- Inheritance: "a knife is a kind of wieldable" → `parent_id`
- Containment: "a knife is inside the player's inventory" → containment relationship

These are two independent hierarchies on the same set of objects. See
`03-inheritance.md` for the inheritance hierarchy. This file covers the
spatial/containment hierarchy.

---

## What containment means

An object is "contained by" another object when it is spatially inside or on
that object. Examples:

- A player is in a room → the room contains the player
- A sword is in a player's inventory → the player contains the sword
- An NPC is in a room → the room contains the NPC
- A chair is in a room → the room contains the chair

Containment is a directed relationship: container → contained.

---

## Rooms are containers

A room is an object that contains other objects. That's it. There is nothing
special about a room except that it descends from `$room` and other objects
are inside it.

A room can contain:
- Players (`$pc`)
- NPCs (`$npc`)
- Mobs (`$mob`)
- Items (`$wieldable`, `$immobile`, other)
- Exits (`$exit`)
- Other rooms (nested spaces, if needed)

---

## Exits are objects in rooms

An exit is a full object descended from `$exit`. Exits connect rooms.

### Single-containment exits

A one-way passage: the exit object is contained by the source room. It has a
property pointing to the destination room. Moving through it removes the player
from the source room's containment and adds them to the destination room's
containment.

### Multi-containment: doors

A door between two rooms exists **in both rooms simultaneously**. The exit
object has containment relationships with both rooms. A player in either room
can see the door and interact with it.

This is the one case where an object exists in more than one container at the
same time. It is specific to exits/doors that span two spaces.

Properties on a multi-contained exit:
- `direction` — varies per room (the door is "north" from Room A and "south"
  from Room B). Direction is stored on the containment relationship, not on the
  exit object itself.
- `locked` — a property on the exit object (shared state — if it's locked from
  one side, it's locked from both).

### Exit properties

| Property | Type | Meaning |
|----------|------|---------|
| `destination_id` | UUID | The room this exit leads to |
| `direction` | string | The direction label (on the containment edge, not the exit) |
| `locked` | boolean | Whether the exit is locked |
| `key_id` | UUID \| nil | Object that unlocks this exit |

---

## Movement protocol

When an object moves from one container to another:

1. The destination's `accept` verb is called (if it has one) — can this object
   enter? Check locks, capacity, permissions.
2. Check for containment loops (A contains B contains A is invalid).
3. Remove the object from the old container's containment.
4. Add the object to the new container's containment.
5. The old container's `exitfunc` fires (notification to remaining occupants).
6. The new container's `enterfunc` fires (notification to new occupants,
   room description to the mover).

Steps 1, 5, and 6 are verb calls on the containers. This makes rooms active
participants in movement — a room can refuse entry, trigger events on
arrival/departure, or customize behavior.

This protocol is implemented in the dispatcher's `:move` event handler, not in
individual verbs. The `go` verb emits a `:move` event; the dispatcher executes
the protocol.

---

## Inventory

A player's inventory is the set of objects contained by that player. There is no
separate inventory system — it's just containment.

An item "in inventory" is contained by the player. An item "in the room" is
contained by the room. `get` moves an item from room containment to player
containment. `drop` does the reverse.

---

## Wielding, wearing, and other attachments

Wielding and wearing are **relationship types**, not containment. A wielded
sword is both:
- Contained by the player (spatial — the sword is "on" the player)
- Related to the player via a `:wields_main` relationship (functional — the
  player is actively using it)

Dropping a wielded sword should unrelate the wield relationship AND move the
sword from player containment to room containment.

Current relationship types for attachments:
- `:wields_main` — main hand weapon/tool
- `:wields_off` — off hand weapon/tool
- `:wears` — worn armor/clothing

These may become their own containment-like categories or remain as relationship
types. The key point is that wielding is not the same as carrying.

---

## Containment queries

- **"What's in this room?"** — All objects whose container is the room.
- **"Where is this object?"** — The object's container (follow the containment
  relationship up).
- **"Is the player carrying the sword?"** — Is the sword contained by the player?
- **"What exits does this room have?"** — All exit objects contained by the room.
