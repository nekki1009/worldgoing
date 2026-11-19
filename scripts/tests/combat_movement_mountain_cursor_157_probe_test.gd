extends "res://scripts/tests/combat_movement_formal_mountain_arrival_test.gd"
## Diagnostic-only early stop. The formal 300-sim/240-wall acceptance script is unchanged.

func _advance() -> bool:
	if not super._advance():
		return false
	if _tick < 4500:
		return true
	print("FORMAL_MOUNTAIN_CURSOR_157_PROBE COMPLETE simulated=", _tick * STEP,
		" cursor=", _army.get_active_move_plan().macro_cursor, " wall=", _wall_seconds())
	if is_instance_valid(_lab):
		_lab.queue_free()
	quit(0)
	return false
