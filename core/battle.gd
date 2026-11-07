class_name Battle
extends RefCounted
## Runs one battle from start to finish with no player input and records
## every event for the battle report (Combat core spec, Round procedure).
##
## Each round, the first side takes its turn, then the other. At the start of a
## side's turn its overwatch and hunkering end, suppression it applied ends, and
## its suppressed units lose Morale. Its units then act in Mobility order
## (highest first, ties by roster order), two actions each, chosen by CombatAI.
## Every roll comes from one Dice per battle, always in the same order.

const FIRST_SIDE_RANDOM := "random"
const STANCE_CAUTIOUS := "cautious"
const STANCE_STANDARD := "standard"
const STANCE_ALL_IN := "all_in"

var title: String
var location: String
var invaders: Array[CombatUnit] = []
var defenders: Array[CombatUnit] = []

## Which side takes the first turn: a side, or FIRST_SIDE_RANDOM to roll for it
## at battle start (the roll comes from the seed, so replays stay identical).
## The spec rule is that the attacking side goes first.
var first_side: String = CombatUnit.SIDE_INVADER
## The side being attacked. It holds the field if the round limit is reached.
var attacked_side: String = CombatUnit.SIDE_DEFENDER
## Terrain id from data/terrains.json: starting band, cover mix, flank base.
var terrain_id: String = "test_field"
## If false, units keep the cover the scenario gave them at battle start.
var roll_starting_cover: bool = true
## Single pieces of cover on the field, e.g. {"name": "tree", "cover": "half"}.
## At battle start each one is rolled to a random unit, which stands behind it.
var cover_features: Array[Dictionary] = []
## Invader withdrawal stance: cautious, standard or all_in.
var invader_stance: String = STANCE_STANDARD

var data: GameData
var dice: Dice
var events: Array[Dictionary] = []
var terrain: Dictionary = {}
## How many turns each side has started; Rally timing counts in these.
var side_turns := {CombatUnit.SIDE_INVADER: 0, CombatUnit.SIDE_DEFENDER: 0}

var _starting_counts := {}
var _end: Dictionary = {}


func _init(data_in: GameData, seed_in: int) -> void:
	data = data_in
	dice = Dice.new(seed_in)


func run() -> Dictionary:
	var cfg := data.combat
	terrain = data.terrain_entry(terrain_id)
	for unit in invaders:
		unit.squad = invaders
	for unit in defenders:
		unit.squad = defenders
	for unit in invaders + defenders:
		unit.band = String(terrain["starting_band"])
	_starting_counts = {CombatUnit.SIDE_INVADER: invaders.size(), CombatUnit.SIDE_DEFENDER: defenders.size()}

	var starting_side := _decide_first_side()
	_roll_starting_cover()
	var feature_sides := _place_cover_features()
	var second_side := _other(starting_side)
	var rounds_fought := 0

	for round_number in range(1, int(cfg["round_limit"]) + 1):
		rounds_fought = round_number
		for side: String in [starting_side, second_side]:
			_take_turn(side, round_number)
			if not _end.is_empty():
				break
		if not _end.is_empty():
			break

	if _end.is_empty():
		_end = {"holder": attacked_side, "reason": "round limit reached; the attacked side holds the field"}
	var holder := String(_end["holder"])
	if holder == CombatUnit.SIDE_INVADER:
		_roll_recovery()

	var result := {
		"seed": dice.seed_value,
		"title": title,
		"location": location,
		"terrain": terrain_id,
		"stance": invader_stance,
		"rounds": rounds_fought,
		"first_side": starting_side,
		"feature_sides": feature_sides,
		"holder": holder,
		"end_reason": String(_end["reason"]),
		"withdrew": String(_end.get("withdrew", "")),
		"events": events,
		"invaders": _summaries(invaders),
		"defenders": _summaries(defenders),
		"rolls_made": dice.rolls_made,
	}
	_release_links()
	return result


