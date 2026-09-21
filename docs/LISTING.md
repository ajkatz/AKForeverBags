# Marketplace listing text (copy / paste)

**Name:** AKForeverBags
**Category:** Bags & Inventory
**Game version:** World of Warcraft: Forever (1.60.1)
**License:** MIT
**Summary (one line):** Puts the reagent bag's slots into your combined bag window - right in the grid, in green.

## Description

*Part of a small family of addons built for the WoW: Forever game mode, with one mission: minimalistic UI additions that bring out the utility
Blizzard's UI does not give - minimal in nature, no Lua errors, always smooth.*

WoW: Forever gives you a reagent bag slot - but its contents always open in a separate little window next
to your bags. **AKForeverBags puts those slots into the combined bag window's own grid**, right after your
normal slots, each with a green slot background so you can tell them apart.

- **Nothing is re-implemented.** The slots are Blizzard's own item buttons, only moved: using, dragging,
  splitting, selling, linking, searching and sorting work exactly as before - in and out of combat.
- **One key for everything:** your backpack key opens the reagent bag too (it runs Blizzard's own
  *Open All Bags*).
- **Featherweight:** no timers, no polling - it only runs when your bags are laid out or clicked.
- **Built not to break things:** the addon never calls Blizzard's bag functions and never touches a
  protected frame in combat - no "action blocked" popups.

### Commands

| | |
|---|---|
| `/fbags hide` / `show` | put the reagent slots away / bring them back |
| `/fbags off` / `on` | Blizzard's separate reagent window / the merged view (default) |
| `/fbags key off` / `on` | leave the backpack key alone / it opens all bags (default) |
| `/fbags status`, `/fbags diag` | what it is doing; a report for bug reports |

Needs the **combined bag** setting (the default). Works with or without other UI addons.

### Known limitation of the 1.60.1 beta client

The beta client writes addon settings on logout but never reads them back, so changed settings last
until you log out. The defaults (everything on) need no settings.

## Logo and screenshots

Logo (400 x 400): `..\ForeverBranding\out\AKForeverBags\logo-400.png` (master: `logo-1024.png`).
Screenshot to take in game: the open bag window with the green reagent slots in the grid.
