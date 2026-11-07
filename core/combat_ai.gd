class_name CombatAI
extends RefCounted
## The shared AI decision rules (Combat core spec, "AI decision rules").
## Both sides use them, in the simulation now and on the tactical grid later.
## For each action, a unit takes the first rule that applies:
##   1. Broken: flee. (Breaking happens the moment Morale reaches 0, see CombatRules.)
##   2. Shaken: move away for better cover; in Full cover, hunker down.
##   3. Follow through: if it flanked (or moved for a shot) this turn, shoot.
##   4. Support: a Drone repairs a badly hurt ally; a Harrow Rallies shaken or wounded allies.
##   5. Finish off: shoot an enemy it can kill this shot at 50% or better.
##   6. Take cover: in no cover with one action left, move.
##   7. Psionics: a Harrow uses Mind spike on the highest-Aim enemy at 50% or better.
##   8. Best attack: shoot now, flank then shoot, or move then shoot, if worth 1.5+.
##   9. Suppress: a machine gunner suppresses the highest-Aim enemy in cover.
##  10. Wait: go on overwatch (or hold, if the unit may not shoot again this turn).
##
## Returns an action: {"kind": ..., "rule": ..., plus "target", "band" or "flanked"}.
## Kinds: shoot, move, flank, hunker, repair, rally, mind_spike, suppress, overwatch, hold.

const RULE_SHAKEN := "shaken"
const RULE_FOLLOW_THROUGH := "follow through"
const RULE_SUPPORT := "support"
const RULE_FINISH_OFF := "finish off"
const RULE_TAKE_COVER := "take cover"
const RULE_PSIONICS := "psionics"
const RULE_BEST_ATTACK := "best attack"
const RULE_SUPPRESS := "suppress"
const RULE_WAIT := "wait"

const PLAN_SHOOT := "shoot now"
const PLAN_MOVE := "move then shoot"
const PLAN_FLANK := "flank then shoot"


## side_turn: how many turns the unit's side has started, for Rally's cooldown.
static func choose_action(unit: CombatUnit, enemies: Array[CombatUnit], terrain: Dictionary,
		cfg: Dictionary, actions_left: int, side_turn: int) -> Dictionary:
	var ai: Dictionary = cfg["ai"]
	var targets := _active(enemies)
	if targets.is_empty() or not unit.is_active():
		return {"kind": "hold", "rule": RULE_WAIT}

	# 2. Shaken
	if unit.is_shaken(cfg):
		if unit.effective_cover() == "full":
			return {"kind": "hunker", "rule": RULE_SHAKEN}
		return {"kind": "move", "band": CombatRules.away_band(unit), "rule": RULE_SHAKEN}

	# 3. Follow through
	if unit.can_shoot():
		if unit.flanked_target != null and unit.flanked_target.is_active():
			return {"kind": "shoot", "target": unit.flanked_target, "flanked": true, "rule": RULE_FOLLOW_THROUGH}
		if unit.planned_shot:
			var follow := _best_shot(unit, targets, cfg)
			follow["kind"] = "shoot"
			follow["rule"] = RULE_FOLLOW_THROUGH
			return follow

	# 4. Support
	if unit.has_ability("repair") and unit.repairs_left > 0:
		var patient := _repair_target(unit)
		if patient != null:
			return {"kind": "repair", "target": patient, "rule": RULE_SUPPORT}
	if unit.has_ability("rally") and side_turn >= unit.rally_ready_turn:
		var troubled := 0
		for ally in unit.squad:
			if ally != unit and ally.is_active() and (ally.is_shaken(cfg) or ally.wounded):
				troubled += 1
		if troubled >= int(ai["rally_min_allies"]):
			return {"kind": "rally", "rule": RULE_SUPPORT}

	# 5. Finish off
	if unit.can_shoot():
		var finish := _finish_off(unit, targets, cfg)
		if not finish.is_empty():
			finish["kind"] = "shoot"
			finish["rule"] = RULE_FINISH_OFF
			return finish

	# 6. Take cover
	if unit.cover == "none" and not unit.hunkered and actions_left == 1:
		return {"kind": "move", "band": CombatRules.retreat_band(unit, cfg), "rule": RULE_TAKE_COVER}

	# 7. Psionics
	if unit.has_ability("mind_spike") and not unit.psionic_this_turn:
		var mark := _highest_aim(targets, false)
		if mark != null:
			var chance := CombatRules.mind_spike_chance(unit, mark, cfg)
			if chance >= int(ai["mind_spike_min_chance"]):
				return {"kind": "mind_spike", "target": mark, "chance": chance, "rule": RULE_PSIONICS}

	# 8. Best attack
	var plan := best_plan(unit, targets, terrain, cfg, actions_left)
	if not plan.is_empty() and float(plan["score"]) >= float(ai["best_attack_min_score"]):
		plan["rule"] = RULE_BEST_ATTACK
		match String(plan["plan"]):
			PLAN_SHOOT:
				plan["kind"] = "shoot"
			PLAN_MOVE:
				plan["kind"] = "move"
			PLAN_FLANK:
				plan["kind"] = "flank"
		return plan

	# 9. Suppress
	if unit.has_tag("suppress") and actions_left >= 2 and unit.can_shoot():
		var pinned := _highest_aim(targets, true)
		if pinned != null:
			return {"kind": "suppress", "target": pinned, "rule": RULE_SUPPRESS}

	# 10. Wait. Overwatch is a shot, so no overwatch for weapons that cannot
	# overwatch, for snipers after a move, or after this turn's shot (Hit and run).
	if unit.has_tag("no_overwatch") or unit.shot_this_turn or not unit.can_shoot():
		return {"kind": "hold", "rule": RULE_WAIT}
	return {"kind": "overwatch", "rule": RULE_WAIT}


