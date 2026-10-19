# LineMl

Provider-independent model execution and inference boundary. The target
responsibilities include routing, embeddings, training-data extraction, and
candidate scoring; models never own canonical game-state transitions.

## Implemented

`LineMl.complete/2` accepts a typed item-completion request and a trusted backend
implementing `LineMl.Backend`. It bounds execution time, isolates backend
failures, validates the response, preserves assertions, and returns semantic
data with provenance. Without a configured backend it returns
`{:error, :unavailable}`. No production inference provider is connected.

See [semantic enactment](../../docs/semantic-enactment.md) for the working
contract and usage. These trusted backend modules are not a security sandbox.

## Target architecture

The [adaptive intelligence spec](../../require_reading/10-adaptive-intelligence.md)
defines Play-BERT, a predictive World Model, the Director, and Actor/Jev.
Actor produces intent; Jev proposes action plans; ordinary dispatcher
validation controls what becomes real. The deterministic Event Model in
`line_world` is not Jev.

Those models and their training lifecycle are not implemented yet. The
[foundation plan](../../docs/plans/2026-10-19-adaptive-intelligence-foundation.md)
builds on the [play journal](../../docs/play-journal.md); temporal outcome
extraction comes next. Model outages leave deterministic world execution
available.
