# ForeverBags

Bag window fixes for **World of Warcraft: Forever** (Interface `16001`).

> Part of a small family of addons built for the **WoW: Forever** game mode, with one mission: **minimalistic UI additions that bring out the utility
> Blizzard's UI does not give - minimal in nature, no Lua errors, always smooth.**

Status (2026-09-20): proven in the game - reagent slots in cells 45-48 of Blizzard's own top row, merged in
and out of fights, the "key ring" bug fixed and confirmed, 0 errors and 0 blocked actions in every report.
Then trimmed to the mission: **no timers, no polling** (the addon only runs when Blizzard lays out a bag
window, on a mouse button in the bag window, on an option change and at the end of a fight), nothing of ours
covers any of Blizzard's buttons, the bug-hunt instrumentation is gone. 20 scenarios against a mock of
Blizzard's bag code; 30 of 30 deliberate breakages of the addon are caught by them.

**The performance promise is measured, not claimed** (`lua tests/bench.lua`, and a scenario holds the budgets):

| action | layout passes | reads of Blizzard's frames | writes |
|---|---|---|---|
| bags open or closed, nothing happening | 0 | 0 | 0 |
| a click in the bag window (item, key ring, drag) | 0 | 10-12 | the raise only |
| opening all bags | one per window Blizzard lays out | ~90 | anchors, height, raise |

(A click used to run four full layout passes - ~240 reads; found by measuring, 2026-09-20.) In the game,
`/fbags diag` saves the same gauge (`work`: layout passes, milliseconds spent, the slowest pass, raises on
clicks) next to what the client itself says the addon costs (`performance`: memory, `C_AddOnProfiler`).

## Install

