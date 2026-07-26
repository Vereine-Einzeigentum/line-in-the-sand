# 08 — Health Bars

Three bars: HP, Fatigue, Stress. Each works differently.

---

## HP — Physical Health

| Aspect | Value |
|--------|-------|
| Scales with | **Iron** |
| Zero means | Down (incapacitated) |
| Recovery | Medic skill, rest, items |

HP is how much physical damage you can absorb. Iron determines the pool size.
When HP hits zero, the character is down — they drop carried items, lose some
Dirham, and respawn at the safehouse.

Current implementation: `hp_current` and `hp_max` properties on the player
object. Default is 50/50 (this will change to scale with Iron).

### Death protocol (current)

When HP reaches zero:
1. All carried items drop to the current room.
2. `notify_room` announces the death.
3. Player is moved to the safehouse room.
4. HP is reset to max.
5. Dirham is penalized (configurable, default 50, floor 0).
6. Player receives a wake-up message.

**Known bug:** Wielded and worn items are NOT dropped on death. The death handler
only moves items in `:contains` relationships, not `:wields_main`, `:wields_off`,
or `:wears` relationships.

---

## Fatigue — Energy / Stamina

| Aspect | Value |
|--------|-------|
| Scales with | **Vigor** |
| Zero means | Exhausted (actions degraded or blocked) |
| Recovery | Rest |

Every action costs Fatigue. This is the natural session limiter — you can't
fight and craft and run forever. Eventually you need to rest.

Fatigue forces human rhythms onto gameplay. A character who pushes too hard
becomes sluggish and ineffective.

Not yet implemented. Properties will be `fatigue_current` and `fatigue_max` on
the player object.

---

## Stress — Mental Load

| Aspect | Value |
|--------|-------|
| Capacity | **Flat** (no stat scaling) |
| Gain/loss rates | Scale by behavior, environment, items, social |
| Max means | Breakdown (severe performance degradation) |

Stress does not scale with any attribute. Everyone has the same stress capacity.
What varies is how fast stress builds and how fast it drains — driven by what
you do and where you are.

### Stress-up sources
- Combat
- Failed actions
- Hostile environments
- Isolation

### Stress-down sources
- Apartment comfort
- Social interaction
- Substances (with addiction risk)
- Rest
- Downtime activities

High stress degrades all performance. Max stress means breakdown — the character
can barely function. This creates pressure to maintain a sustainable pace and
engage with the social/comfort systems.

Not yet implemented. Properties will be `stress_current` and `stress_max` on
the player object.

---

## Interactions between bars

- **HP loss spikes Stress.** Getting hurt is stressful.
- **High Fatigue degrades combat.** Tired fighters are worse fighters.
- **High Stress degrades everything.** Stress is the universal performance tax.
- **Rest recovers Fatigue and reduces Stress** but leaves the character
  vulnerable (can't act while resting).

The three bars create a resource triangle. You can't optimize for one without
affecting the others. A player who fights constantly burns Fatigue and Stress.
A player who rests constantly is safe but doesn't advance. The game rewards
sustainable rhythms over pure grind.
