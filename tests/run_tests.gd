extends SceneTree
## Automated checks for the combat core. Exits with code 1 if anything fails.
##
## Usage (from the project folder):
##   godot --headless --script res://tests/run_tests.gd

var _passed := 0
var _failed := 0
var _data: GameData


func _initialize() -> void:
	_data = GameData.load_default()
	_test_data_files()
	_test_hit_chance()
	_test_crit_and_damage()
	_test_wounded_and_death()
	_test_determinism()
	_test_battles_end()
	_test_squads()
	_test_ai_choices()
	_test_cover_rolls()
	_test_bands_and_flanking()
	_test_conditions()
	_test_morale()
	_test_abilities()
	_test_ai_rules()
	_test_battle_invariants()
	_test_withdrawal_and_recovery()

	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: %s %s" % [label, detail])


func _expect(label: String, actual: Variant, expected: Variant) -> void:
	_check(label, actual == expected, "(got %s, expected %s)" % [actual, expected])


func _warden() -> CombatUnit:
	return CombatUnit.from_species("warden", "Warden-1", _data)


func _regular() -> CombatUnit:
	return CombatUnit.from_grade("regular", "assault_rifle", "Rifle-1", _data)


func _test_data_files() -> void:
	for id in GameData.entry_ids(_data.species):
		var weapon_id := String(_data.species[id]["weapon"])
		_check("species %s has a known weapon" % id, _data.weapons.has(weapon_id), weapon_id)
	for id in GameData.entry_ids(_data.weapons):
		var damage: Array = _data.weapons[id]["damage"]
		_check("weapon %s damage min <= max" % id, int(damage[0]) <= int(damage[1]))
		for band: Variant in _data.weapons[id]["optimal"]:
			_check("weapon %s optimal band is valid" % id, CombatRules.BANDS.has(String(band)), String(band))
	for id in GameData.entry_ids(_data.terrains):
		var t: Dictionary = _data.terrains[id]
		for key: String in ["cover_mix", "in_transit_cover"]:
			var mix: Dictionary = t[key]
			_expect("Terrain %s %s adds up to 100" % [id, key], int(mix["full"]) + int(mix["half"]) + int(mix["none"]), 100)
		_check("Terrain %s starting band is valid" % id, CombatRules.BANDS.has(String(t["starting_band"])))
	for id in GameData.entry_ids(_data.matchups):
		var m: Dictionary = _data.matchups[id]
		_check("Matchup %s: invaders squad exists" % id, _data.squads.has(String(m["invaders"])))
		_check("Matchup %s: opposition squad exists" % id, _data.squads.has(String(m["opposition"])))
		_check("Matchup %s: terrain exists" % id, _data.terrains.has(String(m["terrain"])))


func _test_hit_chance() -> void:
	var cfg := _data.combat
	var warden := _warden()
	var rifle := _regular()

	_expect("Warden at Regular, open, Medium", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 75)
	_expect("Regular at Warden, open, Medium (Defense 5)", CombatRules.hit_chance(rifle, warden, cfg)["chance"], 70)

	warden.band = "long"
	_expect("Warden one band outside optimal", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 50)
	warden.band = "medium"

	var carbine_vessel := CombatUnit.from_species("vessel", "Vessel-1", _data)
	carbine_vessel.band = "long"
	_expect("Shard carbine at Long (optimal Close-Medium)", CombatRules.range_modifier(carbine_vessel.weapon, "long", cfg), -15)
	var scatter := CombatUnit.from_species("strider", "Strider-1", _data)
	_expect("Scattergun at Long is two bands out", CombatRules.range_modifier(scatter.weapon, "long", cfg), -30)

	rifle.cover = "half"
	_expect("Half cover", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 55)
	_expect("Flanked ignores cover", CombatRules.hit_chance(warden, rifle, cfg, {"flanked": true})["chance"], 75)
	rifle.cover = "full"
	_expect("Full cover", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 35)
	rifle.cover = "none"

	warden.wounded = true
	_expect("Wounded attacker", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 65)
	warden.wounded = false

	warden.aim = 200
	_expect("Hit chance capped at 95", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 95)
	warden.aim = -100
	_expect("Hit chance floored at 5", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 5)


