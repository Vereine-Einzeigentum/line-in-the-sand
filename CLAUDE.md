# CLAUDE.md

Guidance for AI assistants (and humans) working in this repository.

## What this is

**LINE IN THE SAND** is a multiplayer text **MOO** (MUD, Object-Oriented) set in
THE LINE / NEOM. Players connect over the web and issue text commands (`look`,
`go north`, `attack fence`, `scrap`, `sell knife to fence`) that mutate a shared,
persistent world graph. It is an Elixir/Phoenix umbrella project backed by
PostgreSQL.

The project is early — it is at **Phase 0** (closed playtest spine). The core
object graph, verb dispatch, persistence, combat, presence, an HTTP playtest API,
and a websocket channel are working. `line_world` and `line_ml` are still stubs.

## Stack

- **Elixir** `~> 1.16` / **Erlang/OTP 26**
- **Phoenix** 1.8.x (the README says 1.7+; 1.8 is what's installed)
- **Bandit** HTTP server (`Bandit.PhoenixAdapter`)
- **Ecto** 3.14 + **Postgrex** over **PostgreSQL** 16
- **Phoenix.PubSub** for in-process broadcast; **Phoenix Channels** for websockets
- No Tailwind / CSS framework, no esbuild — static CSS is served from
  `apps/line_web/priv/static/assets/`. Do not add a frontend build pipeline
  without checking first; it was deliberately omitted. The Frontend is the Client. The Repo is the server.

## Umbrella layout

Five sub-apps under `apps/`. Dependencies flow **downward only** — never make a
lower app depend on a higher one.

| App | Role | Status |
|-----|------|--------|
| `line_shared` | Library (no supervision tree). Shared types/helpers. | Stub (`hello/0` only) |
| `line_core` | **The spine.** Object graph, verbs, dispatcher, persistence, combat, presence, playtest sessions, seeds. | Active, the bulk of the code |
| `line_world` | World model / higher-level state transitions. | Stub |
| `line_ml` | ggml interop, port-based ML inference (Object LM). | Stub |
| `line_web` | Phoenix HTTP + Channels. Web interface + playtest API. | Active |

`line_core` depends on `line_shared`. `line_web` depends on `line_core` and
`line_shared`. Each sub-app's `mix.exs` points `build_path`, `config_path`,
`deps_path`, and `lockfile` at the umbrella root — shared `_build`, `deps`,
`config/`, and `mix.lock`.

## Core architecture (read this before touching `line_core`)

The whole game is built on one idea: **everything is an Object in a graph, and
verbs are pure functions that emit events the dispatcher applies.**

### The object graph

Three Ecto schemas in `apps/line_core/lib/line_core/schemas/`:

- **`Object`** (`objects` table) — every player, room, item, NPC, exit. Has
  `type` (`:player | :room | :item | :npc | :exit | :generic`), `name`,
  `description`, `verbs` (string list), `parent_id` (prototype), and
  `deleted_at` (soft delete). UUID (`binary_id`) primary keys throughout.
- **`Property`** (`object_properties` table) — EAV key/value attached to an
  object. `value` is **JSONB**. Scalars are wrapped as `%{"v" => value}` on the
  way in and unwrapped on the way out (see `LineCore.Object.get_property/2`).
  Examples: `hp_current`, `hp_max`, `dirham`, `stat_wire`, `skill_scrap_xp`,
  `custom_description`, `location_phrase`, `active_state`, `instance_type`,
  `source`, `last_seen_at`.
- **`Relationship`** (`object_relationships` table) — directed edges. Types:
  `:contains`, `:exit_to`, `:owns`, `:wields_main`, `:wields_off`, `:wears`,
  `:follows`, `:targeting`. Per-edge `metadata` JSONB (e.g. exit `direction`).

**Always go through `LineCore.Object`** for graph access — it handles property
casting, containment (`contents/1`, `container_of/1`), exits (`exits/1`,
`resolve_exit/2`, `canonicalize_direction/1`), and relationship traversal.
Don't hand-write Ecto queries against the schemas from verbs. (`verbs/wield.ex`
and `verbs/unwield.ex` currently do; that's debt, not a pattern to copy.)

### Prototype inheritance (generics)

MOO-style, and the reason `parent_id` exists. Objects derive from **generics** —
`:generic`-typed prototypes seeded by `LineCore.Seed.Generics`, rooted at a
mother object (`The Line`):

```
The Line
├── Generic Room
├── Generic Thing
│   ├── Generic Weapon
│   └── Generic Scrap
└── Generic Mob
    ├── Generic Human
    │   ├── Generic NPC
    │   └── Generic PC
    └── Generic Agent
        └── Generic Operator
            ├── Generic Supervisor ── Generic Representative
            └── Generic Handler ──── Generic Director ──── Generic Shareholder
```

NPC and PC split at `Human` so the only real difference — whether anyone is
driving it — sits at the leaf, which is what makes a logged-out PC structurally
identical to an NPC. Staff branch at `Mob`: they are of the building, not of the
residents, and the corporate ladder doubles as the permission ladder since
`effective_verbs/1` unions *up* the chain.

`Generic Thing`, `Generic Mob`, `Generic Human` and `Generic Agent` are
**abstract** — they deliberately carry no `instance_type`, so deriving a type
from one is a hard `:abstract_generic` error rather than a silent wrong answer.

Property defaults on the generics follow `mechanics.md` (the canon for health
bars, core stats and chargen attributes). `Generic Mob` carries the three bars
and eight `stat_*` attributes; `Generic PC` carries the four core stats. Skill
*totals* are not stored — canon derives them from two attributes each.

- **Properties resolve up the chain**, nearest wins. An object stores only what
  differs from its generic; `Object.get_property/2` falls back through
  `ancestors/1`. Editing a generic changes every descendant live. Use
  `own_property/2` / `own_properties/1` when you specifically need
  non-inherited values.
- **Verbs union up the chain** (`effective_verbs/1`) — a generic grants
  capabilities, a descendant adds its own.
- **`LineCore.Genesis` is the only supported way to create an object.** Never
  hand-assemble one out of `Object.create/3` plus trailing `relate` and
  `set_property` calls — that was the old pattern, it set no `parent_id`, and it
  was not atomic. `Object.spawn_from/3` is superseded for the same reason: it
  defaults type to the generic's own, and a generic is always `:generic`.
- **Cycles are refused** by `set_parent/2`, and chain walking is capped and
  cycle-tolerant so bad data degrades instead of hanging.
- Ancestor walking deliberately **ignores `deleted_at`** — soft-deleting a
  generic must not silently strip defaults from everything beneath it. Don't
  delete the mother object.

### Creating objects: `LineCore.Genesis`

`Genesis.plan/1` pre-generates the object's UUID and returns the ordered event
list that materialises it — `{:create_object, attrs}` then `:relate` then
`:set_property`, all naming the same id. Because the id exists before anything
is written, a whole object is describable as one event list with no forward
references, so a verb can splice a plan straight into its own `{:ok, events}`.
`plan/1` performs reads but never writes.

`Genesis.create/1` (and `create!/1`, `create_many/1`) applies a plan in one
transaction, for callers outside the dispatcher pipeline. The readable helpers
are `room!/2`, `item!/3`, `npc!/3`, `player!/2`.

```elixir
Genesis.item!(room, "bent crowbar",
  template: :weapon,
  description: "Steel crowbar, bent at the hook.",
  properties: %{scrap_value: 15, damage: 18}
)
```

Type is decided at the call site, never inherited from a `:generic` parent: a
helper fixes it, an explicit `:type` wins, otherwise it resolves from the
template's `instance_type`. `plan/1` **refuses `type: :player`** — creating a
player is an account-lifecycle concern, not a world mutation, and `player!/2` is
the deliberate door. Every created object records a `source` property
(`:seed | :hand | :generated | :playtest | :player`) for attribution — not as a
licence to delete.

### Verbs are pure; the dispatcher is the only side-effecting place

A **verb** implements the `LineCore.Verb` behaviour: `execute(context, args)`
returns `{:ok, [event]}` or `{:error, reason}`. **Verbs must be pure** — no DB
writes, no broadcasts, no `Repo` calls that mutate. They read from the
`LineCore.Verb.Context` (`actor`, `room`, `room_contents`, `command`, `now`) and
*decide* what should happen by returning events.

`LineCore.Dispatcher.dispatch/4` is the **only** place side effects happen:

1. Fetches actor + room, builds the read-only `Context`.
2. Checks optional `requirements/0` (skill/stat gates) → `:insufficient_skill`.
3. Calls `verb_module.execute(context, args)`.
4. Applies **persistent** events via a single `Ecto.Multi` transaction (atomic —
   all or nothing).
5. Broadcasts **notification** events via `LineCore.PubSub`.

**Event types** (full list in `dispatcher.ex` and the `LineCore.Verb` typespec):

- Persistent (in the Multi): `:set_property`, `:delete_property`, `:move`,
  `:relate`, `:unrelate`, `:create_object`, `:delete_object` (**refuses
  `:player`-typed objects** — see Player persistence below).
- Notification (PubSub only): `:notify_actor`, `:notify_room` (supports
  `except: [ids]`), `:notify_object`, `:broadcast_channel`.

This split is *the* design invariant. It makes verbs trivially testable (call
`execute/2`, assert on the event list) and keeps all persistence/broadcast logic
in one auditable place. **When adding a verb, do not break it** — if a verb needs
to read derived data, do it in `execute/2`; if it needs to mutate, emit an event.

### Adding a verb

1. Create `apps/line_core/lib/line_core/verbs/<name>.ex` with
   `@behaviour LineCore.Verb` and an `execute/2` that returns events. Keep it
   pure. Look at `verbs/look.ex` (read-only) and `verbs/attack.ex` (uses
   `LineCore.Combat` to build event lists) as models.
2. Register aliases in `LineCore.Parser`'s `@verb_map` (and add any special
   argument parsing in `parse_args/2` — e.g. `sell <item> to <target>` and
   `wield <item> main|off` parse multiple args via regex).
