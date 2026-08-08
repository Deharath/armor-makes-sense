# Armor Makes Sense - UI Reference

## Tooltip Integration

`client/core/ArmorMakesSense_UITooltip.lua` extends `ISToolTipInv.render`.
During the owner's synchronous render call, AMS temporarily wraps the exposed
item `DoTooltip` entry and routes eligible non-container wearables through
42.20's `DoTooltipEmbedded` contract. Vanilla and AMS populate one shared
`ObjectTooltip.Layout`, which is rendered and measured once before the original
method is restored. When `EuryTooltipController` is installed, AMS registers as
a row provider and leaves the owner's ordinary tooltip path intact.
If the vanilla tooltip class is not ready during the first UI update, AMS
defers installation and retries on a later update.

| Row | Display condition |
|---|---|
| Burden | `physicalLoad >= 1.5` |
| Breathing | `airflowResistance >= 0.8` |

The standalone extension uses a burden bar with a per-item maximum of `28`.
Because the row belongs to vanilla's own layout, the longest vanilla label and
value determine the shared label boundary, progress width, font-dependent bar
height, line spacing, and final tooltip bounds. Only the colored fill varies
with the item's burden fraction. The standalone path reads the Java layout
offset and tooltip padding through PZ's class-field reflection helpers because
direct Lua access to those primitive fields can expose zero rather than the
values used by Java.
The shared-controller provider expresses the same fraction as a percentage
because that controller's row contract is text-based.

Breathing labels:

| Respiratory signal | Label |
|---|---|
| `0.8 <= airflowResistance < 2.0` and unsealed | Mild |
| `airflowResistance >= 2.0` and unsealed | Restricted |
| `sealedRestriction > 0` | Heavily Restricted |

Shoulder-pad backpack-conflict text is cleared from the reslotted script item by
the speed and slot rebalance pass. Existing item instances can retain their
copied vanilla tooltip, so the tooltip owner also suppresses that one obsolete
key for the duration of rendering and restores the item afterward.

## Burden Panel

The Burden panel uses the aggregate equipment profile and the latest runtime
snapshot. It is a compact loadout inspector: stable physical burden first,
currently active secondary pressures second, and item-level cost drivers last.

### Burden Summary

| Element | Display |
|---|---|
| Tier | Qualitative physical burden from `Negligible` through `Extreme` |
| Bar | Physical weight, bulk, and movement restriction on the existing 100-point burden scale |

The summary deliberately does not expose recovery scales, endurance drain
rates, or effective load. Those exact values remain available in support
reports and the dev panel.

### Active Pressures

| Row | Meaning |
|---|---|
| Retained heat | Appears at `thermalContribution >= 0.25`; its bar reaches full width at the configured 14-point maximum |
| Restricted breathing | Appears only while respiratory gear and metabolic effort produce a positive contribution; its bar reaches full width at 7 points |
| Sleep restriction | Appears only while the sleep model is enabled and reports a positive current penalty; its bar reaches full width at a 35% reduction |

If no row is active, the complete section is omitted. Ordinary pressure bars
use the muted burden color, become amber only after 40% of their presentation
scale, and become red at 85%. These bars communicate relative pressure without
publishing precise physiological penalties.

### Burden Tiers

| Physical load | Tier |
|---|---|
| `< 7` | Negligible |
| `7 to < 20` | Light |
| `20 to < 45` | Moderate |
| `45 to < 75` | Heavy |
| `>= 75` | Extreme |

This shorthand describes physical gear burden only. AMS does not translate
thermal state into labels such as Warm or Oppressive, and cold suitability is
diagnostic rather than a player-facing bonus.

### Cost Drivers

- Cost drivers include worn items with `physicalLoad >= 1.5`, sorted by physical
  load descending. The panel retains the complete list rather than truncating it.
- MP clients calculate gear burden, breathing restriction, rigidity, and cost
  drivers from the current local worn-item collection so clothing actions are
  reflected immediately. Dynamic physiology and thermal state remain supplied
  by the server snapshot.

Burden tiers, tooltip breathing tiers, active-pressure visibility, and support
report formatting helpers come from `ArmorMakesSense_PresentationPolicy.lua`.

## Refresh Behavior

- A local player's `OnClothingUpdated` marks the UI dirty; remote-player events
  are ignored and the hook sends no network request.
- SP reads the local profile and runtime snapshot.
- MP combines the current local worn profile with dynamic `mpServerSnapshot`
  telemetry. A visible panel requests server telemetry only when the cache is
  missing or older than 30 wall-clock seconds. Missing data displays a waiting
  state.
- While visible, runtime rows refresh at most once per half game-minute.

## Character Information Integration

AMS patches `ISCharacterInfoWindow.createChildren` to add the Burden tab. If
42.20 created the window before AMS installed its hook, AMS resolves the live
window from `getPlayerData(playerNum).characterInfo` and attaches directly.

- The character window is widened when required to keep the tab strip visible.
- Controller LB/RB input from the Burden tab delegates to vanilla tab switching.
- Controller B closes the active Burden view or focus.
- `AMSBurdenWindow` provides a standalone fallback if tab injection is
  unavailable.

## Support Report

The Burden panel can save a support report under `Lua/ams_reports/`. Reports
include version, options, runtime age, raw heat evidence, numeric AMS endurance
effects, option-aware sleep state, and equipment attribution. In MP, an export
without a cached server snapshot queues one and asks the player to retry.

## Modules

- `client/core/ArmorMakesSense_UITooltip.lua`: wearable-item tooltip integration
- `client/core/ArmorMakesSense_UI.lua`: Burden tab, help, and export UI
- `client/core/ArmorMakesSense_SupportReport.lua`: report data and formatting
- `client/ArmorMakesSense_MPClientRuntime.lua`: MP cache and UI invalidation
- `shared/ArmorMakesSense_PhysiologyShared.lua`: SP runtime snapshot model
