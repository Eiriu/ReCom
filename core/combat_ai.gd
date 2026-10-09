class_name CombatAI
extends RefCounted
## The shared AI decision rules (Combat core spec, "AI decision rules").
## Both sides use them, in the simulation now and on the tactical grid later.
##
## Slice 1.2 covers the shooting rules only:
##   5. Finish off: shoot an enemy it can kill this shot with a hit chance of 50+.
##   8. Best attack: shoot the enemy with the highest expected damage.
## Moving, flanking, overwatch, suppression, Morale and abilities join in later slices.
## Until overwatch exists (slice 1.4), a unit with no attack worth 1.5 still shoots.

const RULE_FINISH_OFF := "finish off"
const RULE_BEST_ATTACK := "best attack"
const RULE_ONLY_OPTION := "best attack, below threshold"


## Picks a target for a unit. Returns {} if no enemy can be shot.
static func choose_shot(unit: CombatUnit, enemies: Array[CombatUnit], cfg: Dictionary) -> Dictionary:
	var ai_cfg: Dictionary = cfg["ai"]
	var finish_min := int(ai_cfg["finish_off_min_hit"])

	var best_finish: Dictionary = {}
	var best_attack: Dictionary = {}
	for index in enemies.size():
		var enemy := enemies[index]
		if not enemy.is_active():
			continue
		var hit := int(CombatRules.hit_chance(unit, enemy, cfg)["chance"])
		var option := {
			"target": enemy,
			"index": index,
			"hit": hit,
			"score": expected_damage(unit, enemy, cfg),
		}
		if hit >= finish_min and can_kill_with_one_hit(unit, enemy, cfg):
			if best_finish.is_empty() or _better_finish(option, best_finish):
				best_finish = option
		if best_attack.is_empty() or _better_attack(option, best_attack):
			best_attack = option

	if not best_finish.is_empty():
		best_finish["rule"] = RULE_FINISH_OFF
		return best_finish
	if best_attack.is_empty():
		return {}
	var below := float(best_attack["score"]) < float(ai_cfg["best_attack_min_score"])
	best_attack["rule"] = RULE_ONLY_OPTION if below else RULE_BEST_ATTACK
	return best_attack


## True if the weapon's best normal (non-crit) roll would take the target to 0.
static func can_kill_with_one_hit(unit: CombatUnit, target: CombatUnit, cfg: Dictionary) -> bool:
	var damage_range: Array = unit.weapon["damage"]
	return CombatRules.damage_from_roll(int(damage_range[1]), false, target.armour, cfg) >= target.health


## Hit chance x average damage, counting crits, never more than the target's
## remaining Health (overkill is worth nothing).
static func expected_damage(unit: CombatUnit, target: CombatUnit, cfg: Dictionary, flanked: bool = false) -> float:
	var hit := int(CombatRules.hit_chance(unit, target, cfg, flanked)["chance"]) / 100.0
	var crit := CombatRules.crit_chance(unit, target, cfg, flanked) / 100.0
	var damage_range: Array = unit.weapon["damage"]
	var low := int(damage_range[0])
	var high := int(damage_range[1])
	var total := 0.0
	for roll in range(low, high + 1):
		var normal := mini(target.health, CombatRules.damage_from_roll(roll, false, target.armour, cfg))
		var critical := mini(target.health, CombatRules.damage_from_roll(roll, true, target.armour, cfg))
		total += (1.0 - crit) * normal + crit * critical
	return hit * total / (high - low + 1)


## Finish off: highest hit chance, then lowest Health, then roster order.
static func _better_finish(a: Dictionary, b: Dictionary) -> bool:
	if a["hit"] != b["hit"]:
		return a["hit"] > b["hit"]
	var a_health: int = a["target"].health
	var b_health: int = b["target"].health
	if a_health != b_health:
		return a_health < b_health
	return a["index"] < b["index"]


## Best attack: highest expected damage, then hit chance, then roster order.
static func _better_attack(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["score"]), float(b["score"])):
		return float(a["score"]) > float(b["score"])
	if a["hit"] != b["hit"]:
		return a["hit"] > b["hit"]
	return a["index"] < b["index"]
