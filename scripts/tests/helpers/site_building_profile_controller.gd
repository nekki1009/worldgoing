extends "res://scripts/terrain_lab/site_controller.gd"
## Same fresh original controller, installed before its existing setup.
var building_probe: RefCounted

func tick(delta: float, accepted_game_seconds: float = -1.0) -> void:
	var started: int = Time.get_ticks_usec()
	super.tick(delta, accepted_game_seconds)
	if building_probe != null: building_probe.add("host.site_tick_inclusive", started)

func _sync_building_actions() -> void:
	var started: int = Time.get_ticks_usec()
	super._sync_building_actions()
	if building_probe != null: building_probe.add("building.selection_ui", started)
