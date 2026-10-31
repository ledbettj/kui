# Developing KUI

Notes for working on the code. For what the addon does, see the README.

## Setup

KUI runs on two clients from this one folder. Each loads its own TOC, and
`Compat.lua` says which client it is and which features run there.

| Client | Interface | TOC | UI code |
| --- | --- | --- | --- |
| TBC Anniversary | 20506 | `KUI_TBC.toc` | Classic UI on a modern client: `C_Container`, `C_CombatLog`, the Settings panel and Edit Mode, with classic gameplay. Everything in KUI was built on it. |
| WoW "forever" (the Camelot game type) | 16001 | `KUI.toc` | Retail's UI code, including **secret values** (see below). Features are switched on here as they're ported. |

- Link this folder into each game's `Interface/AddOns/KUI`. `/reload` picks
  up Lua changes and new files listed in the TOCs.
- Both TOCs list the same files in the same order; change both together.
  The client picks `KUI_TBC.toc` on TBC and falls back to `KUI.toc`
  everywhere else.
- Blizzard's own UI code is the best API reference. Export it from each
  client (`/console exportInterfaceFiles code`) and search the right one
  before relying on memory. The two differ a lot, and both differ from the
  original 2007 client.

### Secret values (forever)

During combat, encounters, Mythic+ and PvP, the forever client hands
addons many unit, aura, cast, threat and combat log values as secrets. They
can be passed straight to widgets (`StatusBar:SetValue`,
`FontString:SetText`) but not compared, used in math, or used as table
keys; doing so raises an error. The generated API docs mark these
(`SecretReturns`, `SecretWhen...Restricted`, `ConditionalSecret`). Ported
code uses the secret-safe APIs instead, such as `UnitHealthPercent`,
`CreateUnitHealPredictionCalculator`, `UnitCastingDuration` with
`StatusBar:SetTimerDuration`, and `Region:SetAlphaFromBoolean`, and checks
`issecretvalue` where it must. Restrictions only apply in those
situations, so test in a fight or dungeon, not just out in the world.
- Lint before reloading: `luacheck .` (settings in `.luacheckrc`). It
  catches typos in names, stray globals and unused variables. When code
  starts using a WoW API it doesn't know yet, add the name to
  `read_globals` there.
- Saved settings live in `WTF/Account/<account>/SavedVariables/KUI.lua`,
  as named profiles plus which one each character uses (see `Core.lua`).

## Layout

Files load in TOC order and share one namespace table, `ns` (the
`...` every file starts with).

| File | Purpose |
| --- | --- |
| `Compat.lua` | Which client this is (`ns.isTBC`, `ns.isForever`, `ns.hasSecrets`) and which features run on it (`ns.supported`) |
| `Defaults.lua` | Which unit frames exist (`ns.units`) and every setting's default (`ns.settingsDefaults`) |
| `Core.lua` | Saved variables, the apply-settings entry points, startup, slash commands |
| `Media.lua`, `Colors.lua` | Textures, borders and fonts by name (with LibSharedMedia); palettes and color lookup |
| `Widgets.lua` | Shared building blocks: bars, text, fonts, borders, hiding Blizzard frames |
| `UIFont.lua` | The optional whole-UI font |
| `Auras.lua`, `Indicators.lua`, `HealPrediction.lua`, `Castbar.lua` | Pieces used by unit frames and nameplates |
| `Frames.lua` | The unit frames and their arrangement |
| `ActionBars.lua`, `Buffs.lua`, `Nameplates.lua`, `StatusBars.lua`, `Chat.lua`, `MenuBar.lua`, `Minimap.lua`, `Tooltip.lua` | Restyling or replacing parts of Blizzard's UI |
| `Vendor.lua` | Auto-repair and selling grey items at vendors |
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

**Porting a feature to forever**
1. Make the module work with the forever client's APIs, branching on
   `ns.isForever` (or `ns.hasSecrets`) only where the clients really
   differ, and keeping the TBC path as it is.
2. Turn it on for forever in `ns.supported` (`Compat.lua`).
3. Its settings sections show up automatically: `b.Section(text, feature)`
   in `Config.lua` hides a section when its feature is off.

Core only calls a feature's `Init*` (and the `Apply*` functions that change
Blizzard frames directly) when the feature is supported. Everything else
is already safe to call before `Init`.

**A new setting**
1. Add it with its default to the right section of `ns.settingsDefaults`.
   Existing users get it filled in on load.
2. Read it as `ns.db.<section>.<key>` where it's used. `ns.db` is the
   current profile and is replaced when the player switches, so look it up
   each time rather than keeping a reference.
3. Add a control in `Config.lua` with `Bind(section, key, setter)`. The
   setter stores the value and calls the cheapest correct apply function.
4. If a setting is renamed or changes meaning, migrate the old value in
   `InitProfile` (`Core.lua`), which runs on every profile as it's loaded.
5. If it only takes effect at login, add it to `LOGIN_ONLY` in `Core.lua`
   so switching profiles asks for a /reload.

**A new info bar readout**
Add an entry to `ns.readouts` in `InfoBar.lua` (a label, an `update`
function returning the text, and an `interval` and/or `events`), then add
its id to the default `order` and `slots` in `Defaults.lua`. Saved layouts
pick it up automatically. Optionally add `tooltip(tt)` to fill the hover
tooltip, and `click` with a `hint` line for it. Returning "" from `update`
hides the readout until it has something to show.

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
