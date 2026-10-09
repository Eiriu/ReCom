extends SceneTree
## Fights many duels without a window and prints win rates.
## An early version of the slice 1.6 batch runner.
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
	var stats := {
		"invader": {"battles": 0, "invader_wins": 0, "rounds": 0},
		"defender": {"battles": 0, "invader_wins": 0, "rounds": 0},
	}
	var round_limit_endings := 0
	var captures := 0

	for seed_value in range(start, start + count):
		var result := Scenarios.duel(data, seed_value).run()
		var bucket: Dictionary = stats[result["first_side"]]
		bucket["battles"] += 1
		bucket["rounds"] += int(result["rounds"])
		if result["holder"] == CombatUnit.SIDE_INVADER:
			bucket["invader_wins"] += 1
			for unit: Dictionary in result["defenders"]:
				if int(unit["state"]) == CombatUnit.State.DOWNED:
					captures += 1
		if String(result["end_reason"]).begins_with("round limit"):
			round_limit_endings += 1

	var total_battles := count
	var total_wins := int(stats["invader"]["invader_wins"]) + int(stats["defender"]["invader_wins"])
	var total_rounds := int(stats["invader"]["rounds"]) + int(stats["defender"]["rounds"])

	print("Duels: seeds %d-%d (%d battles)" % [start, start + count - 1, count])
	print("")
	print("%-22s %8s %12s %12s" % ["", "Battles", "Warden wins", "Avg rounds"])
	_row("Warden shoots first", stats["invader"])
	_row("Regular shoots first", stats["defender"])
	_row("All", {"battles": total_battles, "invader_wins": total_wins, "rounds": total_rounds})
	print("")
	print("Regular captured (downed) in %d of %d Warden wins" % [captures, total_wins])
	print("Ended by round limit: %d" % round_limit_endings)
	quit()


func _row(label: String, bucket: Dictionary) -> void:
	var battles := int(bucket["battles"])
	if battles == 0:
		print("%-22s %8d %12s %12s" % [label, 0, "-", "-"])
		return
	var wins := int(bucket["invader_wins"])
	print("%-22s %8d %11.1f%% %12.1f" % [label, battles, 100.0 * wins / battles, float(bucket["rounds"]) / battles])
