# REQUIRE READING — LINE IN THE SAND

Read these files **in order** before touching the codebase. They are the spec.

| # | File | What it covers |
|---|------|----------------|
| 01 | [game-design-invariants.md](01-game-design-invariants.md) | Hard rules. DO and DO NOT. Read this first, violate nothing. |
| 02 | [object-model.md](02-object-model.md) | Everything is an object. The inheritance tree. MOO equivalents. |
| 03 | [inheritance.md](03-inheritance.md) | How properties and verbs flow from parent to child. |
| 04 | [verb-dispatch.md](04-verb-dispatch.md) | How player input becomes action. Resolution order. Argument matching. |
| 05 | [containment.md](05-containment.md) | Spatial model. Rooms, exits, doors. Multi-containment. |
| 06 | [chargen-attributes.md](06-chargen-attributes.md) | The 8 attributes. The wheel. Opposition pairs. |
| 07 | [skills.md](07-skills.md) | 19 skills as objects. Formulas. Attribute frequencies. |
| 08 | [health-bars.md](08-health-bars.md) | HP, Fatigue, Stress. Scaling. Zero/max behavior. |
| 09 | [core-stats.md](09-core-stats.md) | Faction Rep, Social Clout, Money, Signal. |

Cross-reference: [MECHANICS_CANON.md](../MECHANICS_CANON.md) is the consolidated
numbers source. These specs describe **how to build it**; the canon describes
**what the numbers are**.

This is a MOO — a MUD, Object-Oriented. If you don't know what that means,
read `01` and `02` before anything else. If you think you know, read them anyway.