3. If a new persistent event type is needed, add a clause to
   `Dispatcher.apply_event_to_multi/3` **and** the typespec in `LineCore.Verb`.
4. Add a test using `LineCore.TestHarness` (see Testing).

Existing verbs: `look`, `examine`, `go`, `inventory`, `get`, `drop`, `say`,
`text`, `who`, `desc`, `attack`, `wield`, `scrap`, `sell`. Combat helpers live in
`LineCore.Combat` (HP model, damage/death event builders, respawn). Room/object
display is rendered by `LineCore.Renderer` (a five-section format with word-wrap).

### PubSub, Presence, Sessions

- **`LineCore.PubSub`** wraps `Phoenix.PubSub` (bus name `LineCore.PubSub.Bus`,
  started in `LineCore.Application`) with typed topics: `{:room, id}`,
  `{:actor, id}`, `{:channel, name}`. Subscribers receive `{:msg, text}`,
  `{:room_msg, text, except_ids}`, or `{:channel_msg, channel, text}`.
- **`LineCore.Presence`** — a unique `Registry` (`LineCore.Presence.Registry`)
  keyed on `player_id`. Source of truth for the `who` verb; entries vanish when
  the session process dies.
- **`LineCore.PlaytestSession`** — a `GenServer` (one per session, registered in
  `LineCore.PlaytestRegistry`) that owns a player object, subscribes to its
  topics, and buffers messages in a bounded queue for HTTP long-poll delivery.
  Idle-expires after 15 minutes (overridable via the `:playtest_idle_timeout`
  app env) and marks the player offline — it does **not** delete them.
  [this is not implementation spec, just testing]

