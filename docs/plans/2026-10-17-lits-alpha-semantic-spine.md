# LitS Alpha Semantic Spine Implementation Plan

**Goal:** Establish the alpha semantic spine that lets LINE accept absurd partially specified generated objects, reason about consequences without granting logic engines authority to mutate the world, and realize enacted consequences through an explicit Event Model.

**Architecture:** PostgreSQL remains durable world state and Elixir/OTP remains enactment authority. Generated/model-produced semantics enter as typed partial specifications and logic facts; logic engines derive consequences or solve constraints; Elixir decides whether and when a consequence is enacted; the Event Model alone maps an enacted consequence into executable world events. Models never write world state directly.

**Initial logic direction:** Scryer Prolog first for general relational semantics and CLP(Z); Soufflé/Datalog only when world-scale closure workloads justify it; ECLiPSe CLP only when the mathematical completion/optimization workload exceeds the initial solver.

## Global constraints

- PC/NPC is a control boundary, not a human/AI distinction.
- Human and AI players are equally valid PCs.
- Most NPC cognition may be internal AI; persona remains per NPC.
- Item synthesis is allowed to be absurd. Assertions are preserved, not normalized into familiar equipment classes.
- Effects are bounded and procedural.
- Generated fields are separated into asserted facts, unknown fields, derived facts, and solved facts.
- Logic determines what follows.
- Elixir determines whether and when a consequence is enacted.
- The Event Model determines how enactment becomes concrete events.
- Transitional `type`/verb fields are not expanded to encode generated ontology.
- No Rust or Java mechanics kernel during alpha without profiling evidence.

## Alpha slices

1. **Partial item semantic specification.** Ordered open lineage; asserted properties; explicit unresolved fields; derived and solver-completed facts kept in separate tiers; no silent contradiction of asserted facts; deterministic fact export for future logic adapters.
2. **Logic boundary and semantic consequences.** Engine-neutral logic contract. Facts in; inert semantic consequences with provenance out. No event emission or mutation.
3. **Enactment authority.** `line_world` decides reject, defer, or enact. This layer owns whether/when, not mechanical realization.
4. **Event Model.** Enacted consequences become validated event graphs. The Event Model owns event selection, dependencies, prerequisites, and realization.
5. **Generated-item completion.** Deterministic derivations first, Scryer next; ECLiPSe only for genuinely difficult constraint/optimization workloads; Datalog/Soufflé for large relational closure.
6. **Alpha cognitive loop.** Per-NPC persona/RP; typed action selector; item synthesis; odd-state interpretation; long-term worldstate; AI PCs and human PCs enter through game access; NPCs are controlled internally; all actions ultimately use the same world mechanics.

## Alpha acceptance target

A generated absurd weapon remains mechanically literal; an internally controlled NPC and externally controlled AI PC interact under the same world rules; logic can derive faction/media interest; Elixir can defer/reject/enact those consequences; only the Event Model expands enacted consequences into executable events.

## Open product seams

- Whether generated lineage identifiers are case-sensitive or separately canonicalized from display names.
- Whether an unsatisfiable generated object is discarded, regenerated, or enters the world broken/nonfunctional.
- Whether enactment decisions themselves become durable audit records or only resulting event graphs are persisted.
