extends SceneTree
## Fights the same batch of battles as the saved baseline and prints what changed.
## One battle cannot show a small rule change; hundreds of battles can.
##
## Usage (from the project folder):
##   godot --headless --path . --script res://tools/compare.gd                          compare with the baseline
##   godot --headless --path . --script res://tools/compare.gd -- --save --note="cover 20 to 25"
##                                                                         save the current numbers as the new baseline
##   godot --headless --path . --script res://tools/compare.gd -- --count=5000          more battles, finer sensitivity
##
## How to read the result:
##   The same seeds are used every time, so a change that does not touch any dice roll
##   gives exactly the same numbers. A small rule change flips only a few shots, so most
##   battles stay the same. The tool compares battle by battle (same seed against same seed),
##   which makes small changes visible. "Winner changed" counts the battles that ended
##   differently. The marker says whether a difference is bigger than chance:
##     **  clearly more than chance
##     *   probably more than chance
##     (blank) within chance: do not read anything into it
## Several rows are measured at once, so one lone "*" can still be luck.
## Save a new baseline only after you have looked at the changes and accepted them.

const BASELINE_PATH := "res://tests/baseline.json"
const SCENARIOS: Array[String] = ["squad", "duel"]
const DEFAULT_COUNT := 1000
const DEFAULT_START := 1
const Z_CLEAR := 3.0
const Z_PROBABLE := 2.0

## Rows measured for every battle, so they can be compared seed against seed.
## Their per-battle values are saved in the baseline (-1 means "not applicable").
const PAIRED: Array[String] = ["invader_win", "invader_win_first", "invader_win_second",
	"rounds", "invaders_lost", "defenders_lost", "round_limit"]

## [key, label, scale, decimals]
const METRICS := [
	["invader_win", "Invader wins (%)", 100.0, 1],
	["invader_win_first", "  when invaders go first (%)", 100.0, 1],
	["invader_win_second", "  when defender goes first (%)", 100.0, 1],
	["rounds", "Battle length (rounds)", 1.0, 2],
	["invaders_lost", "Invaders lost per battle", 1.0, 2],
	["defenders_lost", "Defenders lost per battle", 1.0, 2],
	["invaders_lost_in_win", "Invaders lost per won battle", 1.0, 2],
	["captures_in_win", "Defenders captured per won battle", 1.0, 2],
	["round_limit", "Ended by round limit (%)", 100.0, 1],
]


func _initialize() -> void:
	var save := false
	var note := ""
	var count := -1
	var start := -1
	for arg in OS.get_cmdline_user_args():
		if arg == "--save":
			save = true
		elif arg.begins_with("--note="):
			note = arg.trim_prefix("--note=")
		elif arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--start="):
			start = int(arg.trim_prefix("--start="))

	var data := GameData.load_default()

	if save:
		count = DEFAULT_COUNT if count < 0 else count
		start = DEFAULT_START if start < 0 else start
		var baseline := {"count": count, "start": start, "note": note,
			"saved": Time.get_datetime_string_from_system(), "scenarios": {}}
		for scenario in SCENARIOS:
			baseline["scenarios"][scenario] = _measure(scenario, data, start, count)
		var file := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(baseline, "\t"))
		file.close()
		print("Saved baseline: %d battles per scenario, seeds %d-%d. Commit tests/baseline.json." % [count, start, start + count - 1])
		for scenario in SCENARIOS:
			_print_snapshot(baseline["scenarios"][scenario])
		quit()
		return

	if not FileAccess.file_exists(BASELINE_PATH):
		print("No baseline yet. Run with: -- --save --note=\"what this version is\"")
		quit(1)
		return
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	# Use the baseline's own seeds unless told otherwise, so the comparison is like for like.
	count = int(baseline["count"]) if count < 0 else count
	start = int(baseline["start"]) if start < 0 else start
	print("Comparing %d battles per scenario (seeds %d-%d) with baseline%s" % [
		count, start, start + count - 1,
		" \"%s\" saved %s" % [baseline["note"], baseline["saved"]] if String(baseline["note"]) != "" else " saved %s" % baseline["saved"]])

	var anything_moved := false
	for scenario in SCENARIOS:
		if not baseline["scenarios"].has(scenario):
			print("\n%s: not in the baseline, save a new one." % scenario)
			continue
		var now := _measure(scenario, data, start, count)
		if _print_comparison(baseline["scenarios"][scenario], now):
			anything_moved = true
	if not anything_moved:
		print("\nIdentical to the baseline: this change did not alter any battle outcome.")
	quit()


