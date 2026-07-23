# Armor Makes Sense - UI Reference

## Tooltip Integration

`client/core/ArmorMakesSense_UITooltip.lua` extends `ISToolTipInv.render` without
replacing an item's `DoTooltip` implementation. AMS lets the current tooltip
owner build its normal layout and contributes wearable rows immediately before
that layout is finalized. When `EuryTooltipController` is installed, AMS
registers as a row provider instead of wrapping layout finalization.
If the vanilla tooltip class is not ready during the first UI update, AMS
defers installation and retries on a later update.

| Row | Display condition |
|---|---|
| Burden | `physicalLoad >= 1.5` |
| Breathing | `airflowResistance >= 0.8` |

The standalone extension uses a burden bar with a per-item maximum of `28`.
The shared-controller provider expresses the same fraction as a percentage
because that controller's row contract is text-based.

Breathing labels:

| Respiratory signal | Label |
|---|---|
| `0.8 <= airflowResistance < 2.0` and unsealed | Mild |
| `airflowResistance >= 2.0` and unsealed | Restricted |
| `sealedRestriction > 0` | Heavily Restricted |

Shoulder-pad backpack-conflict text is cleared from the reslotted script item by
the speed and slot rebalance pass, outside tooltip rendering.

## Burden Panel

The Burden panel uses the aggregate equipment profile and the latest runtime
snapshot.

### Burden Tiers

| Physical load | Tier |
|---|---|
| `< 7` | Negligible |
| `7 to < 20` | Light |
| `20 to < 45` | Moderate |
| `45 to < 75` | Heavy |
| `>= 75` | Extreme |

### Thermal Labels

| Runtime condition | Label |
|---|---|
| `thermalStrainScale >= 0.50` | Oppressive |
| `thermalStrainScale >= 0.15` | Burdensome |
| `thermalStrainScale > 0.01` | Warm |
| `coldSuitability > 0.45` | Helpful |
| otherwise | Neutral |

### Breathing, Sleep, and Drivers

- Breathing uses the same airflow and sealed-restriction rules as tooltips.
- Sleep impact appears at `rigidityLoad >= 10` and displays `Slower recovery`.
  Exact duration is not shown because the runtime result also depends on
  fatigue, bed quality, traits, and sandbox settings.
- Cost drivers include worn items with `physicalLoad >= 1.5`, sorted by physical
  load descending.
- MP clients use server-supplied driver rows and resolve local display names by
  full item type when possible.

Burden, breathing, and sleep visibility thresholds come from
`ArmorMakesSense_PresentationPolicy.lua`, which is shared by the panel,
tooltips, and support-report formatting.

## Refresh Behavior

- `OnClothingUpdated` marks the UI dirty.
- SP reads the local profile and runtime snapshot.
- MP reads `mpServerSnapshot`; missing or expired data displays a waiting state.
- A change in thermal UI state also marks the panel dirty.

## Character Information Integration

AMS patches `ISCharacterInfoWindow.createChildren` to add the Burden tab. It can
also attach to an existing character window.

- The character window is widened when required to keep the tab strip visible.
- Controller LB/RB input from the Burden tab delegates to vanilla tab switching.
- Controller B closes the active Burden view or focus.
- `AMSBurdenWindow` provides a standalone fallback if tab injection is
  unavailable.

## Support Report

The Burden panel can save a support report under `Lua/ams_reports/`. Reports
include version, options, runtime state, equipment attribution, and the latest
MP incident trace when available.

## Modules

- `client/core/ArmorMakesSense_UITooltip.lua`: wearable-item tooltip integration
- `client/core/ArmorMakesSense_UI.lua`: Burden tab, help, and export UI
- `client/core/ArmorMakesSense_SupportReport.lua`: report data and formatting
- `client/ArmorMakesSense_MPClientRuntime.lua`: MP cache and UI invalidation
- `shared/ArmorMakesSense_PhysiologyShared.lua`: SP runtime snapshot model
