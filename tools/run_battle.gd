extends SceneTree
## Runs the slice 1.1 duel without a window and prints the battle report.
##
## Usage (from the project folder):
##   godot --headless --script res://tools/run_battle.gd -- --seed=48213
##   godot --headless --script res://tools/run_battle.gd -- --seed=48213 --summary


func _initialize() -> void:
	var seed_value := 1
	var level := BattleReport.Level.FULL
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg == "--summary":
			level = BattleReport.Level.SUMMARY

	var data := GameData.load_default()
	var result := Scenarios.duel(data, seed_value).run()
	print(BattleReport.format(result, level))
	quit()
