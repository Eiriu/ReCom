class_name Scenarios
extends RefCounted
## Ready-made battles for testing. Both the screen and the headless runners use
## these, so they always fight exactly the same setup.

const DUEL := "duel"
const SQUAD := "squad"

## Names shown on the screen, by scenario id.
const NAMES := {
	DUEL: "Duel (slice 1.1)",
	SQUAD: "Squad battle (slice 1.2)",
}


static func build(id: String, data: GameData, seed_value: int) -> Battle:
	match id:
		DUEL:
			return duel(data, seed_value)
		SQUAD:
			return squad_battle(data, seed_value)
	push_error("Unknown scenario: %s" % id)
	return duel(data, seed_value)


## Slice 1.1: one Warden against one Regular with an assault rifle,
## at Medium range, with one tree in the middle. The seed decides who shoots
## first and who stands behind the tree (Half cover).
static func duel(data: GameData, seed_value: int) -> Battle:
	var battle := Battle.new(data, seed_value)
	battle.first_side = Battle.FIRST_SIDE_RANDOM
	battle.title = "Duel"
	battle.location = "Open ground, one tree"
	battle.cover_features.append({"name": "tree", "cover": "half"})

	var warden := CombatUnit.from_species("warden", "Warden-1", data)
	var rifle := CombatUnit.from_grade("regular", "assault_rifle", "Rifle-1", data)
	for unit in [warden, rifle]:
		unit.band = "medium"
		unit.cover = "none"

	battle.invaders.append(warden)
	battle.defenders.append(rifle)
	return battle


## Slice 1.2: 2 Wardens and 2 Striders against a Defender squad of 4 Regulars,
## at Medium range with one tree. The seed decides who goes first and who gets
## the tree. Range bands and real cover arrive in slice 1.3.
static func squad_battle(data: GameData, seed_value: int,
		invader_squad: String = "wardens_and_striders", defender_squad: String = "defender_squad") -> Battle:
	var battle := Battle.new(data, seed_value)
	battle.first_side = Battle.FIRST_SIDE_RANDOM
	battle.title = "%s vs %s" % [data.squad_entry(invader_squad)["name"], data.squad_entry(defender_squad)["name"]]
	battle.location = "Open ground, one tree"
	battle.cover_features.append({"name": "tree", "cover": "half"})
	battle.invaders = build_squad(invader_squad, data)
	battle.defenders = build_squad(defender_squad, data)
	return battle


## Builds a squad from data/squads.json. Names are numbered per type:
## Warden-1, Warden-2, Strider-1 ... or Rifle-1, Rifle-2, Shotgun-1, MG-1.
static func build_squad(id: String, data: GameData) -> Array[CombatUnit]:
	var entry := data.squad_entry(id)
	var units: Array[CombatUnit] = []
	var counts := {}
	if String(entry["side"]) == CombatUnit.SIDE_INVADER:
		for species_id: Variant in entry["species"]:
			var base := String(data.species_entry(String(species_id))["name"])
			units.append(CombatUnit.from_species(String(species_id), _next_name(base, counts), data))
	else:
		var grade := String(entry["grade"])
		for weapon_id: Variant in entry["weapons"]:
			var base := String(data.weapon(String(weapon_id))["short_name"])
			units.append(CombatUnit.from_grade(grade, String(weapon_id), _next_name(base, counts), data))
	for unit in units:
		unit.band = "medium"
		unit.cover = "none"
	return units


static func _next_name(base: String, counts: Dictionary) -> String:
	counts[base] = int(counts.get(base, 0)) + 1
	return "%s-%d" % [base, counts[base]]
