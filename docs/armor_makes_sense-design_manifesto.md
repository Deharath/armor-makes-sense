# Armor Makes Sense – Design North Star

## Core Principle

Armor is a **physical tradeoff**, not a psychological penalty.

It protects the body.
Its cost must also live in the body.

Armor should tax energy, heat regulation, and recovery — not sanity.

---

## Design Goal

Wearing armor should feel:

* Safer in short engagements
* More draining in prolonged activity
* Riskier in hot environments
* Suboptimal for constant, all-day wear

The player should think:

“I’m protected, but I’ll gas out if this drags on.”

Not:

“My moodle is ruining my combat stats.”

---

## What Armor Should Affect

Armor should plug into existing physical systems:

### 1. Endurance (Short-Term Capacity)

Armor increases energy cost of movement and combat.

Effects:

* Slightly higher endurance usage during physical actions
* Slightly slower endurance regeneration while worn
* Greater impact during prolonged activity

Result:
You fatigue sooner in extended fights, but you’re still protected.

---

### 2. Heat

Armor reduces cooling efficiency.

Effects:

* Increased heat retention
* Faster progression toward overheating in hot conditions
* Higher endurance cost in hot weather

Result:
Armor becomes a meaningful risk in summer or during heavy exertion.

---

### 3. Muscle Fatigue

Armor amplifies mechanical load on limbs and torso.

Effects:

* Slight increase in muscle strain accumulation
* More noticeable during heavy weapons or repeated swings

Result:
Long sessions feel physically taxing without being instantly crippling.

---

### 4. Sleep Recovery

Sleeping in rigid or restrictive armor reduces recovery quality.

Effects:

* Lower endurance recovery overnight
* Slight increase in next-day fatigue
* Worse outcome in hot conditions

Result:
Sleeping armored is an emergency choice, not a default.

---

## What Armor Should NOT Do

Armor should not:

* Apply stress or unhappiness as a cost of wearing gear
* Apply arbitrary combat accuracy or damage penalties
* Interact with panic or mood systems

Vanilla PZ uses DiscomfortModifier on armor to induce stress (B42.14+; earlier builds used unhappiness). AMS zeroes DiscomfortModifier on all wearable items at boot — vanilla's psychological discomfort system is completely replaced by AMS's physical cost model. No stress, no unhappiness, no moodle penalties from wearing armor.

---

## System Philosophy

No new emotional meters.
No artificial punishments.
No discomfort tax -- vanilla DiscomfortModifier is zeroed, not rebalanced.

Armor cost emerges naturally from:

Weight
Heat retention
Breathing restriction
Activity duration

The game already simulates endurance, fatigue, muscle strain, and hyperthermia.

AMS integrates into those systems -- it does not bypass them or invent new ones.

---

## Desired Player Experience

Armor becomes a strategic choice:

* Wear it for dangerous operations.
* Remove it to recover efficiency.
* Respect the heat.
* Avoid sleeping in it unless necessary.

The tradeoff feels physical, systemic, and believable.