## Units point at each other (squads, suppressors, flank targets). Clearing the
## links after the battle lets Godot free them, so thousands of battles in a row
## do not pile up memory.
func _release_links() -> void:
	for unit in invaders + defenders:
		unit.squad = []
		unit.suppressed_by = null
		unit.flanked_target = null


## Rolls for the first turn if asked to: 50 or less, invaders start.
## This is the first roll of the battle, so it never shifts later rolls.
func _decide_first_side() -> String:
	if first_side != FIRST_SIDE_RANDOM:
		return first_side
	var roll := dice.percent()
	var side := CombatUnit.SIDE_INVADER if roll <= 50 else CombatUnit.SIDE_DEFENDER
	events.append({"type": "initiative", "roll": roll, "side": side})
	return side


## Rolls each unit's cover from the terrain, invaders first, in roster order.
func _roll_starting_cover() -> void:
	if not roll_starting_cover:
		return
	var cover_mix: Dictionary = terrain["cover_mix"]
	var rolls: Array[Dictionary] = []
	for unit in invaders + defenders:
		var roll := dice.percent()
		unit.cover = CombatRules.cover_from_roll(roll, cover_mix)
		rolls.append({"unit": unit.unit_name, "side": unit.side, "roll": roll, "cover": unit.cover})
	events.append({"type": "cover_rolls", "terrain": terrain_id, "band": terrain["starting_band"],
		"mix": cover_mix, "rolls": rolls})


## Rolls which unit stands behind each cover feature, after the cover rolls.
## Returns the side of each feature's holder, in feature order.
func _place_cover_features() -> Array[String]:
	var sides: Array[String] = []
	var everyone: Array[CombatUnit] = []
	everyone.append_array(invaders)
	everyone.append_array(defenders)
	for feature in cover_features:
		var roll := dice.between(1, everyone.size())
		var unit := everyone[roll - 1]
		unit.cover = String(feature["cover"])
		sides.append(unit.side)
		events.append({"type": "cover_feature", "name": feature["name"], "cover": unit.cover,
			"unit": unit.unit_name, "roll": roll, "options": everyone.size()})
	return sides


func _take_turn(side: String, round_number: int) -> void:
	var cfg := data.combat
	side_turns[side] += 1
	var turn_number: int = side_turns[side]
	events.append({"type": "turn", "round": round_number, "side": side})
	_start_of_turn(side)
	if _check_end():
		return

	var enemies := _units(_other(side))
	for unit in _acting_order(_units(side)):
		if not unit.is_active():
			continue
		unit.reset_turn_flags()
		var actions_left := int(cfg["actions_per_turn"])
		while actions_left > 0 and unit.is_active():
			var action := CombatAI.choose_action(unit, enemies, terrain, cfg, actions_left, turn_number)
			var outcome := _execute(unit, action, actions_left, turn_number)
			_clear_stale_suppression()
			actions_left -= int(outcome["cost"])
			if outcome["ends_turn"] or _check_end():
				break
		if _check_end():
			return

	# Rally's Aim bonus lasts until the end of the side's next turn.
	for unit in _units(side):
		if unit.rally_aim != 0 and unit.rally_until_turn <= turn_number:
			unit.rally_aim = 0


## Upkeep in a fixed order: this side's overwatch and hunkering end; suppression
## this side applied ends; this side's suppressed units lose Morale.
func _start_of_turn(side: String) -> void:
	var cfg := data.combat
	for unit in _units(side):
		unit.overwatch = false
		unit.hunkered = false
	for enemy in _units(_other(side)):
		if enemy.suppressed_by != null and enemy.suppressed_by.side == side:
			events.append({"type": "suppression_ends", "unit": enemy.unit_name, "by": enemy.suppressed_by.unit_name})
			enemy.suppressed_by = null
	var changes: Array[Dictionary] = []
	for unit in _units(side):
		if unit.is_active() and unit.suppressed_by != null:
			var change := CombatRules.change_morale(unit, int(cfg["morale"]["events"]["suppressed_turn"]),
				"suppressed", cfg)
			if not change.is_empty():
				changes.append(change)
	_log_morale(changes)


