# Adaptive intelligence foundation delivery plan

**Governing specification:** [Model Stack & Adaptive World Intelligence](../../require_reading/10-adaptive-intelligence.md).

**Priority:** Replace missing foundations with working, verifiable slices.
Do not add fake model responses, fabricated telemetry, or empty workers to
make the architecture look complete. This plan is not an implementation claim.

## Current footing

The [semantic spine](../semantic-enactment.md) already supports typed partial
items, inert consequences, enact/defer/reject policy, validated event graphs,
and transactional item materialization. Model execution currently means a
bounded item-completion backend contract with explicit unavailability.

The [first journal slice](../play-journal.md) now records dispatcher outcomes,
mechanical effects, and WebSocket sessions with ordered export. There is no
Play-BERT, Actor/Jev runtime, predictive World Model, Director, or training
lifecycle yet. Bounded weapon mechanics and real
solver/inference adapters remain semantic-spine work; the intelligence stack
first needs actual play history.

## 1. Durable structured play journal — first slice implemented

Define a versioned event envelope containing stable event identity, timestamp,
ordering, actor/target/location/faction references, outcome, session identity
and position, elapsed time, content association, and relevant world context.
Allow fields to be explicitly unknown or inapplicable instead of inventing
values. Keep context bounded and use stable object references.

Journal committed gameplay at the canonical dispatcher boundary in the same
transaction as its state changes. Cover ordinary gameplay and the new semantic
enactment path. Export and model work run outside game transactions. A missing
inference backend must never prevent deterministic play.

Record proposal/decision diagnostics with provenance separately from committed
game events: rejection and deferral are useful observations, not enacted
consequences. Human-readable telemetry must make that distinction visible.
Preserve model/request/version references when present.

Capture session lifecycle explicitly. A disconnect is not automatically a
deliberate quit, and a failed action is not automatically frustration.
Behavioral labels such as betrayal, revenge, and content return need attributable,
versioned derivation rather than rewriting raw observations as ground truth.

**Acceptance:** A real command and item enactment produce traceable records;
transaction rollback leaves no committed success record; rejected/deferred
proposals cannot be mistaken for applied events; export preserves ordering and
timing; gameplay works with inference unavailable. Verify delivery/retry
behavior so telemetry retries do not silently duplicate training samples.

## 2. Temporal outcomes and corpus extraction — next slice

Build episode/session extraction over the journal, with explicit observation
cutoffs and content identity. Preserve time gaps and distinguish trigger→quit,
quit→game return, and game return→implicated-content return. Track retries,
adaptation, depth, recruitment, avoidance, and later-session pursuit where
supported by observations.

No observed return means right-censoring at the observation cutoff, not a
negative churn label. Preserve censoring for incomplete intervals. Keep the
conditional content-return population distinct from all players who quit.
Split training/evaluation data without leaking future events into features.

**Acceptance:** Extracted examples can be traced back to journal records;
censored and observed trajectories remain distinguishable; returning to a
different activity does not become a positive implicated-content-return label.

## 3. Phase 1 learning baseline

Train a structured Play-BERT prototype using masked events/spans and explicit
time, then add next-state, gap, ordering, and affinity objectives as data allows.
Produce individual/group/population representations and the specified return,
content-return, frustration, and re-engagement heads. Interpretable projections
remain views over learned embeddings.

Evaluate against simple baselines on held-out temporal data. Record corpus,
schema, objective, model/checkpoint, and evaluation versions. Keep inference
observational until predictions have evidence; no neural state mutation.

**Acceptance:** Reproducible training and evaluation from real journal data,
censor-aware outcomes, auditable prediction provenance, and rollback to a
previous model version. Insufficient evidence is reported rather than replaced
with invented probabilities.

## 4. Phase 2 social intelligence

Build the player/faction/asset/unresolved-event graph and learn faction/conflict
representations. Evaluate reactivation, participation, propagation, revenge,
abandonment, and durable lore. Add drama-potential scoring and candidate
world-event evaluation with the specified penalties.

**Acceptance:** Scores are attributable to observed social context; faction
reactivation is measured across sessions; high combat volume alone cannot
satisfy the durable-play objective.

## 5. Phase 3 Actor/Jev, Director, and consequence prediction

Introduce distinct typed contracts for Actor intent and Jev candidate plans.
Actor context holds identity, memory, and relationships; Jev context holds
current affordances, capabilities, and constraints. Do not reuse the item
completion response as a generic cognition payload.

Dispatch each proposed action through ordinary validation, with plan repair
after changed state or failure. Evaluate personality continuity separately from
actualization success. Preserve the deterministic Event Model's separate role
in approved semantic enactment.

Add Director candidate conditions and predictive World Model evaluation under
the composite objective. Integrate periodic LoRA/QLoRA only with versioned,
evaluated, rollbackable artifacts. Immediate representation updates remain
free of backpropagation.

**Acceptance:** The same Actor intent adapts to different embodiments through
Jev; invalid/stale plans fail through normal rules; models cannot author
canonical writes; inference outage uses deterministic fallback; the Director
does not choose player allegiances, actions, or winners.

## 6. Phase 4 adaptive ecosystem

Add economical model routing, cross-session cultural memory, automated
checkpoint evaluation, consolidation, and long-term player-culture learning.
Require accumulated evidence for durable updates, protect shared world design
from personalization bubbles, and preserve human-readable audit trails.

**Acceptance:** Checkpoints can be evaluated and rolled back; temporary metas
cannot immediately rewrite world design; culture/novelty/agency and abandonment
remain visible alongside retention. Deterministic simulation continues during
model and training outages.
