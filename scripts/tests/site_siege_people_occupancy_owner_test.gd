extends "res://scripts/tests/site_siege_ballista_contract_test.gd"
## Real bound original Controller/Army/Actor/ArmyCrowd occupancy, not a callback stub.
const OccupancyNativeSite = preload("res://scripts/terrain_lab/crowd_site.gd")
var occupancy_checks := 0
var occupancy_failed := false
var occupancy_kind := ""

func _expect(ok: bool, label: String, detail: Variant = null) -> bool:
	occupancy_checks += 1
	if ok: return true
	occupancy_failed = true
	push_error("SIEGE_PEOPLE_OWNER_FAIL: " + occupancy_kind + ": " + label + " " + str(detail))
	return false

func _state(c: Dictionary) -> PackedByteArray:
	var army: TerrainArmy = c.fixture.army
	var actors := []
	for actor: TerrainTestCharacter in c.lab.combat_actors:
		actors.append([actor.person_id, actor.terrain_cell, actor.movement_from_cell, actor.is_moving(), actor.hp, actor.knockout_left, actor.site_exited])
	return var_to_bytes([c.data.site, army.cells, army.moving_to, army.move_progress,
		army._reserved_cells, army._passage_descriptors, actors])

func _case(kind: String) -> bool:
	occupancy_kind = kind
	# Reuse the original real fixture and its actual SiteVehicleTransport binding.
	var c: Dictionary = _ballista_fixture(0)
	var army: TerrainArmy = c.fixture.army
	var anchor := Vector2i(30, 30)
	var native_site: Variant = null
	if kind in ["army_current", "army_ko", "army_dead"]:
		anchor = army.cells[0] # Original deployment, no relocation or invented claims.
		if kind == "army_ko": army.combat_hot_set(0, &"ko", 30.0)
		if kind == "army_dead": army.combat_hot_set(0, &"hp", 0.0) # Body not retired.
	elif kind == "army_destination":
		anchor = Vector2i(17, 18) # Keep (19,19) in the footprint; work slots avoid the old ballista.
		var committed := army._reserve_combat_step(1, Vector2i(19, 19))
		if not _expect(committed and army.moving_to[1] == Vector2i(19, 19)
			and army._reserved_cells.get(Vector2i(19, 19), -1) == 1, "Real original adjacent step holds its destination"):
			_close_ballista(c)
			return false
	elif kind.begins_with("actor_"):
		var actor := TerrainTestCharacter.new()
		actor.data = c.data
		actor.person_id = 70001
		var placed := actor.place(anchor + Vector2i(0, 2) if kind == "actor_destination" else anchor, true)
		c.lab.combat_actors.append(actor)
		if not _expect(placed, "Real Actor admits its original legal initial position"):
			_close_ballista(c)
			return false
		if kind == "actor_ko": actor.knockout_left = 30.0
		if kind == "actor_dead": actor.hp = 0.0 # Not site_exited/retired.
		if kind == "actor_destination":
			var moving := actor.step(Vector2i.UP)
			if not _expect(moving and actor.is_moving() and actor.terrain_cell == anchor + Vector2i(0, 1), "Real Actor original movement holds a destination inside the future footprint"):
				_close_ballista(c)
				return false
	elif kind.begins_with("native_"):
		if not _expect(ClassDB.class_exists(&"ArmyCrowd"), "Real Native DLL required; no fallback or skip"):
			_close_ballista(c)
			return false
		native_site = OccupancyNativeSite.new()
		native_site.lab = c.lab
		c.lab.crowd_site = native_site
		native_site.crowd = ClassDB.instantiate(&"ArmyCrowd")
		native_site.crowd.setup(1, 987)
		if not _expect(native_site.sync_terrain() and native_site.siege_native_supported(), "Actual native terrain and occupancy APIs admitted"):
			c.lab.crowd_site = null
			native_site.free()
			_close_ballista(c)
			return false
		var start_cell: Vector2i = anchor + Vector2i(3, 0) if kind == "native_destination" else anchor
		var group: int = native_site.crowd.add_formation(1, start_cell.x + 0.5, start_cell.y + 0.5, 0.0, 1, 1.0, 0, 0.0)
		var first: int = native_site.crowd.add_soldiers(group, PackedInt64Array([70002]), PackedInt32Array([0]), PackedByteArray([1]), PackedInt32Array([0]))
		var positioned: bool = native_site.crowd.set_start_positions(first, PackedFloat32Array([start_cell.x + 0.5, start_cell.y + 0.5]))
		native_site.crowd.finalize()
		native_site.crowd.set_ai(false)
		native_site.active = true
		if not _expect(first == 0 and positioned, "Real ArmyCrowd original person imported at the exact start"):
			c.lab.crowd_site = null
			native_site.free()
			_close_ballista(c)
			return false
		if kind == "native_destination":
			var ordered: bool = native_site.crowd.order_siege_step(first, c.data.index(anchor + Vector2i(2, 0)))
			if not _expect(ordered, "Actual native controlled-step owner holds its adjacent destination"):
				c.lab.crowd_site = null
				native_site.free()
				_close_ballista(c)
				return false
	var inventory: Dictionary = c.data.site.inventory.duplicate(true)
	# Legacy original Runtime build with no external occupancy callback creates the
	# negative precondition. Its actual paid job is then checked by the real owner.
	var begun: Dictionary = SiteRuntime.begin_siege_build(c.data, "ballista", anchor, Vector2i.RIGHT, int(army.team_id), int(c.commander))
	if not _expect(begun.ok, "Original full-cost unfinished job exists", begun):
		if native_site != null:
			c.lab.crowd_site = null
			native_site.free()
		_close_ballista(c)
		return false
	var key := str(begun.vehicle)
	var vehicle: Dictionary = c.data.site.vehicles[key]
	var cells: Array[Vector2i] = SiteRuntime.siege_cells(c.data, vehicle)
	if kind == "protected":
		# Original Army prepared passage descriptor, same fixture API used by
		# site_army_navigation_test; the real owner predicate reads this record.
		army._passage_descriptors = [{"entry": cells[0] + Vector2i.LEFT, "core": [cells[0]],
			"exit": cells[0] + Vector2i.RIGHT, "protected": [cells[0]]}]
		_expect(not c.controller._actor_people_blocked(cells[0], null) and army._passage_cell_is_protected(cells[0]), "Protected passage is distinct from an actual person")
	var before: PackedByteArray = _state(c)
	var native_hash := str(native_site.crowd.state_hash()) if native_site != null else ""
	var cancelled: Dictionary = SiteRuntime.cancel_siege_job(c.data, key, int(army.team_id), c.controller._siege_people_occupied)
	if kind == "empty_people":
		_expect(cancelled.ok and cancelled.refund == SiteRuntime.SIEGE_DEFINITIONS.ballista.cost
			and c.data.site.inventory == inventory and not c.data.site.vehicles.has(key), "Own vehicle footprint alone cannot block exact original full refund", cancelled)
		var after := _state(c)
		var repeated: Dictionary = SiteRuntime.cancel_siege_job(c.data, key, int(army.team_id), c.controller._siege_people_occupied)
		_expect(not repeated.ok and _state(c) == after, "Cancellation cannot refund twice or rewind allocators", repeated)
	else:
		_expect(not cancelled.ok and cancelled.code == "OCCUPIED" and _state(c) == before,
			"Actual " + kind + " claim keeps job/materials/movement byte-identical", cancelled)
		if native_site != null:
			_expect(str(native_site.crowd.state_hash()) == native_hash, "Occupancy query never mutates the real native world")
	if native_site != null:
		c.lab.crowd_site = null
		native_site.free()
	_close_ballista(c) # Each case is a fresh fixture; never clear a claim to make it pass.
	return not occupancy_failed

func _run() -> void:
	for kind: String in ["empty_people", "army_current", "army_ko", "army_dead", "army_destination",
		"actor_current", "actor_ko", "actor_dead", "actor_destination", "protected", "native_current", "native_destination"]:
		if not _case(kind):
			TerrainArmy.release_contact_source()
			quit(1)
			return
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_PEOPLE_OCCUPANCY_OWNER_PASS checks=%d; real paid job, original GD/Actor/native current/destination/KO/dead/passages; no guard whitelist or movement clearing" % occupancy_checks)
	quit(0)