## Carries out one action. Returns {"cost": actions used, "ends_turn": bool}.
func _execute(unit: CombatUnit, action: Dictionary, actions_left: int, turn_number: int) -> Dictionary:
	var cfg := data.combat
	var kind := String(action["kind"])
	match kind:
		"shoot":
			var target: CombatUnit = action["target"]
			var flanked: bool = action.get("flanked", false)
			var record := CombatRules.resolve_attack(unit, target, dice, cfg, {"flanked": flanked})
			record["rule"] = action["rule"]
			events.append(record)
			unit.shot_this_turn = true
			unit.flanked_target = null
			unit.planned_shot = false
			_log_morale(CombatRules.morale_after_attack(unit, target, record, cfg))
			# Hit and run: shooting does not end the turn (still one shot per turn).
			return {"cost": 1, "ends_turn": not unit.has_ability("hit_and_run")}
		"move":
			_move(unit, String(action["band"]), action)
			if action["rule"] == CombatAI.RULE_BEST_ATTACK:
				unit.planned_shot = unit.is_active()
			return {"cost": 1, "ends_turn": false}
		"flank":
			_flank(unit, action["target"], action)
			return {"cost": 1, "ends_turn": false}
		"hunker":
			unit.hunkered = true
			events.append({"type": "hunker", "unit": unit.unit_name, "rule": action["rule"]})
			return {"cost": actions_left, "ends_turn": true}
		"repair":
			var patient: CombatUnit = action["target"]
			var before := patient.health
			patient.health = mini(patient.max_health, patient.health + int(cfg["abilities"]["repair_amount"]))
			unit.repairs_left -= 1
			events.append({"type": "repair", "unit": unit.unit_name, "target": patient.unit_name,
				"before": before, "after": patient.health, "max": patient.max_health,
				"left": unit.repairs_left, "rule": action["rule"]})
			return {"cost": 1, "ends_turn": false}
		"rally":
			var a: Dictionary = cfg["abilities"]
			unit.rally_ready_turn = turn_number + int(a["rally_every"])
			var changes: Array[Dictionary] = []
			var rallied: Array[String] = []
			for ally in unit.squad:
				if ally == unit or not ally.is_active():
					continue
				ally.rally_aim = int(a["rally_aim"])
				ally.rally_until_turn = turn_number + 1
				rallied.append(ally.unit_name)
				var change := CombatRules.change_morale(ally, int(cfg["morale"]["events"]["rallied"]), "Rallied", cfg)
				if not change.is_empty():
					changes.append(change)
			events.append({"type": "rally", "unit": unit.unit_name, "allies": rallied, "rule": action["rule"]})
			_log_morale(changes)
			return {"cost": 1, "ends_turn": false}
		"mind_spike":
			var mark: CombatUnit = action["target"]
			var chance := int(action["chance"])
			var roll := dice.percent()
			unit.psionic_this_turn = true
			var success := roll <= chance
			events.append({"type": "mind_spike", "unit": unit.unit_name, "target": mark.unit_name,
				"chance": chance, "roll": roll, "success": success, "harrow_will": unit.will,
				"target_will": mark.will, "rule": action["rule"]})
			if success:
				var spiked: Array[Dictionary] = []
				var change := CombatRules.change_morale(mark, -int(cfg["abilities"]["mind_spike_morale"]), "Mind spike", cfg)
				if not change.is_empty():
					spiked.append(change)
				_log_morale(spiked)
			return {"cost": 1, "ends_turn": false}
		"suppress":
			var pinned: CombatUnit = action["target"]
			pinned.suppressed_by = unit
			pinned.suppression_reacted = false
			unit.shot_this_turn = true
			events.append({"type": "suppress", "unit": unit.unit_name, "target": pinned.unit_name,
				"penalty": CombatRules.suppression_penalty(pinned, cfg), "will": pinned.will, "rule": action["rule"]})
			return {"cost": actions_left, "ends_turn": true}
		"overwatch":
			unit.overwatch = true
			events.append({"type": "overwatch", "unit": unit.unit_name, "rule": action["rule"]})
			return {"cost": actions_left, "ends_turn": true}
	events.append({"type": "hold", "unit": unit.unit_name, "rule": action["rule"]})
	return {"cost": actions_left, "ends_turn": true}