## Compares every plan the remaining actions allow and returns the best:
## {"plan", "score", "target", and "band" for a move}. Scores are expected damage:
## chance the move works (1 for a plain move) x hit chance x average damage with crits.
## Ties prefer shooting now, then moving, then flanking, then roster order.
static func best_plan(unit: CombatUnit, targets: Array[CombatUnit], terrain: Dictionary,
		cfg: Dictionary, actions_left: int) -> Dictionary:
	var best: Dictionary = {}
	if unit.can_shoot():
		for index in targets.size():
			var target := targets[index]
			best = _keep_better(best, {"plan": PLAN_SHOOT, "target": target, "index": index,
				"score": expected_damage(unit, target, cfg)})
	if actions_left >= 2 and unit.can_shoot() and not unit.has_tag("no_move_and_fire"):
		var home := unit.band
		for band in CombatRules.neighbour_bands(home):
			unit.band = band
			for index in targets.size():
				best = _keep_better(best, {"plan": PLAN_MOVE, "target": targets[index], "index": index,
					"band": band, "score": expected_damage(unit, targets[index], cfg)})
			unit.band = home
	if actions_left >= 2 and unit.can_shoot():
		var flank := float(CombatRules.flank_chance(unit, terrain, cfg)["chance"]) / 100.0
		# With ai.flank_counts_fallback_shot, a failed flank is scored as the plain shot
		# the unit still gets; without it (the spec's wording) a failed flank scores 0.
		var fallback: bool = cfg["ai"].get("flank_counts_fallback_shot", false)
		for index in targets.size():
			var target := targets[index]
			var score := flank * expected_damage(unit, target, cfg, {"flanked": true})
			if fallback:
				score += (1.0 - flank) * expected_damage(unit, target, cfg)
			best = _keep_better(best, {"plan": PLAN_FLANK, "target": target, "index": index,
				"flank_chance": int(round(flank * 100.0)), "score": score})
	return best


## Hit chance x average damage, counting crits (the spec's scoring). With
## ai.cap_damage_at_health, damage beyond the target's remaining Health counts
## for nothing (slice 1.2 did this; it makes nearly dead enemies unattractive).
static func expected_damage(unit: CombatUnit, target: CombatUnit, cfg: Dictionary, opts: Dictionary = {}) -> float:
	var flanked: bool = opts.get("flanked", false)
	var cap := target.health if cfg["ai"].get("cap_damage_at_health", false) else 9999
	var hit := int(CombatRules.hit_chance(unit, target, cfg, opts)["chance"]) / 100.0
	var crit := CombatRules.crit_chance(unit, target, cfg, flanked, opts.get("reaction", false)) / 100.0
	var damage_range: Array = unit.weapon["damage"]
	var low := int(damage_range[0])
	var high := int(damage_range[1])
	var total := 0.0
	for roll in range(low, high + 1):
		var normal := mini(cap, CombatRules.damage_from_roll(roll, false, target.armour, cfg))
		var critical := mini(cap, CombatRules.damage_from_roll(roll, true, target.armour, cfg))
		total += (1.0 - crit) * normal + crit * critical
	return hit * total / (high - low + 1)


