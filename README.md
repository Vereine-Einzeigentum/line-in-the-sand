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
| `line_world` | World model. State transitions. |
| `line_ml` | ggml interop. Port-based ML inference. |
| `line_web` | Phoenix HTTP + Channels. Web interface. |

## License

ESL-ANCSA-MRA-IndiModSHA v1.0 (Evermoor Sanctuary License — NonCommercial except Original Creator, ShareAlike for Adaptations, Independent Module Safe Harbor for Small Entities. See LICENSE file.)