func _test_crit_and_damage() -> void:
	var cfg := _data.combat
	_expect("Crit 5 x1.5 rounds down to 7", CombatRules.damage_from_roll(5, true, 0, cfg), 7)
	_expect("Crit 3 x1.5 rounds down to 4", CombatRules.damage_from_roll(3, true, 0, cfg), 4)
	_expect("Armour subtracts", CombatRules.damage_from_roll(4, false, 1, cfg), 3)
	_expect("Minimum 1 damage", CombatRules.damage_from_roll(3, false, 3, cfg), 1)

	var warden := _warden()
	var rifle := _regular()
	_expect("Weapon crit", CombatRules.crit_chance(warden, rifle, cfg), 10)
	_expect("Flanked crit +50", CombatRules.crit_chance(warden, rifle, cfg, true), 60)
	_expect("Reaction shots cannot crit", CombatRules.crit_chance(warden, rifle, cfg, true, true), 0)
	var bulwark := CombatUnit.from_species("bulwark", "Bulwark-1", _data)
	_expect("Plated cannot be crit", CombatRules.crit_chance(rifle, bulwark, cfg, true), 0)


func _test_wounded_and_death() -> void:
	var dice := Dice.new(1)
	var rifle := _regular()
	var record := {}
	CombatRules.apply_damage(rifle, 4, dice, record)
	_check("4/8 is not Wounded (needs below half)", not rifle.wounded)
	CombatRules.apply_damage(rifle, 1, dice, record)
	_check("3/8 is Wounded", rifle.wounded)
	CombatRules.apply_damage(rifle, 10, dice, record)
	_check("Defender at 0 is out of action", not rifle.is_active())
	_check("Defender at 0 is downed or dead",
		rifle.state == CombatUnit.State.DOWNED or rifle.state == CombatUnit.State.DEAD)
	_check("Downed roll was made", record.has("downed_roll"))

	var warden := _warden()
	var warden_record := {}
	CombatRules.apply_damage(warden, 99, dice, warden_record)
	_expect("Invader at 0 dies", warden.state, CombatUnit.State.DEAD)
	_check("No downed roll for invaders", not warden_record.has("downed_roll"))

	var downed := 0
	for seed_value in range(1, 2001):
		var victim := _regular()
		CombatRules.apply_damage(victim, 99, Dice.new(seed_value), {})
		if victim.state == CombatUnit.State.DOWNED:
			downed += 1
	_check("Regular downed about 25% of the time", downed > 400 and downed < 600, "(%d of 2000)" % downed)




func _test_determinism() -> void:
	for id in Scenarios.ids(_data):
		var first := BattleReport.format(Scenarios.build(id, _data, 48213).run())
		var second := BattleReport.format(Scenarios.build(id, _data, 48213).run())
		_check("%s: same seed gives the same battle" % id, first == second)

	var distinct := {}
	for seed_value in range(1, 11):
		distinct[BattleReport.format(Scenarios.duel(_data, seed_value).run())] = true
	_check("Different seeds give different battles", distinct.size() > 5, "(%d distinct of 10)" % distinct.size())

	var first_sides := {}
	for seed_value in range(1, 51):
		first_sides[Scenarios.duel(_data, seed_value).run()["first_side"]] = true
	_check("Duel: both sides sometimes shoot first", first_sides.size() == 2)

	var tree_sides := {}
	for seed_value in range(1, 51):
		var result := Scenarios.duel(_data, seed_value).run()
		_expect("Seed %d: one tree placed" % seed_value, result["feature_sides"].size(), 1)
		tree_sides[result["feature_sides"][0]] = true
	_check("Both sides sometimes get the tree", tree_sides.size() == 2)

	var fixed := Scenarios.duel(_data, 5)
	fixed.first_side = CombatUnit.SIDE_DEFENDER
	_expect("A fixed first side is respected", fixed.run()["first_side"], CombatUnit.SIDE_DEFENDER)
	for id in Scenarios.target_ids(_data):
		_expect("%s: the attacking invaders go first (spec)" % id,
			Scenarios.build(id, _data, 3).run()["first_side"], CombatUnit.SIDE_INVADER)


func _test_battles_end() -> void:
	var limit := int(_data.combat["round_limit"])
	for id in Scenarios.ids(_data):
		for seed_value in range(1, 201):
			var result := Scenarios.build(id, _data, seed_value).run()
			_check("%s %d ends within the round limit" % [id, seed_value], int(result["rounds"]) <= limit)
			_check("%s %d has a side holding the field" % [id, seed_value], String(result["holder"]) != "")


