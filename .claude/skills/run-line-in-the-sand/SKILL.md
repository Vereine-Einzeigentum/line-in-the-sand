---
name: run-line-in-the-sand
description: Build, run, and drive LINE IN THE SAND. Use when asked to start the app, run its tests, build the Svelte client, take a screenshot of the UI, or interact with the running game.
---

LINE IN THE SAND is an Elixir/Phoenix umbrella app with a Svelte 5 frontend.
Start the Phoenix dev server, then drive with oculus (`node view.js`) or curl.
The login page is at `/`, and the Terminal UI renders after authentication via
`POST /api/register` or `POST /api/login`.

## Prerequisites

Postgres must be running. The session-start hook handles this automatically.

## Setup

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
cd apps/line_web/assets && npm install && cd ../../..
```

## Build

```bash
cd apps/line_web/assets && npm run build && cd ../../..
```

Produces `apps/line_web/priv/static/assets/js/app.js` (~204 kB) and
`apps/line_web/priv/static/assets/css/app.css` (~17 kB).

## Run (agent path)

### 1. Start the server

```bash
lsof -ti:4000 -sTCP:LISTEN | xargs -r kill 2>/dev/null
MIX_ENV=dev mix phx.server &>/tmp/phx.log &
timeout 30 bash -c 'until curl -sf http://localhost:4000 >/dev/null 2>&1; do sleep 1; done'
```

Server listens on `localhost:4000`. Logs at `/tmp/phx.log`.

### 2. Register a test player

```bash
curl -s -X POST http://localhost:4000/api/register \
  -H "Content-Type: application/json" \
  -d '{"name":"smoketest","password":"smoketest123"}'
# → {"token":"...","player_id":"..."}
```

### 3. Screenshot the login page

```bash
node /root/.claude/skills/oculus/scripts/view.js "http://localhost:4000" --engine firefox
```

Screenshot lands in `oculus-out/localhost-4000-<epoch>/screenshot.png`.

### 4. Screenshot the terminal UI (post-login)

The driver uses `createRequire` to resolve playwright from oculus's `node_modules`,
so it runs from any working directory:

```bash
node .claude/skills/run-line-in-the-sand/drive.mjs
```

This logs in as `smoketest` / `smoketest123`, waits for the Terminal UI to render,
and saves a screenshot to `/tmp/terminal-ui.png`. Read that file to verify the UI.

Override credentials or output path with env vars:

```bash
SMOKE_USER=alice SMOKE_PASS=secret SCREENSHOT_PATH=/tmp/shot.png node .claude/skills/run-line-in-the-sand/drive.mjs
```

### 5. Stop the server

```bash
lsof -ti:4000 -sTCP:LISTEN | xargs -r kill
```

## Run (human path)

```bash
mix phx.server
# → http://localhost:4000 in a browser. Ctrl-C twice to stop.
```

The Vite watcher in `config/dev.exs` rebuilds assets on change automatically.

## Test

```bash
mix test
```

Runs the full umbrella test suite (line_shared, line_core, line_web, line_world).

## API endpoints

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/api/register` | `{"name","password"}` | `{"token","player_id"}` |
| POST | `/api/login` | `{"name","password"}` | `{"token","player_id"}` |

WebSocket at `/socket/websocket?token=<token>`, channel `player:<player_id>`,
send commands via `cmd` event with `{"raw": "look"}`.

## Gotchas

- **"Connecting..." loop in Terminal UI** — `PlayerChannel.join` requires the
  player to have a room assignment. A freshly registered player has no room,
  so the channel join fails and the client reconnects. The game world (rooms,
  exits) needs to be seeded for channel join to succeed.

- **Svelte component classes are hashed** — don't select by `.terminal` or `.app`.
  The Svelte compiler hashes class names (e.g. `svelte-5zgg7r`). Use semantic
  selectors like `textarea`, `button[type="submit"]`, or text content matchers.

- **Port 4000 not freed on crash** — `mix phx.server` spawns a BEAM VM. If it
  crashes, the port stays bound. Always `lsof -ti:4000 | xargs -r kill` before
  relaunching.

## Troubleshooting

- **`npm run build` fails with "Cannot find module svelte"**: Run `npm install`
  inside `apps/line_web/assets/` first.
