<!--
Reference notes on HellCore, not on this codebase.

HellCore (github.com/necanthrope/HellCore) is the LambdaMOO fork HellMOO ran
on, and this project sits in that tradition. These are analysis notes with
line citations into its `hellcore.db` — our own observations about how its
systems are put together, not its source. Nothing here is a design commitment;
where it informs one, that lives in the issue it informs.

Two standing caveats, both load-bearing:

- The db is a **pruned** fork. Its README says large amounts of Hell-specific
  content were deleted. Absence in it is weak evidence of absence upstream.
- Object *numbers* in that db are unreliable. The header declares 373 live
  objects while code references numbers in the hundreds of thousands, because
  LambdaMOO recycles ids. Several constants in live verbs now dereference to
  entirely unrelated objects. Trust the parsed object table, not the constants.
-->

# HellCore combat/world subsystems — sourced specification

Source files:
- `HellCore/hellcore.db` (LambdaMOO db format v5, plain text, 766,470 lines).
  All line numbers below are 1-indexed lines in this exact file, verified by
  direct `grep`/`sed`/parsing (a custom Python parser was written to walk the
  real LambdaMOO object table — see Methodology).
- `hellmoo/pages/*.wiki` — the HellMOO wiki corpus, used only as corroborating
  *external* evidence about canonical/upstream HellMOO, never as a substitute
  for reading the db.

**Global caveat inherited from the README**: this db is a pruned fork
("deleted tons of Hell-specific objects and verbs"). The header declares
`nobjects = 373` (line 2) — i.e. only 373 objects are actually alive in this
snapshot, even though object numbers referenced throughout the code and data
range into the hundreds of thousands (highest object id ever allocated is
far larger than 373; the gap is prior objects that were created and later
recycled/deleted). This single fact turns out to be central to sections 1 and
2 below.

## Methodology note (important for trusting the line numbers)

The db contains, in addition to the 373 real objects, a **huge stale-looking
cache blob** (roughly lines 101,640–~200,000+) formatted as bare text like
`#413385:soaks` or bare `#161470` lines, one verb-name-reference per line,
apparently a verb-name/grep index property (a single STRING with embedded
newlines, or similar) built at some point in the object's history. Naively
`grep`-ing this file will match those cache lines and mistake them for real
object headers or real verb code — I hit this trap myself early on. I
verified structurally that this blob is *not* real object/verb data (it has
none of the fixed-field structure a real LambdaMOO object record has), then
wrote a parser that walks the file using the actual LambdaMOO object-record
grammar (id line → name line → **blank line** → flags/owner/location/next/
parent/child/sibling ints → verbdef count → verbdefs → propdef count →
propdef names → propval count → propvals) and found **exactly 373** matches,
agreeing with the header's declared `nobjects`. All claims below that name a
specific object (`#N = "name"`, parent, verb list, property list) come from
that parser, cross-checked against `grep -n '^#N$'` returning a *unique* line.
All claims about actual verb **source code** come from the separate,
distinct program-dump section of the file (headers of the form `#objid:N`
where `N` is a small integer *verb index*, not a verb name — this is how the
dump format differs from the cache blob, whose entries are `#objid:verbname`
or bare `#objid`).

---

## 1. Damage types

**Verified in the db:**

- `$damage` (the corified name) resolves to object **#102**, name `"damage"`,
  parent `#1` (`root`) — confirmed by directly decoding property #56 ("damage")
  on `#0` (The System Object)'s property-value table (line 449 begins the
  347-entry propval list; property `damage` decodes to `#102`). `#102` is
  defined at **line 69452**. Its own properties (`messages`, `autopsy_msg`,
  `absorb_msg`, `bleed_chance`, `knockout_chance`, `shock_chance`, `abbrev`,
  `burn_chance`, `blood_min`, `stun_chance`, `code`) and verbs (`affect`,
  `bleed`, `knockout`, `shock`, `burn`, `stun`, `tree_tag`) are exactly the
  API surface actually invoked elsewhere in real combat code — e.g.
  `type:affect(this, amount, bodypart)` and `if (amount > type.blood_min)` in
  `$creature:take_damage` (line 734615, line 734619) — confirming `#102` is
  the genuine generic damage-type prototype, not a coincidence match.