func _test_squads() -> void:
	var defenders := Scenarios.build_squad("defender_squad", _data)
	var names: Array[String] = []
	for unit in defenders:
		names.append(unit.unit_name)
	_expect("Defender squad names", names, ["Rifle-1", "Rifle-2", "Shotgun-1", "MG-1"] as Array[String])
	_expect("Defender squad is Regulars", defenders[0].kind, "regular")
	_expect("Machine gunner carries a machine gun", defenders[3].weapon_id, "machine_gun")

	var battle := Scenarios.build("squad", _data, 1)
	var order: Array[String] = []
	for unit in battle._acting_order(battle.invaders):
		order.append(unit.unit_name)
	_expect("Invaders act by Mobility, ties in roster order", order,
		["Strider-1", "Strider-2", "Warden-1", "Warden-2"] as Array[String])

	for id in GameData.entry_ids(_data.squads):
		_check("Squad %s builds" % id, not Scenarios.build_squad(id, _data).is_empty())

	for id in GameData.entry_ids(_data.terrains):
		var b := Scenarios.matchup(_data, 9, "four_wardens", "defender_squad", id)
		b.run()
		_check("Terrain %s: both sides start in its starting band" % id,
			b.events.any(func(e: Dictionary) -> bool: return e["type"] == "cover_rolls" and e["band"] == _data.terrains[id]["starting_band"]))


func _test_ai_choices() -> void:
	var cfg := _data.combat
	var warden := _warden()

	var healthy := _regular()
	healthy.unit_name = "Healthy"
	var hurt := _regular()
	hurt.unit_name = "Hurt"
	hurt.health = 3
	hurt.cover = "half"
	var enemies: Array[CombatUnit] = [healthy, hurt]
	var choice := CombatAI.choose_shot(warden, enemies, cfg)
	_expect("Finish off a killable target at 50%+", choice["target"].unit_name, "Hurt")
	_expect("Finish off rule recorded", choice["rule"], CombatAI.RULE_FINISH_OFF)

	hurt.cover = "full"
	choice = CombatAI.choose_shot(warden, enemies, cfg)
	_expect("No finish off below 50%: take the best expected damage", choice["target"].unit_name, "Healthy")

	var tough := _regular()
	tough.health = 1
	_check("Expected damage ignores remaining Health (spec)", CombatAI.expected_damage(warden, tough, cfg) > 1.0)
	var capped := cfg.duplicate(true)
	capped["ai"]["cap_damage_at_health"] = true
	_check("With the cap switched on, never more than remaining Health", CombatAI.expected_damage(warden, tough, capped) <= 1.0)
	# Pulse rifle 3-5: normal average 4; crits floor(4.5, 6, 7.5) = 4, 6, 7, average 17/3.
	_check("Expected damage = hit x average damage with crits",
		absf(CombatAI.expected_damage(warden, _regular(), cfg) - 0.75 * (0.9 * 4.0 + 0.1 * 17.0 / 3.0)) < 0.001)

	healthy.state = CombatUnit.State.DEAD
	hurt.state = CombatUnit.State.DOWNED
	_check("No shot when no enemy can fight", CombatAI.choose_shot(warden, enemies, cfg).is_empty())


func _test_cover_rolls() -> void:
	var mix: Dictionary = _data.terrain_entry("test_field")["cover_mix"]
	_expect("Roll 15 is Full", CombatRules.cover_from_roll(15, mix), "full")
	_expect("Roll 16 is Half", CombatRules.cover_from_roll(16, mix), "half")
	_expect("Roll 40 is Half", CombatRules.cover_from_roll(40, mix), "half")
	_expect("Roll 41 is None", CombatRules.cover_from_roll(41, mix), "none")
	_expect("Roll 100 is None", CombatRules.cover_from_roll(100, mix), "none")

	var counts := {"full": 0, "half": 0, "none": 0}
	var units := 0
	for seed_value in range(1, 1001):
		var battle := Scenarios.build("squad", _data, seed_value)
		battle.run()
		for event: Dictionary in battle.events:
			if event["type"] == "cover_rolls":
				for roll: Dictionary in event["rolls"]:
					counts[roll["cover"]] += 1
					units += 1
	_expect("Every unit in every squad battle rolls starting cover", units, 8000)
	_check("About 15% Full", absf(100.0 * counts["full"] / units - 15.0) < 2.0, str(counts))
	_check("About 25% Half", absf(100.0 * counts["half"] / units - 25.0) < 2.0, str(counts))
	_check("About 60% None", absf(100.0 * counts["none"] / units - 60.0) < 2.0, str(counts))


