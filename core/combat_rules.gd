class_name CombatRules
extends RefCounted
## The combat rulebook from the Combat core spec. Pure functions only: the
## simulation now and the tactical grid later both call these.

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


## Cover from a terrain's cover mix: a roll of 1-100 against Full, then Half,
## then None. E.g. 15/25/60 gives Full on 1-15, Half on 16-40, None on 41-100.
static func cover_from_roll(roll: int, cover_mix: Dictionary) -> String:
	var limit := 0
	for cover: String in ["full", "half", "none"]:
		limit += int(cover_mix.get(cover, 0))
		if roll <= limit:
			return cover
	return "none"


## Hit chance = Aim - Defense - Cover + Modifiers, clamped to 5-95.
## Returns the chance plus each term, so reports can show the working.
static func hit_chance(attacker: CombatUnit, target: CombatUnit, cfg: Dictionary, flanked: bool = false) -> Dictionary:
	var parts: Array = []  # each entry: [label, value]
	parts.append(["Aim", attacker.aim])
	if target.defense != 0:
		parts.append(["Defense", -target.defense])
	var cover_value := 0 if flanked else int(cfg["cover"][target.cover])
	if cover_value != 0:
		parts.append(["cover", -cover_value])
	var range_mod := range_modifier(attacker.weapon, attacker.band, cfg)
	if range_mod != 0:
		parts.append(["range", range_mod])
	if attacker.wounded:
		parts.append(["wounded", -int(cfg["wounded_aim_penalty"])])

	var raw := 0
	for part: Array in parts:
		raw += int(part[1])
	var clamp_range: Array = cfg["hit_clamp"]
	var chance := clampi(raw, int(clamp_range[0]), int(clamp_range[1]))
	return {"chance": chance, "raw": raw, "parts": parts}


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


## Resolves one shot, in the fixed roll order from the spec:
## hit roll, then (on a hit) crit roll, damage roll, and downed roll at 0 Health.
## Changes the target and returns a record of everything that happened.
static func resolve_attack(attacker: CombatUnit, target: CombatUnit, dice: Dice, cfg: Dictionary,
		flanked: bool = false, reaction: bool = false) -> Dictionary:
	var hit_info := hit_chance(attacker, target, cfg, flanked)
	var record := {
		"type": "attack",
		"attacker": attacker.unit_name,
		"target": target.unit_name,
		"attacker_band": attacker.band,
		"target_cover": target.cover,
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
	elif not target.wounded and target.health * 2 < target.max_health:
		# Wounded = below half Health, the first time it happens.
		target.wounded = true
		record["became_wounded"] = true