- **Only one concrete damage-type instance survives pruning**: `#199`, name
  `"beating"`, parent `#102` (`damage`) — line 102117 (verified via the
  object-table parser; it defines no verb/property overrides of its own, i.e.
  it's a pure leaf instance that only overrides inherited property *values*
  like `abbrev`). No object named/parented as Slash, Stab, Bullet, Burn,
  Electric, or Acid exists among the 373 live objects. This strongly implies
  the other six original damage-type instances were pruned along with
  everything else, and only Beat was (re)created afterward as a child of the
  surviving `$damage` generic.
- **`is_a` usage against damage types is real and load-bearing**, found in two
  independent real verbs:
  - `$creature:take_damage` (`#107:6`, lines 734573–734645): `if (is_a(type,
    atype))` where `atype` comes from a `{atype, amin, amax, ?frontmod}`
    armor-entry tuple and `type` is the incoming attack's damage-type object.
  - `$clothing:take_damage` (`#111:3`, lines 738239–738255): `if (is_a(type,
    x[1]))` where `x` is one entry of `this.armor`.

  This confirms damage types are matched by **ancestor relationship**
  (`is_a`), not raw equality — i.e. the system is architected so a more
  specific damage-type object (a hypothetical child of `Slash`, say) would
  still be soaked by armor registered against the parent `Slash` type. In
  this pruned db there is only one surviving leaf (`beating`) under `#102`,
  so in practice today the hierarchy is flat (root `damage` → one leaf), but
  the *mechanism* is fully hierarchy-aware, confirming damage types do form
  (or are designed to form) an inheritance tree exactly like every other MOO
  object.

**What #268 and #277–#282 actually are in *this* db (the critical finding):**

The `gear`/`blind_gear` player-report verbs (object `#6`, "generic player",
parent `#100` "generic RPG player") contain, at the exact lines the task
pointed at:

```
691976:dtypes = {#268, #277, #278, #279, #280, #281, #282};      (in #6:94 "gear", lines 691960-692094)
694311:dtypes = {#268, #277, #278, #279, #280, #281, #282};      (in #6:211 "blind_gear", lines 694298-694427)
694312:dtypenames = {"Beat", "Slash", "Stab", "Bullet", "Burn", "Electric", "Acid"};
```

positionally pairing `#268`→Beat, `#277`→Slash, `#278`→Stab, `#279`→Bullet,
`#280`→Burn, `#281`→Electric, `#282`→Acid. **But none of those seven object
numbers are damage types in this db.** Resolving each via the object-table
parser (all unique, confirmed real headers):

| # | line | actual name | actual parent |
|---|------|-------------|----------------|
| #268 | 630406 | `random number generator` | `#1` root |
| #277 | 631325 | `wave` (a social/emote) | `#162` social |
| #278 | 631434 | `builtin function utilities` | `#72` Generic Utilities Package |
| #279 | 631517 | `Exit Utilities` | `#72` Generic Utilities Package |
| #280 | 631658 | `leg` | `#110` **body** (a real body-part object — see §3) |
| #281 | 631725 | `statistics utilities` | `#72` Generic Utilities Package |
| #282 | 631805 | `map utilities` | `#72` Generic Utilities Package |

So `dtypes[5]` (`#280`, meant to be "Burn") is now the *body part* `leg`,
and the other six numbers are now core utility objects. **The `gear`/
`blind_gear` verbs, as they literally stand in this pruned db, are broken**:
they compute per-body-part soak numbers keyed against damage types that no
longer exist at those numbers, and their "Burn" column is silently keyed to
the `leg` body-part object instead.

**External corroboration this was once correct upstream:** the wiki page
`Flyers _Programming_.wiki` (an apparently auto-generated stat dump of live
game data for the `cessna`/`mosquito`/`dragoon` vehicles) lists an `armor`
property value verbatim as
`{{#277, 200, 200}, {#278, 200, 200}, {#172505, 200, 200}, {#268, 20, 50},
{#308, 10, 20}, {#281, 5, 30}, {#1326, 200, 200}, {#37210, 10, 30},
{#99011, 5, 10}, {#279, 10, 20}}` — i.e. `#268`, `#277`, `#278`, `#279`,
`#281` genuinely were damage-type object numbers in a live/canonical HellMOO
snapshot, exactly matching the `gear` verb's assumptions. This is strong,
independent (wiki-sourced) confirmation that the numbers were valid *at some
point*, and that this pruned db has since had those object slots reused
(LambdaMOO recycles freed object numbers on `create()`), silently breaking
the hardcoded literals in `gear`/`blind_gear`. This is not limited to that
one verb either — see the "systemic" note in §2.

