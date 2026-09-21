# AKForeverBags

## 0.2.0 - first public release

For **World of Warcraft: Forever** (1.60.1, Interface 16001).

- The reagent bag's slots appear **inside the combined bag window's own grid**, right after your normal
  slots, each with a green slot background. They are Blizzard's own item buttons: using, dragging,
  splitting, selling, searching and sorting work as ever, in and out of combat.
- The backpack key opens the reagent bag too (it runs Blizzard's own *Open All Bags*).
- The bag bar's reagent bag button stays Blizzard's: a click hides the reagent slots, the next brings them
  back; the bag can be picked up, swapped and unequipped as ever.
- No timers, no polling: the addon only runs when something happened.
- `/fbags hide` / `show` puts the reagent slots away / brings them back; `/fbags off` / `on` switches the
  whole thing; `/fbags status`; `/fbags diag`.
- Fixed before release: a click in the bag window (or on a bag bar docked into it) put that window in
  front of the reagent slots - the items vanished, the green slots stayed.

Known limits of the 1.60.1 beta client, not of the addon: it writes addon settings on logout but never
reads them back, so `/fbags hide`, `off` and `key off` last until you log out. The defaults
(everything on) need no settings.
