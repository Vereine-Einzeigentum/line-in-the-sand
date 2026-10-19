# LINE IN THE SAND — Model Stack & Adaptive World Intelligence

**Status:** Governing design specification, adopted 2026-10-19. This describes
the target architecture, not a claim that the neural stack is implemented.
The Actor/Jev separation below supersedes any earlier specification in which
the Actor directly generated executable LitS actions.

## 0. Purpose

LitS uses specialized learning systems rather than one monolithic AI. The world
remains authoritative in deterministic game state. Neural systems observe,
predict, recommend, generate, and adapt; they never own canonical transitions.

> Players teach the world; the world changes more slowly than players act.

Learn what players actually respond to: social conflict, factional pressure,
rivalry, emergent narrative, frustration-engagement, and dormant-player return.

## 1. Architectural separation

| Layer | Responsibility | Output |
|---|---|---|
| Play-BERT / Event-BERT | Encode structured actual play; learn affinity, frustration, return, churn, and social activation | Embeddings and prediction heads |
| Predictive World Model | Learn dynamics and consequences of candidate interventions | Predicted outcomes, not transitions to apply |
| Actor / Jev pair | Actor owns character personality and intent; Jev actualizes intent using available mechanics | Intent, then candidate verb/action plans |
| Director | Propose pressures and opportunities for rich, durable play | Candidate world conditions, not scripted player choices |

These responsibilities remain conceptually separate even if some later share
base weights. Actor/Jev together occupy the character-cognition layer.

## 2. Authority boundary

| Application | Authority / responsibility |
|---|---|
| `line_core` | Object graph, verbs, dispatch, persistence, event application, invariants |
| `line_world` | World-transition policy, simulation, faction/economic/environmental processes |
| `line_ml` | Inference routing, model execution, embeddings, training extraction, candidate scoring |

The canonical path is **AI proposal → ordinary verb/dispatcher validation →
canonical event → persisted state**. No model writes authoritative state.

The predictive World Model is a neural role, distinct from the deterministic
`line_world` application. Likewise, Jev is a learned planner, distinct from the
existing deterministic **Event Model**. For approved semantic consequences, the
Event Model constructs concrete event graphs within the normal enactment path.
Jev proposes verb use; it cannot submit privileged event graphs to bypass rules.

## 3. Play-BERT / Event-BERT

### 3.1 Structured gameplay input

Train a BERT-style encoder on `[event₁, event₂, event₃, …]`, not primarily raw
text. Event vocabulary includes:

`MOVE`, `LOOK`, `ATTACK`, `DAMAGE`, `DIE`, `FLEE`, `CHAT`, `TRADE`, `LOOT`,
`JOIN_FACTION`, `LEAVE_FACTION`, `BETRAY`, `LOGIN`, `QUIT`, `RETURN_TO_CONTENT`,
`FORM_GROUP`, `CLAIM_ASSET`, `LOSE_ASSET`, and `REVENGE_ACTION`.

Each event embedding may contain **event_type + actor + target + location +
faction + outcome + Δt + session_position + world_context**. Time must be
explicit; event order alone is insufficient.

### 3.2 Self-supervised objectives

- Masked event prediction and masked event-span reconstruction.
- Next-state prediction, temporal-gap prediction, and event ordering.
- Actor/content affinity prediction.

For `MOVE → ATTACK → DAMAGE → [MASK] → QUIT`, learn plausible missing
transitions such as death, flight, or disconnection. Span reconstruction should
capture episodes such as exploration, a masked 12-event conflict, rage quit,
return, and a revenge campaign.

Learn latent concepts such as humiliating loss, faction conflict, betrayal,
scarcity, mastery/revenge loops, exploration payoff, and failed coordination
without requiring all of them to be manually labeled.

## 4. Player preference representation

Maintain learned `player_embedding ∈ ℝᵈ`, social-group/faction embeddings, and
population-level embeddings. Do not reduce players to static human categories.