The 11-damage-type list itself (`beat, slash, stab, bullet, electric, acid,
burn, radiation, cold, laser, explode`) comes from `hellmoo/pages/Damage
Types.wiki`; the pruned db's `gear` verb only ever handled 7 of these even
upstream, so `radiation`/`cold`/`laser`/`explode` were always outside that
particular report verb's scope (this is a wiki-sourced fact about canonical
HellMOO, not something I verified inside hellcore.db beyond the 7-name
array itself).

## 2. Soak / resistance

**Storage.** An `armor` property, wherever it appears (creatures, locations,
clothing/weapons via `$clothing`/`$smashable_thing`), is a **list of tuples**
`{OBJ damagetype, INT min-reduction, INT max-reduction, ?INT frontmod}`. This
is both documented in-db and implemented in-db:

- Documentation, literally attached as a help/comment string on `$clothing`
  itself (object `#111`, lines 73895–73912):
  ```
  73904:  $clothing.covers = a list of body locations (kids of $bodypart) covered by this item.
  73906:  $clothing.armor = a list of damage reductions, of the form {{OBJ damagetype, INT min-reduction, INT max-reduction}, {...}}
  73908:  $clothing.breakdown_chance = chance on each attack that this clothing will lose one point of armor protection, if any
  ```
- Confirmed by direct value-decoding of `#107`'s (`$creature`) own `armor`
  property default: `armor = [['#308', 50, 100]]` — one baseline
  (unarmored) soak entry. (`#308` itself is *also* a renumbering casualty —
  see below.)

**Per-item soak computation with random roll (`$clothing:take_damage`,
verb `#111:3`, lines 738239–738255):**

```
738241:for x in (this.armor)
738242:if (is_a(type, x[1]))
738243:rand = (x[3] <= x[2]) ? 0 | random(x[3] - x[2]);
738244:abx = max(0, (x[2] + rand) - ((this.health_max - this.health) / 3));
738245:absorbed = absorbed + abx;
```

This confirms, verbatim from source:
- **Min/max reduction IS randomly rolled per hit**: `rand = random(max-min)`,
  soak this hit = `min + rand`.
- **The "deter"/deterioration term** = `(this.health_max - this.health) / 3`
  — i.e. it is simply how much *damage the armor item itself has already
  taken*, divided by 3, subtracted from the rolled soak value. As the item's
  own `health` drops (from combat wear, see below), its effective soak drops
  linearly. This is the same formula the `gear` report verb uses verbatim
  (`deter = is_a(armor, $clothing) ? (armor.health_max - armor.health) / 3 |
  0;`, lines 691988 and 694324).
- **Multiple `armor` entries on the same item matching the incoming type are
  summed** (`absorbed = absorbed + abx` inside the loop, before capping at
  `amount`).
- **Wear/deterioration mechanism** (`#111:4`, "deteriorate", lines
  738256–738262): each hit that isn't fully absorbed has a
  `this.breakdown_chance`-scaled probability (`#111:3`, lines after the
  quoted block) of calling `this:deteriorate(1)`, which does
  `this.health = this.health - args[1]` and, if `health < 1`, calls
  `this:disintegrate()` (`#111:5`, lines 738263–738270), which recycles the
  item. So armor genuinely degrades and is eventually destroyed by combat
  use, exactly matching the wiki's plain-language description in
  `Clothing and Armor.wiki`/`Damage Types.wiki`.

**Per-body-part combination of multiple worn items** — this happens in
`$creature:take_damage` (`#107:6`, lines 734573–734645), *not* inside the
clothing verb itself:

```
734582:if (armor = this:wearing_on(bodypart))
734583:for x in (armor)
734584:if (amount > 0)
734585:amount = x:take_damage(type, amount);
734586:endif
734587:endfor
734588:endif
```

So it is a **sequential/cascading pipeline**, not a merged pool: each item
currently worn on the hit body part (`this:wearing_on(bodypart)`, itself
found on `#107`) independently absorbs from whatever `amount` is left after
the previous item, in wear-order. (The `gear`/`blind_gear` *display* verbs
instead show a simple *sum* of each item's `(min-deter)`/`(max-deter)` per
damage type for a given body part — e.g. lines 694335–694336: `data[i][1] =
data[i][1] + max(0, aval[2] - deter);` — which is a reporting approximation
of the cascading mechanic above, not identical math.)

**After worn-item armor, `#107:6` applies a second, separate layer** — the
creature's *own* intrinsic `armor` property plus the room/location's
`armor` property (lines 734590–734603):

