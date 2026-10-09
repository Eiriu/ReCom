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
	_expect("Flanked ignores cover", CombatRules.hit_chance(warden, rifle, cfg, true)["chance"], 75)
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
	var first := BattleReport.format(Scenarios.duel(_data, 48213).run())
	var second := BattleReport.format(Scenarios.duel(_data, 48213).run())
	_check("Same seed gives the same battle", first == second)

	var distinct := {}
	for seed_value in range(1, 11):
		distinct[BattleReport.format(Scenarios.duel(_data, seed_value).run())] = true
	_check("Different seeds give different battles", distinct.size() > 5, "(%d distinct of 10)" % distinct.size())

	var first_sides := {}
	for seed_value in range(1, 51):
		first_sides[Scenarios.duel(_data, seed_value).run()["first_side"]] = true
	_check("Both sides sometimes shoot first", first_sides.size() == 2)

	var tree_sides := {}
	for seed_value in range(1, 51):
		var battle := Scenarios.duel(_data, seed_value)
		var result := battle.run()
		var behind := 0
		for unit in battle.invaders + battle.defenders:
			if unit.cover == "half":
				behind += 1
		_expect("Seed %d: exactly one unit behind the tree" % seed_value, behind, 1)
		tree_sides[result["feature_sides"][0]] = true
	_check("Both sides sometimes get the tree", tree_sides.size() == 2)

	var fixed := Scenarios.duel(_data, 5)
	fixed.first_side = CombatUnit.SIDE_DEFENDER
	_expect("A fixed first side is respected", fixed.run()["first_side"], CombatUnit.SIDE_DEFENDER)


func _test_battles_end() -> void:
	var limit := int(_data.combat["round_limit"])
	var invader_wins := 0
	var total := 1000
	for seed_value in range(1, total + 1):
		var result := Scenarios.duel(_data, seed_value).run()
		_check("Battle %d ends within the round limit" % seed_value, int(result["rounds"]) <= limit)
		_check("Battle %d has a side holding the field" % seed_value, String(result["holder"]) != "")
		if result["holder"] == "invader":
			invader_wins += 1
	print("Duel: Warden wins %d of %d (%.1f%%)" % [invader_wins, total, 100.0 * invader_wins / total])
