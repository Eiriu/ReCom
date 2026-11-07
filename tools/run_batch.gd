extends SceneTree
## Slice 1.6 batch runner: fights many battles per matchup and compares the
## invader win rate with the spec's balance targets (data/matchups.json).
##
## Usage (from the project folder):
##   godot --headless --path . --script res://tools/run_batch.gd                         every matchup with a target
##   godot --headless --path . --script res://tools/run_batch.gd -- --count=2000 --start=1001
##   godot --headless --path . --script res://tools/run_batch.gd -- --matchup=mixed_forest
##   godot --headless --path . --script res://tools/run_batch.gd -- --all                 also the test-only matchups
##   godot --headless --path . --script res://tools/run_batch.gd -- --detail              extra rows per matchup
##
## A result outside its target means a number in the data files needs tuning;
## the rules themselves do not change (Combat core spec, Balance targets).

const LENGTH_TARGET := [4.0, 8.0]
const LOSS_TARGET := 1.5


func _initialize() -> void:
	var count := 1000
	var start := 1
	var only := ""
	var include_all := false
	var detail := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--start="):
			start = int(arg.trim_prefix("--start="))
		elif arg.begins_with("--matchup="):
			only = arg.trim_prefix("--matchup=")
		elif arg == "--all":
			include_all = true
		elif arg == "--detail":
			detail = true

	var data := GameData.load_default()
	var ids: Array[String] = []
	if only != "":
		ids.append(only)
	elif include_all:
		ids = Scenarios.ids(data)
	else:
		ids = Scenarios.target_ids(data)

	print("%d battles per matchup, seeds %d-%d\n" % [count, start, start + count - 1])
	print("%-58s %9s %9s %7s %8s %9s" % ["Matchup", "Inv. win", "Target", "", "Rounds", "Lost/win"])
	var stats_by_id := {}
	for id in ids:
		var stats := measure(id, data, start, count)
		stats_by_id[id] = stats
		var target := _target(id, data)
		var verdict := ""
		if not target.is_empty():
			var rate := float(stats["win_rate"])
			if rate < float(target[0]):
				verdict = "LOW"
			elif rate > float(target[1]):
				verdict = "HIGH"
			else:
				verdict = "ok"
		print("%-58s %8.1f%% %9s %7s %8.1f %9.2f" % [Scenarios.display_name(id, data).left(58),
			stats["win_rate"], "%d–%d%%" % [target[0], target[1]] if not target.is_empty() else "—", verdict,
			stats["avg_rounds"], stats["lost_per_win"]])

	print("\nTargets for every matchup: %d–%d rounds on average, %.1f or fewer invaders lost per won battle." % [
		LENGTH_TARGET[0], LENGTH_TARGET[1], LOSS_TARGET])
	print("Lost/win counts invaders killed and not recovered; units that fled survive.")

	if detail:
		for id in ids:
			_print_detail(Scenarios.display_name(id, data), stats_by_id[id])
	quit()


static func _target(id: String, data: GameData) -> Array:
	if id == Scenarios.DUEL:
		return []
	return data.matchup_entry(id).get("target", [])


## Fights the battles and adds up everything the table and details show.
static func measure(id: String, data: GameData, start: int, count: int) -> Dictionary:
	var s := {"battles": 0, "wins": 0, "rounds": 0, "lost_in_wins": 0, "captures": 0, "round_limit": 0,
		"invader_withdrew": 0, "defender_withdrew": 0, "fled": {"invader": 0, "defender": 0},
		"recovered": 0, "flanks": {}, "actions": {}}
	for seed_value in range(start, start + count):
		var result := Scenarios.build(id, data, seed_value).run()
		var won: bool = result["holder"] == CombatUnit.SIDE_INVADER
		s["battles"] += 1
		s["rounds"] += int(result["rounds"])
		if won:
			s["wins"] += 1
			for unit: Dictionary in result["invaders"]:
				if int(unit["state"]) == CombatUnit.State.DEAD and not unit["recovered"]:
					s["lost_in_wins"] += 1
				if unit["recovered"]:
					s["recovered"] += 1
			for unit: Dictionary in result["defenders"]:
				if int(unit["state"]) == CombatUnit.State.DOWNED:
					s["captures"] += 1
		if String(result["end_reason"]).begins_with("round limit"):
			s["round_limit"] += 1
		match String(result["withdrew"]):
			"invader":
				s["invader_withdrew"] += 1
			"defender":
				s["defender_withdrew"] += 1
		for side_key: String in ["invaders", "defenders"]:
			for unit: Dictionary in result[side_key]:
				if int(unit["state"]) == CombatUnit.State.FLED:
					s["fled"]["invader" if side_key == "invaders" else "defender"] += 1
		var kinds := {}
		for unit: Dictionary in result["invaders"] + result["defenders"]:
			kinds[unit["name"]] = unit["kind_name"]
		for event: Dictionary in result["events"]:
			var type := String(event["type"])
			if type == "flank":
				var kind := String(kinds.get(event["unit"], "?"))
				var f: Array = s["flanks"].get(kind, [0, 0])
				f[0] += 1
				f[1] += 1 if event["success"] else 0
				s["flanks"][kind] = f
			if type in ["move", "flank", "hunker", "overwatch", "suppress", "repair", "rally", "mind_spike", "hold"] \
					or (type == "attack" and not event.get("reaction", false)):
				s["actions"][type] = int(s["actions"].get(type, 0)) + 1
			if type == "attack" and event.get("reaction", false):
				s["actions"]["reaction shot"] = int(s["actions"].get("reaction shot", 0)) + 1
	var n := float(s["battles"])
	s["win_rate"] = 100.0 * s["wins"] / n
	s["avg_rounds"] = s["rounds"] / n
	s["lost_per_win"] = 0.0 if s["wins"] == 0 else float(s["lost_in_wins"]) / s["wins"]
	return s


static func _print_detail(title: String, s: Dictionary) -> void:
	var n := float(s["battles"])
	print("\n%s" % title)
	print("  Ended by round limit %.1f%% · invaders withdrew %.1f%% · Defender withdrew %.1f%%" % [
		100.0 * s["round_limit"] / n, 100.0 * s["invader_withdrew"] / n, 100.0 * s["defender_withdrew"] / n])
	print("  Fled per battle: invaders %.2f, Defender %.2f · captured per won battle %.2f · recovered alive per won battle %.2f" % [
		s["fled"]["invader"] / n, s["fled"]["defender"] / n,
		0.0 if s["wins"] == 0 else float(s["captures"]) / s["wins"],
		0.0 if s["wins"] == 0 else float(s["recovered"]) / s["wins"]])
	var flank_parts: Array[String] = []
	for kind: String in s["flanks"]:
		var f: Array = s["flanks"][kind]
		flank_parts.append("%s %.2f per battle (%.0f%% succeed)" % [kind, f[0] / n, 100.0 * f[1] / maxf(1.0, f[0])])
	print("  Flank attempts: %s" % ("none" if flank_parts.is_empty() else ", ".join(flank_parts)))
	var action_parts: Array[String] = []
	for kind: String in s["actions"]:
		action_parts.append("%s %.1f" % ["shot" if kind == "attack" else kind, s["actions"][kind] / n])
	print("  Actions per battle: %s" % ", ".join(action_parts))
