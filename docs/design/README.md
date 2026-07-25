# LITS design

Design artifacts for LINE IN THE SAND, synced from the claude.ai/design
project ("Line In The Sand"). The claude-design project holds design consent;
this directory is the repo-side mirror of its output.

## client/

`LINE-MOO-Client.html` — standalone prototype of the MOO web client. Not wired
to the backend yet; it is the visual/interaction target. Self-contained except
Google Fonts (JetBrains Mono, Noto Sans Arabic, Noto Sans SC).

Grounded against real repo conventions (see `PROVENANCE.md`): verb list and
aliases from `LineCore.Parser`, the five-section word-wrapped room format from
`LineCore.Renderer`, dispatcher notify semantics, and `game:*` channel flow.

Design language: CRT terminal — amber/cyan on void purple, scanline overlay,
plus a light "Boundless cream" paper theme (the client goes paper on
Boundless-held ground). HUD: VIT/STRESS/FATIGUE, SIG, currency, faction
standings, sector minimap. Feed includes inline `render <OBJECT>` placeholder
chips — the intended hook for object-model-generated portraits/sprites.

`screenshots/` — reference captures of the prototype states.

## reference/

Worldbuilding and research inputs the design was built from: setting/energy
notes, SF-tradition survey, research on the real THE LINE project, urban
research, and two concept sketches.
