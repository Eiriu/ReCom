class_name CombatUnit
extends RefCounted
## One unit on either side of a battle: its stats, weapon and current condition.

## ACTIVE units can fight. DEAD and DOWNED units were taken out by damage.
## FLED units broke (Morale 0) and left the battle alive.
enum State { ACTIVE, DEAD, DOWNED, FLED }

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

## Morale starts equal to Will. Machines (the "machine" ability) have none.
var morale: int = 0
## The unit's own side, in roster order. Set by Battle; used by Swarm and Rally.
var squad: Array[CombatUnit] = []

## Reactions and conditions that last across turns.
var overwatch: bool = false
var hunkered: bool = false
## The enemy suppressing this unit, or null.
var suppressed_by: CombatUnit = null
## True once this suppression has drawn its one reaction shot.
var suppression_reacted: bool = false
## +Aim from Rally, and the side-turn number after which it ends.
var rally_aim: int = 0
var rally_until_turn: int = -1
## Harrow: the first own side-turn on which Rally can be used again.
var rally_ready_turn: int = 1
## Drone: Repair uses left this battle.
var repairs_left: int = 0
## Set at the end of the battle if a dead invader is recovered alive.
var recovered: bool = false

## Per-turn flags, reset at the start of each of the unit's turns.
var flanked_target: CombatUnit = null
var planned_shot: bool = false
var moved_this_turn: bool = false
var shot_this_turn: bool = false
var psionic_this_turn: bool = false


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
	if unit.has_ability("repair"):
		unit.repairs_left = int(data.combat["abilities"]["repair_uses"])
	unit.morale = 0 if unit.is_machine() else unit.will
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
	unit.morale = unit.will
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


func has_tag(tag: String) -> bool:
	return Array(weapon.get("tags", [])).has(tag)


func is_machine() -> bool:
	return has_ability("machine")


## Shaken below the threshold in combat.json (25). Machines never shake.
func is_shaken(cfg: Dictionary) -> bool:
	return not is_machine() and morale < int(cfg["morale"]["shaken_below"])


## Below half Health right now (Wounded is the permanent flag from the first time).
func below_half_health() -> bool:
	return health * 2 < max_health


## Cover that counts against shots at this unit: hunkering counts as Full.
func effective_cover() -> String:
	return "full" if hunkered else cover


## Whether the unit may still take a shot this turn.
## Every unit shoots at most once per turn. Weapons tagged no_move_and_fire
## cannot shoot after a plain move (a flank attempt is not a move for this).
func can_shoot() -> bool:
	if shot_this_turn:
		return false
	return not (moved_this_turn and has_tag("no_move_and_fire"))


func health_text() -> String:
	return "%d/%d" % [health, max_health]


func reset_turn_flags() -> void:
	flanked_target = null
	planned_shot = false
	moved_this_turn = false
	shot_this_turn = false
	psionic_this_turn = false
