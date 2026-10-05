class_name FortressDemoBalance
extends Resource

@export var mode: String = "expedition"
@export var round_limit: int = 3
@export var initial_gold: int = 20
@export var castle_max_hp: int = 100
@export var castle_start_hp: int = 100
@export var castle_repair_floor: int = 65
@export var initial_tower_levels: Array[int] = [1, 0, 0, 0, 0, 0]
@export var tower_max_level: int = 2
@export var build_gold_cost: int = 25
@export var upgrade_gold_cost: int = 35
@export var repair_gold_cost: int = 20
@export var repair_amount: int = 35
@export var sealed_chest_gold: int = 20
