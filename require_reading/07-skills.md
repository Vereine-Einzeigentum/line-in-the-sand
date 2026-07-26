# 07 — Skills

19 skills. Each is an object descended from `$skill`. Skill total = sum of two
chargen attributes.

---

## Skills are objects

Skills are not an enum. They are not a hardcoded list in code. Each skill is an
object in the database, descended from the `$skill` archetype.

The `$skill` prototype defines common properties:
- `stat_a` — first attribute name (e.g., `"grit"`)
- `stat_b` — second attribute name (e.g., `"shade"`)
- `category` — skill category (e.g., `"combat"`, `"dodge"`, `"craft"`)
- `attack_speed_stat` — for combat skills, which attribute drives attack speed

Each of the 19 skill objects is a child of `$skill` with these properties set.
A player's skill total is computed: `get_property(player, stat_a) + get_property(player, stat_b)`.

---

## Combat / Weapon Skills (5)

Power comes from two stats. Attack speed is a separate layer driven by
Vigor (melee) or Rigor (ranged/tech/chem).

| Skill | Domain | Total | Attack speed |
|-------|--------|-------|-------------|
| **Blade** | Edged melee | Grit + Shade | Vigor |
| **Brawl** | Unarmed / blunt / improvised | Iron + Grit | Vigor |
| **Barrel** | Firearms | Wit + Grit | Rigor |
| **Surge** | Tech attacks (EMP, hacking, drones) | Wire + Wit | Rigor |
| **Venom** | Chemical, poison, gas, drugs | Shade + Face | Rigor |

Attack speed modifies how often you can act, not how hard you hit. Vigor/Rigor
never add to weapon skill totals.

---

## Dodge Skills (2)

| Skill | Total | Counters |
|-------|-------|----------|
| **Evade** | Shade + Vigor | Blade, Brawl (melee dodge) |
| **Slip** | Shade + Wit | Barrel, Surge, Venom (ranged/tech/chem dodge) |

Armor penalizes both dodge skills. **Shade** is the core defensive stat.

---

## Hacking Skills (3)

All Wire + second stat. Failed hacks spike Signal upload (increase visibility).

| Skill | Total | Use |
|-------|-------|-----|
| **Spoof** | Wire + Face | Fake IDs, forge data, spoof Signal. Also a crime-job. |
| **Entry** | Wire + Grit | Break locks (digital + physical). Burglary tool. |
| **Trace** | Wire + Shade | Cover own tracks AND track others. Dual-purpose. |

---

## Stealth Skills (2)

| Skill | Total | Use |
|-------|-------|-----|
| **Prowl** | Shade + Grit | Don't be seen. Move unseen, tail, hide. |
| **Cover** | Face + Rigor | Be seen as someone else. Disguise, social camouflage. |

---

## Medical (1)

| Skill | Total | Use |
|-------|-------|-----|
| **Medic** | Iron + Rigor | Heal HP, cut fatigue, field medicine. Essential gang role. |

---

## Craft Skills (4)

| Skill | Total | Use |
|-------|-------|-----|
| **Flash** | Wit + Wire | Electronics, circuit boards, chip/firmware |
| **Forge** | Wit + Rigor | Design/print objects, weapons, tools, parts, locks |
| **Rig** | Wit + Iron | Physical construction, fixing gear, installing augs |
| **Scrap** | Rigor + Vigor | Disassembly, salvage, material recovery |

Pattern: Scrappers disassemble → Wit characters build → Iron characters install.

---

## Social Skills (2)

| Skill | Total | Use |
|-------|-------|-----|
| **Hustle** | Vigor + Face | Fast-talk, deal-make. Street salesperson. |
| **Menace** | Iron + Face | Intimidate, shake down, interrogate. Enforcer. |

---

## Skill objects in the seed

The seed creates 19 skill objects as children of `$skill`. Each skill object
has its `stat_a`, `stat_b`, `category`, and (for combat skills) `attack_speed_stat`
properties set.

A player's relationship to skills is through properties on the player object:
- `skill_blade` — current skill level/XP (derived from `stat_grit + stat_shade`
  at chargen, can advance)
- `skill_blade_xp` — experience points accumulated

The skill object defines what the skill IS (formula, category). The player's
properties record their progress in that skill.

---

## Adding a new skill

1. Create a new child object of `$skill` in the seed.
2. Set `stat_a`, `stat_b`, `category`, and other properties.
3. That's it. The skill exists. Players can develop it. Verbs can gate on it.

Do not add a new enum value. Do not add a new module. Do not modify a hardcoded
list. Create an object.