func _test_bands_and_flanking() -> void:
	var cfg := _data.combat
	_expect("Close neighbours", CombatRules.neighbour_bands("close"), ["medium"] as Array[String])
	_expect("Medium neighbours", CombatRules.neighbour_bands("medium"), ["close", "long"] as Array[String])
	_expect("Long neighbours", CombatRules.neighbour_bands("long"), ["medium"] as Array[String])

	var warden := _warden()
	warden.band = "medium"
	_expect("Warden retreats to Long on a range tie", CombatRules.retreat_band(warden, cfg), "long")
	var strider := CombatUnit.from_species("strider", "Strider-1", _data)
	strider.band = "medium"
	_expect("Strider moves for cover towards its Close optimum", CombatRules.retreat_band(strider, cfg), "close")
	warden.band = "close"
	_expect("Warden at Close moves back to its Medium optimum", CombatRules.retreat_band(warden, cfg), "medium")

	var urban := _data.terrain_entry("urban")
	var forest := _data.terrain_entry("forest")
	var farmland := _data.terrain_entry("farmland")
	_expect("Strider flank in Urban: 25 + 5x3", CombatRules.flank_chance(strider, urban, cfg)["chance"], 40)
	_expect("Strider flank in Forest: 30 + 15", CombatRules.flank_chance(strider, forest, cfg)["chance"], 45)
	_expect("Warden flank in Farmland: 15 + 0", CombatRules.flank_chance(_warden(), farmland, cfg)["chance"], 15)
	var bulwark := CombatUnit.from_species("bulwark", "Bulwark-1", _data)
	_expect("Bulwark flank in Urban: 25 - 5", CombatRules.flank_chance(bulwark, urban, cfg)["chance"], 20)
	var fast := _warden()
	fast.mobility = 20
	_expect("Flank chance capped at 60", CombatRules.flank_chance(fast, urban, cfg)["chance"], 60)
	var slow := _warden()
	slow.mobility = 0
	_expect("Flank chance floored at 0", CombatRules.flank_chance(slow, _data.terrain_entry("desert"), cfg)["chance"], 0)
	var tweaked := urban.duplicate(true)
	tweaked["band_modifier"]["long"] = -10
	var sniper := CombatUnit.from_grade("veteran", "sniper_rifle", "Sniper-1", _data)
	sniper.band = "long"
	_expect("Band modifier adjusts the flank chance", CombatRules.flank_chance(sniper, tweaked, cfg)["chance"], 25 + 10 - 10)

	# A flank attempt never changes the flanker's band; a move changes it by one.
	for seed_value in range(1, 301):
		var result := Scenarios.build("mixed_forest", _data, seed_value).run()
		for event: Dictionary in result["events"]:
			if event["type"] == "move":
				var gap := absi(CombatRules.BANDS.find(String(event["from_band"])) - CombatRules.BANDS.find(String(event["to_band"])))
				_expect("A move shifts exactly one band", gap, 1)


func _test_conditions() -> void:
	var cfg := _data.combat
	var warden := _warden()
	var rifle := _regular()
	_expect("Base: Warden at Regular, open, Medium", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 75)

	rifle.hunkered = true
	_expect("Hunkered counts as Full cover", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 35)
	rifle.hunkered = false
	_expect("In-transit cover overrides the target's cover",
		CombatRules.hit_chance(warden, rifle, cfg, {"cover": "half"})["chance"], 55)

	_expect("Reaction shot: Steady Warden takes no penalty",
		CombatRules.hit_chance(warden, rifle, cfg, {"reaction": true})["chance"], 75)
	_expect("Reaction shot: -15 for others",
		CombatRules.hit_chance(rifle, warden, cfg, {"reaction": true})["chance"], 55)

	_expect("Suppression -30 at Will 50", CombatRules.suppression_penalty(rifle, cfg), 30)
	var harrow := CombatUnit.from_species("harrow", "Harrow-1", _data)
	_expect("Suppression -10 at Will 90", CombatRules.suppression_penalty(harrow, cfg), 10)
	var veteran := CombatUnit.from_grade("veteran", "assault_rifle", "Rifle-1", _data)
	_expect("Suppression -20 at Will 70", CombatRules.suppression_penalty(veteran, cfg), 20)
	var vessel := CombatUnit.from_species("vessel", "Vessel-1", _data)
	_expect("Suppression -30 below Will 50", CombatRules.suppression_penalty(vessel, cfg), 30)
	rifle.suppressed_by = warden
	_expect("Suppressed shooter", CombatRules.hit_chance(rifle, warden, cfg)["chance"], 40)
	rifle.suppressed_by = null

	rifle.morale = 24
	_check("Morale 24 is Shaken", rifle.is_shaken(cfg))
	_expect("Shaken shooter -15", CombatRules.hit_chance(rifle, warden, cfg)["chance"], 55)
	rifle.morale = 25
	_check("Morale 25 is not Shaken", not rifle.is_shaken(cfg))

	warden.rally_aim = 5
	_expect("Rallied +5", CombatRules.hit_chance(warden, rifle, cfg)["chance"], 80)
	warden.rally_aim = 0

	var sniper := CombatUnit.from_grade("regular", "sniper_rifle", "Sniper-1", _data)
	_check("Sniper can shoot before moving", sniper.can_shoot())
	sniper.moved_this_turn = true
	_check("Sniper cannot shoot after a move", not sniper.can_shoot())
	sniper.moved_this_turn = false
	sniper.flanked_target = rifle
	_check("Sniper can shoot after a flank attempt", sniper.can_shoot())
	sniper.shot_this_turn = true
	_check("Nobody shoots twice in a turn", not sniper.can_shoot())


