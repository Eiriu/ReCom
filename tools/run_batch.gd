extends SceneTree
## Fights many battles without a window and prints win rates and losses.
## An early version of the slice 1.6 batch runner.
##
## Usage (from the project folder):
##   godot --headless --path . --script res://tools/run_batch.gd -- --count=500 --start=1001
##   godot --headless --path . --script res://tools/run_batch.gd -- --scenario=duel --count=500
## Scenarios: squad (default), duel.


func _initialize() -> void:
	var count := 500
	var start := 1
	var scenario := Scenarios.SQUAD
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--start="):
			start = int(arg.trim_prefix("--start="))
		elif arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")

	var data := GameData.load_default()
	var all := _new_bucket()
	var by_first := {"invader": _new_bucket(), "defender": _new_bucket()}
	var by_tree := {"invader": _new_bucket(), "defender": _new_bucket()}
	var round_counts := {}
	var title := ""

	for seed_value in range(start, start + count):
		var result := Scenarios.build(scenario, data, seed_value).run()
		title = String(result["title"])
		var buckets: Array = [all, by_first[result["first_side"]]]
		if not result["feature_sides"].is_empty():
			buckets.append(by_tree[result["feature_sides"][0]])
		for bucket: Dictionary in buckets:
			_add(bucket, result)
		var rounds := int(result["rounds"])
		round_counts[rounds] = int(round_counts.get(rounds, 0)) + 1

	print("%s · seeds %d-%d (%d battles)" % [title, start, start + count - 1, count])
	print("")
	print("%-24s %8s %13s %11s %15s %15s" % ["", "Battles", "Invader wins", "Avg rounds", "Invaders lost", "Defender lost"])
	_row("Invaders go first", by_first["invader"])
	_row("Defender goes first", by_first["defender"])
	_row("Invader behind the tree", by_tree["invader"])
	_row("Defender behind the tree", by_tree["defender"])
	_row("All", all)
	print("")
	print("Invaders lost per WON battle: %.2f (spec target: 1.5 or fewer)" % _ratio(all["invader_losses_in_wins"], all["wins"]))
	print("Defender soldiers captured: %d of %d downed or killed" % [all["captures"], all["defender_losses"]])
	print("Ended by round limit: %d" % all["round_limit"])
	var spread: Array[String] = []
	var keys := round_counts.keys()
	keys.sort()
	for rounds: int in keys:
		spread.append("%d:%d" % [rounds, round_counts[rounds]])
	print("Battle length (rounds:battles): %s" % "  ".join(spread))
	quit()


func _new_bucket() -> Dictionary:
	return {"battles": 0, "wins": 0, "rounds": 0, "invader_losses": 0, "defender_losses": 0,
		"invader_losses_in_wins": 0, "captures": 0, "round_limit": 0}


func _add(bucket: Dictionary, result: Dictionary) -> void:
	var won: bool = result["holder"] == CombatUnit.SIDE_INVADER
	var invader_lost := _out_of_action(result["invaders"])
	var defender_lost := _out_of_action(result["defenders"])
	bucket["battles"] += 1
	bucket["rounds"] += int(result["rounds"])
	bucket["invader_losses"] += invader_lost
	bucket["defender_losses"] += defender_lost
	if won:
		bucket["wins"] += 1
		bucket["invader_losses_in_wins"] += invader_lost
		for unit: Dictionary in result["defenders"]:
			if int(unit["state"]) == CombatUnit.State.DOWNED:
				bucket["captures"] += 1
	if String(result["end_reason"]).begins_with("round limit"):
		bucket["round_limit"] += 1


func _out_of_action(units: Array) -> int:
	var count := 0
	for unit: Dictionary in units:
		if int(unit["state"]) != CombatUnit.State.ACTIVE:
			count += 1
	return count


func _ratio(a: Variant, b: Variant) -> float:
	return 0.0 if int(b) == 0 else float(a) / float(b)


func _row(label: String, bucket: Dictionary) -> void:
	var battles := int(bucket["battles"])
	if battles == 0:
		return
	print("%-24s %8d %12.1f%% %11.1f %15.2f %15.2f" % [label, battles,
		100.0 * int(bucket["wins"]) / battles, _ratio(bucket["rounds"], battles),
		_ratio(bucket["invader_losses"], battles), _ratio(bucket["defender_losses"], battles)])