### Player persistence

**Players are never deleted.** A session ending — by `terminate/1`, idle expiry,
or websocket disconnect — releases connection-scoped resources only. The body
stays in the room it was standing in, marked offline via an `active_state`
property, visible in `look` and still a legal target. The refusal is enforced in
`Dispatcher.apply_event_to_multi/3`, so no verb can route around it, and
`Genesis` exposes no delete function at all.

**`LineCore.Catchup`** owns the transition. `mark_offline/2` sets `active_state`
and stamps `last_seen_at`; `mark_online/1` clears the marker; `digest/1` replays
what happened while nobody was driving. That replay is a **journal read** — a
death notice is published to an actor topic with no subscriber and would
otherwise evaporate, but the journal recorded the event list, so the
`notify_object` events naming the player are recoverable. `GameChannel` pushes
the digest on join.

`who` remains a connection roster and lists online players only.

### The web layer (`line_web`)

Two ways into the game, both routing raw input through `LineCore.Parser` and then
`LineCore.Dispatcher`:

- **Websocket** — `LineWebWeb.UserSocket` (`game:*` channel →
  `LineWebWeb.GameChannel`). Auth takes a **signed `token`** in connect params
  (`LineWebWeb.PlayerToken`, backed by `Phoenix.Token` and the endpoint's
  `secret_key_base`, 24h lifetime); the socket verifies the signature, then that
  the id it names is a live `:player` object. **Raw player UUIDs are not
  accepted** — ids are identifiers, not credentials, which matters because the
  journal records `actor_id` on every dispatch and the world model reads it.
  The playtest API returns a `socket_token` alongside the session. There are
  still no passwords; token minting is whatever authenticates the player.
  The channel subscribes the connection to the actor + room topics, registers
  presence, forwards PubSub messages to the client, and re-subscribes on room
  changes after `go`.
