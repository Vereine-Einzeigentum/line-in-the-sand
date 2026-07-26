# 06 — Chargen Attributes

The 8 attributes that define a character. The wheel.

---

## The 8 attributes

Characters are built from 8 attributes. These are set at character generation
and are the foundation for all skills, health bars, and derived stats.

### Opposition pairs (tension — they pull against each other)

| Pair | Left | Right | Tension |
|------|------|-------|---------|
| **Wire ↔ Shade** | systems interface, connectivity | stealth, staying hidden | You can't be wired in and invisible |
| **Grit ↔ Face** | raw survival, toughness | social finesse, charisma | Roughnecks don't charm; charmers don't dig trenches |
| **Wit ↔ Iron** | cunning, intelligence | brute force, physicality | Brains vs brawn |

Opposition pairs create build tension. Investing in one side of a pair costs
the other. This forces specialization — you can't be everything.

### Independent axis (stackable — no conflict)

| Attribute | Meaning |
|-----------|---------|
| **Rigor** | Discipline, precision, methodology |
| **Vigor** | Energy, vitality, drive |

Rigor and Vigor don't oppose each other or anything else. They can be stacked
freely. They serve dual duty — see below.

---

## Special roles

### Iron → HP pool + augmentation capacity

Iron determines:
- **HP pool** — how much damage you can take
- **Bionic augmentation capacity** — how many aug slots you have and the power
  ceiling for installed augmentations

Iron is not a skill stat in itself. It's a survivability/enhancement stat. Every
build needs some Iron or they drop fast.

### Vigor → melee attack speed + advancement rate modifier

Vigor determines:
- **Melee attack speed** — how fast you swing (Blade, Brawl)
- **Advancement rate modifier** — combined with Signal for learning speed

Vigor appears in weapon skill **attack speed**, not weapon skill **totals**.
The skill total for Blade is `Grit + Shade`. Vigor makes you swing faster, not
hit harder.

Vigor also appears in some non-combat skill totals (Evade, Scrap, Hustle).

### Rigor → ranged/tech/chem attack speed + advancement rate modifier

Rigor determines:
- **Ranged/tech/chem attack speed** — how fast you shoot/hack/poison (Barrel,
  Surge, Venom)
- **Advancement rate modifier** — combined with Signal for learning speed

Same dual-duty as Vigor but for ranged/tech/chem weapons. Appears in attack
speed, not skill totals for weapon skills.

Rigor also appears in some non-combat skill totals (Cover, Medic, Forge, Scrap).

### Debt (deferred)

Reserved for Corp-tier advancement. Not implemented in Phase 0.

---

## The wheel (visual model)

```
            Wire
           /    \
         /        \
      Rigor        Shade
       |    \    /    |
       |      \/      |
       |      /\      |
       |    /    \    |
      Vigor        Grit
         \        /
           \    /
            Iron ---- Face
                 \  /
                  Wit
```

Opposition pairs are across: Wire↔Shade, Grit↔Face, Wit↔Iron.
Rigor and Vigor float independently.

---

## Attribute as properties

In the database, attributes are properties on the player object:

- `stat_wire` — integer
- `stat_shade` — integer
- `stat_grit` — integer
- `stat_face` — integer
- `stat_wit` — integer
- `stat_iron` — integer
- `stat_rigor` — integer
- `stat_vigor` — integer

These are set at character generation and stored as properties on the `$pc`
instance. The `$human` prototype may define default values that get overridden
at chargen.

---

## Attribute frequency across skills

How often each attribute appears in the 19 skill formulas (balance check):

| Attribute | Count | Skills |
|-----------|:-----:|--------|
| **Shade** | 6 | Blade, Venom, Evade, Slip, Trace, Prowl |
| **Wit** | 6 | Barrel, Surge, Slip, Flash, Forge, Rig |
| **Wire** | 5 | Surge, Spoof, Entry, Trace, Flash |
| **Grit** | 5 | Blade, Brawl, Barrel, Entry, Prowl |
| **Face** | 5 | Venom, Spoof, Cover, Hustle, Menace |
| **Iron** | 4 | Brawl, Medic, Rig, Menace |
| **Rigor** | 4 | Cover, Medic, Forge, Scrap |
| **Vigor** | 3 | Evade, Scrap, Hustle |

Vigor is thinnest in skill totals (3) but also drives melee attack speed and
advancement rate. Rigor (4) drives ranged/tech/chem attack speed and
advancement rate. The dual-duty compensates for lower formula frequency.
