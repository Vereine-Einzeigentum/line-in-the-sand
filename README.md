# LINE IN THE SAND

Multiplayer text MOO set in THE LINE / NEOM.

## Stack

- Elixir 1.16+ / OTP 26+
- Phoenix 1.7+
- PostgreSQL via Ecto
- Bandit HTTP server

## Setup

```bash
mix deps.get
mix ecto.create
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000) from your browser.

## Sub-applications

| App | Description |
|-----|-------------|
| `line_shared` | Library (no supervision tree). Shared types, schemas, helpers. |
| `line_core` | MOO core. Object graph, verb dispatch, persistence (Ecto). |
| `line_world` | Deterministic world-transition policy and semantic enactment. |
| `line_ml` | Provider-independent inference boundary; currently typed item completion. |
| `line_web` | Phoenix HTTP + Channels. Web interface. |

## Intelligence architecture

The [Model Stack & Adaptive World Intelligence spec](require_reading/10-adaptive-intelligence.md)
defines Play-BERT, the predictive World Model, the Director, and the Actor/Jev
pair. Actor produces intent; Jev proposes actions using available affordances;
the ordinary dispatcher validates and applies canonical events.

See the [implemented semantic enactment path](docs/semantic-enactment.md) and
the [next implementation slices](docs/plans/2026-10-19-adaptive-intelligence-foundation.md).
The trained neural stack is a target, not an existing feature.

## License

ESL-ANCSA-MRA-IndiModSHA v1.0 (Evermoor Sanctuary License — NonCommercial except Original Creator, ShareAlike for Adaptations, Independent Module Safe Harbor for Small Entities. See LICENSE file.)
