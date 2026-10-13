extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

var _lab: TerrainLab
var _controller: SiteController
var _team: TerrainArmy
var _actor: TerrainTestCharacter
var _checks := 0

class PartialExitErrors extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _first: String = ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()
	func first_error() -> String:
		_mutex.lock()
		var result: String = _first
		_mutex.unlock()
		return result

var _errors: PartialExitErrors = PartialExitErrors.new()
var _failed: bool = false
var _finished: bool = false


func _initialize() -> void:
	OS.add_logger(_errors)
	call_deferred("_run")

func _finalize() -> void:
	OS.remove_logger(_errors)

func _process(_delta: float) -> bool:
	if not _guard():
		_cleanup()
		_finished = true
		quit(1)
	return false

func _guard() -> bool:
	if _failed: return false
	var error: String = _errors.first_error()
	return true if error.is_empty() else _check(false, error)

func _cleanup() -> void:
	if is_instance_valid(_team): _team.player_member = null
	if is_instance_valid(_actor): _actor.free()
	if is_instance_valid(_team): _team.free()
	if is_instance_valid(_controller): _controller.free()
	if is_instance_valid(_lab): _lab.free()

func _check(condition: bool, message: String) -> bool:
	if _failed: return false
	_checks += 1
	var error: String = _errors.first_error()
	if not error.is_empty(): condition = false; message = error
	if not condition:
		_failed = true
		push_error("PARTIAL EXIT FOOD: " + message)
		quit(1)
	return condition

func _near(actual: float, expected: float, message: String) -> bool:
	return _check(absf(actual - expected) < 0.000001, "%s: %.12f != %.12f" % [message, actual, expected])

func _total_food(entry: Dictionary) -> float:
	var total := SiteSustain.rations(entry.sustain, entry.inventory)
	if not _guard(): return 0.0
	for container: Dictionary in _lab.terrain.site.ground_loot.values():
		total += SiteSustain.rations({"open_rations": container.get("open_rations", 0.0)}, container.cargo)
		if not _guard(): return 0.0
	return total

func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		if not _finished: _check(false, "timed out"))
	_lab = TerrainLab.new()
	_lab.terrain = Helper.build_flat_map(24, 20)
	if not _guard():
		_cleanup()
		return
	_team = Helper.create_test_army(_lab.terrain, 1, 0, 3, Vector2i(0, 6))
	if not _guard():
		_cleanup()
		return
	_lab.combat_armies = [_team]
	_controller = SiteController.new()
	_controller.lab = _lab
	_controller.vehicles.init(_controller)
	if not _guard():
		_cleanup()
		return
	_controller.person_actions.init(_lab)
	if not _guard():
		_cleanup()
		return
	_controller.captivity_supply.init(_controller)
	if not _guard():
		_cleanup()
		return
	_controller.food_delivery.init(_controller)
	if not _guard():
		_cleanup()
		return
	var initialized := SiteRuntime.initialize_item_storage(_lab.terrain.site)
	if not _guard():
		_cleanup()
		return
	var passed := _check(initialized.ok, "Original item storage must initialize")
	if passed:
		for row: Dictionary in _team.combat_units:
			if row.get("item_state", {}).is_empty():
				row["item_state"] = SiteRuntime.new_item_state("person:%d" % int(row.person_id))
			if not row.has("cargo"): row["cargo"] = {}
		passed = _verify()
		if not _guard():
			_cleanup()
			return
	_cleanup()
	passed = passed and _guard()
	_finished = true
	if passed: print("SITE PARTIAL EXIT FOOD PASS: %d checks; original carrier capacity, shared stock/cohort conservation, in-Site bearer, unchanged death/KO drops" % _checks)
	quit(0 if passed else 1)