Optional interpretable projections include conflict, exploration, cooperation,
rivalry, economic play, risk appetite, social drama, frustration tolerance,
novelty preference, and repetition aversion. These are views over embeddings,
not the canonical representation.

## 5. Frustration as a multipart temporal signal

Frustration is neither simply positive nor negative. Track:

| Signal | Interval |
|---|---|
| `Δquit` | Frustration trigger → quit |
| `Δreturn` | Quit → return to LitS |
| `Δcontent` | Return to LitS → re-engagement with implicated content |

Also track re-engagement depth, retries, strategy changes, social recruitment,
information seeking, later-session returns, avoidance, permanent abandonment,
and narrative propagation. A trajectory of failure → rage quit → return → retry
→ adaptation → recruitment → mastery → story can be strongly positive.

Distinguish `P(return_to_game | frustration)` from
`P(return_to_content | returned_to_game, frustration)`. Players who have not
yet returned are **temporally censored**, not immediately labeled churned.

## 6. Frustration outputs

Play-BERT exposes at minimum:

- `P(frustration_abandonment)` — friction leading to avoidance or churn.
- `P(frustration_engagement)` — friction leading to retry, adaptation, revenge,
  coordination, or mastery.
- `P(frustration_conversion)` — initially negative friction becoming culturally
  valuable.
- Expected time-to-quit, time-to-return, time-to-content-return, and depth of
  re-engagement.

Conversion examples: a hated district becomes a rite of passage; a murderous
NPC becomes beloved; an unreliable system becomes a meme; a bottleneck produces
a player-run logistics economy.

## 7. Social drama model

Social conflict is a first-class learned signal. The HellMOO/corpwar precedent
motivates an explicit hypothesis: faction conflict can reactivate dormant
veterans. Learn this from LitS traces rather than assuming every conflict works.

Construct a social graph over players, factions, assets, and unresolved events.
Represent memberships, alliances, rivalries, grudges, disputed ownership, debts,
betrayals, reputation, territorial claims, resource dependencies, succession
disputes, contested infrastructure, shared enemies, social proximity, and
dormant-member affinity.

Prediction heads may include `P(oldhead_return | conflict_state)`,
`P(cross_faction_participation)`, `P(conflict_propagation)`, `P(revenge_loop)`,
`P(post_conflict_retention)`, `P(drama_abandonment)`, `P(player_generated_lore)`,
and `P(faction_reactivation)`.

## 8. Drama potential

Approximate candidate social-condition potential as:

`D = tension × stakes × legibility × agency × social_reach × unresolvedness`

Penalize forcedness, repetition, one-sidedness, incomprehensibility, and coercive
harassment risk. Seek drama potential, not merely combat likelihood.

A corpwar-like condition combines dormant veterans, remembered affiliations,
a scarce strategic asset, a credible rival claimant, public consequences, and
coalition opportunity. Spawning a PvP event alone does not express this.

## 9. Director Model

The Director creates conditions for player-generated history. It may propose
contested salvage, resource scarcity, overlapping contracts, contradictory
intelligence, succession disputes, exposed betrayals, vulnerable strategic
assets, ownership disputes, asymmetric opportunities, faction promotions, debt
calls, neutral-ground crises, logistical bottlenecks, migration pressure, and
economic shocks.

It must not determine who attacks, allies, or betrays whom, who wins, or how
players interpret events. The Director creates pressure and affordances;
players create meaning. Its proposals remain subject to ordinary world rules.

## 10. Predictive World Model

Inputs include current world state, faction graph, player embeddings, recent
event history, economy, territorial state, unresolved conflicts, and latent
social tensions. Outputs may estimate state transitions, player participation,
social propagation, reactivation, abandonment, novelty, and long-term persistence.

The Director generates candidates; the World Model evaluates likely outcomes.
Prediction never grants authority to apply the predicted transition.

## 11. Actor / Jev pair

### Actor — personality and intent

`Actor(identity, memory, relationships, situation) → intent`

