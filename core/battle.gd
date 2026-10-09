class_name Battle
extends RefCounted
## Runs one battle from start to finish with no player input and records
## every event for the battle report.
##
## Slice 1.1: units stand in the open and only shoot. Each unit shoots once per
## turn, because shooting ends a unit's turn. Later slices add movement, cover,
## flanking, reactions and Morale through the shared AI rules.

var title: String
var location: String
var invaders: Array[CombatUnit] = []
var defenders: Array[CombatUnit] = []
## Which side starts. The other side is the one being attacked, and it holds
## the field if the round limit is reached.
var first_side: String = CombatUnit.SIDE_INVADER

var data: GameData
var dice: Dice
var events: Array[Dictionary] = []


func _init(data_in: GameData, seed_in: int) -> void:
	data = data_in
	dice = Dice.new(seed_in)


func run() -> Dictionary:
	var cfg := data.combat
	var round_limit := int(cfg["round_limit"])
	var second_side := _other(first_side)
	var holder := ""
	var end_reason := ""
	var rounds_fought := 0

	for round_number in range(1, round_limit + 1):
		rounds_fought = round_number
		for side: String in [first_side, second_side]:
			_take_turn(side, round_number)
			holder = _side_holding_field()
			if holder != "":
				end_reason = "no enemy able to fight"
				break
		if holder != "":
			break

	if holder == "":
		holder = second_side
		end_reason = "round limit reached; the attacked side holds the field"

	return {
		"seed": dice.seed_value,
		"title": title,
		"location": location,
		"rounds": rounds_fought,
		"holder": holder,
		"end_reason": end_reason,
		"events": events,
		"invaders": _summaries(invaders),
		"defenders": _summaries(defenders),
		"rolls_made": dice.rolls_made,
	}


func _take_turn(side: String, round_number: int) -> void:
	events.append({"type": "turn", "round": round_number, "side": side})
	for unit in _acting_order(_units(side)):
		if not unit.is_active():
			continue
		var target := _pick_target(unit)
		if target == null:
			return
		events.append(CombatRules.resolve_attack(unit, target, dice, data.combat))


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


## Slice 1.1 placeholder: shoot the first enemy still able to fight.
## The full AI decision rules replace this in later slices.
func _pick_target(unit: CombatUnit) -> CombatUnit:
	for enemy in _units(_other(unit.side)):
		if enemy.is_active():
			return enemy
	return null


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
