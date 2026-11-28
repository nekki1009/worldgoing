extends SceneTree
## SiteRegionCheckpoint._json_write_state settles a state whose numbers Godot's JSON parser never reads back exactly
## (some values under 1e-7: a Site phase of 1.59119128984031e-09 refused every save, UNSTABLE_REGION_SNAPSHOT_JSON,
## found 2026-11-28 with the 選現成人物 leader long run). Every such state now settles within the snapshot hash's 12
## significant digits; a value that does not parse at all is still refused.
const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
var checks := 0
var failed := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("SITE_REGION_SNAPSHOT_TINY_FLOAT_FAIL: " + message)

## Godot's own read-write rounds (8, as the checkpoint): -1 when the text never repeats.
func _settles(value: float) -> int:
	var encoded: String = JSON.stringify({"v": value}, "", true, true)
	for round_index: int in range(8):
		var next: String = JSON.stringify(JSON.parse_string(encoded), "", true, true)
		if next == encoded: return round_index
		encoded = next
	return -1

func _initialize() -> void:
	var seen := 1.59119128984031e-09
	check(_settles(seen) < 0, "The refused Site phase still does not settle in Godot's own JSON (else this test proves nothing)")
	var written: Dictionary = Checkpoint._json_write_state({"minute": 4347, "phase": seen, "name": "溪前鎮"})
	check(written.ok, "A state holding it is written: %s" % str(written.get("message", "")))
	if written.ok:
		check(absf(float(written.state.phase) - seen) <= seen * 0.000000000001 and int(written.state.minute) == 4347 and str(written.state.name) == "溪前鎮", "It is read back within 1e-12 of itself, the rest exactly")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var unsettled := 0
	var refused := 0
	for exponent: int in range(-12, -6):
		for i: int in range(500):
			var value := rng.randf_range(1.0, 10.0) * pow(10.0, float(exponent))
			if _settles(value) >= 0: continue
			unsettled += 1
			var row: Dictionary = Checkpoint._json_write_state({"v": value, "list": [value, 1, "x"]})
			if not row.ok or absf(float(row.state.v) - value) > value * 0.000000000001: refused += 1
	check(unsettled > 0, "Some sampled values do not settle in Godot's JSON (%d)" % unsettled)
	check(refused == 0, "Every one of them is written and read back within 1e-12 (%d refused or off)" % refused)
	if failed:
		quit(1)
		return
	print("SITE_REGION_SNAPSHOT_TINY_FLOAT_PASS checks=%d (%d unsettled values written)" % [checks, unsettled])
	quit(0)
