class_name FortressDefenseBalance
extends Resource

@export_range(1, 999) var orc_health: int = 48
@export_range(1.0, 200.0) var orc_speed: float = 45.0
@export_range(0.1, 10.0) var first_spawn_delay: float = 1.0
@export_range(0.1, 10.0) var spawn_interval: float = 3.0
@export_range(0.1, 10.0) var castle_attack_interval: float = 2.4
@export_range(1, 100) var orc_castle_damage: int = 10
@export_range(1, 100) var tower_level_one_damage: int = 8
@export_range(1, 100) var tower_level_two_damage: int = 10
@export_range(0.1, 5.0) var tower_level_one_interval: float = 0.9
@export_range(0.1, 5.0) var tower_level_two_interval: float = 0.75
@export_range(1.0, 1000.0) var tower_range: float = 330.0
@export_range(0.1, 20.0) var rally_duration: float = 4.0
@export_range(1.0, 60.0) var rally_cooldown: float = 12.0
@export_range(0.1, 1.0) var rally_interval_factor: float = 0.67
@export_range(1.0, 2000.0) var arrow_speed: float = 510.0
@export var wave_enemy_counts: Array[int] = [6, 8, 10]
@export var later_round_spawn_intervals: Array[float] = [2.75, 2.5]
@export_range(1.0, 4.0, 1.0) var archer_scale: float = 3.0
@export_range(0.1, 2.0) var archer_shoot_duration: float = 0.55
@export_range(1, 999) var skeleton_health: int = 48
@export_range(1, 999) var armored_skeleton_health: int = 140
@export_range(1, 999) var skull_health: int = 32
@export_range(1, 999) var vampire_health: int = 110
@export_range(1.0, 200.0) var skeleton_speed: float = 45.0
@export_range(1.0, 200.0) var armored_skeleton_speed: float = 36.0
@export_range(1.0, 200.0) var skull_speed: float = 60.0
@export_range(1.0, 200.0) var vampire_speed: float = 58.0
@export_range(1, 100) var skeleton_castle_damage: int = 10
@export_range(1, 100) var armored_skeleton_castle_damage: int = 18
@export_range(1, 100) var skull_castle_damage: int = 8
@export_range(1, 100) var vampire_castle_damage: int = 20
@export_range(0.5, 10.0) var vampire_castle_attack_interval: float = 1.8
@export_range(0, 30) var vampire_drain_heal: int = 6

@export_range(1, 999) var slime_health: int = 40
@export_range(1.0, 200.0) var slime_speed: float = 55.0
@export_range(1, 100) var slime_castle_damage: int = 10

func firepower_boost_percent() -> int:
	return maxi(0, ceili((1.0 / maxf(0.1, rally_interval_factor) - 1.0) * 100.0))
