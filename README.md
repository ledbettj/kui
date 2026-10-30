# KUI

A clean, minimal UI replacement for World of Warcraft: The Burning Crusade
Anniversary.

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
- Readouts for gold, bag slots, durability, map coordinates, fps, latency
  and the clock, each placed on the left, center or right (or hidden) and
  reorderable, with adjustable spacing

## Minimap

- Optional square minimap in the KUI border; minimap buttons from other
  addons follow the square edge
- Round button rings around the square map are cleaned up, and the mouse
  wheel zooms in place of the zoom buttons

## Chat

- Optionally hides the button column beside the chat windows

## Damage meter

- Damage and healing for everyone in your group, current fight or overall
- Pets, totems and summons count toward their owner
- Healing counts only what landed, plus damage absorbed by shields
- Totals and per-second numbers on class-colored bars
- The current fight is named after the enemy you hit hardest; hover the
  title for every enemy in it
- Click a player's bar to split their total by spell, with their pets'
  spells listed separately; each spell has its icon and a bar colored by
  its school (fire, shadow, ...). Right-click to go back
- Click the title to switch views, drag it to move

## Customization

Open the settings with `/kui`, or go to Options → AddOns → KUI.

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
- Reset to defaults at any time
