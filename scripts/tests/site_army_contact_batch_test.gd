extends SceneTree
## GPU-backed original Army projection contract, not 200-person combat/FPS.
## Diagnostic sweeps use original projected polygons; no production shape is changed.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

class ObservedArmy extends TerrainArmy:
	var fixture: TerrainLab
	var probe_enabled := true
	var previous: Array[PackedVector2Array] = []
	var current: Array[PackedVector2Array] = []
	var geometry_calls := 0
	var ground_calls := 0
	var ground_deltas: Array[int] = []
	var sampled_grounds: Array[Vector2] = []
	var bounds_snapshots := {}
	var weapon_calls := 0
	var snapshots := {}
	var results: Array = []
	var history_counts: Array[int] = []
	func combat_ground(index: int) -> Vector2:
		ground_calls += 1
		return super.combat_ground(index)
	func combat_bounds(index: int) -> Rect2:
		var result := super.combat_bounds(index)
		bounds_snapshots[index] = result
		return result
	func incoming_geometry(index: int) -> Dictionary:
		geometry_calls += 1
		var result := super.incoming_geometry(index)
		snapshots[index] = result
		return result
	func combat_shapes(index: int, kind: String) -> Array[PackedVector2Array]:
		weapon_calls += int(kind == "weapon")
		return super.combat_shapes(index, kind)
	func sample_combat() -> void:
		if not probe_enabled:
			super.sample_combat()
			return
		results.clear()
		ground_deltas.clear()
		for source: int in [2, 3, 2, 3]:
			var source_position := combat_ground(source)
			var before := ground_calls
			results.append(fixture._collect_army_contacts(previous, current, cells[source], source_position, self, source))
			ground_deltas.append(ground_calls - before)
		var targets: Array = fixture._army_contact_geometry[["targets", get_instance_id()]]
		assert(targets.size() == combat_units.size(), "Private target slots match only this batch's actual roster")
		for index in range(targets.size()):
			if targets[index] == null:
				continue
			for other in range(index + 1, targets.size()):
				if targets[other] != null:
					assert(not is_same(targets[index], targets[other]), "Each original target has its own lazy Dictionary")
		sampled_grounds = fixture._army_contact_geometry[["grounds", get_instance_id()]].duplicate()

func _initialize() -> void:
	call_deferred("run")

func _same_geometry(team: TerrainArmy, index: int, sampled: Dictionary) -> void:
	assert(sampled.keys() == ["body", "shield", "parry", "bounds"])
	assert(sampled.bounds == team.combat_bounds(index), "World bounds remain exact")
	for kind: String in ["body", "shield", "parry"]:
		var original := team.combat_shapes(index, kind)
		assert(sampled[kind].size() == original.size())
		for polygon: int in range(original.size()):
			assert(sampled[kind][polygon] == original[polygon], "Every original vertex must match, without a tolerance or rounded time")

func _batch(lab: TerrainLab, team: ObservedArmy) -> void:
	var previous_calls := team.geometry_calls
	team.snapshots.clear()
	team.bounds_snapshots.clear()
	lab._advance_combat(1.0 / 120.0)
	assert(team.sampled_grounds.size() == team.combat_units.size())
	for index: int in team.combat_units.size():
		assert(team.sampled_grounds[index] == team.combat_ground(index), "Every cached anchor is the exact original ground, not a rounded cell")
	assert(team.ground_deltas[2] == 0 and team.ground_deltas[3] == 0, "Repeated same-step contacts do not recompute any ground after original target geometry is cached")
	assert(team.bounds_snapshots.size() == 4, "The same four original targets retain exact pose bounds")
	var sweep_bounds := Rect2(team.current[0][0], Vector2.ZERO)
	for shapes: Array in [team.previous, team.current]:
		for shape: PackedVector2Array in shapes:
			for vertex: Vector2 in shape:
				sweep_bounds = sweep_bounds.expand(vertex)
	sweep_bounds = sweep_bounds.grow(0.001)
	var required := 0
	for index: int in team.bounds_snapshots:
		var needs_polygons: bool = sweep_bounds.intersects(team.bounds_snapshots[index], true)
		assert(team.snapshots.has(index) == needs_polygons, "Only exact intersecting bounds expand original world polygons")
		required += int(needs_polygons)
	assert(required > 0 and required < 4 and team.geometry_calls - previous_calls == required,
		"Repeated attacks expand each required target once and skip the provably disjoint targets")
	assert(not lab._sampling_army_contacts and lab._army_contact_geometry.is_empty(), "The original batch must discard all snapshots before applying contacts")
	var total_hits := 0
	for attempt: int in 4:
		var source := 2 if attempt % 2 == 0 else 3
		var source_position := team.combat_ground(source)
		var before := team.ground_calls
		var direct := lab._collect_army_contacts(team.previous, team.current, team.cells[source], source_position, team, source)
		assert(team.ground_calls > before and lab._army_contact_geometry.is_empty(), "Outside the batch all ground queries stay live and retain no snapshot")
		assert(team.results[attempt] == direct, "Cached and uncached target/identity/faction/fraction/point/body/block/distance/order must be exactly identical")
		total_hits += direct.size()
	assert(total_hits > 0, "Include actual intersections, not an all-miss cache test")
	for index: int in range(team.combat_units.size()):
		# Independently inspect every original target after the measured batch,
		# including polygons the optimized broad phase correctly never needed.
		var original_geometry := team.incoming_geometry(index)
		assert(original_geometry.bounds == team.bounds_snapshots[index])
		_same_geometry(team, index, team.snapshots[index])
		for ranged: bool in [false, true]:
			var direct := team.combat_contact(index, team.previous, team.current, ranged)
			assert(direct == team.combat_contact(index, team.previous, team.current, ranged, team.snapshots[index]))