## Fights the battles and reduces them to
## {title, start, count, metrics: {key: {n, mean, se}}, per_seed: {key: "1,0,-1,..."}}.
func _measure(scenario: String, data: GameData, start: int, count: int) -> Dictionary:
	var acc := {}
	var per_seed := {}
	for key in PAIRED:
		per_seed[key] = []
	var title := ""
	for seed_value in range(start, start + count):
		var result := Scenarios.build(scenario, data, seed_value).run()
		title = String(result["title"])
		var won: bool = result["holder"] == CombatUnit.SIDE_INVADER
		var invaders_lost := _out_of_action(result["invaders"])
		var defenders_lost := _out_of_action(result["defenders"])
		var win_value := 1.0 if won else 0.0
		var invaders_first: bool = result["first_side"] == CombatUnit.SIDE_INVADER
		var limit_value := 1.0 if String(result["end_reason"]).begins_with("round limit") else 0.0
		_add(acc, "invader_win", win_value)
		_add(acc, "invader_win_first" if invaders_first else "invader_win_second", win_value)
		_add(acc, "rounds", float(result["rounds"]))
		_add(acc, "invaders_lost", float(invaders_lost))
		_add(acc, "defenders_lost", float(defenders_lost))
		_add(acc, "round_limit", limit_value)
		per_seed["invader_win"].append(int(win_value))
		per_seed["invader_win_first"].append(int(win_value) if invaders_first else -1)
		per_seed["invader_win_second"].append(-1 if invaders_first else int(win_value))
		per_seed["rounds"].append(int(result["rounds"]))
		per_seed["invaders_lost"].append(invaders_lost)
		per_seed["defenders_lost"].append(defenders_lost)
		per_seed["round_limit"].append(int(limit_value))
		if won:
			_add(acc, "invaders_lost_in_win", float(invaders_lost))
			var captured := 0
			for unit: Dictionary in result["defenders"]:
				if int(unit["state"]) == CombatUnit.State.DOWNED:
					captured += 1
			_add(acc, "captures_in_win", float(captured))

	var metrics := {}
	for key: String in acc:
		var n: float = acc[key][0]
		var mean: float = acc[key][1] / n
		var variance := maxf(0.0, acc[key][2] / n - mean * mean) * n / maxf(1.0, n - 1.0)
		metrics[key] = {"n": int(n), "mean": mean, "se": sqrt(variance / n)}
	# Stored as one compact text per row so the baseline file stays small.
	var packed := {}
	for key in PAIRED:
		packed[key] = ",".join(PackedStringArray(per_seed[key].map(func(v: int) -> String: return str(v))))
	return {"title": title, "start": start, "count": count, "metrics": metrics, "per_seed": packed}


func _add(acc: Dictionary, key: String, value: float) -> void:
	if not acc.has(key):
		acc[key] = [0.0, 0.0, 0.0]
	acc[key][0] += 1.0
	acc[key][1] += value
	acc[key][2] += value * value


func _out_of_action(units: Array) -> int:
	var count := 0
	for unit: Dictionary in units:
		if int(unit["state"]) != CombatUnit.State.ACTIVE:
			count += 1
	return count


func _print_snapshot(snapshot: Dictionary) -> void:
	print("\n%s" % snapshot["title"])
	for spec: Array in METRICS:
		if snapshot["metrics"].has(spec[0]):
			print("  %-36s %*.*f" % [spec[1], 8, spec[3], snapshot["metrics"][spec[0]]["mean"] * spec[2]])
	print("  %-36s %*.*f" % ["First-turn swing (points)", 8, 1, _swing(snapshot["metrics"])["mean"] * 100.0])


