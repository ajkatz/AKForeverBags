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
- **The bag buttons, docked under the bag window.** On Forever a bag is swapped by dropping it on a bag slot
  button, and those only live on Blizzard's bag bar at the bottom right - which the combined bag window has
  none of. The bar is docked under the bag window's right end instead, with a small arrow that folds it away
  and brings it back; it shows, hides and scales with your bags, and every button on it is still Blizzard's own.
- **Built not to break things:** the addon never calls Blizzard's bag functions and never touches a
  protected frame in combat - no "action blocked" popups.

### Commands

| | |
|---|---|
| `/fbags hide` / `show` | put the reagent slots away / bring them back |
| `/fbags off` / `on` | Blizzard's separate reagent window / the merged view (default) |
| `/fbags key off` / `on` | leave the backpack key alone / it opens all bags (default) |
| `/fbags order top` / `bottom` | the backpack top left in the combined window, as before October 8 / at the bottom, as the client lays it out now (default) |
| `/fbags reagents top` / `bottom` | the reagent slots after the last of Blizzard's, at the top (default) / in the bottom rows, Blizzard's slots above them |
| `/fbags sort` | the reagent pouch filled first, the client's sort, then your pinned items at the very bottom. The client's own sort (its button, `/sort`) gets the pouch fill and the pins too; `/fbags sort auto off` leaves it alone |
| `/fbags pin <item>` / `unpin <item>` / `pins` | what stays at the bottom after a sort (a shaman's four totems out of the box) |
| `/fbags bagbar window` / `show` / `hide` | the bag buttons docked under the bag window (default) / in Blizzard's place, always / away |
| `/fbags bagbar fold` / `unfold` | what the arrow under the bag window's corner does; remembered over a logout |
| `/fbags status`, `/fbags diag` | what it is doing; a report for bug reports |

Needs the **combined bag** setting (the default). Works with or without other UI addons.

### Saved settings

Settings are saved per character and survive logging out (client build 1.60.1.70170 of Oct 1 2026 and
later). The defaults (everything on) need no settings.

### Community

Questions, bug reports and ideas for the AKForever addons: join the Discord - https://discord.gg/cFvvvHVm4J

## Logo and screenshots

Logo (400 x 400): `..\ForeverBranding\out\AKForeverBags\logo-400.png` (master: `logo-1024.png`).
Screenshot to take in game: the open bag window with the green reagent slots in the grid.
