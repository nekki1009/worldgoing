extends "res://scripts/tests/site_technology_artisan_production_base.gd"
## Named original-owner engineering subset; FULL G06/D10 remain OPEN.
func _g06_category() -> String:
	return "F12"

## Crowd port (2026-11-12): this siege production test steps the whole Lab, so it runs on the native crowd.
func _crowd_port() -> bool:
	return not OS.get_cmdline_user_args().has("--grid")