## A move: shift one band, take reaction shots, then roll new cover.
func _move(unit: CombatUnit, band: String, action: Dictionary) -> void:
	var record := {"type": "move", "unit": unit.unit_name, "from_band": unit.band, "to_band": band,
		"from_cover": unit.cover, "rule": action["rule"]}
	if action.has("target"):
		record["for_target"] = action["target"].unit_name
	unit.band = band
	unit.moved_this_turn = true
	events.append(record)
	_reactions(unit)
	_reroll_cover(unit, record)


## A flank attempt: roll the flank chance, take reaction shots, then roll new
## cover. The unit stays in its band. It counts as repositioning, not moving.
func _flank(unit: CombatUnit, target: CombatUnit, action: Dictionary) -> void:
	var info := CombatRules.flank_chance(unit, terrain, data.combat)
	var roll := dice.percent()
	var success := roll <= int(info["chance"])
	var record := {"type": "flank", "unit": unit.unit_name, "target": target.unit_name, "band": unit.band,
		"chance": info["chance"], "raw": info["raw"], "parts": info["parts"], "roll": roll,
		"success": success, "from_cover": unit.cover, "rule": action["rule"]}
	events.append(record)
	_reactions(unit)
	if success and unit.is_active():
		unit.flanked_target = target
	_reroll_cover(unit, record)


## Reaction shots at a unit that is moving: every enemy on overwatch, in roster
## order, then the unit's suppressor (once per suppression). The mover's cover
## for these shots is one roll from the terrain's in-transit mix. Reaction shots
## take -15 Aim (not for Steady) and cannot crit.
func _reactions(mover: CombatUnit) -> void:
	var cfg := data.combat
	var shooters: Array = []  # [unit, trigger]
	for enemy in _units(_other(mover.side)):
		if enemy.is_active() and enemy.overwatch:
			shooters.append([enemy, "overwatch"])
	var suppressor := mover.suppressed_by
	if suppressor != null and suppressor.is_active() and not mover.suppression_reacted:
		shooters.append([suppressor, "suppression"])
		mover.suppression_reacted = true
	if shooters.is_empty():
		return
	var roll := dice.percent()
	var transit := CombatRules.cover_from_roll(roll, terrain["in_transit_cover"])
	events.append({"type": "transit_cover", "unit": mover.unit_name, "roll": roll, "cover": transit,
		"mix": terrain["in_transit_cover"]})
	for pair: Array in shooters:
		if not mover.is_active():
			break
		var shooter: CombatUnit = pair[0]
		if not shooter.is_active():
			continue
		if pair[1] == "overwatch":
			shooter.overwatch = false
		var record := CombatRules.resolve_attack(shooter, mover, dice, cfg, {"reaction": true, "cover": transit})
		record["trigger"] = pair[1]
		events.append(record)
		_log_morale(CombatRules.morale_after_attack(shooter, mover, record, cfg))


## The mover's new cover, rolled after any reaction shots. It is written onto
## the move or flank record so the report can show it on the same line.
func _reroll_cover(unit: CombatUnit, record: Dictionary) -> void:
	if not unit.is_active():
		return
	var roll := dice.percent()
	unit.cover = CombatRules.cover_from_roll(roll, terrain["cover_mix"])
	record["cover_roll"] = roll
	record["to_cover"] = unit.cover


## Suppression ends early if the suppressor is out of the battle.
func _clear_stale_suppression() -> void:
	for unit in invaders + defenders:
		if unit.suppressed_by != null and not unit.suppressed_by.is_active():
			unit.suppressed_by = null


func _log_morale(changes: Array[Dictionary]) -> void:
	if not changes.is_empty():
		events.append({"type": "morale", "changes": changes})


