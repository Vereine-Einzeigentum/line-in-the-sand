# MECHANICS CANON — LINE IN THE SAND

Single source of truth for **health bars, core stats, chargen attributes, and skills**.
Consolidated from `setting-spec.md` (master) and cross-checked against `handoff eine`.
When these disagree, `setting-spec.md` wins and the conflict is logged below.

Last consolidated: 2026-07-25.

---



## ✓ RESOLVED

~~ **C1 — Vigor/Rigor & skill totals** *(resolved 2026-07-25, Handler)*.
They never appear in **weapon skill** totals; in weapon skills they instead drive **attack speed** — Vigor for melee (Blade, Brawl), Rigor for ranged/tech/chem (Barrel, Surge, Venom). They **do** legitimately appear in non-combat skill totals (Evade, Cover, Medic, Forge, Scrap, Hustle). Body reflects this.
*(Supersedes the earlier "accuracy modifier" wording in `setting-spec.md` — flag it there on next canon pass.)* ~~

---

## HEALTH BARS (3)

| Bar | What | Scaling | Zero / Max |
|-----|------|---------|-----------|
| **HP** | Physical health | Iron | Zero = down |
| **Fatigue** | Energy / stamina; every action costs it, rest resets | Vigor | Natural session limiter |
| **Stress** | Mental load | Flat capacity (no stat scaling); gain/loss **rates** scale by behavior, environment, items, social | Max = breakdown; high stress degrades all performance |

Stress-down sources: apartment comfort, social interaction, substances (addiction risk), rest, downtime. Forces human rhythms.

---

## CORE STATS (4)

Everything else derives from these + chargen attributes. World-limit barriers gate on combinations of these.

1. **Faction Rep** — who trusts you.
2. **Social Clout** — who knows you.
3. **Money** — Dirham (local) + Yuan (premium/foreign).
4. **Signal** — bandwidth (up/down).
   - Upload = what you push to city systems (**visibility**). High upload → faster Social Clout gain.
   - Download = what the city gives you (**access, intel, services**). High download → faster learning/skill advancement.
   - Signal = average of up/down. Gates overall advancement rate over time.

---

## CHARGEN ATTRIBUTES (8) — the wheel

**Opposition pairs** (tension, pull against each other):

| Pair | Meaning |
|------|---------|
| **Wire ↔ Shade** | systems interface vs stealth |
| **Grit ↔ Face** | survival vs social finesse |
| **Wit ↔ Iron** | cunning vs brute force |

**Independent axis** (stackable, no conflict): **Rigor** (discipline, precision, methodology), **Vigor** (energy, vitality, drive).

**Special roles:**
- **Iron** → HP pool **and** bionic augmentation capacity (slots + power ceiling). Survivability/enhancement, not a skill stat in itself. Every build needs some or they drop fast.
- **Vigor / Rigor** → **attack-speed** modifiers in weapon skills (Vigor = melee, Rigor = ranged/tech/chem) + Signal-linked advancement-rate modifiers. Never in **weapon** skill totals; they **do** appear in non-combat skill totals.
- **Debt** → reserved for Corp-tier advancement (deferred).

---

## SKILLS (19) — total = sum of two chargen attributes

### Combat / Weapon (5) — power via 2 stats; attack speed is a separate layer
| Skill | Domain | Skill total | Attack speed |
|-------|--------|-------------|--------------|
| **Blade** | edged melee | Grit + Shade | Vigor |
| **Brawl** | unarmed / blunt / improvised | Iron + Grit | Vigor |
| **Barrel** | firearms | Wit + Grit | Rigor |
| **Surge** | tech attacks (EMP, hacking, drones) | Wire + Wit | Rigor |
| **Venom** | chemical, poison, gas, drugs | Shade + Face | Rigor |

Attack speed: **Vigor** → melee (Blade, Brawl); **Rigor** → ranged/tech/chem (Barrel, Surge, Venom). Neither adds to the weapon skill total — power comes only from the two listed stats.

