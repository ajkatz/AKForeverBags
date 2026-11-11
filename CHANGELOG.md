# AKForeverBags

## 0.5.0

- **The sort no longer gets stuck.** A sort with nothing to move (the bags already in order) sends no word from
  the client, and the run waited for it for good - every sort after it, Blizzard's button or `/fbags sort`, was
  turned away until a reload. Now the run goes on a moment later all the same.
- **Labels: every item can carry one, and the sort stacks them in groups.** From the bottom up: Permanent
  (the pinned totems), Profession tools, Main spec, Off spec, Trade goods, Consumables, Quest items; then
  everything unlabelled, as the sort left it; Junk (greys) in the top cells, handy for selling.
- **Most label themselves.** Trade goods, consumables, quest items and junk are read from the item; the old
  profession tools (mining pick, skinning knife, hammer, spanner, runed rods, fishing poles...) are known
  by name; Permanent is the pin list. Main spec and Off spec you set by hand. A label you set always wins -
  "No label" too, which keeps an item out of its automatic group. `/fbags labels auto off` turns the
  automatic ones off.
- **The padlock.** A small padlock hangs under the bag window's bottom-left corner. Click it for the list of
  labels, pick one, and left-click items to give them that label - each goes straight back to its slot;
  clicking an item that already has it takes it off. The padlock glows in the label's colour while you
  label; the padlock again, or closing the bags, finishes. A key binding (Key Bindings > AddOns >
  AKForeverBags) does the same for the item under the mouse. Labels you set by hand wear a border in the
  label's colour, and so do trade goods (cyan) and quest items (orange) all by themselves. Every copy of an item counts, kept per character. `/fbags labels` lists them,
  `/fbags labels clear` takes them all off. Nothing of Blizzard's is hooked or covered.

## 0.4.1

- **Works the same without a reagent pouch.** With no pouch equipped (or its window not open), the sort's pins
  stopped with "the bag window's grid is not known" and `/fbags order top` was ignored. Both now work on the
  backpack alone, and taking a pouch off puts everything of the merge back.

## 0.4.0

- **The reagent pouch first, pins at the bottom - around the client's sort.** `/fbags sort` fills the
  reagent pouch with everything that belongs there, runs the client's sort, then swaps the pinned items
  into the bottom-right cells of the window, everything else keeping its order and closing up (one
  permutation, done in two rounds of simultaneous swaps). Every sort the client runs on its
  own (Blizzard's button, `/sort`) is followed by the same pouch fill and pins (`/fbags sort auto off`
  leaves it alone). `/fbags pin <item>`, `/fbags unpin`, `/fbags pins`; a shaman's four totems are pinned
  out of the box. (Blizzard's sort button drew nothing on client builds up to 70338; 1.60.1.70425 has its
  artwork back, so there is no button of ours.)
- **`/fbags reagents bottom`: the reagent rows at the bottom of the window** (asked for on CurseForge). The
  reagent slots take the bottom cells and Blizzard's buttons move up by that many - the same re-anchoring
  `order top` does for the mirror, and the two compose. `reagents top` (the default) is the picture as
  before. Pinned items still go to the bottom of the ordinary bags, right above the reagent rows.

## 0.3.2

- **`/fbags order top`: the backpack top left again.** Client build 70291 (Oct 8 2026) turned the combined
  bag window the other way round: the backpack now sorts first and stands at the bottom right, as in
  retail. `order top` mirrors the grid after every layout of Blizzard's - the buttons stay Blizzard's, only
  re-anchored - so the backpack's first slot is top left as before; `order bottom` (the default) leaves the
  client's new picture. The reagent slots follow either way.

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