The Actor owns personality, disposition, preferences, loyalties, grudges, fears,
ambitions, conversational style, event interpretation, social judgment, memory
salience, goals, desired outcomes, and intended response. Its output is an
intention or desired course of action, never an executable canonical action.

Example: “I do not trust this player. I want to embarrass them publicly, but I
do not want open combat yet.”

### Jev — actualization and affordance intelligence

`Jev(intent, affordances, world_state) → candidate action plan`

Jev receives Actor intent, current state, physical constraints, available
objects and verbs, permissions, skills/capabilities, topology, inventory,
timing, social context, local opportunities, and candidate consequences.
It learns **intent × state × affordances → viable action**.

For the embarrassment intent, Jev might observe a crowded bar, a faction debt,
a bartender who knows about it, and available `SAY` / `EMOTE` / `PAY` / `GIVE` /
`SIGNAL` verbs. It can propose signaling the bartender and exposing the debt
with a pointed remark. Availability and validity must still be checked by
the dispatcher; examples do not declare those verbs implemented.

### Authority chain

World perception → Actor → intent → Jev → candidate action/action sequence →
LitS dispatcher → validated canonical event → world state.

Neither Actor nor Jev directly mutates state. Plans are proposals, and each
attempted action must satisfy current game rules. A previously valid plan is
not a grant of future permission.

### Why the split matters

Actor asks “What would this person want to do?” Jev asks “Given that intention,
what can actually be done here, and how?” Personality remains independent of
mechanics. The same Actor can inhabit a human body, security drone, injured
body, vehicle, or remote terminal with different Jev capabilities and without
personality retraining. Different Actors can share a Jev capability substrate
while expressing different intentions.

### Training and quality

| Model | Training emphasis | Primary quality criterion |
|---|---|---|
| Actor | Identity consistency, long-term personality, relationship continuity, social memory, faction alignment, personal history, affective interpretation, stable preferences, goal formation, believable change | Character continuity and socially coherent intent |
| Jev | Verb availability, successful/failed sequences, object affordances, topology, inventory, social/combat mechanics, environmental constraints, prerequisites, consequences, legality, efficiency, plan repair, alternate routes, multi-step planning, adaptation | Valid, context-sensitive actualization without violating invariants |

### Play-BERT and Director interaction

Play-BERT's player/social representation conditions Actor interpretation.
Its predicted response and engagement trajectories separately inform Jev
candidate scoring. For an Actor's “challenge this player” intent, Jev might
consider public insult, theft, formal duel, or contract sabotage. Predictions
about economic retaliation versus opaque theft can help select among valid
plans while preserving intent and the composite objectives in section 14.

**Director → conditions. Actor → desire. Jev → actualization.
Dispatcher → reality.**

The Director operates above the pair by changing proposed conditions, not by
dictating player behavior or replacing character-specific intent.

## 12. Hierarchical cognition

Use deterministic behavior → small classifier/encoder → small Actor/Jev model
→ LitS-native generative model → large reasoning model as complexity warrants.
Most routine activity stays cheap; expensive inference is an escalation.

## 13. Training cadence

| Cadence | Updates | Timescale |
|---|---|---|
| Immediate | Player embeddings, affinity vectors, faction/social state, short-term memory, live preference estimates; **no backpropagation** | Seconds to minutes |
| Periodic | LoRA/QLoRA on recent traces; adapters, preference heads, World Model and Actor/Jev adaptations | Hours to days |
| Consolidation | Larger retraining/checkpoints; stable learning, adapter consolidation, drift correction | Weeks or major dataset milestones |

Immediate representation updates do not change model weights or bypass
canonical world-state authority. Long-term changes require accumulated evidence.

## 14. Engagement objective

Never optimize solely for session duration or retention. Evaluate voluntary
return, re-engagement, content pursuit, social propagation, novelty,
player-created plans, durable faction activity, narrative persistence,
expressed approval, successful mastery, meaningful frustration, and long-term
retention together.

