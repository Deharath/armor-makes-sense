# Armor Makes Sense - UI Reference

AMS shows every readout as a strip of four pips (tooltips) or four cells
(Burden tab). Pips count lit bands from
`shared/ArmorMakesSense_PresentationPolicy.lua`; drawing lives in
`client/core/ArmorMakesSense_Draw.lua` and is shared by the tooltip and the
Burden tab. Exact numbers are left to the support report and the dev panel.

## Pip Bands

A pip lights once the value reaches its band threshold.

| Strip | Input | Pip 1 | Pip 2 | Pip 3 | Pip 4 |
|---|---|---|---|---|---|
| Load | `loadFraction` (share of body mass) | 0.02 | 0.07 | 0.13 | 0.25 |
| Item | one item's `burdenKg` | 1.5 | 3.0 | 4.5 | 6.0 |
| Heat | `heat` (insulation × heat strain) | 0.05 | 0.20 | 0.40 | 0.65 |
| Breathing | `breathingSeverity` of worn gear | 0.10 | 0.35 | 0.60 | 0.90 |
| Sleep | `sleepPenaltyFraction` | 0.03 | 0.10 | 0.20 | 0.30 |
| Melee | `armKg` (swing-chain effective kg) | 1.5 | 3.0 | 5.0 | 8.0 |

Load pips also name a tier: 0 Negligible, 1 Light, 2 Moderate, 3 Heavy,
4 Extreme. Strips use their channel color at 1–2 pips, amber at 3 and red at 4.
The tier label is dim at 0 pips, plain at 1–2, then amber and red. The Burden
tab fills cells continuously with `Policy.fill`: whole cells for passed bands
and a partial cell for progress toward the next, so `floor(fill)` always equals
the pip count.

The item bands start above 1.0 kg because vanilla leaves most shoes and
trousers at the default script weight: every pair of shoes is exactly 1.0 kg of
burden, which should not read as a cost.

## Tooltip Integration

`client/core/ArmorMakesSense_UITooltip.lua` wraps `ISToolTipInv.render`. For
eligible wearables (non-container items with a body location) it publishes the
item/tooltip pair and relies on one persistent `DoTooltip` wrapper per item
class. The wrapper takes over only while that pair is active. It renders
vanilla's rows through `DoTooltipEmbedded`, then draws the AMS pip block
underneath and extends the tooltip height and width. Outside an AMS render, or
for any other tooltip, the wrapper calls vanilla directly. That makes it safe
next to other mods that wrap `DoTooltip`. Measure-only passes size the tooltip
without drawing.

| Row | Shown when |
|---|---|
| Burden | item burden reaches the first item band (1.5 kg) |
| Breathing | breathing channel enabled and item severity reaches the first breathing band |

The label column clears the widest vanilla clothing label, so AMS pips line up
with vanilla values. If the vanilla tooltip class is not ready at the first UI
update, installation is deferred and retried.

When `EuryTooltipController` is installed, AMS registers as a row provider.
It leaves the owner render alone and exposes the same rows as `n/4` text.

Shoulderpads are reslotted by AMS, so vanilla's "no backpack" note is wrong for
them. The render wrapper hides that one tooltip key for the duration of the
render and restores it afterwards, even if the owner render errors.

## Burden Tab

The tab answers "what is my gear costing me, and what would fix it". Content is
built by the pure view model `BurdenView.build` and drawn by `BurdenPanel`.