func _test_morale() -> void:
	var cfg := _data.combat
	var rifle := _regular()
	_expect("Morale starts at Will", rifle.morale, 50)
	var drone := CombatUnit.from_species("drone", "Drone-1", _data)
	_check("Drones are machines", drone.is_machine())
	_check("Machines never shake", not drone.is_shaken(cfg))
	_check("Machines ignore Morale changes", CombatRules.change_morale(drone, -50, "test", cfg).is_empty())

	var change := CombatRules.change_morale(rifle, -26, "test", cfg)
	_expect("Morale 50 - 26 = 24", rifle.morale, 24)
	_check("Crossing below 25 is reported as Shaken", change.get("shaken", false))
	CombatRules.change_morale(rifle, 30, "test", cfg)
	_check("Back to 54 is no longer Shaken", not rifle.is_shaken(cfg))
	CombatRules.change_morale(rifle, 100, "test", cfg)
	_expect("Gains stop at Will + 20", rifle.morale, 70)
	change = CombatRules.change_morale(rifle, -70, "test", cfg)
	_check("At 0 the unit breaks", change.get("broke", false))
	_expect("A broken unit has fled", rifle.state, CombatUnit.State.FLED)
	_check("A fled unit cannot fight", not rifle.is_active())

	# One attack: crit then Wounded on the target, a kill for the shooter, allies of the fallen.
	var squad := Scenarios.build_squad("defender_squad", _data)
	for unit in squad:
		unit.squad = squad
	var shooter := _warden()
	var target := squad[0]
	var record := {"hit": true, "crit": true, "became_wounded": true}
	var changes := CombatRules.morale_after_attack(shooter, target, record, cfg)
	_expect("Crit -5 then Wounded -10", target.morale, 35)
	_expect("Two changes for the target", changes.size(), 2)
	target.state = CombatUnit.State.DEAD
	changes = CombatRules.morale_after_attack(shooter, target, {"hit": true, "outcome": "dead"}, cfg)
	_expect("Kill +5 for the shooter", shooter.morale, 55)
	_expect("Each ally of the fallen -10", squad[1].morale, 40)
	_expect("Shooter + 3 allies changed", changes.size(), 4)

	var invaders := Scenarios.build_squad("wardens_and_harrow", _data)
	for unit in invaders:
		unit.squad = invaders
	var harrow := invaders[4]
	harrow.state = CombatUnit.State.DEAD
	CombatRules.morale_for_fallen(harrow, cfg)
	_expect("A fallen Harrow costs allies 20", invaders[0].morale, 30)


func _test_abilities() -> void:
	var cfg := _data.combat
	var swarm := Scenarios.build_squad("vessel_swarm", _data)
	for unit in swarm:
		unit.squad = swarm
	_expect("Swarm caps at +15 with 5 other Vessels", CombatRules.swarm_bonus(swarm[0], cfg), 15)
	swarm[1].state = CombatUnit.State.DEAD
	swarm[2].state = CombatUnit.State.DEAD
	swarm[3].state = CombatUnit.State.FLED
	_expect("Swarm counts only Vessels still fighting (2 left)", CombatRules.swarm_bonus(swarm[0], cfg), 10)
	_expect("The Drone gets no Swarm", CombatRules.swarm_bonus(swarm[6], cfg), 0)
	_expect("Drone starts with 2 repairs", swarm[6].repairs_left, 2)

	var harrow := CombatUnit.from_species("harrow", "Harrow-1", _data)
	_expect("Mind spike vs Will 50: 50 + 40/2", CombatRules.mind_spike_chance(harrow, _regular(), cfg), 70)
	var veteran := CombatUnit.from_grade("veteran", "assault_rifle", "Rifle-1", _data)
	_expect("Mind spike vs Will 70: 60", CombatRules.mind_spike_chance(harrow, veteran, cfg), 60)
	var strong := _regular()
	strong.will = 300
	_expect("Mind spike floored at 5", CombatRules.mind_spike_chance(harrow, strong, cfg), 5)

	var bulwark := CombatUnit.from_species("bulwark", "Bulwark-1", _data)
	_expect("Plated: no crit even flanked", CombatRules.crit_chance(_regular(), bulwark, cfg, true), 0)
	_check("Siege lance cannot overwatch", bulwark.has_tag("no_overwatch"))

	# Strider (Hit and run) never takes two normal shots in one turn.
	for seed_value in range(1, 301):
		var result := Scenarios.build("mixed_forest", _data, seed_value).run()
		var shots := {}
		var turn := ""
		for event: Dictionary in result["events"]:
			if event["type"] == "turn":
				turn = "%d-%s" % [event["round"], event["side"]]
			elif event["type"] == "attack" and not event.get("reaction", false):
				var key := "%s-%s" % [turn, event["attacker"]]
				_check("Seed %d: %s shoots at most once a turn" % [seed_value, event["attacker"]], not shots.has(key))
				shots[key] = true


