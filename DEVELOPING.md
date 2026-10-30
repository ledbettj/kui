# Developing KUI

Notes for working on the code. For what the addon does, see the README.

## Setup

- The client is WoW TBC Anniversary (interface 20506), a modern client
  running the classic game. Its API is mostly the modern one (`C_Container`,
  `C_CombatLog`, the Settings panel, Edit Mode) with classic gameplay.
- Link this folder into the game's `Interface/AddOns/KUI`. `/reload` picks up
  Lua changes and new files listed in `KUI.toc`.
- Blizzard's own UI code is the best API reference. Export it from the
  client (the `ExportInterfaceFiles code` console command) and search it
  before relying on memory; many things differ from both retail and the
  original 2007 client.
- Syntax check before reloading: `luac5.1 -p *.lua`.
- Saved settings live in `WTF/Account/<account>/SavedVariables/KUI.lua`.

## Layout

Files load in `KUI.toc` order and share one namespace table, `ns` (the
`...` every file starts with).

| File | Purpose |
| --- | --- |
| `Defaults.lua` | Which unit frames exist (`ns.units`) and every setting's default (`ns.settingsDefaults`) |
| `Core.lua` | Saved variables, the apply-settings entry points, startup, slash commands |
| `Media.lua`, `Colors.lua` | Textures, borders and fonts by name (with LibSharedMedia); palettes and color lookup |
| `Widgets.lua` | Shared building blocks: bars, text, fonts, borders, hiding Blizzard frames |
| `UIFont.lua` | The optional whole-UI font |
| `Auras.lua`, `Indicators.lua`, `HealPrediction.lua`, `Castbar.lua` | Pieces used by unit frames and nameplates |
| `Frames.lua` | The unit frames and their arrangement |
| `ActionBars.lua`, `Buffs.lua`, `Nameplates.lua`, `StatusBars.lua`, `Chat.lua`, `MenuBar.lua`, `Minimap.lua` | Restyling or replacing parts of Blizzard's UI |
| `InfoBar.lua`, `Meter.lua` | The info bar with its readouts, and the damage meter |
| `Config.lua` | The settings pages |

## Conventions

The header of `Core.lua` has the full list; in short:

- `ns:Verb()` is module API; `ns.Verb(frame)` is a per-frame function shared
  between files (plain functions, so they can go straight into event tables).
- `Init*` runs once at startup. `Layout*` (sizes, anchors), `Style*`
  (textures, colors, fonts) and `Apply*` (on/off state) rerun on every
  settings change, so they must be safe to call repeatedly.
- Unit frames are secure (click targeting, Clique). Anything that moves,
  resizes, shows or hides them is blocked in combat, so it goes through
  `ns:ApplyLayout()`, which defers to the end of combat. Other frames can be
  changed at any time.
- Blizzard frames are hidden with `ns.SetHidden`, which can undo it, and
  hooked with `hooksecurefunc`, never replaced, to avoid tainting them.
- Event-heavy code (auras, the combat log, nameplates) avoids creating
  tables or closures per event.
- Fields KUI adds to Blizzard's frames are prefixed `kui` (`btn.kuiBorder`).
- Comments explain why, and anything a caller has to know first.

## Common changes

**A new setting**
1. Add it with its default to the right section of `ns.settingsDefaults`.
   Existing users get it filled in on load.
2. Read it as `KUIDB.<section>.<key>` where it's used.
3. Add a control in `Config.lua` with `Bind(section, key, setter)`. The
   setter stores the value and calls the cheapest correct apply function.
4. If a setting is renamed or changes meaning, migrate the old value in
   `InitDB` (`Core.lua`).

**A new info bar readout**
Add an entry to `ns.readouts` in `InfoBar.lua` (a label, an `update`
function returning the text, and an `interval` and/or `events`), then add
its id to the default `order` and `slots` in `Defaults.lua`. Saved layouts
pick it up automatically.

**A new color**
Add the key to the kind's order table and defaults in `Colors.lua`, a label
in `Config.lua`, and optionally a palette entry.

## Testing

There are no automated tests; everything is checked in game.

- `/kui preview` (or opening the settings) shows every unit frame with
  placeholder contents.
- Change settings in combat as well as out of it: layout changes should
  wait for combat to end with a chat message, nothing should error.
- Turn on Lua error display (`/console scriptErrors 1`) while testing.
