# line_core Drop-In — Integration Notes

These files extend the `apps/line_core/` sub-app of the umbrella. Manus already scaffolded `LineCore.Application` and `LineCore.Repo`; this drop adds the object graph, verb dispatch, persistence, broadcasting, and the first verb.

## Where files go

Unzip at the umbrella root. Files land at:

```
apps/line_core/lib/line_core/
├── schemas/
│   ├── object.ex
│   ├── property.ex
│   └── relationship.ex
├── verb/
│   └── context.ex
├── verbs/
│   └── look.ex
├── object.ex
├── verb.ex
├── dispatcher.ex
├── pubsub.ex
└── renderer.ex

apps/line_core/priv/repo/migrations/
└── 20260605000001_create_object_graph.exs
```

No files conflict with anything Manus scaffolded.

## Two small edits to existing files

### 1. `apps/line_core/lib/line_core/application.ex`

Add `LineCore.PubSub` to the supervision tree. Replace the children list with:

```elixir
children = [
  LineCore.Repo,
  LineCore.PubSub,
  {Phoenix.PubSub, name: LineCore.PubSub.Bus}
]
```

(If `Phoenix.PubSub` isn't already pulled into `line_core`'s `mix.exs`, add `{:phoenix_pubsub, "~> 2.1"}` to its deps and run `mix deps.get`.)

### 2. `apps/line_core/mix.exs`

Confirm deps include:

```elixir
{:ecto_sql, "~> 3.11"},
{:postgrex, "~> 0.17"},
{:phoenix_pubsub, "~> 2.1"}
```

## Verification

After dropping in:

```bash
mix compile          # should be clean, no warnings
mix ecto.migrate     # creates objects, object_properties, object_relationships
iex -S mix
```

In the IEx session:

```elixir
# Sanity check: create a room and a player, place player in room, look.
{:ok, room} = LineCore.Object.create(:room, "Hub", %{description: "A small concrete cube with a folding chair."})
{:ok, player} = LineCore.Object.create(:player, "Graves")
LineCore.Object.relate(room.id, player.id, :contains)

# Subscribe so we receive notify_actor broadcasts
LineCore.PubSub.subscribe({:actor, player.id})

# Dispatch look
LineCore.Dispatcher.dispatch(player.id, LineCore.Verbs.Look, [], "look")

# flush() should show {:msg, "Hub\nA small concrete cube...\n\nNo obvious exits.\n"}
flush()
```

If that flushes a `{:msg, ...}` tuple with the rendered room, the spine is alive.

## What's next (Handler builds after this lands)

- Migration runs clean → second verb (`get`/`drop`) → second verb (`go <direction>`) → first hand-authored room with exits → Phoenix Channel in `:line_web` subscribing to PubSub topics → PWA scaffolding.
