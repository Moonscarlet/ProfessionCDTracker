# Profession CD Tracker

Track profession cooldowns across characters with a clean, movable bar UI. Saves data account-wide and keeps timers accurate across sessions by storing absolute epoch expiries.

## Features

- Track multiple profession cooldowns across all characters and realms
- Persist timers across logouts/reloads (no lost progress)
- Auto-detect cooldowns when open a trade skill window, or an item cooldown updates
- Manual scan command when you want to refresh on demand
- Compact, movable status bars with remaining time and ready-at clock
- Configurable bar width and height

### Tracked cooldowns (out of the box)

- Mooncloth (Tailoring) — trade skill cooldown
- Transmute: Arcanite (Alchemy) — trade skill cooldown
- Salt Shaker (Leatherworking) — item cooldown

> Want more? See “Extend: add more tracked cooldowns”.

## Installation

1. Download or clone this repository.
2. Ensure the folder name is exactly `ProfessionCDTracker` and contains `ProfessionCDTracker.toc`.
3. Place the folder into your WoW AddOns directory:
4. Restart the game or reload the UI.

## Usage

Use the slash command `/pct`:

- `/pct scan` — force a rescan of known cooldowns
- `/pct show` — show the bars
- `/pct hide` — hide the bars
- `/pct lock` — lock the frame (prevent dragging)
- `/pct unlock` — unlock the frame (drag to move)
- `/pct width <number>` — set bar width (default 205)
- `/pct height <number>` — set bar height (default 12)

Examples:

- `/pct unlock` then drag the bars; `/pct lock` when done
- `/pct width 240` and `/pct height 14` to resize

Behavior:

- Bars turn green when a cooldown is ready, red while on cooldown.
- Right label shows remaining time and the local-time when it will be ready.
- The frame position is remembered per-account.

## Configuration

- Position: `/pct unlock`, drag, then `/pct lock` to save
- Size: `/pct width <n>`, `/pct height <n>`

All settings are stored in SavedVariables and persist across sessions.

## Data storage

SavedVariables: `ProfessionCDTrackerDB`

Structure overview:

```json
{
  "realms": {
    "<RealmName>": {
      "<CharacterName>": {
        "cooldowns": {
          "Mooncloth": { "duration": 604800, "expiresEpoch": 1727385600 },
          "Transmute: Arcanite": { "duration": 172800, "expiresEpoch": 1727200000 },
          "15846": { "duration": 604800, "expiresEpoch": 1727385600 }
        }
      }
    }
  },
  "settings": {
    "barWidth": 205,
    "barHeight": 12,
    "locked": false,
    "anchor": { "point": "CENTER", "relativePoint": "CENTER", "x": 0, "y": 0 }
  }
}
```

Notes:

- Cooldowns are saved using `expiresEpoch` to stay accurate across reloads and logins.
- Data is account-wide; characters and realms are nested under `realms`.

## Extend: add more tracked cooldowns

You can add more cooldowns by extending the tracking table. Trade skill entries use the recipe name returned by the API; item entries use the numeric item ID.

```lua
-- In ProfessionCDTracker.lua, near the TRACKED table
local TRACKED = {
  ["Mooncloth"] = { label = "Mooncloth", type = "trade", icon = 14342 },
  ["Transmute: Arcanite"] = { label = "Transmute: Arcanite", type = "trade", icon = 12360 },
  [15846] = { label = "Salt Shaker", type = "item", icon = 15846 },
  -- Add your own:
  ["Transmute: Living Elements"] = { label = "Transmute: Living Elements", type = "trade", icon = 35624 },
  [12345] = { label = "Your Item Name", type = "item", icon = 12345 },
}
```

Tips:

- For trade skills, the name must match exactly what `GetTradeSkillInfo(i)` returns.
- For items, the key must be the item ID (number). The icon is cosmetic here.

## Troubleshooting

- Bars don’t appear
  - Run `/pct show`. If still hidden, `/reload`.
- A cooldown you expect isn’t showing
  - Open the relevant profession window so the game can report recipe cooldowns, then `/pct scan`.
  - For item-based cooldowns (e.g., Salt Shaker), ensure the item is in your bags and has been used at least once.
- Frame can’t be moved
  - Run `/pct unlock`, drag it, then `/pct lock`.
- Times look wrong after logging in
  - The addon stores absolute expiries. If your system clock changed significantly, trigger a rescan: open the profession window and run `/pct scan`.

## Credits

- Author: Moonscarlet
- Addon: Profession CD Tracker