## True if the weapon's best normal (non-crit) roll would take the target to 0.
static func can_kill_with_one_hit(unit: CombatUnit, target: CombatUnit, cfg: Dictionary) -> bool:
	var damage_range: Array = unit.weapon["damage"]
	return CombatRules.damage_from_roll(int(damage_range[1]), false, target.armour, cfg) >= target.health


## Kept from slice 1.2 for tests and tools: the shot this unit would take now.
static func choose_shot(unit: CombatUnit, enemies: Array[CombatUnit], cfg: Dictionary) -> Dictionary:
	var targets := _active(enemies)
	if targets.is_empty():
		return {}
	var finish := _finish_off(unit, targets, cfg)
	if not finish.is_empty():
		finish["rule"] = RULE_FINISH_OFF
		return finish
	var shot := _best_shot(unit, targets, cfg)
	shot["rule"] = RULE_BEST_ATTACK
	return shot


static func _finish_off(unit: CombatUnit, targets: Array[CombatUnit], cfg: Dictionary) -> Dictionary:
	var finish_min := int(cfg["ai"]["finish_off_min_hit"])
	var best: Dictionary = {}
	for index in targets.size():
		var enemy := targets[index]
		var hit := int(CombatRules.hit_chance(unit, enemy, cfg)["chance"])
		if hit < finish_min or not can_kill_with_one_hit(unit, enemy, cfg):
			continue
		var option := {"target": enemy, "index": index, "hit": hit}
		if best.is_empty() or _better_finish(option, best):
			best = option
	return best


static func _best_shot(unit: CombatUnit, targets: Array[CombatUnit], cfg: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for index in targets.size():
		best = _keep_better(best, {"plan": PLAN_SHOOT, "target": targets[index], "index": index,
			"score": expected_damage(unit, targets[index], cfg)})
	return best


## The other ally below half Health with the lowest Health share; ties in roster order.
static func _repair_target(unit: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	for ally in unit.squad:
		if ally == unit or not ally.is_active() or not ally.below_half_health():
			continue
		if best == null or ally.health * best.max_health < best.health * ally.max_health:
			best = ally
	return best


## Highest base Aim; ties in roster order. in_cover_only: only Full or Half cover
## (suppression) and skip targets already suppressed. Otherwise only units with Morale.
static func _highest_aim(targets: Array[CombatUnit], in_cover_only: bool) -> CombatUnit:
	var best: CombatUnit = null
	for enemy in targets:
		if in_cover_only:
			if enemy.effective_cover() == "none" or enemy.suppressed_by != null:
				continue
		elif enemy.is_machine():
			continue
		if best == null or enemy.aim > best.aim:
			best = enemy
	return best


static func _active(units: Array[CombatUnit]) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for unit in units:
		if unit.is_active():
			out.append(unit)
	return out


const _PLAN_ORDER := {PLAN_SHOOT: 0, PLAN_MOVE: 1, PLAN_FLANK: 2}


static func _keep_better(best: Dictionary, option: Dictionary) -> Dictionary:
	if best.is_empty():
		return option
	var a := float(option["score"])
	var b := float(best["score"])
	if not is_equal_approx(a, b):
		return option if a > b else best
	if _PLAN_ORDER[option["plan"]] != _PLAN_ORDER[best["plan"]]:
		return option if _PLAN_ORDER[option["plan"]] < _PLAN_ORDER[best["plan"]] else best
	return option if int(option["index"]) < int(best["index"]) else best


## Finish off: highest hit chance, then lowest Health, then roster order.
static func _better_finish(a: Dictionary, b: Dictionary) -> bool:
	if a["hit"] != b["hit"]:
		return a["hit"] > b["hit"]
	var a_health: int = a["target"].health
	var b_health: int = b["target"].health
	if a_health != b_health:
		return a_health < b_health
	return a["index"] < b["index"]