## Win rate when invaders go first minus when the defender does: how much going first matters.
func _swing(metrics: Dictionary) -> Dictionary:
	var a: Dictionary = metrics.get("invader_win_first", {"mean": 0.0, "se": 0.0})
	var b: Dictionary = metrics.get("invader_win_second", {"mean": 0.0, "se": 0.0})
	return {"mean": float(a["mean"]) - float(b["mean"]), "se": sqrt(float(a["se"]) ** 2 + float(b["se"]) ** 2)}


## Prints the before/after table. Returns true if any number moved.
func _print_comparison(before: Dictionary, now: Dictionary) -> bool:
	print("\n%s" % now["title"])
	print("  %-36s %9s %9s %9s" % ["", "Baseline", "Now", "Change"])
	var pairable: bool = before.has("per_seed") and int(before["start"]) == int(now["start"]) \
		and int(before["count"]) == int(now["count"])
	var moved := false
	var swing_se_sq := 0.0
	var swing_a := 0.0
	var swing_b := 0.0
	for spec: Array in METRICS:
		var key: String = spec[0]
		if not before["metrics"].has(key) or not now["metrics"].has(key):
			continue
		var a := float(before["metrics"][key]["mean"])
		var b := float(now["metrics"][key]["mean"])
		var se := sqrt(float(before["metrics"][key]["se"]) ** 2 + float(now["metrics"][key]["se"]) ** 2)
		if pairable and key in PAIRED:
			se = _paired_se(String(before["per_seed"][key]), String(now["per_seed"][key]), se)
		if _print_row(spec[1], a, b, se, spec[2], spec[3]):
			moved = true
		if key == "invader_win_first":
			swing_a += a
			swing_b += b
			swing_se_sq += se ** 2
		elif key == "invader_win_second":
			swing_a -= a
			swing_b -= b
			swing_se_sq += se ** 2
	if _print_row("First-turn swing (points)", swing_a, swing_b, sqrt(swing_se_sq), 100.0, 1):
		moved = true
	if pairable:
		var flipped := _count_flipped(String(before["per_seed"]["invader_win"]), String(now["per_seed"]["invader_win"]))
		print("  Winner changed in %d of %d battles" % [flipped, int(now["count"])])
	return moved


## Standard error of the average per-battle difference, comparing the same seeds.
## Battles where a row does not apply (-1) are skipped. Falls back to the plain error if unusable.
func _paired_se(before_text: String, now_text: String, fallback: float) -> float:
	var a := before_text.split(",")
	var b := now_text.split(",")
	if a.size() != b.size():
		return fallback
	var n := 0
	var sum := 0.0
	var sum_sq := 0.0
	for i in a.size():
		var x := int(a[i])
		var y := int(b[i])
		if x < 0 or y < 0:
			continue
		var d := float(y - x)
		n += 1
		sum += d
		sum_sq += d * d
	if n < 2:
		return fallback
	var mean := sum / n
	var variance := maxf(0.0, sum_sq / n - mean * mean) * n / (n - 1.0)
	return sqrt(variance / n)


func _count_flipped(before_text: String, now_text: String) -> int:
	var a := before_text.split(",")
	var b := now_text.split(",")
	var flipped := 0
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			flipped += 1
	return flipped


func _print_row(label: String, before: float, now: float, se: float, scale: float, decimals: int) -> bool:
	var a := before * scale
	var b := now * scale
	var delta := b - a
	var marker := ""
	if se > 0.0:
		var z := absf(delta) / (se * scale)
		marker = "**" if z >= Z_CLEAR else ("*" if z >= Z_PROBABLE else "")
	elif absf(delta) > 0.0000001:
		marker = "**"
	print("  %-36s %9.*f %9.*f %+9.*f  %s" % [label, decimals, a, decimals, b, decimals, delta, marker])
	return absf(delta) > 0.0000001
