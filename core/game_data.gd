class_name GameData
extends RefCounted
## Loads the JSON files in res://data. Every tunable number lives there,
## so balance can change without touching code.
##
## Note: JSON numbers arrive as floats. Code that reads them converts with int().

const DATA_DIR := "res://data/"

var combat: Dictionary = {}
var weapons: Dictionary = {}
var species: Dictionary = {}
var defender_grades: Dictionary = {}


static func load_default() -> GameData:
	var data := GameData.new()
	data.combat = _load_json("combat.json")
	data.weapons = _load_json("weapons.json")
	data.species = _load_json("species.json")
	data.defender_grades = _load_json("defender_grades.json")
	return data


static func _load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Could not read data file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Data file is not valid JSON: %s" % path)
		return {}
	return parsed


func weapon(id: String) -> Dictionary:
	if not weapons.has(id):
		push_error("Unknown weapon id: %s" % id)
		return {}
	return weapons[id]


func species_entry(id: String) -> Dictionary:
	if not species.has(id):
		push_error("Unknown species id: %s" % id)
		return {}
	return species[id]


func grade_entry(id: String) -> Dictionary:
	if not defender_grades.has(id):
		push_error("Unknown Defender grade id: %s" % id)
		return {}
	return defender_grades[id]


## Ids of real entries in a table, skipping "_about" notes.
static func entry_ids(table: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key: String in table.keys():
		if not key.begins_with("_"):
			ids.append(key)
	return ids
