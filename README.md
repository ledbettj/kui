# KUI

A clean, minimal UI replacement for World of Warcraft: The Burning Crusade
Anniversary.

Support for WoW "forever" is under way, with features switched on as
they're ported. So far: the unit frames (with their cast bars, auras and
incoming heals), the info bar, tooltips, vendor repair and grey selling,
chat buttons, the whole-UI font, bag and menu buttons, and the buff and
action button styling. Nameplates, XP bars and the minimap are still TBC
only. The damage meter stays TBC only: forever has its own, which you turn
on under Options → Advanced and place with Edit Mode.

Forever hides some combat details from addons, so there a few things show
less: no cast pushback, no aggro border or PvP flag while they're hidden,
and class colors fall back to reaction colors in PvP.

## Unit frames

- Player, target, target of target, focus and pet frames
- Party and party pet frames
- Health colored by class for players and by reaction for NPCs
- Incoming heals shown on the health bar, yours and other healers' separately
- Aggro border: player, pet and party frames turn yellow, orange or red as a
  mob comes after them
- Buffs and debuffs above the player and target, and below party members
- Cast bars built into the player and target frames, and under the focus
  frame
- Raid target markers, leader and master looter icons, PvP flag, and
  resting / in combat icon
- Combo points on the target frame
- Party members fade when out of range
- Works with Clique for click casting

## Cast bars

- Spell icon, name and remaining time
- Separate colors for casts, channels and interrupted or failed casts
- Pushback shown in red beside the time: how much later a cast will finish
  (+0.5s), or how much was cut off a channel (-0.5s)

## Nameplates

- Restyled to match the unit frames, with name and health percentage
- Threat border and threat percentage while you're on a mob's threat list
- Your own debuffs above enemy plates, plus the buffs your class can dispel
  or purge
- Your own buffs above friendly plates
- Cast bar under the plate while the unit is casting

## Action bars

- Square icons with a clean border, highlighted while an action is active
- Icons turn red when the target is out of range
- Optional keybind and macro name text
- A green dot on any button holding a spell below its highest known rank

## Bags and menu

- Show all bag buttons, only the backpack, or none at all
- Optionally hide the micro menu (character, spellbook, game menu and so on)

## Buffs and debuffs

- Your buff and debuff icons (top right) restyled with square icons and
  borders
- Debuff borders colored by type (magic, curse, disease, poison)
- Weapon enchants like oils and poisons have their own border color

## XP and reputation

- Slim XP and reputation bars at the top or bottom of the screen
- Rested XP shown on the XP bar
- Numbers appear when you hover the bar

## Info bar

- A full-width strip along the bottom of the screen in the KUI style, with
  the XP and reputation bars resting on top of it
- Readouts for gold, bag slots, durability, friends and guild members
  online, map coordinates, XP per hour, mana regen, fps, latency and the
  clock, each placed on the left, center or right (or hidden) and
  reorderable, with adjustable spacing
- Hover a readout for details: gold on all your characters and gained this
  session, each bag's space, which items need repair, who's online and
  where, time to level, addon memory use, local and realm time
- Click one to open the matching window: bags, character, friends, guild,
  world map, clock options

## Tooltips

- KUI border and background, with item tooltips bordered in the item's
  quality color
- Player names in their class color, and a line showing what the unit is
  targeting
- Slim health bar colored like the unit frames
- Optionally hidden for units while you're in combat

## Vendors

- Repairs automatically, from the guild bank if you allow it and it can
  cover the bill
- Sells grey items, with the total in chat
- Hold Shift while opening a vendor to skip both

## Minimap

- Optional square minimap in the KUI border; minimap buttons from other
  addons follow the square edge
- Round button rings around the square map are cleaned up, and the mouse
  wheel zooms in place of the zoom buttons

## Chat

- Optionally hides the button column beside the chat windows

## Damage meter

- Damage and healing for everyone in your group, current fight or overall;
  overkill on killing blows doesn't count
- Pets, totems and summons count toward their owner
- Healing counts only what landed, plus damage absorbed by shields;
  overhealing has its own view, with how much of each player's and each
  spell's healing was wasted
- Totals and per-second numbers on class-colored bars
- The current fight is named after the enemy you hit hardest; hover the
  title for every enemy in it
- Click a player's bar to split their total by spell, with their pets'
  spells listed separately; each spell has its icon and a bar colored by
  its school (fire, shadow, ...). Right-click to go back
- Click the title to switch views, drag it to move
- Resets itself when you enter a different instance (optional); the Reset
  button asks first

## Customization

Open the settings with `/kui`, or go to Options → AddOns → KUI.

- Profiles: every character uses Default until you give it its own
  profile (a copy of the current settings). Characters can share a
  profile, copy settings from another one, or switch at any time
- One font for the whole Blizzard UI (Arial Narrow by default), keeping
  each text's own size
- Fonts, font size, bar textures, border style, size and color, and
  background opacity, with LibSharedMedia textures and fonts supported
- Frame widths, positions and spacing, power and cast bar heights
- Color palettes (Default and Muted), plus per-color overrides for classes,
  reactions, power types, cast bars, heals, threat and spell schools
- Every feature can be switched on or off individually
- `/kui preview` shows every frame with placeholder contents so you can
  arrange the layout outside a group
- Reset a profile to the defaults at any time
