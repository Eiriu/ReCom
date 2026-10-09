extends SceneTree
## Fights many duels without a window and prints win rates, split by who shot
## first and who stood behind the tree. An early version of the slice 1.6 runner.
##
## Usage (from the project folder):
##   godot --headless --path . --script res://tools/run_batch.gd -- --count=500 --start=1001


func _initialize() -> void:
	var count := 500
	var start := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--start="):
			start = int(arg.trim_prefix("--start="))

	var data := GameData.load_default()
	var buckets := {}
	var captures := 0
	var round_limit_endings := 0
	var all := _new_bucket()

	for seed_value in range(start, start + count):
		var result := Scenarios.duel(data, seed_value).run()
		var tree_side := String(result["feature_sides"][0]) if not result["feature_sides"].is_empty() else "none"
		var key := "%s|%s" % [result["first_side"], tree_side]
		if not buckets.has(key):
			buckets[key] = _new_bucket()
		var won: bool = result["holder"] == CombatUnit.SIDE_INVADER
		for bucket: Dictionary in [buckets[key], all]:
			bucket["battles"] += 1
			bucket["rounds"] += int(result["rounds"])
			if won:
				bucket["wins"] += 1
		if won:
			for unit: Dictionary in result["defenders"]:
				if int(unit["state"]) == CombatUnit.State.DOWNED:
					captures += 1
		if String(result["end_reason"]).begins_with("round limit"):
			round_limit_endings += 1

	print("Duels: seeds %d-%d (%d battles)" % [start, start + count - 1, count])
	print("")
	print("%-14s %-16s %8s %12s %11s" % ["First shot", "Behind the tree", "Battles", "Warden wins", "Avg rounds"])
	for first: String in ["invader", "defender"]:
		for tree: String in ["invader", "defender"]:
			_row(_who(first), _who(tree), buckets.get("%s|%s" % [first, tree], _new_bucket()))
	_row("All", "", all)
	print("")
	print("Regular captured (downed) in %d of %d Warden wins" % [captures, all["wins"]])
	print("Ended by round limit: %d" % round_limit_endings)
	quit()


func _new_bucket() -> Dictionary:
	return {"battles": 0, "wins": 0, "rounds": 0}


func _who(side: String) -> String:
	return "Warden" if side == CombatUnit.SIDE_INVADER else "Regular"


func _row(first: String, tree: String, bucket: Dictionary) -> void:
	var battles := int(bucket["battles"])
	if battles == 0:
		print("%-14s %-16s %8d %12s %11s" % [first, tree, 0, "-", "-"])
		return
	print("%-14s %-16s %8d %11.1f%% %11.1f" % [first, tree, battles,
		100.0 * int(bucket["wins"]) / battles, float(bucket["rounds"]) / battles])
