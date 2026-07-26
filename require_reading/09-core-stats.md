# 09 — Core Stats

Four core stats that drive the metagame: Faction Rep, Social Clout, Money, Signal.

---

## 1. Faction Rep — Who trusts you

Reputation with factions in the world. Determines access to faction-controlled
areas, services, jobs, and items.

Faction Rep is per-faction, not global. You can be trusted by one faction and
hated by another. Actions that help one faction may hurt your standing with
a rival.

Stored as properties on the player object, keyed per faction:
`rep_<faction_name>`.

---

## 2. Social Clout — Who knows you

How well-known you are in the world. High Social Clout means NPCs recognize you,
doors open, and opportunities appear. Low Social Clout means you're a nobody.

Social Clout gain rate is driven by **Signal upload** — the more visible you
are to city systems, the faster your reputation spreads.

Stored as: `social_clout` property on the player object.

---

## 3. Money — Dirham (local) + Yuan (premium/foreign)

Two currencies:

| Currency | Role |
|----------|------|
| **Dirham** | Local currency. Earned from scrapping, selling, jobs. Spent on goods, services, rent. |
| **Yuan** | Premium/foreign currency. Harder to obtain. Required for high-end items, corp services, black market. |

Current implementation: `dirham` property on the player object. Yuan is not yet
implemented.

---

## 4. Signal — Bandwidth (up/down)

Signal is the character's connection to city systems. It has two components:

### Upload — What you push to city systems (visibility)

High upload means you're visible to the city. You show up on scanners, cameras,
databases. This accelerates Social Clout gain but also makes you easier to find.

### Download — What the city gives you (access, intel, services)

High download means the city feeds you information. You get access to better
services, faster learning, and deeper intel. This accelerates skill advancement.

### Signal = average of up/down

The combined Signal stat is the average of upload and download. It gates overall
advancement rate over time.

### Signal interactions

- **Failed hacks spike Signal upload.** A botched hack increases your visibility
  — the system noticed you.
- **Failed burglary spikes Signal + triggers owner alert.** Getting caught
  breaking in broadcasts your presence.
- **Social Clout gain rate ← Signal upload.** Visibility = fame.
- **Learning/skill advancement rate ← Signal download.** Access = growth.
- **Overall advancement rate ← Signal (gated) + Vigor/Rigor modifiers.**

Signal creates a fundamental tension: you need bandwidth to advance, but
bandwidth makes you visible. Stealth-oriented characters (high Shade) want low
upload but need download. Social characters (high Face) want high upload for
Clout but risk exposure.

Stored as: `signal_upload` and `signal_download` properties on the player object.

---

## Derivation summary

```
Iron ──────────────→ HP pool
Vigor ─────────────→ Fatigue capacity
(flat) ────────────→ Stress capacity

Iron ──────────────→ Aug slots + power ceiling

Signal upload ─────→ Social Clout gain rate
Signal download ───→ Learning / skill advancement rate
Signal (avg) ──────→ Overall advancement gate
Vigor/Rigor ───────→ Advancement rate modifiers

Failed hacks ──────→ Signal upload spike
Failed burglary ───→ Signal spike + owner alert
```

---

## World-limit barriers

Combinations of core stats gate access to content. You can't enter a high-rep
zone without Faction Rep. You can't buy corp gear without Yuan. You can't learn
advanced skills without Signal bandwidth.

These gates are properties on objects in the world (doors, NPCs, services) that
check the player's core stats before allowing interaction. They are not hardcoded
— they are data on objects.