| Area | Content |
|---|---|
| Verdict | One sentence at the top, colored by severity. Priority: walking drains endurance > overheating > extreme load > heavy load > heavily restricted breathing > warm > moderate load > light load > poor sleep > keeping warm > free. |
| Body map | Vanilla `ISBodyPartPanel` silhouette colored by effective kg per body part (dark at 0, amber around 1.5 kg, red at 3 kg), with a color scale underneath. Hovering narrows it to a cause: a gear row shows that item; the Load, Melee, Breathing or Sleep row shows the gear feeding it (swing-chain gear, masks and sealed gear, stiff gear by rigid kg) and lights those gear rows; a body part shows its kg and lights the gear on it. |
| Load | Tier, four cells, total effective kg. The detail line shows the clothing allowance while under it, otherwise the body mass and Strength the load is rated against. |
| Endurance | Two lines: Recovery (standing, walking) and Exertion (running, sprinting). Each pace reads "normal", a signed percent against vanilla, or "drains" when walking recovery goes below zero. |
| Heat | Heat state and cells. While running hot, the detail line gives the recovery penalty at rest. In the cold, a positive "Keeping you warm" state. Omitted when the thermal model is disabled. |
| Breathing | Restriction state and cells. Omitted when the breathing model is disabled. |
| Melee | Arm load state from `armKg`, with the summed swing slowdown from `SpeedRebalance.combatSpeedModifier` and whether arm strain applies. |
| Sleep | What stiff gear (vanilla discomfort above 0) would cost if the character slept now. Omitted when the sleep penalty is disabled. |
| Heaviest gear | Up to six rows of worn items at or above 1.5 effective kg: item icon, name, cells and kg. Pieces with the same display name and burden (left and right shin guards are separate item types) share one row with a count and combined kg; cells rate one piece. Lighter items are summed on one line. |
| Tip | At Moderate load or above, the one piece whose removal drops the load tier most: "Without the X: Y load." |
| Armor buttons | Bottom left, shown only when they would act. **Take Off Armor** and **Drop Armor** remove every worn rigid item (the Sleep row's stiff gear), outer layers first, into the inventory or onto the floor, and remember the set. **Wear Armor (N)** puts back on the remembered pieces that are nearby, inner layers first, picking them up from bags or the 3×3 floor around the player (not through walls). The tooltip lists the pieces and names any that are not nearby. Buttons are disabled while the player is asleep or busy. They move onto their own row when they do not fit beside Save Report and Help. |

Rows whose cells would be empty (no heat, clear breathing) collapse to their
header line so active channels stand out.

Each row label (Load, Endurance, Heat, Breathing, Melee, Sleep, Heaviest gear)
is followed by a small boxed "?". Hovering it shows a plain-language
explanation of that row in a vanilla `ISToolTip` that follows the mouse
(`BurdenView.info(key)`, keys `UI_AMS_Info_*`). The panel owns one tooltip and
hides it when the mouse leaves the marker or the panel is hidden.

Each `UI_AMS_Info_*` string is one line per `\n`: the first line is a bright
summary, `# ` starts a gold heading, `- ` a bulleted point with a hanging
indent (bullet from `UI_AMS_Info_Bullet`), and any other line a dim closing
note. Percent figures are `%1`/`%2` arguments, since a bare `%` breaks Java
format strings.

The **Help** button opens a separate window with the overview the rows do not
cover: what AMS changes and leaves vanilla, how to read the tab, the armor
buttons, tips, sandbox options, modded gear and support reports
(`UI_AMS_Help_*`).

Endurance percentages are previews for each pace with the current loadout and
heat, not the activity of the moment.

Translation placeholders: B42 loads translation files as Java format strings,
so `getText` returns `%1` as `%1$s`. `BurdenView.tr` substitutes both forms.

Body parts come from `item:getCoveredParts()` (BloodBodyPartType indices,
cached per item type). Back (17) folds into the upper torso. Items without
covered parts fall back to a body-location table; locations containing "left"
or "right" load only that side. An item's burden is spread evenly over its
parts.

## Refresh Behavior

- A local player's `OnClothingUpdated` marks the tab dirty. Remote-player
  events are ignored, and the hook sends no network request.
- While visible, the tab refreshes on dirty or at most once per half
  game-minute.
- SP: `Physiology.project` builds a read-only preview from the current worn
  profile and the live thermal state.
- MP: burden, drivers and per-pace scales come from the local worn items, so
  clothing changes show immediately. `Physiology.projectWithServerThermal`
  combines them with the thermal fields of the cached server snapshot. The tab
  requests a new snapshot when the cache is older than
  `MP.SNAPSHOT_UI_REFRESH_SECONDS` (30 s). Until the first snapshot arrives,
  only the Heat row waits; everything else is shown from local gear.

## Character Information Integration

AMS patches `ISCharacterInfoWindow.createChildren` to add the Burden tab. If
the window already exists when AMS installs its hook, AMS resolves the live
window from `getPlayerData(playerNum).characterInfo` and attaches directly.

- Like vanilla views, the tab sets its exact size every frame with
  `setWidthAndParentWidth` / `setHeightAndParentHeight`, unconditionally:
  other tabs resize the shared window while Burden is hidden. The channel column is
  measured from its rows (up to 380 px) beside the 123 px body map, so the
  window fits the content and the buttons never clip. Details wrap; long item
  names are truncated.
- Adding a tab widens the strip past vanilla's five-tab width, which would put
  scroll arrows on narrower views. After attaching (and on each UI update, in
  case another mod adds a tab later), AMS raises every view's width floor to
  `getWidthOfAllTabs() + 2`: vanilla views keep `max(self.width, content)`, and
  Health keeps `tabtotalwidth`. The Burden tab uses the same floor, and its
  channel column stretches to fill it.
- Controller LB/RB input from the Burden tab uses vanilla tab switching.
- Controller B closes the Burden view or focus.
- `AMSBurdenWindow` is a standalone fallback when tab injection is unavailable.

## Support Report

The Burden tab can save a support report under `Lua/ams_reports/`. Reports
include version, options, runtime age, raw thermal evidence, numeric endurance
scales, sleep penalty, and per-item burden attribution. In MP, an export without
a cached server snapshot requests one and asks the player to retry.

## Modules

- `client/core/ArmorMakesSense_Draw.lua`: colors, text metrics, pip strips
- `client/core/ArmorMakesSense_UITooltip.lua`: wearable tooltip rows
- `client/core/ArmorMakesSense_BurdenView.lua`: Burden tab view model (verdict, rows, gear, body parts, tip)
- `client/core/ArmorMakesSense_BurdenPanel.lua`: Burden tab drawing, body map, sizing, armor and export buttons
- `client/core/ArmorMakesSense_ArmorSet.lua`: remembered armor set; take off, drop and wear through vanilla timed actions
- `client/core/ArmorMakesSense_UI.lua`: character-tab hook, fallback window, help window
- `client/core/ArmorMakesSense_SupportReport.lua`: report data and formatting
- `client/ArmorMakesSense_MPClientRuntime.lua`: MP snapshot cache and UI invalidation
- `shared/ArmorMakesSense_PresentationPolicy.lua`: pip bands and tiers
- `shared/ArmorMakesSense_PhysiologyShared.lua`: runtime and preview snapshots

## Armor Set

`ArmorSet` stores the remembered set in player modData under `AMSArmorSet` as
`{ id, fullType, label }` entries in worn order. It is the only persistent AMS
data. Pieces are matched by item id first, then by full type, so a set still
resolves if ids change across a reload. Each candidate is claimed once.

- Take off and drop: the new set is the worn armor plus remembered pieces that
  are still nearby, so taking armor off again after a partial re-wear forgets
  nothing. Unequip uses `ISUnequipAction`; drop uses vanilla
  `ISInventoryPaneContextMenu.dropItem`, which also handles vehicles.
- Wear: items in bags get an inventory transfer. Floor items use
  `ISGrabItemAction` in SP and an inventory transfer in MP, matching vanilla
  `onGrabWItem`. Each is followed by `ISWearClothing`, which replaces whatever
  now occupies the slot.
- All changes are vanilla timed actions, so MP servers validate them as usual.