- **HTTP playtest API** — `LineWebWeb.PlaytestController` under
  `/api/playtest/*`. Gated by an `Authorization: Bearer <PLAYTEST_TOKEN>` header;
  **if `PLAYTEST_TOKEN` is unset the entire API returns 503** (disabled).
  Accepts `{"raw": "..."}` (goes through the parser) or pre-parsed
  `{"verb": "...", "args": [...]}`.

## Commands

Run from the umbrella root.

```bash
# First-time setup
mix deps.get
mix ecto.create
mix ecto.migrate
mix line_core.seed        # seeds District One; prints room IDs for env vars

# Run the server (http://localhost:4000)
mix phx.server
iex -S mix phx.server     # with a REPL

# Tests (uses Ecto SQL Sandbox; needs Postgres up)
mix test                  # whole umbrella
mix test apps/line_core   # one app
mix cmd --app line_core mix test path/to/test.exs:42   # single test

# Formatting & compile hygiene
mix format
mix compile --warnings-as-errors   # CI/project standard: zero warnings
```

### Environment variables

- `PLAYTEST_TOKEN` — bearer token enabling the HTTP playtest API (unset = 503).
- `PLAYTEST_STARTING_ROOM_ID` — required for creating playtest sessions; set it
  to a seeded room id (the seed task prints one).
- `SAFEHOUSE_ROOM_ID` — respawn room for combat death (Combat raises if unset).
- Production (`config/runtime.exs`): `DATABASE_URL`, `SECRET_KEY_BASE`,
  `PHX_HOST`, `PORT`, optional `POOL_SIZE`, `ECTO_IPV6`.

Dev DB defaults (`config/dev.exs`): `postgres`/`postgres` @ `localhost`, database
`line_in_the_sand_dev`. Tests use `line_in_the_sand_test<PARTITION>`.

## Testing conventions

- Tests live in each app's `test/` directory; `line_core` has the meat
  (`test/line_core/*_test.exs`).
- **`LineCore.TestHarness`** is the ergonomic way to test the MOO: it spawns
  rooms/players/items, subscribes the **calling test process** to actor topics,
  dispatches verbs synchronously (bypassing HTTP/websockets), and offers
  `assert_msg/1` (string or regex). Prefer it over wiring PubSub by hand. Its
  spawners go through `Genesis` and take **keyword opts** (`description:`,
  `properties:`, `template:`), so harness-built objects inherit exactly like
  seeded content and the verb/combat suites exercise inheritance transitively.
  They call `ensure_generics/0` first, since the sandbox rolls back per test.
