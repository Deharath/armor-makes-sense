# Armor Makes Sense — UI Reference (v1.1.4)

_As of March 7, 2026_  
`SCRIPT_VERSION=1.1.4`  
`SCRIPT_BUILD=ams-b42-2026-03-07-v114`

## Tooltip Rows

Tooltip rows are injected through an AMS-local `ISToolTipInv.render` patch that builds a vanilla `ObjectTooltip` layout via `InventoryItem:DoTooltipEmbedded(...)`.

Display conditions:
- burden row if `physicalLoad >= 1.5`
- breathing row if `breathingLoad >= 0.8`

Burden bar normalization:
- `TOOLTIP_BAR_MAX = 28`

Breathing tiers:
- `0.8 .. 1.99`: `Mildly Restricted`
- `2.0 .. 3.44`: `Restricted`
- `>= 3.45`: `Heavily Restricted`

Shoulderpad tooltip cleanup removes vanilla backpack-conflict rows.

## Burden Panel

### Burden Tiers

Panel burden thresholds by `physicalLoad`:
- `<7`: Negligible
- `<20`: Light
- `<45`: Moderate
- `<75`: Heavy
- otherwise: Extreme

### Thermal Labels

Panel thermal labels use the runtime snapshot:
- Burdensome if `hotStrain > 0.15`
- Helpful if `coldAppropriateness > 0.30`
- Neutral otherwise

### Composition Rules

Panel composition is additive:
- summary lines such as `No armor burden.`, `Light clothing -- minimal burden.`, and `Low weight, but heat-sensitive outfit.` are informational text
- breathing renders whenever `breathingLoad >= 0.8`
- thermal renders alongside breathing and burden when applicable
- `Cost Drivers` use physical load only (`physicalLoad >= 1.5`)

### Sleep Estimate

Sleep estimate appears when `rigidityLoad >= 10`:

```lua
rigidityNorm = rigidity / (rigidity + 80.0) * 2.0
sleepPct = floor(rigidityNorm * 6.75 + 0.5)
```

### Cost Drivers

`Cost Drivers` are worn items with `physicalLoad >= 1.5`, sorted descending.

## UI Refresh and Window Behavior

Clothing change detection:
- `Events.OnClothingUpdated` marks the burden panel dirty for immediate re-render

Tab behavior:
- attempts Burden tab injection into character info tabs by patching `ISCharacterInfoWindow.createChildren`
- clamps the character window to the full tab-strip width so all buttons remain visible
- retroactively attaches to any already-created instance
- uses standalone `AMSBurdenWindow` if tab injection fails

## UI-Related Modules

- `client/core/ArmorMakesSense_UI.lua` — tooltip injection, burden panel/tab rendering, help window, clothing-update refresh
- `client/ArmorMakesSense_MPClientRuntime.lua` — MP snapshot-fed UI invalidation and waiting-state behavior
- `client/models/ArmorMakesSense_Physiology.lua` — SP runtime snapshot production for UI
