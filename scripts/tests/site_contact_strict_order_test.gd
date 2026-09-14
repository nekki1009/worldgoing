extends "res://scripts/tests/site_contact_sort_cull_test.gd"
## Native comparator/owner guards only: internal 5s / canonical helper 20s.
## The old proof remains unchanged; strict ordering intentionally changes its
## nearly simultaneous ordering. Culling is compared against STRICT uncull.
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

func run() -> void:
	var started := Time.get_ticks_usec()
	assert(DisplayServer.get_name() == "headless")
	lab = TerrainLab.new()
	Geometry.strict_contact_order_enabled = false
	Geometry.melee_hit_cull_enabled = false
	var old := _native_distance_counterexample()
	assert(old.full_sorted == [5, 3, 4], "Preserve the old comparator's independently recorded counterexample")
	Geometry.strict_contact_order_enabled = true
	var cases: Array = [old.input, [
		{"identity": 3, "fraction": 0.0, "distance": -0.0},
		{"identity": 4, "fraction": -0.0, "distance": 0.0},
		{"identity": 5, "fraction": 1.0 / 256.0, "distance": 0.0}], [
		{"identity": 3, "fraction": NAN, "distance": 0.0},
		{"identity": 4, "fraction": 0.5, "distance": NAN},
		{"identity": 5, "fraction": 0.5, "distance": INF}]]
	var checks := 0
	for fixture: Array in cases:
		var typed: Array[Dictionary] = []
		typed.assign(fixture)
		var expected := _identities(_sorted(typed))
		for permutation: Array in PERMUTATIONS:
			var input: Array[Dictionary] = []
			for index: int in permutation:
				input.append(typed[index])
			var ordered := _sorted(input)
			assert(_identities(ordered) == expected)
			for mask: int in 8:
				var removed := {}
				for index: int in 3:
					if mask & (1 << index):
						removed[index + 3] = true
				assert(_identities(_without(ordered, removed)) == _identities(_sorted(_without(input, removed))),
					"Strict ordered survivors are independent of already-hit removal before sorting")
				checks += 1
	assert(_identities(_sorted(old.input)) == [5, 4, 3], "Explicit behavior correction, not old-sort equivalence")
	_owner_guards()
	assert(Time.get_ticks_usec() - started < 5000000)
	var report := {"strict_survivor_checks": checks, "old_native_distance_order": old.full_sorted,
		"new_native_distance_order": [5, 4, 3], "nan_policy": "Retain contact; NaN sorts after numbers per field, then original identity; not a NaN numerical order",
		"geometry_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_weapon_collision.gd"),
		"scope": "Actual native sorter and real owner hit-set routing, not mesh/gameplay/FPS acceptance"}
	var output := "res://output/site_combat_performance_20260913/strict_contact_order/%d_%d" % [int(Time.get_unix_time_from_system()), started]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK)
	var file := FileAccess.open(output + "/native.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	Geometry.strict_contact_order_enabled = false
	Geometry.melee_hit_cull_enabled = false
	lab.free()
	print("SITE CONTACT STRICT ORDER PASS ", JSON.stringify(report))
	quit(0)

func _owner_guards() -> void:
	# Metadata routing fixture only; no invented geometry or combatants are used
	# as gameplay/performance evidence. These are the actual owner classes.
	var team := TerrainArmy.new()
	var actor := TerrainTestCharacter.new()
	var recorded := {41: true, 42: true}
	team.combat_units.assign([{"hits": recorded}])
	actor._attack_hits = {43: true}
	for strict: bool in [false, true]:
		Geometry.strict_contact_order_enabled = strict
		for cull: bool in [false, true]:
			Geometry.melee_hit_cull_enabled = cull
			var enabled := strict and cull
			assert(lab._contact_hit_exclusions(team, 0).is_empty() != enabled)
			assert(lab._contact_hit_exclusions(actor, -1).is_empty() != enabled)
			if enabled:
				assert(is_same(lab._contact_hit_exclusions(team, 0), recorded))
				assert(is_same(lab._contact_hit_exclusions(actor, -1), actor._attack_hits))
			for source: Variant in [null, lab, 17, {"hits": recorded}]:
				assert(lab._contact_hit_exclusions(source, 0).is_empty())
			assert(lab._contact_hit_exclusions(team, -1).is_empty())
			assert(lab._contact_hit_exclusions(team, 1).is_empty())
			assert(lab._contact_hit_exclusions(actor, 0).is_empty())
			assert(lab._contact_hit_exclusions(team, 0, true).is_empty())
			assert(lab._contact_hit_exclusions(actor, -1, true).is_empty())
	assert(recorded == {41: true, 42: true} and actor._attack_hits == {43: true})
	team.free()
	actor.free()