func _anchor_edges(lab: TerrainLab, team: ObservedArmy) -> void:
	# A second real Army uses a separate snapshot and still submits index zero
	# to exact bounds even when its ground is far outside the 256px broad phase.
	var second := ObservedArmy.new()
	root.add_child(second)
	second.set_process(false)
	second.probe_enabled = false
	second.roster_size = 2
	var cells: Array[Vector2i] = [Vector2i(40, 40), Vector2i(41, 40)]
	assert(second.deploy_at(team.data, null, null, cells) and second.enable_combat(false))
	second._ensure_live_presenters()
	second.advance_frame(0.0)
	assert(second._uses_live_presenter(0) and second._unit_editor(0) != null)
	second.bounds_snapshots.clear()
	lab.combat_armies.append(second)
	var far := Geometry.shifted(team.current, Vector2(-10000.0, -10000.0))
	assert(lab._army_contact_geometry.is_empty())
	lab._sampling_army_contacts = true
	assert(lab._collect_army_contacts([], far, team.cells[2], Vector2.ZERO, team, 2).is_empty())
	assert(lab._army_contact_geometry.has(["grounds", team.get_instance_id()]) and lab._army_contact_geometry.has(["grounds", second.get_instance_id()]))
	assert(second.bounds_snapshots.keys() == [0], "Far index zero remains checked; far ordinary index one retains the exact old anchor rejection")
	var before := team.ground_calls + second.ground_calls
	assert(lab._collect_army_contacts([], far, team.cells[2], Vector2.ZERO, team, 2).is_empty())
	assert(team.ground_calls + second.ground_calls == before, "Repeated broad-phase misses reuse both teams' original anchors")
	lab._sampling_army_contacts = false
	lab._army_contact_geometry.clear()
	# Advance an already committed real step outside the collection batch. The
	# next direct query must read its new ground immediately, not the old snapshot.
	var old_ground := team.combat_ground(1)
	var old_bounds := team.combat_bounds(1)
	team.prepare_combat(1.0 / 120.0)
	assert(team.combat_ground(1) != old_ground)
	team.bounds_snapshots.clear()
	var direct := lab._collect_army_contacts(team.previous, team.current, team.cells[2], team.combat_ground(2), team, 2)
	assert(team.bounds_snapshots[1] == team.combat_bounds(1) and team.bounds_snapshots[1] != old_bounds)
	assert(direct == lab._collect_army_contacts(team.previous, team.current, team.cells[2], team.combat_ground(2), team, 2))
	assert(lab._army_contact_geometry.is_empty(), "Direct movement queries must not recreate a batch cache")
	var next_ground := team.combat_ground(1)
	lab._advance_combat(1.0 / 120.0)
	assert(team.sampled_grounds[1] == team.combat_ground(1) and team.sampled_grounds[1] != next_ground)
	assert(not lab._sampling_army_contacts and lab._army_contact_geometry.is_empty(), "The next real batch clears both teams' anchor/geometry snapshots")
	lab.combat_armies.erase(second)
	second.free()

func _remove(team: TerrainArmy, index: int, slot: String) -> void:
	var row: Dictionary = team.combat_units[index]
	var identity := str(row.item_state.equipped[slot])
	assert(Runtime.transfer_items(team.data, row.item_state, row.cargo, team.data.site.depot_items, team.data.site.inventory,
		{}, [identity], int(row.item_state.version), int(team.data.site.depot_items.version), int(team.data.site.capacity)).ok)
	assert(not row.item_state.item_ids.has(identity) and team.data.site.depot_items.item_ids.has(identity))

