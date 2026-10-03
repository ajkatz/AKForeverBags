# AKForeverBags

## 0.3.1

- **Settings follow the character again.** Client build 1.60.1.70170 (Oct 1 2026) moved a character's
  surname into the realm slot of `UnitName`, so every character started a fresh, empty profile. The profile
  is now keyed by the full name and the realm (`Purrdee Bubson - ClassicBetaPvE`, the spelling the older
  builds saved under) and bound at PLAYER_LOGIN, when the client knows the name for sure, so a cold login no
  longer lands in an `Unknown` profile. Profiles saved under the other spellings are folded into it the
  first time each character logs in: the long-standing profile keeps its values, the others fill its gaps,
  and `/fbags diag` says what was adopted.
- The same client build reads saved settings back again, so "changed settings last until you log out" is
  history; the saved-settings bridge (`tools/Install-SavedStateBridge.ps1`) is no longer needed and
  `-Remove` takes it out.

## 0.3.0

- **The bag buttons dock under the bag window.** A bag is swapped by dropping it on a bag slot button, and
  those only live on Blizzard's bag bar - which floats on its own once an action bar addon has put
  Blizzard's bottom fixtures away, and leaves no way to swap a bag once hidden. The bar is now a child of
  the combined bag window, hanging under its right end, with a little arrow beside it that folds it away
  and brings it back (`/fbags bagbar window|show|hide`, `fold|unfold`). Every button on it stays
  Blizzard's own; only `SetParent` and the raw anchor methods are used, never while Edit Mode is open, and
  no timer. With separate bag windows the bar shows in Blizzard's place while a bag is open, and while
  Blizzard's own action bars are on the screen it is never docked (the main bar's end cap hangs on it).
  Moved here from AKForeverActionBars, which leaves the bar alone while this addon runs.

## 0.2.2

- Opening the bags no longer trips Blizzard's "attempt to call a nil value" error on build 70009 and
  later: the reagent slots take the window's height from the window itself instead of hooking
  Blizzard's resize method. Nothing of Blizzard's is hooked or run for it.

## 0.2.1

- Now on Wago Addons too. The addon itself is unchanged.

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
