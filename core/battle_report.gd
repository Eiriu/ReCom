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
const COVER_SHORT := {"none": "None", "half": "Half", "full": "Full"}
const STANCE_LABEL := {"cautious": "Cautious", "standard": "Standard", "all_in": "All-in"}


static func format(result: Dictionary, level: Level = Level.FULL) -> String:
	var lines: Array[String] = []
	var w := _name_width(result)

	lines.append("Seed %d · %s · %s · Invader stance %s" % [result["seed"], result["location"], result["title"],
		STANCE_LABEL.get(String(result.get("stance", "standard")), "Standard")])
	lines.append("")
	_append_roster(lines, "Invaders", result["invaders"], w)
	_append_roster(lines, "Defender", result["defenders"], w)

	if level == Level.FULL:
		lines.append("")
		for event: Dictionary in result["events"]:
			var line := _event_line(event, w)
			if line != "":
				lines.append(line)

	lines.append("")
	var holder := String(result["holder"])
	lines.append("Result: %s %s the field after round %d (%s)" % [
		SIDE_LABEL[holder], "hold" if holder == "invader" else "holds", result["rounds"], result["end_reason"]])
	lines.append("Losses: Invaders %s · Defender %s" % [
		_loss_counts(result["invaders"], holder == "invader"), _loss_counts(result["defenders"], holder == "defender")])
	lines.append("")
	_append_losses(lines, "Invaders", result["invaders"], holder == "invader", w)
	_append_losses(lines, "Defender", result["defenders"], holder == "defender", w)
	return "\n".join(lines)


static func _event_line(event: Dictionary, w: int) -> String:
	var pad := " ".repeat(w + 4)
	match String(event["type"]):
		"initiative":
			return "First turn: %s (rolled %d; Invaders start on 50 or less)" % [SIDE_LABEL[event["side"]], event["roll"]]
		"cover_rolls":
			var mix: Dictionary = event["mix"]
			var out: Array[String] = ["Both sides start at %s range. Cover (Full on 1–%d, Half on %d–%d, None above):" % [
				BAND_LABEL[event["band"]], int(mix["full"]), int(mix["full"]) + 1, int(mix["full"]) + int(mix["half"])]]
			for side: String in ["invader", "defender"]:
				var parts: Array[String] = []
				for roll: Dictionary in event["rolls"]:
					if roll["side"] == side:
						parts.append("%s %s (%d)" % [roll["unit"], COVER_SHORT[roll["cover"]], roll["roll"]])
				out.append("  %-9s %s" % [SIDE_LABEL[side], ", ".join(parts)])
			return "\n".join(out)
		"cover_feature":
			return "%s: %s stands behind it, %s (rolled %d of 1–%d)" % [
				String(event["name"]).capitalize(), event["unit"], COVER_LABEL[event["cover"]],
				event["roll"], event["options"]]
		"turn":
			return "\nRound %d — %s" % [event["round"], SIDE_LABEL[event["side"]]]
		"attack":
			return _attack_line(event, w)
		"move":
			var text := "  %s moves %s → %s" % [_n(event["unit"], w), BAND_LABEL[event["from_band"]], BAND_LABEL[event["to_band"]]]
			if event.has("for_target"):
				text += " to shoot %s" % event["for_target"]
			return text + _cover_change(event) + _rule(event)
		"flank":
			return "  %s tries to flank %s from %s: %d%% %s, rolled %d — %s%s%s" % [
				_n(event["unit"], w), event["target"], BAND_LABEL[event["band"]], event["chance"],
				_flank_working(event), event["roll"], "success" if event["success"] else "failed",
				_cover_change(event), _rule(event)]
		"transit_cover":
			var mix: Dictionary = event["mix"]
			return "%sCaught moving: %s %s while crossing (rolled %d; Full on 1–%d, Half on %d–%d)" % [
				pad, event["unit"], COVER_LABEL[event["cover"]], event["roll"],
				int(mix["full"]), int(mix["full"]) + 1, int(mix["full"]) + int(mix["half"])]
		"hunker":
			return "  %s hunkers down (counts as Full cover until its next turn)%s" % [_n(event["unit"], w), _rule(event)]
		"overwatch":
			return "  %s goes on overwatch%s" % [_n(event["unit"], w), _rule(event)]
		"hold":
			return "  %s holds position%s" % [_n(event["unit"], w), _rule(event)]
		"suppress":
			return "  %s suppresses %s (−%d Aim until %s next turn; Will %d)%s" % [
				_n(event["unit"], w), event["target"], event["penalty"], event["unit"], event["will"], _rule(event)]
		"suppression_ends":
			return "  %s is no longer suppressed by %s" % [_n(event["unit"], w), event["by"]]
		"repair":
			return "  %s repairs %s: %d → %d/%d (%d repairs left)%s" % [
				_n(event["unit"], w), event["target"], event["before"], event["after"], event["max"], event["left"], _rule(event)]
		"rally":
			return "  %s Rallies %s (+20 Morale, +5 Aim until the end of their next turn)%s" % [
				_n(event["unit"], w), ", ".join(event["allies"]) if not event["allies"].is_empty() else "nobody", _rule(event)]
		"mind_spike":
			return "  %s uses Mind spike on %s: %d%% [50 + (Will %d − %d) / 2], rolled %d — %s%s" % [
				_n(event["unit"], w), event["target"], event["chance"], event["harrow_will"], event["target_will"],
				event["roll"], "success, −40 Morale" if event["success"] else "resisted", _rule(event)]
		"morale":
			return _morale_line(event, pad)
		"withdraw":
			return "\n%s withdraw: %s" % [SIDE_LABEL[event["side"]], event["reason"]]
		"recovery":
			var parts: Array[String] = []
			for roll: Dictionary in event["rolls"]:
				parts.append("%s %s (rolled %d, needed %d or less)" % [roll["unit"],
					"recovered alive, Injured" if roll["recovered"] else "not recovered", roll["roll"], roll["chance"]])
			return "\nRecovering the fallen: %s" % "; ".join(parts)
	return ""