func _verify() -> bool:
	var enabled := _controller.captivity_supply.enable_team(_team)
	if not _guard(): return false
	if not _check(enabled.ok, "Original shared supply could not start: " + str(enabled)): return false
	var entry: Dictionary = enabled.entry
	_team.combat_units[0]["logistics"] = true
	entry.inventory.grain = 11
	entry.sustain.open_rations = 0.5
	entry.sustain.routed = true
	entry.sustain.morale = 20.0
	var supply_before := entry.duplicate(true)
	var cohort_before: Array = entry.sustain.cohorts.duplicate(true)
	var original_inventory: Dictionary = entry.inventory
	var total := _total_food(entry)
	if not _guard(): return false
	if not _near(_controller.team_food_capacity(_team), 12.0, "Initial original 6/3/3 capacity"): return false
	_team._finish_site_exit(0)
	if not _guard(): return false
	if not _check(bool(_team.combat_hot_get(0, &"site_exited", false)) and not _team.combat_can_act(0), "Fixture must use the original spatial exit commit"): return false
	if not _near(_controller.team_food_capacity(_team), 12.0, "Exited logistics member still carries original shared food"): return false
	var dropped := _controller.food_delivery.drop_excess(_team)
	if not _guard(): return false
	if not _check(dropped.ok and entry == supply_before and _lab.terrain.site.ground_loot.is_empty() and is_same(entry.inventory, original_inventory), "Partial exit must not move original stock, credits, or supply ownership"): return false
	# Later loss of a person still on this Site keeps the pre-existing capacity rule.
	_team.combat_hot_set(1, &"ko", 100.0)
	if not _guard(): return false
	_team.combat_hot_set(1, &"pose", "unconscious")
	if not _guard(): return false
	if not _near(_controller.team_food_capacity(_team), 9.0, "KO must still lose three rations of capacity"): return false
	dropped = _controller.food_delivery.drop_excess(_team)
	if not _guard(): return false
	if not _check(dropped.ok and dropped.has("container_id"), "Actual post-KO excess must use original ground stock: " + str(dropped)): return false
	var container: Dictionary = _lab.terrain.site.ground_loot[dropped.container_id]
	if not _check(int(container.original_owner) == _team.combat_identity(1) and int(container.cell) == _lab.terrain.index(_team.cells[1]) and int(container.cell) != _lab.terrain.index(_team.cells[0]), "Exited first row must not become the current-Site bearer"): return false
	if not _near(SiteSustain.rations(entry.sustain, entry.inventory), 9.0, "Only true post-KO excess leaves the shared store"): return false
	var observed_total_1: float = _total_food(entry)
	if not _guard(): return false
	if not _near(observed_total_1, total, "Whole and opened food stay conserved after KO"): return false
	var ground_before: Dictionary = _lab.terrain.site.ground_loot.duplicate(true)
	dropped = _controller.food_delivery.drop_excess(_team)
	if not _guard(): return false
	if not _check(dropped.ok and _lab.terrain.site.ground_loot == ground_before, "Repeated settling must not duplicate drops"): return false
	_team.combat_hot_set(2, &"hp", 0.0)
	if not _guard(): return false
	if not _near(_controller.team_food_capacity(_team), 6.0, "Death must still lose three rations of capacity"): return false
	dropped = _controller.food_delivery.drop_excess(_team)
	if not _guard(): return false
	if not _check(dropped.ok, "True post-death excess must retain the existing drop rule"): return false
	if not _near(SiteSustain.rations(entry.sustain, entry.inventory), 6.0, "Only the exited original logistics capacity remains"): return false
	var observed_total_2: float = _total_food(entry)
	if not _guard(): return false
	if not _near(observed_total_2, total, "Food remains conserved after later death"): return false
	if not _check(entry.sustain.cohorts == cohort_before, "Exit and drops must not rewrite original feeding cohorts"): return false
	# All spatial people leave; their original shares remain owned, never cloned.
	_team.combat_hot_set(1, &"ko", 0.0)
	if not _guard(): return false
	_team.combat_hot_set(1, &"pose", "idle")
	if not _guard(): return false
	_team.combat_hot_set(2, &"hp", 100.0)
	if not _guard(): return false
	for index: int in [1, 2]:
		_team.combat_hot_set(index, &"site_exited", true)
		if not _guard(): return false
		_team.combat_hot_set(index, &"present", false)
		if not _guard(): return false
	var all_exited := entry.duplicate(true)
	ground_before = _lab.terrain.site.ground_loot.duplicate(true)
	if not _near(_controller.team_food_capacity(_team), 12.0, "All exited original carriers retain capacity"): return false
	dropped = _controller.food_delivery.drop_excess(_team)
	if not _guard(): return false
	if not _check(dropped.ok and entry == all_exited and _lab.terrain.site.ground_loot == ground_before, "All exited must not drop retained stock back into this Site"): return false
	# An externally introduced excess still cannot use an off-Site body as a drop point.
	entry.inventory.grain = 20
	var no_bearer := entry.duplicate(true)
	dropped = _controller.food_delivery.drop_excess(_team)
	if not _guard(): return false
	if not _check(dropped.code == "BUSY" and entry == no_bearer and _lab.terrain.site.ground_loot == ground_before, "No on-Site bearer must preserve stock instead of remote dropping"): return false
	_actor = TerrainTestCharacter.new()
	_actor.person_id = 987654
	_actor.data = _lab.terrain
	_actor.terrain_cell = Vector2i(0, 10)
	_actor.item_state = SiteRuntime.new_item_state("person:%d" % _actor.person_id)
	_actor.site_exited = true
	_lab.character = _actor
	_lab.combat_actors = [_actor]
	_team.player_member = _actor
	if not _near(_controller.team_food_capacity(_team), 15.0, "Original exited player_member retains three capacity"): return false
	dropped = _controller.food_delivery.drop_excess(_team)
	if not _guard(): return false
	if not _check(dropped.code == "BUSY" and entry == no_bearer, "Exited player_member cannot be a current-Site bearer"): return false
	_actor.knockout_left = 100.0
	if not _near(_controller.team_food_capacity(_team), 12.0, "Exited Actor KO still loses capacity"): return false
	for field: String in ["captive", "surrender_pending", "departed"]:
		_team.combat_hot_set(0, StringName(field), true)
		if not _guard(): return false
		if not _near(_controller.team_food_capacity(_team), 6.0, "Exited logistics member remains ineligible when " + field): return false
		_team.combat_hot_set(0, StringName(field), false)
		if not _guard(): return false
	return true
