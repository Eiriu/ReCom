class_name CombatRules
extends RefCounted
## The combat rulebook from the Combat core spec. Pure rules only: the
## simulation now and the tactical grid later both call these.
## Every number comes from data/*.json via cfg (combat.json) or the terrain entry.

const BANDS: Array[String] = ["close", "medium", "long"]


## +10 inside the weapon's optimal range, -15 per band outside it.
static func range_modifier(weapon: Dictionary, band: String, cfg: Dictionary) -> int:
	var optimal: Array = weapon.get("optimal", [])
	if optimal.has(band):
		return int(cfg["range_bonus_optimal"])
	var here := BANDS.find(band)
	var distance := BANDS.size()
	for optimal_band: Variant in optimal:
		distance = mini(distance, absi(BANDS.find(String(optimal_band)) - here))
	return -int(cfg["range_penalty_per_band"]) * distance


## The bands one move away: one closer and/or one further.
static func neighbour_bands(band: String) -> Array[String]:
	var here := BANDS.find(band)
	var out: Array[String] = []
	if here > 0:
		out.append(BANDS[here - 1])
	if here < BANDS.size() - 1:
		out.append(BANDS[here + 1])
	return out


## Where a unit moves for "Take cover": the
## neighbouring band with the best range modifier for its own weapon.
## On a tie it moves further away (index order: a later band wins ties).
static func retreat_band(unit: CombatUnit, cfg: Dictionary) -> String:
	var best := ""
	var best_mod := -9999
	for band in neighbour_bands(unit.band):
		var mod := range_modifier(unit.weapon, band, cfg)
		if mod >= best_mod:
			best = band
			best_mod = mod
	return best


## Where a Shaken unit moves: one band further from the enemy, or back to
## Medium if it is already at Long.
static func away_band(unit: CombatUnit) -> String:
	var here := BANDS.find(unit.band)
	return BANDS[here + 1] if here < BANDS.size() - 1 else BANDS[here - 1]


## Cover from a mix: a roll of 1-100 against Full, then Half, then None.
## E.g. 15/25/60 gives Full on 1-15, Half on 16-40, None on 41-100.
static func cover_from_roll(roll: int, cover_mix: Dictionary) -> String:
	var limit := 0
	for cover: String in ["full", "half", "none"]:
		limit += int(cover_mix.get(cover, 0))
		if roll <= limit:
			return cover
	return "none"


## Suppression Aim penalty: 30, less 1 for every 2 Will above 50 (never below 0).
static func suppression_penalty(unit: CombatUnit, cfg: Dictionary) -> int:
	var s: Dictionary = cfg["suppression"]
	var relief := maxi(0, unit.will - int(s["will_threshold"])) / int(s["will_per_point"])
	return maxi(0, int(s["aim_penalty"]) - relief)


## Swarm: +5 Aim per other Vessel still fighting on the same side, up to +15.
static func swarm_bonus(unit: CombatUnit, cfg: Dictionary) -> int:
	if not unit.has_ability("swarm"):
		return 0
	var a: Dictionary = cfg["abilities"]
	var others := 0
	for ally in unit.squad:
		if ally != unit and ally.is_active() and ally.has_ability("swarm"):
			others += 1
	return mini(others * int(a["swarm_per_ally"]), int(a["swarm_max"]))