```
734596:armor = {@this.armor, @`this.location.armor ! ANY => {}'};
734598:for x in (armor)
734599:{atype, amin, amax, ?frontmod = E_NONE} = x;
734600:if (is_a(type, atype))
734601:range = amax - amin;
734602:abx = amin + (max(0, range) ? random(range) | 0);
734603:if (frontmod)
734604:if ((!this.attacking) || (attacker != this.attacking[1]))
734605:abx = toint(tofloat(abx) * frontmod);
734606:endif
734607:endif
734608:amount = max(0, amount - abx);
```

This is the *same* random-roll-in-[min,max] pattern, applied a second time
for the creature's natural/environmental armor, and it introduces a
**"front modifier"**: an armor entry can carry a 4th element `frontmod` that
*reduces* its effectiveness specifically when the attacker is not the
creature it's currently fighting (i.e., a rear/sneak-attack penalty to
armor effectiveness), gated on `this.attacking[1]`.

**Systemic note on stale numeric references (not confined to `gear`):**
`$creature`'s own baseline `armor` default resolves to `[['#308', 50, 100]]`
(decoded directly from `#107`'s property table). `#308` in this pruned db is
`"generic file"` (line 642700, no verbs/props of its own) — a completely
unrelated core utility object, not a damage type. This is the *same*
renumbering problem found in §1's `gear` verb, but this time baked into a
live property *value* on the creature root generic itself, meaning the
default unarmored-soak entry on every creature in this db is currently
keyed against a nonsense object. This is strong evidence the stale-numeric-
reference problem is systemic across this fork, not a one-off bug in a
single reporting verb.

## 3. Body parts

**Confirmed real body-part model.** `$bodypart` (corified name on `#0`)
resolves to object `#110`, name `"body"`, parent `#1` root, defined at line
73632. It defines properties `size`, `max_damage`, `critical`, `severable`,
`exclusive_to` and verbs `take_damage`, `jizz_msg`, `tree_tag`, `add_to`,
`lick_msg`, `bite_msg`, `modify_nude` (all real, from the object-table
parse).

**Its 11 children (the actual body parts), each `parent = #110`:**
`#217 hand`, `#234 ass`, `#242 face`, `#262 back`, `#280 leg`, `#286
abdomen`, `#315 foot`, `#344 groin`, `#348 head`, `#351 chest`, `#368 arm`.

This is independently confirmed by decoding `$creature`'s (`#107`) own
`body_parts` property default value directly from the property table:
```
body_parts = ['#348','#351','#286','#344','#315','#217','#242','#262','#234','#280','#368']
```
— the exact same 11 objects, in a fixed (not alphabetical) order:
head, chest, abdomen, groin, foot, hand, face, back, ass, leg, arm.

**Hit-location selection is weighted-random by the `size` property**,
verified in real verb code, `$creature:random_bodypart` (`#107:11`, lines
734917–734926):

```
734918:r = random(100);
734919:total = 0;
734920:parts = this.body_parts;
734921:for x in (parts)
734922:if (r < (total = total + x.size))
734923:return x;
734924:endif
734925:endfor
734926:return parts[$];
```

I.e. roll `1..100`, walk the body-part list accumulating each part's `size`
weight, and return the first part whose cumulative weight exceeds the roll
(falling back to the last part). This matches `#110`'s own `size` property
def exactly (each body-part object presumably overrides `size` with its own
value; I did not individually decode all 11 `size` values — noted as
unverified detail, not needed to establish the mechanism).

## 4. Corpses and decay