## " (Full → Half cover)" from the cover rolled after the move, if the unit survived.
static func _cover_change(event: Dictionary) -> String:
	if not event.has("to_cover"):
		return " (did not survive the move)"
	return " (%s → %s cover, rolled %d)" % [COVER_SHORT[event["from_cover"]], COVER_SHORT[event["to_cover"]], event["cover_roll"]]


static func _flank_working(event: Dictionary) -> String:
	var parts: Array[String] = []
	for part: Array in event["parts"]:
		parts.append("%s %s" % [part[0], _signed(int(part[1])) if String(part[0]) != "base" else str(int(part[1]))])
	var text := ", ".join(parts)
	if int(event["raw"]) != int(event["chance"]):
		text += " = %d, limited to %d" % [event["raw"], event["chance"]]
	return "[%s]" % text


static func _morale_line(event: Dictionary, pad: String) -> String:
	var groups := {}
	var order: Array[String] = []
	for change: Dictionary in event["changes"]:
		var reason := String(change["reason"])
		if not groups.has(reason):
			groups[reason] = []
			order.append(reason)
		var text := "%s %d→%d" % [change["unit"], change["before"], change["after"]]
		if change.get("broke", false):
			text += " BROKEN, flees the battle"
		elif change.get("shaken", false):
			text += " now Shaken"
		elif change.get("steadied", false):
			text += " no longer Shaken"
		groups[reason].append(text)
	var out: Array[String] = []
	for reason in order:
		out.append("%sMorale (%s): %s" % [pad, reason, ", ".join(PackedStringArray(groups[reason]))])
	return "\n".join(out)


## "2 killed, 1 downed (captured)" or "none".
static func _loss_counts(units: Array, held_field: bool) -> String:
	var killed := 0
	var recovered := 0
	var downed := 0
	var fled := 0
	for unit: Dictionary in units:
		match int(unit["state"]):
			CombatUnit.State.DEAD:
				if unit.get("recovered", false):
					recovered += 1
				else:
					killed += 1
			CombatUnit.State.DOWNED:
				downed += 1
			CombatUnit.State.FLED:
				fled += 1
	var parts: Array[String] = []
	if killed > 0:
		parts.append("%d killed" % killed)
	if recovered > 0:
		parts.append("%d recovered alive" % recovered)
	if downed > 0:
		parts.append("%d downed (%s)" % [downed, "recovered" if held_field else "captured"])
	if fled > 0:
		parts.append("%d fled" % fled)
	return "none" if parts.is_empty() else ", ".join(parts)


static func _append_roster(lines: Array[String], label: String, units: Array, width: int) -> void:
	for unit: Dictionary in units:
		lines.append("%-9s %s  %s, %s, %d Health" % [
			label, String(unit["name"]).rpad(width), unit["kind_name"], unit["weapon_name"], unit["max_health"]])


static func _append_losses(lines: Array[String], label: String, units: Array, held_field: bool, width: int) -> void:
	for unit: Dictionary in units:
		var status := ""
		match int(unit["state"]):
			CombatUnit.State.DEAD:
				status = "killed, recovered alive (Injured)" if unit.get("recovered", false) else "killed"
			CombatUnit.State.DOWNED:
				status = "downed, recovered by own side" if held_field else "downed, captured"
			CombatUnit.State.FLED:
				status = "broke and fled (survives)"
			_:
				status = "%d/%d Health" % [unit["health"], unit["max_health"]]
				if unit["wounded"]:
					status += ", Wounded"
				if not unit.get("machine", false):
					status += ", Morale %d" % unit["morale"]
		lines.append("%-9s %s  %s" % [label, String(unit["name"]).rpad(width), status])


static func _attack_line(event: Dictionary, w: int) -> String:
	var where := "%s, %s" % [COVER_LABEL[event["target_cover"]], BAND_LABEL[event["attacker_band"]]]
	if event["flanked"]:
		where = "flanked, %s" % BAND_LABEL[event["attacker_band"]]
	var lead := "  %s shoots" % _n(event["attacker"], w)
	if event.get("reaction", false):
		var trigger := "overwatch" if event.get("trigger", "") == "overwatch" else "suppression"
		lead = "%s↳ %s reacts (%s) and shoots" % [" ".repeat(w + 4), event["attacker"], trigger]
	var text := "%s %s (%s): %d%% %s, rolled %d — " % [lead, event["target"], where,
		event["hit_chance"], _working(event), event["hit_roll"]]

	var rule := _rule(event)
	if not event["hit"]:
		return text + "miss" + rule

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
	return text + rule


static func _rule(event: Dictionary) -> String:
	return " · %s" % event["rule"] if event.has("rule") else ""


static func _n(name: Variant, w: int) -> String:
	return String(name).rpad(w)


## "[Aim 65, half cover −20, range +10]", plus the cap if the raw total was clamped.
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
