repo: Vereine-Einzeigentum/line-in-the-sand
branch: master

## Last sync
date: 2026-07-25T22:04:24Z

### Updated in this project
- Reviewed repo docs (README, CLAUDE.md, INTEGRATION_REPORT.md) to ground the client prototype in real backend conventions (verbs, dispatcher events, channel/playtest API, renderer format).
- No repo assets copied — `LINE - MOO Client.html` is a standalone frontend prototype, not built from repo UI code (repo has no frontend build pipeline; static CSS only).

## Screen map
| Project screen | Repo grounding |
|---|---|
| LINE - MOO Client.html | Verb list & aliases (LineCore.Parser), room/object render format (LineCore.Renderer, 5-section word-wrapped), event/notify types (Dispatcher), channel semantics (GameChannel over `game:*`) |
