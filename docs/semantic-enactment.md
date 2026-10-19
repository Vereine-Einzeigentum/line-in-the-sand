# Semantic enactment: first working slice

`line_ml` completes item semantics, `line_world` decides whether they may enter
the world, the Event Model selects the concrete events, and `line_core` executes
them. Ordinary commands continue through their existing dispatcher path.

The [governing intelligence spec](../require_reading/10-adaptive-intelligence.md)
adds Actor → intent → Jev → candidate verb plan for future character cognition.
That learned planning path is distinct from this deterministic Event Model.
This item-completion slice implements neither Actor/Jev nor the predictive
World Model. The [next delivery slice](plans/2026-10-19-adaptive-intelligence-foundation.md)
is the structured play journal needed by the learning stack.

## Working path

1. `LineMl.complete/2` accepts a `LineMl.Request` and a trusted configured
   backend implementing `LineMl.Backend`. It bounds execution time, isolates
   backend crashes, validates output, and preserves all asserted facts.
2. `LineWorld.Logic.derive/2` accepts the resulting `ItemSpec` and provenance.
   Its engine-neutral contract returns inert `Consequence` values. The first
   deterministic rule proposes item materialization; no solver is required.
3. `LineWorld.enact/2` sends the proposal through the dispatcher. Policy is
   evaluated inside its transaction against the current actor. Explicit
   `can_materialize_items: true` or administrator authority is required.
4. Unknown fields defer the proposal. Invalid or contradictory specifications
   and unauthorized actors are rejected. These outcomes return reasons and
   produce neither objects nor success notifications.
5. An approved proposal becomes an Event Model graph: create the item, store
   semantic tiers and provenance, contain it in the actor, then notify. The
   graph validates event shapes, dependencies, cycles, and created references.
6. All writes commit together. Notifications are sent only after commit;
   failures roll back creation and suppress notifications. Calling enactment
   from an already-open transaction returns `:nested_enactment` because the
   dispatcher cannot promise an outer transaction has committed.

## Example from trusted server code

The actor must already exist in a room, have materialization authority, and the
world archetypes must be seeded. No new public command or HTTP endpoint grants
this authority.

```elixir
spec = LineCore.ItemSpec.new(
  ["Weapon", "Flute", "Weather"],
  %{"name" => "thunder flute", "powered" => false, "capacity" => 1000},
  unknown: ["mass"]
)

request = %LineMl.Request{
  id: "workshop-request-1",
  spec: spec,
  instruction: "Complete unresolved fields without changing asserted facts."
}

with {:ok, completion} <- LineMl.complete(request),
     {:ok, [proposal]} <- LineWorld.Logic.derive(completion.spec, completion.provenance) do
  LineWorld.enact(actor_id, proposal)
end
```

Configure `:line_ml, :backend` with a trusted adapter module. The default is
`{:error, :unavailable}`; there is no fabricated completion or silent fallback.
Adapters return exactly `{:ok, %{derived: map, solved: map}}`. Assertions,
lineage, executable events, and module names are not accepted response fields.
Adapters run as trusted server code, not in a security sandbox.

Deterministic callers may instead complete an `ItemSpec` with `put_derived/3`
or `put_solved/3`, then call `Logic.derive/2` with a source and reference. Both
methods reject contradictions with assertions or previously completed facts.

## Deliberate alpha boundaries

- This slice materializes an ordinary `$item` carrying `semantic_spec` and
  `semantic_provenance`. The open semantic lineage is preserved case-sensitively,
  independently of the MOO prototype tree. An asserted `admin` or `damage`
  value remains semantic data; it does not directly become a live property.
- Turning asserted weapon traits into bounded combat behavior remains an
  Event Model extension. This slice does not claim generated weapons already
  have mechanically realized behavior.
- Deferral is explicit and caller-managed. There is no scheduler, durable
  decision journal, or exactly-once request deduplication yet. Re-enacting an
  accepted proposal deliberately creates another item.
- Scryer integration and a production inference adapter remain separate work.
  The real boundary and failure semantics are implemented and tested now.
- The new transaction path locks the acting object. It does not solve all
  existing multiplayer movement or combat races.

CI now runs on `alpha/semantic-spine`, compiles with warnings as errors, tests
against PostgreSQL, and builds the Svelte client. Formatting is enforced for
changed Elixir files so this slice does not require an unrelated repository-wide
formatting sweep.