## Hit chance = Aim - Defense - Cover + Modifiers, clamped to 5-95.
## opts: flanked (bool), reaction (bool), cover (String, overrides the target's cover).
## Returns the chance plus each term, so reports can show the working.
static func hit_chance(attacker: CombatUnit, target: CombatUnit, cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var flanked: bool = opts.get("flanked", false)
	var reaction: bool = opts.get("reaction", false)
	var cover: String = opts.get("cover", target.effective_cover())
	var parts: Array = []  # each entry: [label, value]
	parts.append(["Aim", attacker.aim])
	if target.defense != 0:
		parts.append(["Defense", -target.defense])
	var cover_value := 0 if flanked else int(cfg["cover"][cover])
	if cover_value != 0:
		parts.append(["%s cover" % cover, -cover_value])
	var range_mod := range_modifier(attacker.weapon, attacker.band, cfg)
	if range_mod != 0:
		parts.append(["range", range_mod])
	if attacker.wounded:
		parts.append(["wounded", -int(cfg["wounded_aim_penalty"])])
	if attacker.is_shaken(cfg):
		parts.append(["shaken", -int(cfg["morale"]["shaken_aim_penalty"])])
	if attacker.suppressed_by != null:
		var penalty := suppression_penalty(attacker, cfg)
		if penalty != 0:
			parts.append(["suppressed", -penalty])
	if reaction and not attacker.has_ability("steady"):
		parts.append(["reaction", -int(cfg["reaction_aim_penalty"])])
	var swarm := swarm_bonus(attacker, cfg)
	if swarm != 0:
		parts.append(["swarm", swarm])
	if attacker.rally_aim != 0:
		parts.append(["rallied", attacker.rally_aim])

	var raw := 0
	for part: Array in parts:
		raw += int(part[1])
	var clamp_range: Array = cfg["hit_clamp"]
	var chance := clampi(raw, int(clamp_range[0]), int(clamp_range[1]))
	return {"chance": chance, "raw": raw, "parts": parts, "cover": cover}


## Weapon crit, +50 against a flanked target. Reaction shots and Plated
## targets cannot be critically hit.
static func crit_chance(attacker: CombatUnit, target: CombatUnit, cfg: Dictionary,
		flanked: bool = false, reaction: bool = false) -> int:
	if reaction or target.has_ability("plated"):
		return 0
	var chance := int(attacker.weapon.get("crit", 0))
	if flanked:
		chance += int(cfg["flank_crit_bonus"])
	return clampi(chance, 0, 100)


## Damage roll -> x1.5 on a crit, rounded down -> minus Armour -> at least 1.
static func damage_from_roll(roll: int, crit: bool, armour: int, cfg: Dictionary) -> int:
	var damage := roll
	if crit:
		damage = floori(roll * float(cfg["crit_multiplier"]))
	return maxi(int(cfg["min_damage"]), damage - armour)


## Flank chance = terrain base + 5 x (Mobility - 5) + band modifier, clamped 0-60.
static func flank_chance(unit: CombatUnit, terrain: Dictionary, cfg: Dictionary) -> Dictionary:
	var f: Dictionary = cfg["flank"]
	var parts: Array = []
	parts.append(["base", int(terrain["flank_base"])])
	var mobility_term := int(f["per_mobility"]) * (unit.mobility - int(f["mobility_pivot"]))
	if mobility_term != 0:
		parts.append(["Mobility", mobility_term])
	var band_term := int(terrain.get("band_modifier", {}).get(unit.band, 0))
	if band_term != 0:
		parts.append([unit.band, band_term])
	var raw := 0
	for part: Array in parts:
		raw += int(part[1])
	var limits: Array = f["clamp"]
	return {"chance": clampi(raw, int(limits[0]), int(limits[1])), "raw": raw, "parts": parts}


## Mind spike success = 50 + (Harrow Will - target Will) / 2, clamped 5-95.
static func mind_spike_chance(harrow: CombatUnit, target: CombatUnit, cfg: Dictionary) -> int:
	var m: Dictionary = cfg["abilities"]
	var raw := int(m["mind_spike_base"]) + (harrow.will - target.will) / 2
	var limits: Array = m["mind_spike_clamp"]
	return clampi(raw, int(limits[0]), int(limits[1]))


## Resolves one shot, in the fixed roll order from the spec:
## hit roll, then (on a hit) crit roll, damage roll, and downed roll at 0 Health.
## Changes the target and returns a record of everything that happened.
## Morale changes are applied afterwards by morale_after_attack().
static func resolve_attack(attacker: CombatUnit, target: CombatUnit, dice: Dice, cfg: Dictionary,
		opts: Dictionary = {}) -> Dictionary:
	var flanked: bool = opts.get("flanked", false)
	var reaction: bool = opts.get("reaction", false)
	var hit_info := hit_chance(attacker, target, cfg, opts)
	var record := {
		"type": "attack",
		"attacker": attacker.unit_name,
		"target": target.unit_name,
		"attacker_band": attacker.band,
		"target_cover": hit_info["cover"],
		"flanked": flanked,
		"reaction": reaction,
		"hit_chance": hit_info["chance"],
		"hit_raw": hit_info["raw"],
		"hit_parts": hit_info["parts"],
	}

	var hit_roll := dice.percent()
	record["hit_roll"] = hit_roll
	record["hit"] = hit_roll <= int(hit_info["chance"])
	if not record["hit"]:
		return record

	var crit_target := crit_chance(attacker, target, cfg, flanked, reaction)
	var crit_roll := dice.percent()
	record["crit_chance"] = crit_target
	record["crit_roll"] = crit_roll
	record["crit"] = crit_roll <= crit_target

	var damage_range: Array = attacker.weapon["damage"]
	var damage_roll := dice.between(int(damage_range[0]), int(damage_range[1]))
	var damage := damage_from_roll(damage_roll, record["crit"], target.armour, cfg)
	record["damage_roll"] = damage_roll
	record["armour"] = target.armour
	record["damage"] = damage

	apply_damage(target, damage, dice, record)
	return record


## Applies damage and settles Wounded, downed and dead states.
static func apply_damage(target: CombatUnit, damage: int, dice: Dice, record: Dictionary) -> void:
	target.health = maxi(0, target.health - damage)
	record["health_after"] = target.health
	record["max_health"] = target.max_health

	if target.health == 0:
		if target.downed_chance > 0:
			var downed_roll := dice.percent()
			record["downed_roll"] = downed_roll
			record["downed_chance"] = target.downed_chance
			target.state = CombatUnit.State.DOWNED if downed_roll <= target.downed_chance else CombatUnit.State.DEAD
		else:
			target.state = CombatUnit.State.DEAD
		record["outcome"] = "downed" if target.state == CombatUnit.State.DOWNED else "dead"
	elif not target.wounded and target.below_half_health():
		# Wounded = below half Health, the first time it happens.
		target.wounded = true
		record["became_wounded"] = true


## Changes one unit's Morale. Gains stop at Will + 20. At 0 or below the unit
## breaks and flees. Returns a change record, or {} if nothing changed.
static func change_morale(unit: CombatUnit, delta: int, reason: String, cfg: Dictionary) -> Dictionary:
	if unit.is_machine() or not unit.is_active() or delta == 0:
		return {}
	var m: Dictionary = cfg["morale"]
	var before := unit.morale
	var after := before + delta
	if delta > 0:
		after = mini(after, maxi(before, unit.will + int(m["cap_over_will"])))
	if after == before:
		return {}
	var was_shaken := unit.is_shaken(cfg)
	unit.morale = after
	var change := {"unit": unit.unit_name, "before": before, "after": after, "reason": reason}
	if after <= int(m["broken_at"]):
		unit.state = CombatUnit.State.FLED
		unit.overwatch = false
		unit.hunkered = false
		change["broke"] = true
	elif unit.is_shaken(cfg) and not was_shaken:
		change["shaken"] = true
	elif was_shaken and not unit.is_shaken(cfg):
		change["steadied"] = true
	return change


## Morale changes caused by one attack, in a fixed order: the target (crit,
## then Wounded), then the shooter (a kill), then the target's allies (an ally
## went down). Being downed counts as dying for Morale.
static func morale_after_attack(attacker: CombatUnit, target: CombatUnit, record: Dictionary,
		cfg: Dictionary) -> Array[Dictionary]:
	var ev: Dictionary = cfg["morale"]["events"]
	var changes: Array[Dictionary] = []
	if not record.get("hit", false):
		return changes
	if record.get("crit", false):
		_add_change(changes, change_morale(target, int(ev["crit_taken"]), "hit by a crit", cfg))
	if record.get("became_wounded", false):
		_add_change(changes, change_morale(target, int(ev["wounded"]), "Wounded", cfg))
	if record.has("outcome"):
		_add_change(changes, change_morale(attacker, int(ev["kill"]), "took down %s" % target.unit_name, cfg))
		changes.append_array(morale_for_fallen(target, cfg))
	return changes


## Every ally of a unit that just went down loses Morale (more for a Harrow).
static func morale_for_fallen(fallen: CombatUnit, cfg: Dictionary) -> Array[Dictionary]:
	var ev: Dictionary = cfg["morale"]["events"]
	var loss := int(ev["harrow_down"]) if fallen.has_ability("rally") else int(ev["ally_down"])
	var changes: Array[Dictionary] = []
	for ally in fallen.squad:
		if ally != fallen:
			_add_change(changes, change_morale(ally, loss, "%s went down" % fallen.unit_name, cfg))
	return changes


static func _add_change(changes: Array[Dictionary], change: Dictionary) -> void:
	if not change.is_empty():
		changes.append(change)
