class_name Scenarios
extends RefCounted
## Ready-made battles for testing. The screen, the tests and the headless tools
## all use these, so they always fight exactly the same setup.
## Matchups live in data/matchups.json; the duel is the slice 1.1 test.

const DUEL := "duel"
const SQUAD := "squad"


## Every scenario id: the duel, then the matchups in file order.
static func ids(data: GameData) -> Array[String]:
	var out: Array[String] = [DUEL]
	out.append_array(GameData.entry_ids(data.matchups))
	return out


## Matchup ids that have a spec win-rate target, in file order.
static func target_ids(data: GameData) -> Array[String]:
	var out: Array[String] = []
	for id in GameData.entry_ids(data.matchups):
		if data.matchups[id].has("target"):
			out.append(id)
	return out


static func display_name(id: String, data: GameData) -> String:
	if id == DUEL:
		return "Duel (slice 1.1)"
	return String(data.matchup_entry(id).get("name", id))


static func build(id: String, data: GameData, seed_value: int) -> Battle:
	if id == DUEL:
		return duel(data, seed_value)
	if not data.matchups.has(id):
		push_error("Unknown scenario: %s" % id)
		return duel(data, seed_value)
	var m := data.matchup_entry(id)
	return matchup(data, seed_value, String(m["invaders"]), String(m["opposition"]),
		String(m["terrain"]), String(m.get("stance", Battle.STANCE_STANDARD)), String(m.get("first_side", "attacker")))


## Slice 1.1: one Warden against one Regular with an assault rifle, at Medium
## range, with one tree in the middle. The seed decides who shoots first and who
## stands behind the tree (Half cover). Since slice 1.3 they can move and flank.
static func duel(data: GameData, seed_value: int) -> Battle:
	var battle := Battle.new(data, seed_value)
	battle.first_side = Battle.FIRST_SIDE_RANDOM
	battle.title = "Duel"
	battle.location = "Open ground, one tree"
	battle.terrain_id = "test_field"
	battle.roll_starting_cover = false
	battle.cover_features.append({"name": "tree", "cover": "half"})
	battle.invaders.append(CombatUnit.from_species("warden", "Warden-1", data))
	battle.defenders.append(CombatUnit.from_grade("regular", "assault_rifle", "Rifle-1", data))
	return battle


## Any invader squad against any opposition on any terrain.
## first_side: "attacker" (spec rule: the invaders attack, so they go first),
## "random", or a side id.
static func matchup(data: GameData, seed_value: int, invader_squad: String, opposition: String,
		terrain_id: String, stance: String = Battle.STANCE_STANDARD, first_side: String = "attacker") -> Battle:
	var battle := Battle.new(data, seed_value)
	match first_side:
		"attacker":
			battle.first_side = CombatUnit.SIDE_INVADER
		"random":
			battle.first_side = Battle.FIRST_SIDE_RANDOM
		_:
			battle.first_side = first_side
	battle.invader_stance = stance
	battle.terrain_id = terrain_id
	battle.title = "%s vs %s" % [data.squad_entry(invader_squad)["name"], data.squad_entry(opposition)["name"]]
	battle.location = String(data.terrain_entry(terrain_id)["name"])
	battle.invaders = build_squad(invader_squad, data)
	battle.defenders = build_squad(opposition, data)
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
	return units


## Squad ids for one side, in file order.
static func squad_ids(data: GameData, side: String) -> Array[String]:
	var out: Array[String] = []
	for id in GameData.entry_ids(data.squads):
		if String(data.squads[id]["side"]) == side:
			out.append(id)
	return out


static func _next_name(base: String, counts: Dictionary) -> String:
	counts[base] = int(counts.get(base, 0)) + 1
	return "%s-%d" % [base, counts[base]]