Negative terms include repetitive loops, opaque failure, forced content,
homogenization, frustration abandonment, coercive engagement, and novelty
collapse. More local activity alone is not evidence of better play.

## 15. Player propagation as a high-value signal

Explicitly measure when events enter player culture: telling others,
nicknaming an NPC/location, forming organizations, pursuing revenge,
memorializing events, returning voluntarily, producing jokes or rituals,
creating economic activity, changing faction politics, or referencing events
weeks later. Prefer durable player culture over a transient activity increase.

## 16. Structured data principle

Prefer typed events, object IDs, relation graphs, timestamps, and outcomes
over dumping all chat logs into an LLM. Chat may be an auxiliary modality;
LitS event history is the canonical training substrate.

This keeps input interpretable, queryable, replayable, temporally grounded,
easier to anonymize and audit, associated with real consequences, and usable
by non-generative models.

## 17. Inference / training infrastructure

`line_ml` is a provider-independent compute router. Execution classes may
include cheap/free edge inference, CPU GGUF, serverless GPU inference, burst
GPU training, and local/offline inference.

AI availability must not equal world availability. During inference outages,
deterministic systems and world simulation continue, NPCs use fallback
behavior, and cached plans remain usable subject to current validation.
Neural cognition resumes later.

## 18. Distributed state relationship

Global object namespace → distributed state fabric → BEAM world execution →
event journal → training corpus → model updates.

Neural systems consume the logical LitS state fabric, not individual database
topology. Physical Neon projects or other persistence providers are
implementation details. World state, player activity, and training data remain
logically unified. This is a target architecture, not a claim that distributed
persistence is already deployed.

## 19. Safety / control invariants

1. Neural systems cannot directly mutate canonical state.
2. Every generated action passes through ordinary game rules.
3. Training changes are versioned.
4. Adapters and checkpoints are rollbackable.
5. Preference learning distinguishes engagement from coercion.
6. Social drama generation creates conditions, never forced player behavior.
7. Player-specific learning does not collapse global design into personalization bubbles.
8. One temporary meta cannot rewrite the entire world.
9. Long-term updates require accumulated evidence.
10. Human-readable telemetry remains available for audit.

## 20. Minimum viable neural stack

| Phase | Deliverables |
|---|---|
| 1 | Structured event schema, telemetry pipeline, Play-BERT prototype, player embeddings, quit/return/content-return heads, frustration-engagement heads |
| 2 | Social graph, faction/conflict embeddings, reactivation predictor, drama-potential scoring, candidate world-event evaluator |
| 3 | Generative Director, Actor/Jev integration, World Model consequence predictor, periodic LoRA training |
| 4 | Adaptive ecosystem, model ensemble/routing, cross-session cultural memory, automated checkpoint evaluation, long-term player-culture learning |

The foundation is actual structured play data. Do not substitute fabricated
predictions or placeholder model outputs for an unimplemented phase.

## 21. Core thesis

LitS must learn what pressures produce play, what frustration produces mastery
or abandonment, what social configurations reactivate dormant players, which
conflicts become history, which events become culture, what to preserve, and
what to stop repeating.

The generative World Model does not decide what players like. The structured
play model learns from what players actually do. The Director then creates
conditions in which players can produce new history.

## Implementation status and next slice

The existing [semantic enactment slice](../docs/semantic-enactment.md) provides
typed item completion, inert consequences, enact/defer/reject policy, validated
event graphs, and transactional materialization. `LineMl` currently has an
item-completion backend contract, not a trained encoder or an Actor/Jev runtime.
The [first play-journal slice](../docs/play-journal.md) records committed
mechanics, distinct proposal diagnostics, and WebSocket session observations.
Temporal outcome extraction, the neural systems, and training lifecycle remain
work to implement.

The [delivery plan](../docs/plans/2026-10-19-adaptive-intelligence-foundation.md)
starts with a durable structured play journal and explicit outcome/censoring
semantics. It separates implemented behavior from each subsequent model slice.
