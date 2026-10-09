class_name Battle
extends RefCounted
## Runs one battle from start to finish with no player input and records
## every event for the battle report.
##
## Each side's units act in Mobility order (highest first, ties by roster
## order). Each unit has two actions, chosen by CombatAI. Shooting ends a
## unit's turn, so until movement arrives (slice 1.3) every unit shoots once.

var title: String
var location: String
var invaders: Array[CombatUnit] = []
var defenders: Array[CombatUnit] = []
const FIRST_SIDE_RANDOM := "random"

## Which side takes the first turn: a side, or FIRST_SIDE_RANDOM to roll for it
## at battle start (the roll comes from the seed, so replays stay identical).
var first_side: String = CombatUnit.SIDE_INVADER
## The side being attacked. It holds the field if the round limit is reached.
var attacked_side: String = CombatUnit.SIDE_DEFENDER
## Single pieces of cover on the field, e.g. {"name": "tree", "cover": "half"}.
## At battle start each one is rolled to a random unit, which stands behind it.
var cover_features: Array[Dictionary] = []
## Terrain id from data/terrains.json. If set, every unit rolls its cover from
## the terrain's cover mix at battle start, before any cover features apply.
var terrain_id: String = ""

var data: GameData
var dice: Dice
var events: Array[Dictionary] = []


func _init(data_in: GameData, seed_in: int) -> void:
	data = data_in
	dice = Dice.new(seed_in)


func run() -> Dictionary:
	var cfg := data.combat
	var round_limit := int(cfg["round_limit"])
	var starting_side := _decide_first_side()
	_roll_starting_cover()
	var feature_sides := _place_cover_features()
	var second_side := _other(starting_side)
	var holder := ""
	var end_reason := ""
	var rounds_fought := 0

	for round_number in range(1, round_limit + 1):
		rounds_fought = round_number
		for side: String in [starting_side, second_side]:
			_take_turn(side, round_number)
			holder = _side_holding_field()
			if holder != "":
				end_reason = "no enemy able to fight"
				break
		if holder != "":
			break

	if holder == "":
		holder = attacked_side
		end_reason = "round limit reached; the attacked side holds the field"

	return {
		"seed": dice.seed_value,
		"title": title,
		"location": location,
		"rounds": rounds_fought,
		"first_side": starting_side,
		"feature_sides": feature_sides,
		"holder": holder,
		"end_reason": end_reason,
		"events": events,
		"invaders": _summaries(invaders),
		"defenders": _summaries(defenders),
		"rolls_made": dice.rolls_made,
	}


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
	if terrain_id == "":
		return
	var cover_mix: Dictionary = data.terrain_entry(terrain_id)["cover_mix"]
	var rolls: Array[Dictionary] = []
	for unit in invaders + defenders:
		var roll := dice.percent()
		unit.cover = CombatRules.cover_from_roll(roll, cover_mix)
		rolls.append({"unit": unit.unit_name, "side": unit.side, "roll": roll, "cover": unit.cover})
	events.append({"type": "cover_rolls", "terrain": terrain_id, "mix": cover_mix, "rolls": rolls})


## Rolls which unit stands behind each cover feature, after the first-turn roll.
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
	events.append({"type": "turn", "round": round_number, "side": side})
	var enemies := _units(_other(side))
	for unit in _acting_order(_units(side)):
		if not unit.is_active():
			continue
		var actions_left := int(cfg["actions_per_turn"])
		while actions_left > 0 and unit.is_active():
			var choice := CombatAI.choose_shot(unit, enemies, cfg)
			if choice.is_empty():
				return
			var record := CombatRules.resolve_attack(unit, choice["target"], dice, cfg)
			record["rule"] = choice["rule"]
			events.append(record)
			# Shooting ends the unit's turn, whatever actions are left.
			actions_left = 0
		if _side_holding_field() != "":
			return


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


## Returns the side holding the field if the other side can no longer fight.
func _side_holding_field() -> String:
	if not _any_active(defenders):
		return CombatUnit.SIDE_INVADER
	if not _any_active(invaders):
		return CombatUnit.SIDE_DEFENDER
	return ""


func _any_active(units: Array[CombatUnit]) -> bool:
	for unit in units:
		if unit.is_active():
			return true
	return false


func _units(side: String) -> Array[CombatUnit]:
	return invaders if side == CombatUnit.SIDE_INVADER else defenders


static func _other(side: String) -> String:
	return CombatUnit.SIDE_DEFENDER if side == CombatUnit.SIDE_INVADER else CombatUnit.SIDE_INVADER


static func _summaries(units: Array[CombatUnit]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for unit in units:
		out.append({
			"name": unit.unit_name,
			"kind_name": unit.kind_name,
			"weapon_name": String(unit.weapon.get("name", unit.weapon_id)),
			"state": unit.state,
			"health": unit.health,
			"max_health": unit.max_health,
			"wounded": unit.wounded,
		})
	return out