func _setup(invader_species: Array, defender_weapons: Array, terrain_id: String = "urban") -> Dictionary:
	var inv: Array[CombatUnit] = []
	var counts := {}
	for id: String in invader_species:
		counts[id] = int(counts.get(id, 0)) + 1
		inv.append(CombatUnit.from_species(id, "%s-%d" % [id.capitalize(), counts[id]], _data))
	var defs: Array[CombatUnit] = []
	for i in defender_weapons.size():
		defs.append(CombatUnit.from_grade("regular", String(defender_weapons[i]), "D-%d" % (i + 1), _data))
	for unit in inv:
		unit.squad = inv
		unit.band = "medium"
	for unit in defs:
		unit.squad = defs
		unit.band = "medium"
	return {"inv": inv, "def": defs, "terrain": _data.terrain_entry(terrain_id)}


func _test_ai_rules() -> void:
	var cfg := _data.combat
	var s := _setup(["warden"], ["assault_rifle"])
	var warden: CombatUnit = s["inv"][0]
	var enemies: Array[CombatUnit] = s["def"]
	var terrain: Dictionary = s["terrain"]

	warden.morale = 20
	warden.cover = "full"
	_expect("Shaken in Full cover: hunker", CombatAI.choose_action(warden, enemies, terrain, cfg, 2, 1)["kind"], "hunker")
	warden.cover = "half"
	var act := CombatAI.choose_action(warden, enemies, terrain, cfg, 2, 1)
	_expect("Shaken in Half cover: move", act["kind"], "move")
	_expect("Shaken rule recorded", act["rule"], CombatAI.RULE_SHAKEN)
	warden.morale = 50

	warden.flanked_target = enemies[0]
	act = CombatAI.choose_action(warden, enemies, terrain, cfg, 1, 1)
	_expect("Follow through after a flank", act["kind"], "shoot")
	_check("Follow-through shot is flanked", act.get("flanked", false))
	warden.flanked_target = null

	warden.cover = "none"
	enemies[0].cover = "full"
	act = CombatAI.choose_action(warden, enemies, terrain, cfg, 1, 1)
	_expect("In the open with one action and no good shot: take cover", act["rule"], CombatAI.RULE_TAKE_COVER)
	act = CombatAI.choose_action(warden, enemies, terrain, cfg, 2, 1)
	_check("With two actions, take cover does not apply", act["rule"] != CombatAI.RULE_TAKE_COVER)
	_expect("Poor shots (35% at Full cover) lead to overwatch", act["kind"], "overwatch")
	enemies[0].health = 3
	enemies[0].cover = "none"
	act = CombatAI.choose_action(warden, enemies, terrain, cfg, 1, 1)
	_expect("Finish off comes before take cover", act["rule"], CombatAI.RULE_FINISH_OFF)
	enemies[0].health = 8

	var d := _setup(["vessel", "drone"], ["assault_rifle"])
	var vessel: CombatUnit = d["inv"][0]
	var drone: CombatUnit = d["inv"][1]
	vessel.health = 2
	act = CombatAI.choose_action(drone, d["def"], d["terrain"], cfg, 2, 1)
	_expect("Drone repairs an ally below half Health", act["kind"], "repair")
	drone.repairs_left = 0
	_check("No repairs left: no repair", CombatAI.choose_action(drone, d["def"], d["terrain"], cfg, 2, 1)["kind"] != "repair")

	var h := _setup(["warden", "warden", "harrow"], ["assault_rifle"])
	var harrow: CombatUnit = h["inv"][2]
	h["inv"][0].wounded = true
	act = CombatAI.choose_action(harrow, h["def"], h["terrain"], cfg, 2, 1)
	_expect("One troubled ally: no Rally, Mind spike instead", act["kind"], "mind_spike")
	h["inv"][1].morale = 10
	act = CombatAI.choose_action(harrow, h["def"], h["terrain"], cfg, 2, 1)
	_expect("Two troubled allies: Rally", act["kind"], "rally")
	harrow.rally_ready_turn = 3
	_check("Rally not ready: no Rally", CombatAI.choose_action(harrow, h["def"], h["terrain"], cfg, 2, 2)["kind"] != "rally")
	harrow.psionic_this_turn = true
	_check("One Mind spike per turn", CombatAI.choose_action(harrow, h["def"], h["terrain"], cfg, 1, 2)["kind"] != "mind_spike")

	var m := _setup(["warden"], ["machine_gun"])
	var mg: CombatUnit = m["def"][0]
	var target: CombatUnit = m["inv"][0]
	target.cover = "full"
	act = CombatAI.choose_action(mg, m["inv"], m["terrain"], cfg, 2, 1)
	_expect("Machine gunner suppresses a target in cover", act["kind"], "suppress")
	act = CombatAI.choose_action(mg, m["inv"], m["terrain"], cfg, 1, 1)
	_check("Suppression needs both actions", act["kind"] != "suppress")
	target.cover = "none"
	_check("No suppression of targets in the open",
		CombatAI.choose_action(mg, m["inv"], m["terrain"], cfg, 2, 1)["kind"] != "suppress")

	warden.morale = 20
	warden.cover = "half"
	warden.band = "medium"
	_expect("Shaken units move away from the enemy", CombatAI.choose_action(warden, enemies, terrain, cfg, 2, 1)["band"], "long")
	var vessel_s := CombatUnit.from_species("vessel", "Vessel-1", _data)
	vessel_s.morale = 10
	vessel_s.band = "long"
	_expect("Shaken at Long falls back to Medium", CombatRules.away_band(vessel_s), "medium")
	warden.morale = 50

	var sn := _setup(["warden"], ["sniper_rifle"])
	var sniper: CombatUnit = sn["def"][0]
	sn["inv"][0].cover = "full"
	sniper.cover = "half"
	sniper.moved_this_turn = true
	_expect("A sniper that moved holds instead of overwatch",
		CombatAI.choose_action(sniper, sn["inv"], sn["terrain"], cfg, 1, 1)["kind"], "hold")

	var hr := _setup(["strider"], ["assault_rifle"])
	var runner: CombatUnit = hr["inv"][0]
	runner.cover = "half"
	runner.shot_this_turn = true
	_check("Hit and run: no overwatch after shooting",
		CombatAI.choose_action(runner, hr["def"], hr["terrain"], cfg, 1, 1)["kind"] != "overwatch")

	var b := _setup(["bulwark"], ["assault_rifle"])
	b["def"][0].cover = "full"
	b["inv"][0].band = "close"
	act = CombatAI.choose_action(b["inv"][0], b["def"], b["terrain"], cfg, 2, 1)
	_check("Bulwark never goes on overwatch", act["kind"] != "overwatch")

	var r := _setup(["strider"], ["assault_rifle"])
	var strider: CombatUnit = r["inv"][0]
	strider.band = "long"
	var plan := CombatAI.best_plan(strider, r["def"], r["terrain"], cfg, 2)
	_expect("Strider at Long plans to move closer first", plan["plan"], CombatAI.PLAN_MOVE)
	_expect("... to Medium", plan["band"], "medium")


