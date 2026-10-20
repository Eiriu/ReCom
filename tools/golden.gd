extends SceneTree
## Replays a fixed set of battles and compares each report with the saved copy
## in tests/golden/. Use it after every change to see exactly which battles moved.
##
## Usage (from the project folder):
##   godot --headless --path . --script res://tools/golden.gd                 check
##   godot --headless --path . --script res://tools/golden.gd -- --diff       check and show changed lines
##   godot --headless --path . --script res://tools/golden.gd -- --record     save the current reports as the new golden copies
##
## How to read the result:
##   SAME     the battle is identical to the saved copy.
##   CHANGED  something in the battle moved. A small change should move a few
##            shots in a few battles. If every battle is rewritten, look closer.
## Golden copies change on purpose whenever you change a rule: after you have
## looked at the differences and are happy, run --record and commit the new files.

const GOLDEN_DIR := "res://tests/golden"
const CASES := [
	{"scenario": "squad", "seeds": [1, 2, 3, 7, 42, 100, 1001, 48213]},
	{"scenario": "duel", "seeds": [1, 2, 3, 4]},
]
const MAX_DIFF_LINES := 12


func _initialize() -> void:
	var record := false
	var show_diff := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--record":
			record = true
		elif arg == "--diff":
			show_diff = true

	var data := GameData.load_default()
	var dir := ProjectSettings.globalize_path(GOLDEN_DIR)
	DirAccess.make_dir_recursive_absolute(dir)

	var same := 0
	var changed := 0
	var missing := 0
	var broken_replay := 0

	for entry: Dictionary in CASES:
		var scenario := String(entry["scenario"])
		for seed_value: int in entry["seeds"]:
			var report := _report(scenario, data, seed_value)
			# The same seed must always give the same battle.
			if report != _report(scenario, data, seed_value):
				print("REPLAY BROKEN  %s seed %d: two runs of the same seed differ" % [scenario, seed_value])
				broken_replay += 1
				continue
			var path := "%s/%s_%d.txt" % [dir, scenario, seed_value]
			var label := "%s seed %d" % [scenario, seed_value]
			if record:
				_write(path, report)
				print("recorded  %s" % label)
				continue
			if not FileAccess.file_exists(path):
				print("MISSING   %s (run with --record to create it)" % label)
				missing += 1
				continue
			var saved := FileAccess.get_file_as_string(path)
			if saved == report:
				print("SAME      %s" % label)
				same += 1
			else:
				changed += 1
				print("CHANGED   %s  %s" % [label, _describe(saved, report, show_diff)])

	if record:
		print("\nSaved golden copies in tests/golden/. Commit them together with the change.")
	else:
		print("\n%d same, %d changed, %d missing" % [same, changed, missing])
		if changed == 0 and missing == 0 and broken_replay == 0:
			print("Every golden battle is identical: this change did not touch any of them.")
	quit(1 if broken_replay > 0 else 0)


func _report(scenario: String, data: GameData, seed_value: int) -> String:
	var result := Scenarios.build(scenario, data, seed_value).run()
	return BattleReport.format(result, BattleReport.Level.FULL)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## One-line summary of how a battle moved, plus the changed lines when asked.
func _describe(saved: String, now: String, show_diff: bool) -> String:
	var old_lines := saved.split("\n")
	var new_lines := now.split("\n")
	var total := maxi(old_lines.size(), new_lines.size())
	var differing: Array[int] = []
	for i in total:
		var a := old_lines[i] if i < old_lines.size() else ""
		var b := new_lines[i] if i < new_lines.size() else ""
		if a != b:
			differing.append(i)
	var text := "%d of %d lines differ, first at line %d" % [differing.size(), total, differing[0] + 1]
	if show_diff:
		for n in mini(differing.size(), MAX_DIFF_LINES):
			var i := differing[n]
			text += "\n            line %d" % (i + 1)
			text += "\n              was: %s" % (old_lines[i] if i < old_lines.size() else "(none)")
			text += "\n              now: %s" % (new_lines[i] if i < new_lines.size() else "(none)")
		if differing.size() > MAX_DIFF_LINES:
			text += "\n            ... and %d more lines" % (differing.size() - MAX_DIFF_LINES)
	return text
