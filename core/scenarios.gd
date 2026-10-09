class_name Scenarios
extends RefCounted
## Ready-made battles for testing. Both the screen and the headless runner use
## these, so they always fight exactly the same setup.


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
