# Armor Makes Sense — Technical Reference (v0.5.74)

## Scope & Design Constraints

Armor Makes Sense (AMS) is a **singleplayer-only** Build 42 mod for Project Zomboid. It no-ops in multiplayer contexts.

Core philosophy: armor is a **physical tradeoff**, not a psychological penalty. The mod taxes endurance, heat regulation, breathing, muscle strain, and sleep recovery — never stress or unhappiness. Vanilla discomfort is explicitly zeroed and replaced by AMS's physics-based load model.

---

## File Layout

- **`common/`** — Source of truth for all shared Lua, translations, and media.
- **`42/`** — Minimal metadata only (`mod.info`, `icon.png`, `poster.png`). No Lua duplication.

If a `42/` override becomes identical to `common/`, it belongs in `common/`.

---

## Module Architecture

### `shared/` (loaded before client)

| File | Purpose |
|---|---|
| `ArmorMakesSense_Config.lua` | Defines `DEFAULTS` table — all tuning knobs with default values. |
| `ArmorMakesSense_ArmorClassifier.lua` | Heuristic classifier that decides whether an item is "armor-like" based on defense stats, tags, keywords, and body location. |
| `ArmorMakesSense_SpeedRebalance.lua` | Zeroes `DiscomfortModifier` on all wearable items globally and normalises `RunSpeedModifier`/`CombatSpeedModifier` for known protective gear via `DoParam`. |
| `ArmorMakesSense_SlotCompat.lua` | Registers custom `ItemBodyLocation` slots (e.g. `ams:shoulderpad_left`, `ams:forearm_left`, `ams:cuirass`) and configures exclusivity/hideModel rules so armor pieces don't conflict. |

### `client/core/`

| File | Purpose |
|---|---|
| `ArmorMakesSense_LoadModel.lua` | Transforms each worn item into a per-item load signal (`physicalLoad`, `thermalLoad`, `breathingLoad`, `rigidityLoad`) and aggregates them into a full armor profile. |
| `ArmorMakesSense_Strain.lua` | Swing-chain muscle strain — computes extra `addCombatMuscleStrain` based on swing-chain armor load during melee hits. |
| `ArmorMakesSense_Combat.lua` | Hooks `OnPlayerAttackFinished` to trigger the strain overlay on each melee hit. |
| `ArmorMakesSense_Tick.lua` | Per-minute tick pipeline orchestration — reads options, builds armor profile, runs models, updates UI. |
| `ArmorMakesSense_Runtime.lua` | Startup checks, event registration, and the `EveryOneMinute` / `OnPlayerUpdate` dispatch. |
| `ArmorMakesSense_State.lua` | Per-player state lifecycle — merges defaults + sandbox + ModOptions into a resolved options table. |
| `ArmorMakesSense_UI.lua` | Tooltip overlay on inventory items, "Burden" tab in character info panel, and in-game help window. |
| `ArmorMakesSense_Environment.lua` | Reads world environment state (temperature, weather). |
| `ArmorMakesSense_Stats.lua` | Player stat readers/writers (endurance, fatigue, temperature, etc.). |
| `ArmorMakesSense_Utils.lua` | Shared primitives (`clamp`, `softNorm`, `safeMethod`, `containsAny`, `lower`). |
| `ArmorMakesSense_Bootstrap.lua` | Registers runtime events and developer-facing test API binding. |

### `client/models/`

| File | Purpose |
|---|---|
| `ArmorMakesSense_Physiology.lua` | The core formula model — endurance drain/regen, thermal pressure (hot + cold), breathing restriction, sleep-in-armor fatigue recovery penalty. |

### `client/` (root)

| File | Purpose |
|---|---|
| `ArmorMakesSense_Main.lua` | Orchestration facade — requires all modules, builds static context tables, wires module references, and triggers `configureTestingContext`. |

## Runtime Flow

1. **Startup bootstrap** — `SlotCompat` registers custom body locations during shared module load; `SpeedRebalance` applies discomfort zeroing and speed normalisation on `OnGameBoot` / `OnMainMenuEnter` / `OnGameStart`.
2. **`Events.EveryOneMinute`** — Main tick pipeline per local player:
   - Read resolved options (defaults + sandbox + ModOptions)
   - Build armor profile from worn items via `LoadModel.computeArmorProfile`
   - Detect sleep ↔ wake transitions
   - Apply sleep-in-armor fatigue recovery penalty (continuous while sleeping)
   - Apply endurance model (regen throttling + activity drain)
   - Update UI layer (burden panel + tooltip hooks)
3. **`Events.OnPlayerUpdate`** — Per-frame runtime hook for state upkeep (e.g. discomfort invariant enforcement and sleep catch-up while asleep).
4. **`OnPlayerAttackFinished`** — Applies muscle strain overlay on melee hits.

---

## Models

