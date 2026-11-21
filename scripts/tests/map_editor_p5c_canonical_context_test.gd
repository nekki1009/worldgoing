extends SceneTree
## P5C-S2: canonical comparison of multi-Site author birth contexts and the
## fault seam default. Pure: no package, no open_map, no birth, no files.
## The two-file birth and fault-on-second-file transaction are NOT covered here;
## they need a body-bearing start Site fixture (see NOTES.md, S2 section).
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
var _failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> bool:
	if value: return true
	if not _failed:
		_failed = true
		push_error("MAP_EDITOR_P5C_CANONICAL_FAIL: " + message)
		quit(1)
	return false

func _context(sites: Array, start: Array) -> Dictionary:
	return {"version": 2, "mode": "author",
		"author_identity": {"scenario_id": "p5c_fixture", "scenario_revision": 1, "scenario_package_sha256": "a".repeat(64)},
		"starting_site": start.duplicate(), "expected_initial_sites": sites.duplicate(true),
		"start": {"mode": "created_player", "site": start.duplicate(), "cell": [10, 10]}}

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: push_error("MAP_EDITOR_P5C_CANONICAL_TIMEOUT"); quit(1))
	var listed: Dictionary = _context([[7, 1], [5, 5], [-2, 3]], [5, 5])
	var permuted: Dictionary = _context([[-2, 3], [5, 5], [7, 1]], [5, 5])
	if not _check(Slot.same_author_initial_context(listed, permuted), "same site set in another list order is the same birth"): return
	var sorted_text: String = str(Slot.author_initial_site_order(listed))
	if not _check(sorted_text == str(Slot.author_initial_site_order(permuted)), "canonical order identical for permutations: " + sorted_text): return
	var extra: Dictionary = _context([[7, 1], [5, 5], [-2, 3], [0, 0]], [5, 5])
	if not _check(not Slot.same_author_initial_context(listed, extra), "an added companion Site changes the birth"): return
	var missing: Dictionary = _context([[7, 1], [5, 5]], [5, 5])
	if not _check(not Slot.same_author_initial_context(listed, missing), "a dropped companion Site changes the birth"): return
	var moved_start: Dictionary = _context([[7, 1], [5, 5], [-2, 3]], [7, 1])
	if not _check(not Slot.same_author_initial_context(listed, moved_start), "a different start changes the birth"): return
	var single: Dictionary = _context([[5, 5]], [5, 5])
	if not _check(Slot.same_author_initial_context(single, _context([[5, 5]], [5, 5])), "single-Site comparison unchanged"): return
	# Fault seam default: no fault is injected unless a caller sets it.
	var slot: RegionSaveSlot = Slot.new()
	if not _check(not slot.initial_write_fault.is_valid(), "fault seam is invalid by default"): return
	quit(0)
