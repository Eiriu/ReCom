extends Control
## A plain test screen: pick a seed, fight, read the report.
## It only displays results. All game logic lives in res://core.

var _data: GameData
var _seed_input: LineEdit
var _show_rolls: CheckBox
var _report_view: TextEdit
var _status: Label
var _last_result: Dictionary = {}


func _ready() -> void:
	_data = GameData.load_default()
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
	title.text = "Slice 1.1 — Duel: one Warden against one Regular, one tree, shooting only"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	column.add_child(controls)

	var seed_label := Label.new()
	seed_label.text = "Seed"
	controls.add_child(seed_label)

	_seed_input = LineEdit.new()
	_seed_input.custom_minimum_size = Vector2(160, 0)
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
	_last_result = Scenarios.duel(_data, seed_value).run()
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
