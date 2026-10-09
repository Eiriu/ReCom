class_name CombatUnit
extends RefCounted
## One unit on either side of a battle: its stats, weapon and current condition.

enum State { ACTIVE, DEAD, DOWNED }

const SIDE_INVADER := "invader"
const SIDE_DEFENDER := "defender"

var unit_name: String
var side: String
## Species id for invaders, grade id for Defender soldiers.
var kind: String
var kind_name: String

var max_health: int
var health: int
var aim: int
var defense: int
var mobility: int
var will: int
var armour: int

var weapon_id: String
var weapon: Dictionary = {}
var abilities: Array[String] = []
## Percent chance to be downed instead of killed at 0 Health (Defender only).
var downed_chance: int = 0

## Range band to the enemy line: "close", "medium" or "long".
var band: String = "medium"
## Cover state: "none", "half" or "full".
var cover: String = "none"
var wounded: bool = false
var state: State = State.ACTIVE


static func from_species(species_id: String, name_in: String, data: GameData) -> CombatUnit:
	var entry := data.species_entry(species_id)
	var unit := CombatUnit.new()
	unit.unit_name = name_in
	unit.side = SIDE_INVADER
	unit.kind = species_id
	unit._apply_stats(entry)
	unit.weapon_id = String(entry["weapon"])
	unit.weapon = data.weapon(unit.weapon_id)
	for ability: Variant in entry.get("abilities", []):
		unit.abilities.append(String(ability))
	return unit


static func from_grade(grade_id: String, weapon_id_in: String, name_in: String, data: GameData) -> CombatUnit:
	var entry := data.grade_entry(grade_id)
	var unit := CombatUnit.new()
	unit.unit_name = name_in
	unit.side = SIDE_DEFENDER
	unit.kind = grade_id
	unit._apply_stats(entry)
	unit.weapon_id = weapon_id_in
	unit.weapon = data.weapon(weapon_id_in)
	unit.downed_chance = int(entry.get("downed_chance", 0))
	return unit


func _apply_stats(entry: Dictionary) -> void:
	kind_name = String(entry["name"])
	max_health = int(entry["health"])
	health = max_health
	aim = int(entry["aim"])
	defense = int(entry["defense"])
	mobility = int(entry["mobility"])
	will = int(entry["will"])
	armour = int(entry["armour"])


func is_active() -> bool:
	return state == State.ACTIVE


func has_ability(id: String) -> bool:
	return abilities.has(id)


func health_text() -> String:
	return "%d/%d" % [health, max_health]
