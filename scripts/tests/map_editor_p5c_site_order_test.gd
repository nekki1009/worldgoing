extends SceneTree
## P5C-S1: pure schema cap and canonical birth order for multi-Site authored
## contexts. No package, no open_map, no birth, no files.
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
var _failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> bool:
	if value: return true
	if not _failed:
		_failed = true
		push_error("MAP_EDITOR_P5C_SITE_ORDER_FAIL: " + message)
		quit(1)
	return false

func _context(sites: Array, start: Array) -> Dictionary:
	return {"version": 2, "mode": "author",
		"author_identity": {"scenario_id": "p5c_fixture", "scenario_revision": 1, "scenario_package_sha256": "a".repeat(64)},
		"starting_site": start.duplicate(), "expected_initial_sites": sites.duplicate(true),
		"start": {"mode": "created_player", "site": start.duplicate(), "cell": [10, 10]}}

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: push_error("MAP_EDITOR_P5C_SITE_ORDER_TIMEOUT"); quit(1))
	# One Site stays admitted and keeps its single-entry order.
	var single: Dictionary = _context([[0, 0]], [0, 0])
	if not _check(Slot.author_initial_context_valid(single), "single-Site context stays valid"): return
	if not _check(Slot.author_initial_site_order(single) == [Vector2i(0, 0)], "single-Site order is the start"): return
	# Several Sites: the start first, the rest in x,y order, regardless of input order.
	var multi: Dictionary = _context([[7, 1], [5, 5], [-2, 3], [5, -4]], [5, 5])
	if not _check(Slot.author_initial_context_valid(multi), "multi-Site context admitted by schema"): return
	var order: Array = Slot.author_initial_site_order(multi)
	var expected: Array = [Vector2i(5, 5), Vector2i(-2, 3), Vector2i(5, -4), Vector2i(7, 1)]
	if not _check(order == expected, "multi-Site order is start then x,y sorted: " + str(order)): return
	# The input context is not mutated by ordering.
	if not _check(multi.expected_initial_sites == [[7, 1], [5, 5], [-2, 3], [5, -4]], "ordering does not mutate the context"): return
	# Exactly the cap is admitted; one more is refused.
	var at_limit: Array = []
	for i: int in range(Slot.AUTHOR_INITIAL_SITE_LIMIT):
		at_limit.append([i, 0])
	if not _check(Slot.author_initial_context_valid(_context(at_limit, [0, 0])), "cap-sized context admitted"): return
	at_limit.append([Slot.AUTHOR_INITIAL_SITE_LIMIT, 0])
	if not _check(not Slot.author_initial_context_valid(_context(at_limit, [0, 0])), "over-cap context refused"): return
	if not _check(Slot.author_initial_site_order(_context(at_limit, [0, 0])).is_empty(), "over-cap context has no order"): return
	# Refusals: duplicate, missing start, malformed pair.
	if not _check(not Slot.author_initial_context_valid(_context([[5, 5], [5, 5]], [5, 5])), "duplicate Site refused"): return
	if not _check(not Slot.author_initial_context_valid(_context([[1, 1]], [5, 5])), "missing start Site refused"): return
	if not _check(not Slot.author_initial_context_valid(_context([[5, 5], [1]], [5, 5])), "malformed pair refused"): return
	if not _check(Slot.author_initial_site_order(_context([[1, 1]], [5, 5])).is_empty(), "invalid context has no order"): return
	quit(0)