## Checks whether the battle is over: a side with nobody able to fight, or a
## side that withdraws. Returns true once the battle has ended.
func _check_end() -> bool:
	if not _end.is_empty():
		return true
	if not _any_active(defenders):
		_end = {"holder": CombatUnit.SIDE_INVADER, "reason": "no enemy able to fight"}
	elif not _any_active(invaders):
		_end = {"holder": CombatUnit.SIDE_DEFENDER, "reason": "no enemy able to fight"}
	else:
		for side: String in [CombatUnit.SIDE_INVADER, CombatUnit.SIDE_DEFENDER]:
			var why := _withdraw_reason(side)
			if why != "":
				_end = {"holder": _other(side), "reason": why, "withdrew": side}
				events.append({"type": "withdraw", "side": side, "reason": why})
				break
	return not _end.is_empty()


## Standard rule: lost half its starting units and outnumbered two to one.
## Invaders follow their stance: cautious withdraws at the first death, all_in never.
func _withdraw_reason(side: String) -> String:
	var w: Dictionary = data.combat["withdrawal"]
	var units := _units(side)
	if side == CombatUnit.SIDE_INVADER:
		if invader_stance == STANCE_ALL_IN:
			return ""
		if invader_stance == STANCE_CAUTIOUS:
			for unit in units:
				if unit.state == CombatUnit.State.DEAD:
					return "Cautious stance: withdrew after the first death"
			return ""
	var start := int(_starting_counts[side])
	var active := _count_active(units)
	var enemy_active := _count_active(_units(_other(side)))
	var lost := start - active
	if lost >= float(w["lost_fraction"]) * start and enemy_active >= float(w["outnumbered_ratio"]) * active:
		return "lost %d of %d and outnumbered %d to %d" % [lost, start, enemy_active, active]
	return ""


## When the invaders hold the field, each dead invader may be recovered alive.
func _roll_recovery() -> void:
	var r: Dictionary = data.combat["recovery"]
	var rolls: Array[Dictionary] = []
	for unit in invaders:
		if unit.state != CombatUnit.State.DEAD:
			continue
		var chance := int(r.get(unit.kind, r["default"]))
		var roll := dice.percent()
		unit.recovered = roll <= chance
		rolls.append({"unit": unit.unit_name, "roll": roll, "chance": chance, "recovered": unit.recovered})
	if not rolls.is_empty():
		events.append({"type": "recovery", "rolls": rolls})


## Highest Mobility first; ties keep roster order.
func _acting_order(units: Array[CombatUnit]) -> Array[CombatUnit]:
	var indexed: Array = []
	for i in units.size():
		indexed.append([units[i], i])
	indexed.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0].mobility != b[0].mobility:
			return a[0].mobility > b[0].mobility
		return a[1] < b[1])
	var ordered: Array[CombatUnit] = []
	for pair: Array in indexed:
		ordered.append(pair[0])
	return ordered


func _any_active(units: Array[CombatUnit]) -> bool:
	return _count_active(units) > 0


func _count_active(units: Array[CombatUnit]) -> int:
	var count := 0
	for unit in units:
		if unit.is_active():
			count += 1
	return count


func _units(side: String) -> Array[CombatUnit]:
	return invaders if side == CombatUnit.SIDE_INVADER else defenders


static func _other(side: String) -> String:
	return CombatUnit.SIDE_DEFENDER if side == CombatUnit.SIDE_INVADER else CombatUnit.SIDE_INVADER


static func _summaries(units: Array[CombatUnit]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for unit in units:
		out.append({
			"name": unit.unit_name,
			"kind": unit.kind,
			"kind_name": unit.kind_name,
			"weapon_name": String(unit.weapon.get("name", unit.weapon_id)),
			"state": unit.state,
			"health": unit.health,
			"max_health": unit.max_health,
			"wounded": unit.wounded,
			"morale": unit.morale,
			"machine": unit.is_machine(),
			"recovered": unit.recovered,
		})
	return out