func _test_battle_invariants() -> void:
	var cfg := _data.combat
	for id in Scenarios.ids(_data):
		for seed_value in range(1, 151):
			var result := Scenarios.build(id, _data, seed_value).run()
			var label := "%s %d" % [id, seed_value]
			var out := {}
			var flanked_ok := {}
			var turn := ""
			var side := ""
			for event: Dictionary in result["events"]:
				var type := String(event["type"])
				if type == "turn":
					turn = "%d-%s" % [event["round"], event["side"]]
					side = String(event["side"])
					flanked_ok = {}
					continue
				var actor := String(event.get("attacker", event.get("unit", "")))
				if type in ["attack", "move", "flank", "hunker", "overwatch", "suppress", "repair", "rally", "mind_spike"]:
					_check("%s: %s acts only while able to fight" % [label, actor], not out.has(actor))
				if type == "flank" and event["success"]:
					flanked_ok["%s>%s" % [event["unit"], event["target"]]] = true
				if type == "attack":
					_check("%s: %s is not shot after leaving the fight" % [label, event["target"]], not out.has(String(event["target"])))
					if event["flanked"]:
						_check("%s: flanked shot follows a successful flank" % label,
							flanked_ok.has("%s>%s" % [event["attacker"], event["target"]]))
					if event.get("reaction", false):
						_check("%s: reaction shots never crit" % label, not event.get("crit", false))
					else:
						var shaken := false
						for part: Array in event["hit_parts"]:
							if String(part[0]) == "shaken":
								shaken = true
						_check("%s: Shaken units take no normal shots" % label, not shaken)
					if event.has("outcome"):
						out[String(event["target"])] = true
				if type == "morale":
					for change: Dictionary in event["changes"]:
						if change.get("broke", false):
							out[String(change["unit"])] = true

			var killed := 0
			var downed := 0
			var fled := 0
			for unit: Dictionary in result["invaders"] + result["defenders"]:
				match int(unit["state"]):
					CombatUnit.State.DEAD:
						killed += 1
					CombatUnit.State.DOWNED:
						downed += 1
					CombatUnit.State.FLED:
						fled += 1
			var killed_log := 0
			var downed_log := 0
			var fled_log := 0
			for event: Dictionary in result["events"]:
				match String(event.get("outcome", "")):
					"dead":
						killed_log += 1
					"downed":
						downed_log += 1
				if event["type"] == "morale":
					for change: Dictionary in event["changes"]:
						if change.get("broke", false):
							fled_log += 1
			_expect("%s: kills in the log match the final count" % label, killed_log, killed)
			_expect("%s: downed in the log match the final count" % label, downed_log, downed)
			_expect("%s: breaks in the log match the fled count" % label, fled_log, fled)

			if String(result["end_reason"]) == "no enemy able to fight":
				var losers: Array = result["defenders"] if result["holder"] == "invader" else result["invaders"]
				for unit: Dictionary in losers:
					_check("%s: losing side has nobody able to fight" % label, int(unit["state"]) != CombatUnit.State.ACTIVE)


