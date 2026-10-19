# LineWorld

Deterministic world-transition policy and semantic enactment. The application
owns whether and when proposed consequences may occur; `line_core` dispatch
and persistence retain canonical event-application authority.

## Implemented

`LineWorld.Logic.derive/2` returns inert semantic consequences. `LineWorld.enact/2`
routes them through a transactional dispatcher path where `LineWorld.decide/2`
evaluates enact, defer, or reject policy. For accepted item materialization, `LineWorld.EventModel`
constructs a validated event graph. Item creation and semantic storage commit
together; notifications follow commit. See [semantic enactment](../../docs/semantic-enactment.md)
for authorization, usage, and remaining limits.

## Target architecture

The [adaptive intelligence spec](../../require_reading/10-adaptive-intelligence.md)
keeps this application distinct from the neural predictive World Model.
World/faction/economic/environmental simulation belongs here; predicted
outcomes and Director proposals have no direct write authority.

Actor supplies intent and Jev supplies candidate verb plans. Jev is a learned
planner, not this application's deterministic Event Model. Every proposed
action still passes through ordinary dispatcher validation.

The [foundation plan](../../docs/plans/2026-10-19-adaptive-intelligence-foundation.md)
puts structured play history first. The [play journal](../../docs/play-journal.md)
now records proposal outcomes and applied mechanics. The neural stack and a
deferral scheduler remain unimplemented.