func _active_boundary(team: ObservedArmy) -> void:
	team.probe_enabled = false
	team.contact_query = func(previous: Array[PackedVector2Array], _current: Array[PackedVector2Array], _cell: Vector2i, _position: Vector2, _owner: Variant, _index: int) -> Array[Dictionary]:
		team.history_counts.append(previous.size())
		return []
	var row: Dictionary = team.combat_units[2]
	row.pose = "walk_slash"
	row.attack = true
	row.blocked = false
	row.attack_reduction = 0.0
	row.attack_fatigue = 0.0
	row.previous = team.combat_shapes(2, "weapon")
	var events := TerrainArmy.CombatTimings.events(&"walk_slash")
	var initial := team.weapon_calls
	row.age = float(events.active_start) - 0.0001
	team.sample_combat()
	assert(team.weapon_calls == initial and row.previous.is_empty() and team.history_counts.is_empty())
	row.age = float(events.active_start)
	team.sample_combat()
	assert(team.weapon_calls == initial + 1 and team.history_counts == [0])
	var active_polygon_count: int = row.previous.size()
	assert(active_polygon_count > 0)
	row.age += 0.001
	team.sample_combat()
	assert(team.weapon_calls == initial + 2 and team.history_counts == [0, active_polygon_count])
	row.age = float(events.active_end) + 0.0001
	team.sample_combat()
	assert(team.weapon_calls == initial + 2 and row.previous.is_empty() and team.history_counts == [0, active_polygon_count])

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless", "This contract includes the original woman's live geometry; use the GPU verifier")
	var lab := TerrainLab.new() # Only the original combat coordinator, no unrelated UI setup.
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	SiteEnvironment.initialize(data, "army-contact-batch-contract")
	# Explicit spatial test fixture, not a generated-terrain save or game benchmark.
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	assert(Runtime.initialize_item_storage(data.site).ok)
	lab.terrain = data
	var team := ObservedArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(20, 20), Vector2i(21, 20), Vector2i(20, 21), Vector2i(21, 21)]
	assert(team.deploy_at(data, null, null, cells) and team.enable_combat(false))
	team._ensure_live_presenters()
	team.advance_frame(0.0)
	assert(team._uses_live_presenter(0) and team._unit_editor(0) != null)
	for index: int in range(team.combat_units.size()):
		var row: Dictionary = team.combat_units[index]
		row.appearance = team._unit_editor(0).capture_appearance() if index == 0 else TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		row.item_state = {}
		row.cargo = {}
		assert(Runtime.seed_person_equipment(data, row.item_state, team.combat_identity(index), row.appearance).ok)
		row.think = 100.0
	team.equipment_appearance_query = func(identity: int) -> Dictionary:
		var row: Dictionary = team.combat_units[team.index_for_identity(identity)]
		return Runtime.equipment_appearance(data, row.item_state, row.appearance)
	lab.combat_armies.assign([team])
	team.fixture = lab
	var target: Dictionary = team.combat_units[1]
	var original_body: Dictionary = target
	var item_count: int = data.site.item_records.size()
	var source_editor: int = TerrainArmy._contact_source.editor.get_instance_id()
	var female_editor: int = team._unit_editor(0).get_instance_id()
	# Contact diagnostics use one exact original body polygon and its translated
	# previous position so comparisons cover a real narrow-phase intersection.
	team.current = [team.combat_shapes(1, "body")[0]]
	team.previous = Geometry.shifted(team.current, Vector2(-20.0, 0.0))
	_batch(lab, team)
	target.pose = "guard"
	target.age = 0.073
	_batch(lab, team)
	assert(not team.snapshots[1].shield.is_empty())
	_remove(team, 1, "shield")
	_batch(lab, team)
	assert(team.snapshots[1].shield.is_empty() and not team.snapshots[1].parry.is_empty())
	assert(not team.snapshots[2].shield.is_empty(), "Removing one original shield cannot change another person")
	_remove(team, 1, "weapon")
	_remove(team, 1, "armor")
	_batch(lab, team)
	assert(team.snapshots[1].shield.is_empty() and team.snapshots[1].parry.is_empty())
	assert(team.equipment_appearance(1).parts.weapon == "none" and team.equipment_appearance(1).parts.armor == "none")
	target.pose = "idle"
	target.age = 0.0
	assert(team._reserve_combat_step(1, cells[1] + Vector2i.RIGHT))
	_batch(lab, team)
	var moving_bounds: Rect2 = team.snapshots[1].bounds
	_batch(lab, team)
	assert(team.snapshots[1].bounds.position != moving_bounds.position and team.moving_to[1] != TerrainArmy.INVALID_CELL, "Next 120Hz step sees the actual moving origin")
	_anchor_edges(lab, team)
	_active_boundary(team)
	assert(is_same(target, original_body) and data.site.item_records.size() == item_count)
	assert(TerrainArmy._contact_source.editor.get_instance_id() == source_editor and team._unit_editor(0).get_instance_id() == female_editor)
	lab.combat_armies.clear()
	lab.free()
	team.free()
	TerrainArmy.release_contact_source()
	print("SITE ARMY CONTACT BATCH PASS: exact original vertices and ordered contact fields cached/uncached; same-batch original ground reuse and second-Army far-index0 preservation, live women plus ordinary actual equipment/guard/movement/removal, direct movement/next-step invalidation, ranged parry exclusion and active-only weapon history; not FPS")
	quit(0)