### Endurance Drain & Regen Throttling

The primary model. Effective load is computed as:

```
effectiveLoad = massLoad + thermalContribution + breathingContribution
```

When `effectiveLoad` exceeds `ArmorLoadMin` (default 5.0), the mod:

- **Throttles vanilla regen**: reduces endurance recovery by up to `EnduranceRegenPenalty` (0.45), scaled by load, environment, posture, and activity.
- **Applies additive drain** during non-idle activity: `BaseEnduranceDrainPerMinute` (0.0033) × load × activity × environment.

Walking applies drain only under stressed conditions (high env factor or low endurance). Idle never drains. Sitting improves regen slightly.

### Thermal Pressure

AMS reads PZ's thermoregulator API (core temp, skin temp, perspiration, shivering, vasodilation, insulation, wetness) and computes a composite hot/cold strain signal.

- **Hot strain** amplifies endurance cost. Derived from skin temperature, perspiration rate, vasodilation, and ambient heat.
- **Cold appropriateness** — when armor insulation is helping in cold weather, thermal burden is reduced. Computed from insulation evidence, shiver suppression, and skin comfort.
- Asymmetric EMA smoothing prevents jitter; signal gates require minimum thresholds before activating.

### Breathing Restriction

Face coverings and sealed headgear add `breathingLoad`. The penalty is intensity-thresholded:

- Below `BreathingDemandThreshold` (0.52 ventilation demand) — near-invisible.
- Above threshold — ramps with a smoothstep curve.
- Sealed masks (load ≥ `BreathingSealLoadStart` 3.45) ramp much steeper via `BreathingSealedDynamicLoadWeight` (29.0).
- At rest, breathing gear provides a small static relief (reduces load slightly).

### Muscle Strain (Swing-Chain)

On each melee hit, AMS adds extra `addCombatMuscleStrain` based on upper-body/swing-chain armor load:

- Load sources: shoulder, forearm, elbow, hand armor (weighted by discomfort factor).
- Ramps from `MuscleStrainLoadStart` (3.0) to `MuscleStrainLoadFull` (22.0).
- Maximum extra strain per hit: `MuscleStrainMaxExtra` (0.15), using a `t * √t` curve.
- Respects vanilla `muscleStrainFactor` sandbox setting — if vanilla sets it to 0, AMS strain is also disabled.

### Sleep Recovery Penalty

Sleeping in rigid/heavy armor slows fatigue recovery:

- **Continuous effect** while sleeping: `SleepRigidityFatigueRate` (0.003) × rigidity norm × `max(0.1, 1 - fatigue)`.
- Rigidity is computed from item discomfort, defense scores, and weight.
- The AMS counteraction applies only while fatigue is below `0.85` (`min(0.85, fatigue + counteract)`), so it slows recovery but never pushes fatigue upward past that cap.

---

## Armor Classification

The `ArmorClassifier` decides whether each worn item is "armor-like" using a layered heuristic:

1. **Defense stats** — `ScratchDefense`, `BiteDefense`, `BulletDefense`, `NeckProtectionModifier`. A composite `defenseScore` is computed with weighted contributions (bite 0.75, bullet 1.25, scratch 0.30, neck 0.45).
2. **Thermal stats** — `Insulation`, `WindResistance` contribute to `thermalScore`.
3. **Protective tags** — `GasMask`, `Respirator`, `HazmatSuit`, `WeldingMask`, `BulletProof`, `Helmet`, `ProtectiveGear` display category.
4. **Keyword matching** — item name checked against armor keywords (`armor`, `vest`, `plate`, `kevlar`, `tactical`, `helmet`, etc.).
5. **Body location hints** — slot name checked against armor-typical locations (`torso`, `vest`, `bullet`, `helmet`, `mask`, etc.).

Classification logic:
- **Civilian floor**: lightweight items (< 1.5 kg) with no indicators and low discomfort are never classified as armor.
- **Strong defense** (score ≥ 8, or bullet ≥ 1, or bite ≥ 4) → armor.
- **Protective tag** present → armor.
- **Keyword match** + weight ≥ 1.2 or medium defense or discomfort > 0.15 → armor.

---

## Load Channels

Each worn item produces four load signals:

| Channel | What it measures | Key inputs |
|---|---|---|
| `physicalLoad` | Overall physical burden (weight, bulk, movement penalty) | Weight, discomfort, runSpeedModifier penalty, combatSpeedModifier penalty, defense score |
| `thermalLoad` (aka `wearabilityLoad`) | Heat retention and insulation burden | Insulation, wind resistance, discomfort, water resistance, speed penalties |
| `breathingLoad` | Airflow restriction | Breathing keywords/tags (mask, respirator, gas, hazmat), face/head slot detection |
| `rigidityLoad` | Sleep discomfort (rigid/encumbering gear) | Discomfort, defense score, weight |

