class_name Dice
extends RefCounted
## The only source of randomness in a battle.
##
## Every roll goes through this object, always in the same order, so the same
## seed and the same squads always give the same battle. Never call randi() or
## randf() anywhere else in game logic.

var seed_value: int
var rolls_made: int = 0
var _rng := RandomNumberGenerator.new()


func _init(seed_in: int) -> void:
	seed_value = seed_in
	_rng.seed = seed_in


## A percentile roll from 1 to 100, inclusive.
func percent() -> int:
	rolls_made += 1
	return _rng.randi_range(1, 100)


## A roll between low and high, inclusive.
func between(low: int, high: int) -> int:
	rolls_made += 1
	return _rng.randi_range(low, high)
