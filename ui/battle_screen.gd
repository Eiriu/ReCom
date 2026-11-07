extends Control
## A plain test screen: pick a battle and a seed, fight, read the report.
## It only displays results. All game logic lives in res://core.

const CUSTOM := "custom"
const FIRST_SIDE_OPTIONS := [["attacker", "Invaders first (spec)"], ["random", "Random first turn"],
	["defender", "Defender first"]]
const STANCE_OPTIONS := [["standard", "Standard"], ["cautious", "Cautious"], ["all_in", "All-in"]]

var _data: GameData
var _scenario_ids: Array[String] = []
var _scenario_picker: OptionButton
var _custom_row: HBoxContainer
var _invader_picker: OptionButton
var _opposition_picker: OptionButton
var _terrain_picker: OptionButton
var _stance_picker: OptionButton
var _first_picker: OptionButton
var _invader_ids: Array[String] = []
var _opposition_ids: Array[String] = []
var _terrain_ids: Array[String] = []
var _seed_input: LineEdit
var _show_rolls: CheckBox
var _report_view: TextEdit
var _status: Label
var _last_result: Dictionary = {}


func _ready() -> void:
	_data = GameData.load_default()
	_scenario_ids = Scenarios.ids(_data)
	_scenario_ids.append(CUSTOM)
	_invader_ids = Scenarios.squad_ids(_data, CombatUnit.SIDE_INVADER)
	_opposition_ids = Scenarios.squad_ids(_data, CombatUnit.SIDE_DEFENDER)
	_terrain_ids = GameData.entry_ids(_data.terrains)
	_build_layout()
	_fight(_random_seed())


func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Battle test screen — combat core (slices 1.1–1.6): range, flanking, reactions, Morale"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	column.add_child(controls)

	_scenario_picker = OptionButton.new()
	# Long matchup names would otherwise stretch the row past the window edge.
	_scenario_picker.fit_to_longest_item = false
	_scenario_picker.clip_text = true
	_scenario_picker.custom_minimum_size = Vector2(380, 0)
	_scenario_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in _scenario_ids:
		_scenario_picker.add_item("Custom battle…" if id == CUSTOM else Scenarios.display_name(id, _data))
	_scenario_picker.item_selected.connect(func(_index: int) -> void:
		_custom_row.visible = _scenario_ids[_scenario_picker.selected] == CUSTOM
		_fight_from_input())
	controls.add_child(_scenario_picker)

	var seed_label := Label.new()
	seed_label.text = "Seed"
	controls.add_child(seed_label)

	_seed_input = LineEdit.new()
	_seed_input.custom_minimum_size = Vector2(120, 0)
	_seed_input.tooltip_text = "Same seed = same battle. Type one in to replay a battle exactly."
	_seed_input.text_submitted.connect(func(_text: String) -> void: _fight_from_input())
	controls.add_child(_seed_input)

	controls.add_child(_button("Fight this seed", _fight_from_input))
	controls.add_child(_button("New random battle", func() -> void: _fight(_random_seed())))

	_show_rolls = CheckBox.new()
	_show_rolls.text = "Show every action"
	_show_rolls.button_pressed = true
	_show_rolls.toggled.connect(func(_on: bool) -> void: _refresh_report())
	controls.add_child(_show_rolls)

	controls.add_child(_button("Copy report", _copy_report))

	_custom_row = HBoxContainer.new()
	_custom_row.add_theme_constant_override("separation", 8)
	_custom_row.visible = false
	column.add_child(_custom_row)
	_invader_picker = _picker(_custom_row, "Invaders", _names(_invader_ids, _data.squads))
	_opposition_picker = _picker(_custom_row, "vs", _names(_opposition_ids, _data.squads))
	_terrain_picker = _picker(_custom_row, "on", _names(_terrain_ids, _data.terrains))
	_stance_picker = _picker(_custom_row, "Stance", _labels(STANCE_OPTIONS))
	_first_picker = _picker(_custom_row, "", _labels(FIRST_SIDE_OPTIONS))

	_report_view = TextEdit.new()
	_report_view.editable = false
	_report_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	_report_view.add_theme_font_override("font", mono)
	_report_view.add_theme_font_size_override("font_size", 15)
	_report_view.add_theme_color_override("font_readonly_color", Color(0.92, 0.92, 0.92))
	column.add_child(_report_view)

	_status = Label.new()
	column.add_child(_status)


func _picker(row: HBoxContainer, label_text: String, items: Array[String]) -> OptionButton:
	if label_text != "":
		var label := Label.new()
		label.text = label_text
		row.add_child(label)
	var picker := OptionButton.new()
	for item in items:
		picker.add_item(item)
	picker.item_selected.connect(func(_index: int) -> void: _fight_from_input())
	row.add_child(picker)
	return picker


static func _names(ids: Array[String], table: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		out.append(String(table[id]["name"]))
	return out


static func _labels(options: Array) -> Array[String]:
	var out: Array[String] = []
	for option: Array in options:
		out.append(String(option[1]))
	return out


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func _fight_from_input() -> void:
	var text := _seed_input.text.strip_edges()
	if not text.is_valid_int():
		_status.text = "The seed must be a whole number."
		return
	_fight(int(text))


func _fight(seed_value: int) -> void:
	_seed_input.text = str(seed_value)
	var scenario := _scenario_ids[_scenario_picker.selected]
	var battle: Battle
	if scenario == CUSTOM:
		battle = Scenarios.matchup(_data, seed_value, _invader_ids[_invader_picker.selected],
			_opposition_ids[_opposition_picker.selected], _terrain_ids[_terrain_picker.selected],
			String(STANCE_OPTIONS[_stance_picker.selected][0]), String(FIRST_SIDE_OPTIONS[_first_picker.selected][0]))
	else:
		battle = Scenarios.build(scenario, _data, seed_value)
	_last_result = battle.run()
	_refresh_report()
	_status.text = "Battle %d done. To report a problem, use Copy report and paste it into the chat." % seed_value


func _refresh_report() -> void:
	if _last_result.is_empty():
		return
	var level := BattleReport.Level.FULL if _show_rolls.button_pressed else BattleReport.Level.SUMMARY
	_report_view.text = BattleReport.format(_last_result, level)


func _copy_report() -> void:
	DisplayServer.clipboard_set(_report_view.text)
	_status.text = "Report copied."


func _random_seed() -> int:
	# Picking a seed is the one place randomness is allowed outside Dice;
	# the battle itself is fully decided by the seed.
	return randi_range(1, 999_999)
