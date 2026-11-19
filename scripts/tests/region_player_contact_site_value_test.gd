extends SceneTree
const PlayerSource = preload("res://scripts/tests/region_player_first_siege_contact_physical_test.gd")
var failed: bool = false

func _initialize() -> void:
	var native: Array[int] = [1, 0]
	var wire: Variant = JSON.parse_string("[1,0]")
	var cases: Array[Dictionary] = [
		{"site": native, "matches": true}, {"site": wire, "matches": true}, {"site": [1.0, 0.0], "matches": true},
		{"site": [0, 0], "matches": false}, {"site": [1, 1], "matches": false},
		{"site": [1.5, 0], "matches": false}, {"site": [1, 0.5], "matches": false},
		{"site": ["1", 0], "matches": false}, {"site": [true, 0], "matches": false},
		{"site": [1], "matches": false}, {"site": [1, 0, 0], "matches": false},
		{"site": Vector2i(1, 0), "matches": false}, {"site": null, "matches": false}]
	for entry: Dictionary in cases:
		var before: PackedByteArray = var_to_bytes(entry.site)
		var matches: bool = PlayerSource._player_contact_is_intermediate_site(entry.site)
		if matches != bool(entry.matches) or before != var_to_bytes(entry.site):
			failed = true
			push_error("CC156_PLAYER_SITE_VALUE_FAIL " + var_to_str(entry))
	print("CC156_PLAYER_SITE_VALUE_", "FAILED" if failed else "PASS", " cases=", cases.size())
	quit(1 if failed else 0)