func _test_withdrawal_and_recovery() -> void:
	var withdrawals := 0
	var recoveries := 0
	for seed_value in range(1, 301):
		for id: String in ["squad", "wardens_squad_urban", "vessels_squad_farmland"]:
			var result := Scenarios.build(id, _data, seed_value).run()
			var label := "%s %d" % [id, seed_value]
			var w := String(result["withdrew"])
			if w != "":
				withdrawals += 1
				var units: Array = result["invaders"] if w == "invader" else result["defenders"]
				var foes: Array = result["defenders"] if w == "invader" else result["invaders"]
				var active := 0
				for unit: Dictionary in units:
					if int(unit["state"]) == CombatUnit.State.ACTIVE:
						active += 1
				var foe_active := 0
				for unit: Dictionary in foes:
					if int(unit["state"]) == CombatUnit.State.ACTIVE:
						foe_active += 1
				_check("%s: withdrew after losing half" % label, (units.size() - active) * 2 >= units.size())
				_check("%s: withdrew when outnumbered 2 to 1" % label, foe_active >= 2 * active)
				_check("%s: the other side holds the field" % label, result["holder"] != w)
			for unit: Dictionary in result["invaders"]:
				if unit["recovered"]:
					recoveries += 1
					_expect("%s: recovery only when invaders hold the field" % label, result["holder"], "invader")
					_expect("%s: only the dead are recovered" % label, int(unit["state"]), CombatUnit.State.DEAD)
	_check("Withdrawals happen", withdrawals > 0)
	_check("Recoveries happen", recoveries > 0)

	for seed_value in range(1, 101):
		var cautious := Scenarios.matchup(_data, seed_value, "four_wardens", "strike_team", "urban", Battle.STANCE_CAUTIOUS)
		var result := cautious.run()
		var dead := 0
		for unit: Dictionary in result["invaders"]:
			if int(unit["state"]) == CombatUnit.State.DEAD:
				dead += 1
		if dead > 0 and result["holder"] == "defender" and String(result["end_reason"]) != "no enemy able to fight":
			_expect("Cautious: a death leads to withdrawal (seed %d)" % seed_value, result["withdrew"], "invader")
		if result["withdrew"] == "invader":
			_check("Cautious withdraws only after a death (seed %d)" % seed_value, dead >= 1)
		var all_in := Scenarios.matchup(_data, seed_value, "four_wardens", "strike_team", "urban", Battle.STANCE_ALL_IN).run()
		_check("All-in never withdraws (seed %d)" % seed_value, all_in["withdrew"] != "invader")