From CurseForge or Wago Addons (game version *World of Warcraft: Forever*), or unpack a release zip into
`_classic_beta_\Interface\AddOns\`. It works out of the box; `/fbags` lists the commands.

The 1.60.1 beta client writes addon settings on logout but never reads them back: changed settings last
until you log out (the defaults need none). `tools/Install-SavedStateBridge.ps1` is the workaround used
during development.

## The reagent bag's slots, in the bag window's own grid

Forever has a reagent bag slot - but Blizzard's combined bag view only takes the backpack and bags 1-4
(`ContainerFrame_IsGenericHeldBag`). The reagent bag, bag 5, always gets a window of its own
(`ContainerFrame6`), opened next to the combined window by *Open All Bags*.

ForeverBags puts its slots **into the combined window's grid, as a continuation of the normal slots**, and
gives each of them a **slot background in another colour** (green; with a thin rim that still shows around
an item). No section of their own, no header: Blizzard fills its grid from the bottom right, which leaves
the left end of the top row empty - the reagent slots take those cells, then rows of their own on top, and
the window grows by exactly the rows that are needed (none, if they fit into the gap). None of Blizzard's
normal slots is moved.

| | |
|---|---|
| `/fbags on` / `off` | the merge (default on). Off = Blizzard's separate reagent window, as before |
| `/fbags show` / `hide` | reagent slots shown in the grid (default) / put away - the bag window then looks stock. Remembered over a logout |
| `/fbags key on` / `off` | the backpack key opens the reagent bag too (default on, see below) |
| `/fbags status`, `/fbags diag` | what it is doing; a report into the settings file (then `/reload`) |

### How - and what it deliberately does not do

The reagent slots in the grid are **Blizzard's own item buttons**: still children of Blizzard's reagent
window, still filled, updated, searched, sorted and clicked by Blizzard's own secure code. Using,
dragging, splitting, selling, linking - nothing is re-implemented, no item data is ever read here (so
nothing can be "secret" to us in a fight). The addon only says where things stand:

* the reagent window is pushed off the screen (still open: its buttons only exist while it is);
* the combined window's grid is READ from Blizzard's own buttons (`AnchorUtil.GridLayout`: every button
  anchored `BOTTOMRIGHT` to the money row's `TOPRIGHT`, 42 px apart, 10 wide, from the bottom right) - a
  layout that does not look like that (gamepad mode, a future build) or an unreadable anchor means hands off;
* the reagent buttons are re-anchored to the same money row, into the cells after Blizzard's last one, in
  Blizzard's order (highest slot first, so slot 1 ends up top left);
* the reagent window is kept **in front of the bag window** (next section);
* the combined window is made taller by the extra rows (`SetHeight` on top of the height Blizzard gave it,
  remembered by a post-hook on its `UpdateFrameSize`);
* the coloured slot backgrounds are OUR textures on OUR frame (a child of the bag window) - item buttons
  have no background of their own (in the combined window Blizzard gives each of its buttons one,
  `ItemSlotBackgroundCombinedBagsTemplate`; ours is that art, tinted). Nothing is created on Blizzard's buttons.

### In front of the bag window (the "key ring" bug, 2026-09-20)

Reported: *a click on the key ring makes the reagent items vanish - the green slots stay, and hovering shows
no tooltip.* Every getter said the buttons were shown, visible, at full alpha, where they belong; with
`showKeyring = 0` the click does not run one line of Blizzard's Lua that changes anything.

Blizzard's bag windows live in **two `toplevel` frames**: the combined window itself, and
`ContainerFrameContainer`, the full-screen parent of every separate bag window - the reagent window among
them. A toplevel frame *flattens its render layers*: everything in it is drawn as **one unit**, and which
of two such units is in front is decided by **which was raised last** - not by the strata or level of
anything inside them (the `HIGH` strata the moved buttons once got changed nothing, and is gone). A mouse
button going down anywhere in the combined window's unit raises it over the reagent window's unit, and so
over the reagent slots standing in its grid: items gone, our slot backgrounds (the combined window's
children) still there, the mouse no longer reaching the slots. The key ring is merely the one bag bar button
whose click leaves the bags open - and an addon that docks the bag bar *into* the bag window
(ForeverActionBars does) makes it part of that unit.

The way back is the call Blizzard's own code makes whenever a bag window opens
(`ContainerFrame_GenerateFrame`: `frame:Raise()`) - the reason the slots *are* in front right after *Open
All Bags*. ForeverBags makes it (on the reagent window, and on its toplevel parent) when the slots are
merged, after every `UpdateContainerFrameAnchors`, and on `GLOBAL_MOUSE_DOWN` / `_UP` over anything in the
bag window - at once and once more a frame later, in case the client raises after it has told us (a held
button is a drag: the slots must be there to be dropped on). Nothing is raised while nothing happens, so a
window you put over your bags stays there. Confirmed in the game on 2026-09-20 with a probe that has since
been removed: with the mouse over a merged reagent slot after key ring clicks, the *slot* had the mouse
every time; both frames measured `IsToplevel()`; frame levels unchanged after 17 raises.

The bag bar's **reagent bag button stays Blizzard's**: a click there closes the reagent window (and with it
the merged slots - they only exist while it is open), the next click brings them back. An earlier version
laid a button of its own over it to swallow that click; it also swallowed picking the bag up, swapping and
unequipping it - so it is gone, and nothing of ours covers any of Blizzard's buttons.

Every path in Blizzard's `ContainerFrame.lua` that sizes a bag window or lays out its buttons ends in the
global `UpdateContainerFrameAnchors()`. One `hooksecurefunc` post-hook there re-applies all of this in
the same frame (no flicker). Every call site of `UpdateItemLayout()` in that file is followed by it
(checked in the `forever` branch of wow-ui-source), so there is no watchdog and no timer at all.

**Never done** - the bag code is where "action blocked" taint traditionally starts:

* calling Blizzard's bag functions (`OpenBag`, `ToggleAllBags`, `frame:Update` ...): run by an addon they
  write tainted values into the bag frames;
* re-parenting an item button (its code asks `self:GetParent()` for bag window methods - the lesson of
  ForeverCombatTimers' target cast bar);
* showing / hiding a bag window, `SetScript` / `HookScript` on Blizzard's frames, writing any field on them.

That is why the **backpack key** gets an override binding to Blizzard's own *Open All Bags* command: the
reagent window has to be open for its buttons to exist, the backpack key alone opens only the combined
window (`ToggleBackpack_Combined`), and an addon must not open it. With the override the key press runs
Blizzard's `ToggleAllBags()` securely. A click on the backpack *button* still opens the combined window
alone - then the reagent slots simply are not there. The test mock fails a scenario on every one of the things above.

Getters on Blizzard's frames can answer with secret values on this client: anything unreadable means
hands off. In a fight the frames are only moved because they are not protected (if they ever are, it
waits for the end of the fight).

Known limits: Blizzard works out the bag windows' scale and columns before our extra rows are added (only
matters when the bag window nearly fills the screen's height), and while the bank is open it still
reserves a column for the parked reagent window.

## Development

```
lua tests/run.lua      # scenarios (fail on any Lua error, taint risk, forbidden call in combat, blown budget)
lua tests/bench.lua    # work per player action
```

Releases: a pushed tag (`v0.2.0`) runs the tests and the [BigWigs packager](https://github.com/BigWigsMods/packager)
(`.github/workflows/release.yml`, `.pkgmeta`), which uploads to CurseForge, Wago and GitHub Releases.
`docs/LISTING.md` holds the marketplace text.

`tools/Install-SavedStateBridge.ps1` installs the saved-settings bridge (the 1.60.1 beta client writes
SavedVariables but never reads them back).