**Corpses are modeled, and decay is a scheduled, probabilistic heartbeat
tick — not lazy-on-access.** `$corpse`-equivalent object `#104` ("generic
corpse", parent `#148` "generic body", line 70689) has real verbs including
`heartbeat` and `rot`, and properties `rot_msg`, `original_player`,
`bodyparts`, `restorable_blood`, `timestamp`, `killed_by`. `#245` ("generic
human corpse", line 108643) is a pure leaf child of `#104` with no
overrides.

`#104`'s `heartbeat` verb (`#104:2`, lines 733092–733103):
```
733093:if ((this.location != $tomb) && (random(1000) < 60))
733094:if ((!is_a(this.original_player, $player)) || ((time() - this.timestamp) > $rpg.player_corpse_rot_minimum))
733095:if ((!valid(this.location)) || (!this.location:occupants($player)))
733096:this:rot(1);
733097:elseif (random(100) < 20)
733098:this:rot(1);
```
— i.e. **every heartbeat tick**, a corpse not already in `$tomb` has a 6%
chance (`random(1000) < 60`) to check whether it's eligible to rot (either
it isn't tied to a live player, or enough time has passed per
`$rpg.player_corpse_rot_minimum`), and if the room has no player watching it
it rots immediately, otherwise there's a further 20% chance it rots anyway.

`#104`'s `rot` verb (`#104:3`, lines 733104–733135) is the actual decay
action: announces a `rot_msg` to the room (unless silent), notifies
`$nets.deathnet`, junks or drops the corpse's remaining contents depending
on whether it's an unwatched player corpse, and finally `move(this,
$tomb)` — the corpse is archived into a `$tomb` container object, not
deleted outright.

**The "heartbeat" here is not a native MOO-server feature** — I checked the
actual C server source shipped alongside the db (`HellCore/src/*.c`,
`*.h`) and there is **zero occurrence of "heartbeat"** anywhere in it. The
tick is instead implemented entirely in MOO code as a **self-re-arming
forked task**, seen on `$creature` (`#107:4`, "the heartbeat wrapper", lines
734535–734552):
```
734539:if ((!task_valid(this.heartbeat_task)) && (!this.f))
734540:if (is_a(this, #109))
734541:fork task_id (($rpg.heartbeat_interval - 3) + random(6))
734542:if (is_a(this, $creature))
734543:this.heartbeat_task = 0;
734544:this:_heartbeat();
734546:endfork
734547:this.heartbeat_task = task_id;
734548:this:heartbeat();
```
i.e. it forks a new task `$rpg.heartbeat_interval ± jitter` seconds in the
future that re-invokes itself (guarded by `task_valid`/`this.heartbeat_task`
bookkeeping so an object doesn't accumulate duplicate timers), then
immediately calls `this:heartbeat()` for this tick's real work. Corpses
(`#104`, parent chain includes `#148`→`#107` `$creature`) presumably inherit
this same self-scheduling wrapper, though I did not trace `#104`'s specific
wrapper invocation — noted as inferred, not directly re-verified for the
corpse object specifically (its own `heartbeat` verb, quoted above, is the
per-tick payload; the re-arming wrapper is verified on `$creature` where
corpses' ancestor chain passes through).

**No food-spoilage system was found.** I searched the entire db (not just
object names) for `spoil`, `fresh`, `temperature` — the only real hits were
`felt_temperature`/`change_temperature` verbs on `$creature` (body
temperature, not food) and no `spoil`/`fresh` verbs or properties turned up
on any food-related object. I did not find a `generic food` object among the
373 survivors at all (the corified `$food` name exists per `#0`'s property
list, but I did not resolve which object id it currently points to, and I
found no evidence — positive or negative — either way of a spoilage tick on
it). **This is an explicit gap: I can positively confirm corpse decay, but I
cannot confirm or deny food spoilage from what's in this pruned db** — most
likely absent-from-this-snapshot rather than never-existing, given how much
else was pruned, but I have no direct evidence.

## 5. Containers and vehicles

**Containers: yes, a real generic hierarchy exists.** `$container`
(corified name on `#0`) resolves to `#54`, `"generic container"`, parent
`#255` "generic smashable thing" → `#5` "generic thing" → `#1` root. Its
properties (`capacity`, `weight_reduction`, `opaque`, `dark`, `open`,
`closable`, `max_objects`, ...) and verbs (`open`, `close`, `locked`,
`get_from`, `put_into`, `tell_contents`, ...) are pure inventory-container
behavior — nothing room- or vehicle-related. Real subclasses found: `#188`
generic globbing container, `#146` generic lockable container (child of
`#188`), `#338` generic liquid container, `#347` generic drug container.
(There is also a vestigial, explicitly-deprecated `#8` "LambdaCore generic
container (use $container instead)" — a leftover from the base LambdaCore
distribution, own comment says not to use it.) **Containers do not contain
rooms** — nothing in `#54`'s property/verb set spawns or references a room
interior.

**Vehicles: absent from this pruned db, but demonstrably present in
canonical/upstream HellMOO.**

- No object among the 373 survivors has a name containing "vehicle",
  "flyer", "car", "cessna", "mosquito", "dragoon", "pilot", "helicopter", or
  "boat".
- `#0`'s corified-name property table (the authoritative registry of every
  `$name` in the MOO — I decoded all 337 of its own properties) contains no
  `vehicle` and no `flyer` entry at all, alongside confirmed entries for
  everything else discussed above (`container=#54`, `damage=#102`,
  `bodypart=#110`, `clothing=#111`, `creature=#107`, `player=#6`,
  `area=#114`, `weapon=#95`, `npc=#106`, `thing=#5`, `room=#3`, `exit=#55`,
  `recycler=#57`, `device=#115`). This is a clean, direct absence, not an
  inference from missing objects alone.
- The stale verb-name cache blob (see Methodology) *does* contain entries
  `find_vehicle`/`get_vehicle_type` attributed to objects `#399225` and
  `#355619` (lines 122739–122747) — and I confirmed **neither object id
  exists among the 373 real survivors**. This is direct evidence that
  vehicle-handling objects existed at some point and were subsequently
  pruned, i.e. genuinely "pruned," not "never implemented."
- Static help text (a wiki-help string embedded in the db itself, lines
  77696 and 79352, near-duplicate ANSI-colored and plain versions of the
  same help topic) reads: *"there are a wide variety of vehicles (and at
  least a couple mutations) that can make your movement faster. These range
  from motorcycles for the land, ultralight helicopters to zeppelins for the
  sky, and speedboats up to party yachts for the sea. See 'help travel' for
  more information."* — confirming vehicles were a designed, documented
  feature, just with their implementing objects gone from this snapshot.
- External corroboration from the wiki: `Flyers _Programming_.wiki` documents
  three concrete flyer vehicles (cessna, mosquito, dragoon) with a `blueprint`
  property described as *"the blueprint used to spawn the flyer's interior at
  creation"* — i.e. **in canonical HellMOO, vehicles do contain rooms**,
  generated on demand from a blueprint template. `Pilot.wiki` confirms a
  dedicated "Pilot" skill for "the ability to pilot various vehicles,
  including helicopters, boats, and land vehicles."
- The generic **blueprint-instantiation substrate itself does survive** in
  this pruned db: `$blueprint` resolves to `#334`, `"generic blueprint"`
  (line 672224), parent `#114` `$area` ("generic area"). It has real verbs
  `instantiate`, `rooms`, `dig`, `default_room`, `default_exit`, `bury`,
  `warp`, etc. — a general room/exit templating mechanism. This is
  general-purpose (used for more than just vehicles in HellMOO, per its
  generic name and `$area` parentage), so I can only confirm the *substrate*
  a vehicle's interior-spawning would have used still exists; I found no
  vehicle-specific glue code (nothing wiring a container-like vessel object
  to a blueprint) anywhere in the 373 surviving objects. **Conclusion:
  vehicles as a concrete feature (and their room-containing behavior) are
  absent from this snapshot, most likely pruned rather than never built.**

---

## Summary of things I could NOT find / explicitly unresolved

- The other six original damage-type instance objects (Slash, Stab, Bullet,
  Burn, Electric, Acid) — only `#199` "beating" survives as a concrete
  `$damage` child.
- The `soaks`, `soak_report`, and `highest_and_lowest_soak` verbs named in
  the task prompt: their names appear only in the **stale verb-name cache
  blob** (e.g. `#413385:soaks` at line 117502, `#364606:soak_report` /
  `#91479:soak_report` at 123989/123994, `#298277:highest_and_lowest_soak` /
  `#94743:highest_and_lowest_soak` at 131046/131047), and every one of those
  object ids (`413385`, `364606`, `91479`, `298277`, `94743`) is **absent**
  from the 373 real surviving objects. I could not find real source code for
  any of these three verbs anywhere in the file — they were pruned along
  with their host objects. The actual, currently-live soak/report logic in
  this db lives inline inside `$player:gear`/`$player:blind_gear` (`#6:94`/
  `#6:211`) and inside `$creature:take_damage`/`$clothing:take_damage`, as
  documented in §§1–2, not in separately-named `soaks`/`soak_report`/
  `highest_and_lowest_soak` verbs.
- Exact `size` values for each of the 11 body-part objects (I confirmed the
  weighting *mechanism* and the *list* of parts, not each part's individual
  weight).
- Whether `$food` (corified but its target object id not resolved here) has
  any spoilage logic — no positive or negative evidence found; flagged as an
  open gap above rather than guessed at.
- The corpse object's own heartbeat re-arming wrapper specifically (I
  verified the wrapper mechanism on `$creature` where corpses inherit
  through `#148`, but did not separately trace `#104`'s own copy/override,
  if any).