- Tests that start a `GenServer` (playtest sessions) need a **shared** sandbox
  owner — `Sandbox.start_owner!(Repo, shared: true)` — or the process cannot see
  the test's connection.
- DB tests use the **Ecto SQL Sandbox** in `:manual` mode
  (`apps/line_core/test/test_helper.exs`). Check out the sandbox per test.
- `line_web` test support: `test/support/conn_case.ex`, `channel_case.ex`
  (these are only compiled in `:test` via `elixirc_paths`).
- Because verbs are pure, the fastest unit test is often just calling
  `Verb.execute/2` and asserting on the returned event list — no DB needed.

## Conventions & gotchas

- **UUIDs everywhere.** All IDs are `binary_id`. Don't assume integer ids. [we should probly move towards hex or b64]
- **Soft deletes.** `Object.deleted_at` — all `LineCore.Object` queries already
  filter `is_nil(deleted_at)`. Preserve that filter in any new query (journal
  integrity depends on rows sticking around). [do not delete the mother object]
- **Property values are JSONB-wrapped.** Use `Object.get_property/2,3` and
  `set_property/3`; don't read `Property.value` directly (it's `%{"v" => ...}`
  for scalars).
- **Keep verbs pure.** This is the load-bearing convention. Side effects belong
  in the object as controlled by the dispatcher via events.
- **Zero-warning builds.** The project standard is
  `mix compile --warnings-as-errors` clean, and `mix test` warning-free too —
  test files included (no unused aliases or variables). Project code currently
  meets this. The remaining warnings all come from upstream deps when they are
  recompiled from scratch: `ecto_sql` on OTP 26 (`Process.set_label/1`) and two
  in `phoenix`'s `code_reloader/server.ex`. Those are not ours to fix; anything
  originating in `apps/` is.
- **`mix format`** is configured at the root (`.formatter.exs`, with
  `subdirectories: ["apps/*"]`). Run it before committing.
- Lower apps (`line_world`, `line_ml`, `line_shared`) are intentionally
  near-empty. When you start filling them in, respect the downward dependency
  rule and add a supervision tree only if the app actually needs one. [it probly will]

## World content

Phase 0 content is seeded by `LineCore.Seed.DistrictOne` (run via
`mix line_core.seed`): a Safehouse, a four-room Scrap Zone, a Fence Shop, and a
fence NPC with starter items. It calls `Seed.Generics.seed/0` first — the
prototype chain has to exist before anything can descend from it — and builds
everything through `Genesis`, so seeded content genuinely inherits (the crowbar
gets `wield`/`unwield` from `Generic Weapon` without listing them). The seed is
**idempotent** (keyed on the safehouse name). New canonical content goes in
`apps/line_core/lib/line_core/seed/`.

## Git / workflow

- Default branch: `master`. Develop on a feature branch; don't push to `master`
  without explicit permission.
- Commits in this repo follow Conventional-Commit-ish prefixes
  (`feat(line_core): ...`, `scaffold: ...`).
- **No AI attribution or signing.** Do not add `Co-Authored-By` trailers,
  "Generated with ..." footers, session links, or any tool self-attribution to
  commits, PR titles/bodies, comments, or code. Commit messages describe the
  change and nothing else.
- **No timers.** Agents must not schedule wake-ups, self check-ins, reminders,
  or any other time-based follow-up (e.g. `send_later`, cron-style routines).
  React to events (CI, reviews, pushes) as they arrive; otherwise stay quiet.
- Historical context lives in `SCAFFOLD_REPORT.md`, `INTEGRATION_REPORT.md`, and
  `apps/line_core/INTEGRATION.md` — useful for understanding how the spine was
  assembled, but they describe past phases, not current tasks.

## License

ESL-ANCSA-MRA-IndiModSHA v1.0 (Evermoor Sanctuary License — NonCommercial except
Original Creator, ShareAlike for Adaptations, Independent Module Safe Harbor for
Small Entities) per the README. Note: a `LICENSE` file is referenced but not yet
committed to the repo. All current deps are MIT/Apache-2.0; **do not add
GPL/AGPL dependencies.**
