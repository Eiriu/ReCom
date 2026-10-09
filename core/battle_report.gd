class_name BattleReport
extends RefCounted
## Turns a battle result into readable text.
##
## FULL shows every action with its numbers, for checking the rules.
## SUMMARY shows only the setup, result and losses.

enum Level { FULL, SUMMARY }

const SIDE_LABEL := {"invader": "Invaders", "defender": "Defender"}
const BAND_LABEL := {"close": "Close", "medium": "Medium", "long": "Long"}
const COVER_LABEL := {"none": "no cover", "half": "Half cover", "full": "Full cover"}


static func format(result: Dictionary, level: Level = Level.FULL) -> String:
	var lines: Array[String] = []
	var name_width := _name_width(result)

	lines.append("Seed %d · %s · %s" % [result["seed"], result["location"], result["title"]])
	lines.append("")
	_append_roster(lines, "Invaders", result["invaders"], name_width)
	_append_roster(lines, "Defender", result["defenders"], name_width)

	if level == Level.FULL:
		for event: Dictionary in result["events"]:
			match String(event["type"]):
				"turn":
					lines.append("")
					lines.append("Round %d — %s" % [event["round"], SIDE_LABEL[event["side"]]])
				"attack":
					lines.append(_attack_line(event, name_width))

	lines.append("")
	var holder := String(result["holder"])
	lines.append("Result: %s %s the field after round %d (%s)" % [
		SIDE_LABEL[holder], "hold" if holder == "invader" else "holds", result["rounds"], result["end_reason"]])
	_append_losses(lines, "Invaders", result["invaders"], result["holder"] == "invader", name_width)
	_append_losses(lines, "Defender", result["defenders"], result["holder"] == "defender", name_width)
	return "\n".join(lines)


static func _append_roster(lines: Array[String], label: String, units: Array, width: int) -> void:
	for unit: Dictionary in units:
		lines.append("%-9s %s  %s, %s, %d Health" % [
			label, String(unit["name"]).rpad(width), unit["kind_name"], unit["weapon_name"], unit["max_health"]])


static func _append_losses(lines: Array[String], label: String, units: Array, held_field: bool, width: int) -> void:
	for unit: Dictionary in units:
		var status := ""
		match int(unit["state"]):
			CombatUnit.State.DEAD:
				status = "killed"
			CombatUnit.State.DOWNED:
				status = "downed, recovered by own side" if held_field else "downed, captured"
			_:
				status = "%d/%d Health" % [unit["health"], unit["max_health"]]
				if unit["wounded"]:
					status += ", Wounded"
		lines.append("%-9s %s  %s" % [label, String(unit["name"]).rpad(width), status])


static func _attack_line(event: Dictionary, width: int) -> String:
	var where := "%s, %s" % [COVER_LABEL[event["target_cover"]], BAND_LABEL[event["attacker_band"]]]
	if event["flanked"]:
		where = "flanked, %s" % BAND_LABEL[event["attacker_band"]]
	var text := "  %s shoots %s (%s): %d%% %s, rolled %d — " % [
		String(event["attacker"]).rpad(width), event["target"], where,
		event["hit_chance"], _working(event), event["hit_roll"]]

	if not event["hit"]:
		return text + "miss"

	text += "HIT"
	if event["crit"]:
		text += ", crit (rolled %d, needed %d or less)" % [event["crit_roll"], event["crit_chance"]]
	text += ", %d dmg %s → %s " % [event["damage"], _damage_working(event), event["target"]]

	match String(event.get("outcome", "")):
		"dead":
			text += "killed"
			if event.has("downed_roll"):
				text += " (downed roll %d, needed %d or less)" % [event["downed_roll"], event["downed_chance"]]
		"downed":
			text += "downed (rolled %d, needed %d or less)" % [event["downed_roll"], event["downed_chance"]]
		_:
			text += "%d/%d" % [event["health_after"], event["max_health"]]
			if event.get("became_wounded", false):
				text += ", now Wounded"
	return text


## "[Aim 65, range +10]", plus the cap if the raw total was clamped.
static func _working(event: Dictionary) -> String:
	var parts: Array[String] = []
	for part: Array in event["hit_parts"]:
		var value := int(part[1])
		if String(part[0]) == "Aim":
			parts.append("Aim %d" % value)
		else:
			parts.append("%s %s" % [part[0], _signed(value)])
	var working := ", ".join(parts)
	if int(event["hit_raw"]) != int(event["hit_chance"]):
		working += " = %d, limited to %d" % [event["hit_raw"], event["hit_chance"]]
	return "[%s]" % working


## "(rolled 5 ×1.5, −1 armour)"
static func _damage_working(event: Dictionary) -> String:
	var steps: Array[String] = ["rolled %d" % event["damage_roll"]]
	if event["crit"]:
		steps[0] += " ×1.5"
	if int(event["armour"]) > 0:
		steps.append("−%d armour" % event["armour"])
	return "(%s)" % ", ".join(steps)


static func _signed(value: int) -> String:
	return "+%d" % value if value >= 0 else "−%d" % absi(value)


static func _name_width(result: Dictionary) -> int:
	var width := 0
	for side_key: String in ["invaders", "defenders"]:
		for unit: Dictionary in result[side_key]:
			width = maxi(width, String(unit["name"]).length())
	return width