### Dodge (2)
| Skill | Total | Counters |
|-------|-------|----------|
| **Evade** (melee dodge) | Shade + Vigor | Blade / Brawl |
| **Slip** (ranged/tech/chem dodge) | Shade + Wit | Barrel / Surge / Venom |

Armor penalizes both. **Shade** is the core defensive stat.

### Hacking (3) — all Wire + second; failed hacks spike Signal upload
| Skill | Total | Use |
|-------|-------|-----|
| **Spoof** | Wire + Face | fake IDs, forge data, spoof Signal (also a crime-job) |
| **Entry** | Wire + Grit | break locks (digital + physical); burglary tool |
| **Trace** | Wire + Shade | cover own tracks **and** track others (dual-purpose) |

### Stealth (2)
| Skill | Total | Use |
|-------|-------|-----|
| **Prowl** | Shade + Grit | don't be seen (move unseen, tail, hide) |
| **Cover** | Face + Rigor | be seen as someone else (disguise, social camouflage) |

### Medical (1)
| Skill | Total | Use |
|-------|-------|-----|
| **Medic** | Iron + Rigor | heal HP, cut fatigue, field medicine. Essential gang role |

### Craft (4)
| Skill | Total | Use |
|-------|-------|-----|
| **Flash** | Wit + Wire | electronics, circuit boards, chip/firmware |
| **Forge** | Wit + Rigor | design/print objects, weapons, tools, parts, locks |
| **Rig** | Wit + Iron | physical construction, fixing gear, installing augs |
| **Scrap** | Rigor + Vigor | disassembly, salvage, material recovery |

Pattern: Scrappers disassemble → Wit characters build → Iron characters install.

### Social (2)
| Skill | Total | Use |
|-------|-------|-----|
| **Hustle** | Vigor + Face | fast-talk, deal-make (street salesperson) |
| **Menace** | Iron + Face | intimidate, shake down, interrogate (enforcer) |

---

## ATTRIBUTE-FREQUENCY INTEGRITY TABLE

How many skill totals each chargen attribute appears in (all 19 skills; 38 slots = 19 × 2). Balance check.

| Attribute | Appears in | Skills |
|-----------|:----------:|--------|
| **Shade** | 6 | Blade, Venom, Evade, Slip, Trace, Prowl |
| **Wit** | 6 | Barrel, Surge, Slip, Flash, Forge, Rig |
| **Wire** | 5 | Surge, Spoof, Entry, Trace, Flash |
| **Grit** | 5 | Blade, Brawl, Barrel, Entry, Prowl |
| **Face** | 5 | Venom, Spoof, Cover, Hustle, Menace |
| **Iron** | 4 | Brawl, Medic, Rig, Menace |
| **Rigor** | 4 | Cover, Medic, Forge, Scrap |
| **Vigor** | 3 | Evade, Scrap, Hustle |

Note: Vigor is thinnest in totals (3) but also drives melee **attack speed** + advancement rate. Rigor (4) drives ranged/tech/chem **attack speed** + advancement rate. This dual-duty is intended (C1 resolution) — factor the speed/advancement load in when balancing, not just total counts.

---

## DERIVATIONS / INTERPLAY (quick map)

- HP pool ← Iron · Fatigue capacity ← Vigor · Stress = flat cap, behavior-scaled rates
- Aug slots + power ceiling ← Iron
- Social Clout gain rate ← Signal **upload**
- Learning / skill advancement rate ← Signal **download**
- Overall advancement rate ← Signal (gated) + Vigor/Rigor modifiers
- Failed hacks → Signal upload spike · Failed burglary → Signal spike + owner alert

---

## CHANGELOG

- 2026-07-25 — Initial consolidation from `setting-spec.md`; logged C1 (Vigor/Rigor in totals) and C2 (18 vs 19 skill count).
- 2026-07-25 — **C1 resolved** (Handler): Vigor/Rigor never in weapon skill totals; they drive attack speed there (Vigor melee, Rigor ranged/tech/chem) and stay in non-combat totals. Combat table + special-roles + integrity note updated. Supersedes "accuracy modifier" wording in `setting-spec.md`.
