# Structured play journal: first working slice

The journal records real dispatcher outcomes and transport lifecycle observations
in `line_core`. It does not call inference, assign psychological labels, or own
world transitions. Its governing requirements are in the
[adaptive intelligence spec](../require_reading/10-adaptive-intelligence.md).

## Transaction and authority

Both ordinary and semantic dispatch now lock the acting object before reading
verb context and policy. Applied mechanical effects and their journal record
commit in the same transaction. A failure in either rolls back both, and
notifications leave only after commit. Dispatch refuses an existing outer
transaction because it cannot promise notifications will follow that commit.

A verb/policy refusal produces a separate `rejected` or `deferred` observation
without an effects list. Semantic proposal records retain validated source and
request-reference provenance. A failed database transaction produces no applied
record. Database errors and failures before dispatcher context exists are not
separately journaled in this slice.

The actor lock orders one actor's actions; it does not claim to solve every
race involving multiple actors or pre-dispatch object resolution.

## Version 1 envelope

| Field | Meaning |
|---|---|
| `id`, `schema_version` | Stable observation UUID and envelope version |
| `actor_id`, `position` | Historical actor identity and committed per-actor order |
| `event_type` | `COMMAND`, `PROPOSAL`, `LOGIN`, or `DISCONNECT` |
| `outcome` | `applied`, `rejected`, `deferred`, or `observed` |
| `occurred_at`, `elapsed_us` | UTC observation timestamp and gap from the previous actor observation |
| `session_id`, `session_position`, `session_elapsed_us` | Server-owned connection identity, order, and gap within that connection |
| `location_id`, `target_id` | Pre-action room and resolved direct object when available |
| `faction_id`, `content_id` | Currently unknown (`nil`); no invented association |
| `data` | Trusted verb identifier, optional provenance, and effects or a diagnostic reason tag |

Within an applied record, `data.effects` preserves mechanical event order with
an `index` and typed operations such as `MOVE`, `SET_PROPERTY`, `CREATE_OBJECT`,
and `RELATE`. Created references resolve to the actual persisted UUIDs. Numeric,
boolean, and null property values are retained; text/map/list values are omitted.
Notifications retain their kind, not their message body. Raw commands, arguments,
chat, names/descriptions, password hashes, and arbitrary string diagnostic
payloads are not copied into the journal.

`applied` means the verb's returned events committed, not that its intended goal
succeeded: a verb may return only an explanatory notification. The next corpus
slice must derive outcomes from mechanics, not treat every accepted command as
a successful attack or every failed command as frustration. These observations
are not a lossless world-event replay log.

Unknown values stay null. The first observation has no preceding time gap.
A backward wall-clock jump leaves the gap unknown rather than inventing a
positive interval; `position` remains the ordering authority.

## Sessions

Both WebSocket channels open server-owned sessions and pass them to dispatch.
Client payloads cannot select a session. Closed, unknown, and other actors'
sessions are rejected before verb execution. Cleanly observed transport
termination appends an idempotent `DISCONNECT` record.

`LOGIN` means a connection was observed, not that a dormant player returned.
Multiple simultaneous connections have separate session IDs. A disconnect is
not a deliberate quit. Process/server crashes can leave an unclosed session;
future extraction must preserve observation cutoffs and censoring. No quit,
content-return, frustration, or abandonment labels are inferred yet.

Direct server and HTTP playtest dispatches without session metadata still
journal gameplay with an explicitly unknown session. Setup/admin code that
writes directly through object APIs is outside dispatcher coverage.

## Ordered export

Trusted server code can read bounded pages (maximum 1,000 observations):

```elixir
page = LineCore.Journal.export(actor_id, 0, 100)
next_position = List.last(page).position
next_page = LineCore.Journal.export(actor_id, next_position, 100)
json = Jason.encode!(page)
```

For an empty page, retain the previous cursor. Each page is in committed actor
order. Exporting the same range again returns the same IDs, so consumers can
deduplicate ingestion by observation ID. Repeating a game command really does
execute again and creates another observation; request-level action deduplication
is not provided. Positions from different actors are not a global commit order.

Historical IDs have no cascading object foreign keys. Normal soft deletion
preserves them; explicit object deletion cannot silently erase play history.
There is no public telemetry endpoint, automatic model training, or inferred
population profile in this slice.

## Verification and next work

Tests cover mechanical projection, omitted text/credentials, successful and
refused dispatch, late event failure, journal-write failure, concurrent commands,
repeatable export, session ownership/closure, both WebSocket channels, and
semantic proposals while inference is unavailable.

Next: versioned corpus extraction with explicit observation cutoffs,
quit/disconnect distinctions, content identity, conditional return populations,
and censored trajectories. That is the prerequisite to training the Play-BERT
baseline and evaluating its predictions.