Additionally, `swingChainLoad` and `upperBodyLoad` are derived from `physicalLoad` filtered by body location (shoulder, forearm, elbow, hand locations contribute to swing chain).

Mask-slot items have `physicalLoad` and `thermalLoad` zeroed (they contribute only through `breathingLoad`).

---

## CombatSpeedModifier Suppression & Discomfort Zeroing

`SpeedRebalance` runs on `OnGameBoot`, `OnMainMenuEnter`, and `OnGameStart`:

1. **Discomfort zeroing** — iterates all wearable `ScriptItem`s and sets `DiscomfortModifier = 0.00` via `DoParam`. Original discomfort values are cached in `_originalDiscomfort` for use by the load model.
2. **Speed normalisation** — known protective gear gets region-appropriate speed modifiers: leg armor penalises run speed, arm/shoulder armor penalises combat speed, light pads get no penalty.
3. **Slot reslotting** — items are reassigned to AMS custom body locations (e.g. shoulderpads → `ams:shoulderpad_left`).

---

## Equipment Slot Compatibility

`SlotCompat` registers 8 custom `ItemBodyLocation` entries:

- `ams:shoulderpad_left`, `ams:shoulderpad_right`
- `ams:sport_shoulderpad`, `ams:sport_shoulderpad_on_top`
- `ams:forearm_left`, `ams:forearm_right`
- `ams:cuirass`
- `ams:torso_extra_vest_bullet`

These slots have exclusivity rules configured to prevent conflicts (e.g. cuirass is exclusive with SCBA and torso vests, shoulderpads are exclusive with full suits). HideModel rules ensure correct visual layering. Render indices are placed near their vanilla counterparts.

---

## UI

### Tooltip Overlay
Item tooltips for wearable gear show:
- **Burden bar** — progress bar showing `physicalLoad` as a fraction of 100 (threshold: ≥ 1.5 to display).
- **Breathing tier** — "Restricted" (load ≥ 1.2) or "Heavily Restricted" (load ≥ 3.45).

Hooks via Starlit Library's `onFillItemTooltip` event if available, otherwise monkey-patches `ISToolTipInv:render()`.

### Burden Panel Tab
Adds a "Burden" tab to the character info window showing:
- Burden tier (Negligible / Light / Moderate / Heavy / Extreme) with progress bar.
- Thermal effect (Neutral / Burdensome / Helpful) with contextual annotation.
- Breathing restriction tier if applicable.
- Sleep recovery penalty estimate if wearing rigid gear.
- Cost drivers list — each contributing item sorted by physical load impact.

Falls back to a standalone window if tab injection fails.

### Help Window
Accessible via "? Help" button in the burden panel. Explains each section (Burden, Thermal, Breathing, Sleep, Cost Drivers) in player-friendly language.

---

## Key Config Values (v0.5.74)

From `ArmorMakesSense_Config.lua`:

| Key | Default | Description |
|---|---|---|
| `ArmorLoadMin` | 5.0 | Effective load below this has no effect |
| `BaseEnduranceDrainPerMinute` | 0.0033 | Base endurance drain rate during activity |
| `EnduranceRegenPenalty` | 0.45 | Maximum regen reduction fraction |
| `EnableMuscleStrainModel` | true | Toggle swing-chain strain |
| `EnableSleepPenaltyModel` | true | Toggle sleep recovery penalty |
| `MuscleStrainMaxExtra` | 0.15 | Max extra strain per melee hit |
| `MuscleStrainLoadStart` | 3.0 | Swing-chain load where strain begins |
| `MuscleStrainLoadFull` | 22.0 | Swing-chain load where strain is at max |
| `ThermalEnduranceWeight` | 0.35 | Thermal contribution to effective load |
| `BreathingDemandThreshold` | 0.52 | Activity demand below which breathing penalty is invisible |
| `BreathingCombatDemandFloor` | 0.50 | Minimum demand during active attack |
| `BreathingPenaltyLoadStart` | 1.20 | Breathing load where mask penalty begins |
| `BreathingPenaltyLoadSpan` | 2.20 | Load range for mask penalty normalisation |
| `BreathingSealLoadStart` | 3.45 | Load threshold for sealed-mask ramp |
| `BreathingSealLoadSpan` | 0.20 | Load range for sealed-mask normalisation |
| `BreathingReliefMaxLoad` | 3.30 | Max breathing load that can receive rest/static relief |
| `BreathingStaticReliefWeight` | 0.25 | Static relief weight applied at rest/low demand |
| `BreathingDynamicLoadWeight` | 5.10 | Dynamic breathing penalty multiplier |
| `BreathingSealedDynamicLoadWeight` | 29.00 | Sealed mask dynamic penalty multiplier |
| `SleepRigidityFatigueRate` | 0.003 | Sleep fatigue recovery counteraction rate |
