extends "res://scripts/tests/site_siege_close_visual_test.gd"
## Extra isolated GPU entrypoint; leaves the existing31 visual cases unchanged.
## Original Army rows/items + actual original live rig/Actor meshes and movement.
## Explicit FootSource preparation proves resource availability only; these
## male_live rows contact through original live combat_shapes, not FootSource.
## No ProjectedActor or authored fake body/shield boxes.
const EdgeCollision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
var contact_case := "late_friend"
var edge_flight: Dictionary = {}
var natural_raise_armed := false
var natural_raise_sent := false
var natural_raise_lead := 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--siege-contact-case")
	if at >= 0 and at + 1 < args.size(): contact_case = args[at + 1]
	super._initialize()

func _paid_vehicle(kind: String) -> bool:
	if contact_case == "shield_only":
		if not _expect(kind == "ballista" and lab.terrain.site.vehicles.is_empty(), "finite lawful gun Genesis precedes original paid build"): return false
		anchor = Vector2i(35, 26)
	return super._paid_vehicle(kind)

func _step() -> bool:
	if natural_raise_armed:
		var action: Dictionary = lab.terrain.site.vehicles[key].get("action", {})
		if str(action.get("stage", "")) == "aiming":
			var rule: Dictionary = SiteCombatRules.siege_attack("ballista")
			var multiplier := float(action.get("multiplier", 0.0))
			if not _expect(multiplier > 0.0, "original paid aiming has a real positive crew multiplier"): return false
			var remaining := maxf(0.0, float(rule.aiming) - float(action.elapsed)) / multiplier
			if remaining <= natural_raise_lead + 0.000000001:
				if not _expect(team.set_unit_guard(3, true), "original guard input naturally begins during the actual paid aiming window"): return false
				natural_raise_armed = false
				natural_raise_sent = true
	return super._step()

func _army(positions: Array[Vector2i]) -> bool:
	if contact_case == "shield_only":
		if not _expect(positions.size() == 4 and positions[3] == Vector2i(46, 32), "same four original IDs use the unchanged target-person Genesis"): return false
		positions = positions.duplicate()
		var vehicle: Dictionary = lab.terrain.site.vehicles[key]
		positions[1] = SiteRuntime.siege_crew_cell(lab.terrain, vehicle, "0")
		positions[2] = SiteRuntime.siege_crew_cell(lab.terrain, vehicle, "1")
	team = lab.army
	team.team_id = 1
	team.roster_size = positions.size()
	team.defer_captain_presenter = false
	# Defer only the FIRST original item seed during fresh Genesis. No step/yield
	# occurs here, no existing holder is cleared, and the original callback is
	# restored before any failure return or original UI item transaction.
	var initializer: Callable = team.equipment_initializer
	if not _expect(initializer.is_valid() and initializer.get_object() == ui
		and initializer.get_method() == &"initialize_team_items", "fresh Genesis retains the original UI equipment initializer"): return false
	team.equipment_initializer = Callable()
	var enabled: bool = team.deploy_at(lab.terrain, lab.character, lab.npc, positions) and team.enable_combat(false, 0)
	team.equipment_initializer = initializer
	if not _expect(enabled, "same original Army allocates all true contact rows"): return false
	team.set_process(false)
	team.tactical_ai_enabled = false
	for index in range(positions.size()):
		var unit: Dictionary = team.combat_units[index]
		if not _expect(unit.get("item_state", {}).is_empty(), "fresh original person has no seeded holder before Genesis equipment", team.combat_identity(index)): return false
		unit.visual_role = "male_live"
		var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		appearance.parts.armor = "none"
		appearance.parts.shield = "shield_japanese_wood_01" if contact_case == "shield_only" and index == 3 else "none"
		if not _expect(HumanCharacter3DEditor.valid_appearance(appearance), "full Genesis appearance uses only original legal parts", appearance): return false
		unit.appearance = appearance
		team.facing[index] = Vector2i.LEFT if index >= 3 else Vector2i.RIGHT
	ui.initialize_team_items(team) # First and only seed, through the original real item owner.
	for index in range(positions.size()):
		var unit: Dictionary = team.combat_units[index]
		var id: int = team.combat_identity(index)
		var appearance: Dictionary = ui.person_appearance(id)
		var holder: Dictionary = unit.get("item_state", {})
		var equipped: Dictionary = holder.get("equipped", {})
		var expected_shield: String = "shield_japanese_wood_01" if contact_case == "shield_only" and index == 3 else "none"
		var shield_id: String = str(equipped.get("shield", ""))
		var shield_record: Dictionary = lab.terrain.site.item_records.get(shield_id, {})
		var shield_definition: Dictionary = lab.terrain.site.item_definitions.get(str(shield_record.get("definition", "")), {})
		var actual_shield: bool = shield_id.is_empty() if expected_shield == "none" else (not shield_id.is_empty()
			and str(shield_record.get("holder", "")) == str(holder.get("holder", ""))
			and str(shield_definition.get("slot", "")) == "shield" and str(shield_definition.get("asset", "")) == expected_shield)
		if not _expect(HumanCharacter3DEditor.valid_appearance(appearance) and str(holder.get("holder", "")) == "person:%d" % id
			and str(appearance.get("parts", {}).get("armor", "")) == "none" and str(equipped.get("armor", "")).is_empty()
			and str(appearance.get("parts", {}).get("shield", "")) == expected_shield and actual_shield,
			"original actual holder/records and UI projection match the legal Genesis armor/shield", {"person_id": id, "holder": holder, "appearance": appearance, "shield_record": shield_record, "shield_definition": shield_definition}): return false
		if not _expect(TerrainArmy.prepare_contact_source_for(appearance, lab.character.editor), "explicit FootSource preparation makes the actual body/equipment resource available; contact remains original live rig", id): return false
		original_ids.append(id)
	team._rebuild_visual_instances()
	lab.terrain.site.army_next_team = 2
	if contact_case == "shield_only":
		if not _expect(shared_steps == 0 and team.moving_to[3] == TerrainArmy.INVALID_CELL, "fresh original person direction is chosen before any original shared step"): return false
		team.facing[3] = Vector2i.UP
	return _expect(team._sprites.size() == positions.size(), "all original live person slots remain under the original presenter")

func _ray(geometry: Dictionary, cell: Vector2i, shield_only: bool = false, all_bodies: Array = []) -> Dictionary:
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var start := lab.siege_muzzle(vehicle) * TerrainRenderer.CELL_PIXELS - Vector2(0, 48)
	# The original real-geometry fixture already uses this finite legal ground
	# target lattice. It runs once during explicit setup, never in production.
	for y in range(cell.y - 4, cell.y + 5):
		for x in range(cell.x + 3, cell.x + 13):
			var target := {"type": "ground", "cell": [x, y]}
			if not lab.siege_fire_preview(vehicle, target).ok: continue
			var end := (Vector2(x, y) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, 48)
			var direction := (end - start).normalized()
			var previous: Array[PackedVector2Array] = lab._siege_bolt_shape(start, direction)
			var current: Array[PackedVector2Array] = lab._siege_bolt_shape(end, direction)
			var body: Dictionary = EdgeCollision.contact(previous, current, geometry.body)
			var shield: Dictionary = EdgeCollision.contact(previous, current, geometry.shield)
			if shield_only:
				if shield.is_empty() or not body.is_empty(): continue
			elif body.is_empty(): continue
			var all_hit := true
			for polygons: Array in all_bodies:
				if EdgeCollision.contact(previous, current, polygons).is_empty(): all_hit = false; break
			if all_hit: return {"target": target, "body": body, "shield": shield, "start": start, "end": end}
	return {}

func _shifted(geometry: Dictionary, offset: Vector2) -> Dictionary:
	# Predict only the destination's contact oracle from the original Actor's
	# present mesh; the real Actor still owns position and must finish its step.
	var body: Array[PackedVector2Array] = []
	var shield: Array[PackedVector2Array] = []
	var out := {"body": body, "shield": shield}
	for name: String in ["body", "shield"]:
		for polygon: PackedVector2Array in geometry[name]:
			var moved := PackedVector2Array()
			for point: Vector2 in polygon: moved.append(point + offset)
			out[name].append(moved)
	return out

func _release(target: Dictionary) -> bool:
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var version := int(vehicle.holder.version)
	var before := int(vehicle.cargo.siege_bolt)
	var seq := int(vehicle.next_attack_seq)
	var ordered := ui.vehicles.order_siege(key, "attack", target, original_ids[0], true)
	if not _expect(ordered.ok, "original crew starts one actual paid release", ordered): return false
	for tick in range(1200):
		if not _step(): return false
		if lab.has_siege_projectiles(): break
		if tick % 120 == 0: await process_frame
	if not _expect(lab.siege_projectiles.size() == 1 and lab.siege_shots == 1
		and int(vehicle.cargo.get("siege_bolt", 0)) == before - 1 and int(vehicle.holder.version) == version + 1
		and int(vehicle.next_attack_seq) == seq + 1, "exactly one actual released round owns its original ammo/sequence"): return false
	edge_flight = lab.siege_projectiles[0]
	return _expect(ui.vehicles.order_siege(key, "stop", {}, original_ids[0], true).ok, "stop retains the irreversible original projectile and recovery")

func _settle() -> bool:
	for tick in range(600):
		if not _step(): return false
		if not lab.has_siege_projectiles() and lab.terrain.site.vehicles[key].action.is_empty(): return true
		if tick % 120 == 0: await process_frame
	return _expect(false, "actual contact flight/recovery did not settle", edge_flight)

func _late_friend() -> bool:
	var actor: TerrainTestCharacter = lab.character
	var source := Vector2i(48, 31)
	var destination := source + Vector2i.DOWN
	if not _expect(actor.editor != null and actor.place(source, true), "original live Actor begins outside the eventual ray"): return false
	actor.faction_id = team.faction_id # Explicit same-faction initial fixture.
	var current: Dictionary = actor.incoming_geometry(true)
	if not _expect(not current.body.is_empty(), "actual original rendered Actor publishes body mesh"): return false
	var selected := _ray(_shifted(current, Vector2(0, 64)), destination)
	if not _expect(not selected.is_empty(), "one legal ground ray crosses the real future body", destination): return false
	var direction: Vector2 = (Vector2(selected.end) - Vector2(selected.start)).normalized()
	if not _expect(EdgeCollision.contact(lab._siege_bolt_shape(selected.start, direction), lab._siege_bolt_shape(selected.end, direction), current.body).is_empty()
		and not lab.siege_fire_preview(lab.terrain.site.vehicles[key], selected.target).friendly_ids.has(actor.person_id), "friend is actually outside fire-warning/body ray before original release"): return false
	var hp := actor.hp
	var person_id := actor.person_id
	var holder: Dictionary = actor.item_state
	var before_contacts := lab.siege_contacts
	if not await _release(selected.target): return false
	if not _expect(edge_flight.people.is_empty() and actor.hp == hp, "friend was not hit or counted before its late movement"): return false
	if not _expect(actor.step(Vector2i.DOWN), "after release original friend begins a true adjacent Actor step"): return false
	if not await _settle(): return false
	if not _expect(actor.terrain_cell == destination and not actor.is_moving() and actor.person_id == person_id and is_same(actor.item_state, holder)
		and actor.hp < hp and edge_flight.bodies.has(person_id) and edge_flight.people.size() == 1
		and lab.siege_contacts - before_contacts == 1, "post-release original friendly mesh is hit exactly once through the original HP owner", edge_flight): return false
	return await _capture("01_actual_late_friend", {"geometry_owner": "original live Actor incoming_geometry", "FootSource_preparation_scope": "resource availability only; not this case contact provider", "target_id": person_id, "source": source, "destination": destination, "hp_before": hp, "hp_after": actor.hp, "attack_id": edge_flight.attack_id})

func _shield_only() -> bool:
	var target_id: int = original_ids[3]
	var appearance: Dictionary = ui.person_appearance(target_id)
	if not _expect(team.cells[3] == Vector2i(46, 32) and team.facing[3] == Vector2i.UP
		and str(appearance.parts.shield) == "shield_japanese_wood_01"
		and not str(team.combat_units[3].item_state.equipped.get("shield", "")).is_empty(),
		"same original UP person retains the original legally seeded Japanese shield"): return false
	var raise_clock: Array = TerrainArmy._combat_bake.contact_clocks.guard_raise.up
	var guard_clock: Array = TerrainArmy._combat_bake.contact_clocks.guard.up
	if not _expect(not bool(raise_clock[2]) and bool(guard_clock[2]) and float(guard_clock[1]) > 5.0 * DT,
		"late guard timing uses the actual original contact clocks"): return false
	var desired_guard_age := float(guard_clock[1]) - 5.0 * DT
	if not _expect(team.set_unit_guard(3, true), "original held shield enters original guard stance"): return false
	if not _seconds(float(raise_clock[1]) + desired_guard_age): return false
	var geometry: Dictionary = team.incoming_geometry(3)
	if not _expect(not geometry.body.is_empty() and not geometry.shield.is_empty()
		and str(team.combat_hot_get(3, &"pose")) == "guard", "natural late guard publishes the complete original live body and shield"): return false
	var selected: Dictionary = _ray(geometry, team.cells[3], true)
	if not _expect(not selected.is_empty(), "bounded original mesh query found a legal shield-only/body-miss ray",
		{"body_count": geometry.body.size(), "shield_count": geometry.shield.size()}): return false
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var aim: Dictionary = lab.siege_target(selected.target)
	var rule: Dictionary = SiteCombatRules.siege_attack("ballista")
	var total := lab.siege_muzzle(vehicle).distance_to(Vector2(aim.point)) / float(rule.speed)
	var estimated_contact_seconds := total * float(selected.shield.fraction)
	natural_raise_lead = float(raise_clock[1]) + desired_guard_age - estimated_contact_seconds
	if not _expect(natural_raise_lead > 0.0 and natural_raise_lead < float(rule.aiming),
		"original selected contact fraction yields a finite natural aiming cue", natural_raise_lead): return false
	if not _expect(team.set_unit_guard(3, false), "original guard naturally lowers before the timed real shot"): return false
	if not _seconds(float(raise_clock[1])) or not _expect(str(team.combat_hot_get(3, &"pose")) == "idle", "original lowering naturally settles without a pose or clock write"): return false
	natural_raise_armed = true
	var hp := float(team.combat_hot_get(3, &"hp"))
	var contact_count := lab.siege_contacts
	if not await _release(selected.target) or not await _settle(): return false
	if not _expect(natural_raise_sent and not natural_raise_armed, "real aiming emitted exactly one original guard input"): return false
	if not _expect(edge_flight.shields.has(target_id) and not edge_flight.bodies.has(target_id)
		and float(team.combat_hot_get(3, &"hp")) == hp and lab.siege_contacts == contact_count
		and float(edge_flight.budget) < float(SiteCombatRules.BALLISTA.budget), "actual held-shield-only contact consumes resistance but causes zero body HP loss", edge_flight): return false
	return await _capture("01_actual_shield_only", {"geometry_owner": "original Army male_live combat_shapes", "FootSource_preparation_scope": "resource availability only; not this case contact provider", "target_id": target_id, "hp_loss": 0.0, "body_contact": false, "shield_contact": true, "attack_id": edge_flight.attack_id})

func _wall_fourth() -> bool:
	var wall := _build(lab.terrain, "stone_wall", Vector2i(49, 31), Vector2i(1, 3))
	var wall_before: Dictionary = lab.terrain.site.features[wall].parts.duplicate(true)
	var bodies: Array = []
	var hp_before: Array[float] = []
	for index in range(3, 7):
		var geometry: Dictionary = team.incoming_geometry(index)
		if not _expect(not geometry.body.is_empty(), "each original target publishes its actual original live rig mesh", original_ids[index]): return false
		bodies.append(geometry.body)
		hp_before.append(float(team.combat_hot_get(index, &"hp")))
	var selected := _ray(team.incoming_geometry(6), team.cells[6], false, bodies)
	if not _expect(not selected.is_empty() and team.cells[6].x > 49, "same original ray intersects four actual target bodies with the fourth behind a real paid wall"): return false
	var contact_count := lab.siege_contacts
	if not await _release(selected.target) or not await _settle(): return false
	for ordinal in range(3):
		if not _expect(float(team.combat_hot_get(ordinal + 3, &"hp")) < hp_before[ordinal]
			and edge_flight.bodies.has(original_ids[ordinal + 3]), "the first three actual original bodies each receive one real hit", ordinal): return false
	if not _expect(float(team.combat_hot_get(6, &"hp")) == hp_before[3] and not edge_flight.bodies.has(original_ids[6])
		and edge_flight.people.size() == 3 and lab.siege_contacts - contact_count == 3, "fourth original person behind the real wall receives zero HP after the three-person spent bolt", edge_flight): return false
	# Three original body resistances spend the original budget before the wall;
	# don't pretend this one case independently proves wall stopping power.
	if not _expect(lab.terrain.site.features[wall].parts == wall_before, "spent original bolt cannot continue damaging the wall behind its third person"): return false
	return await _capture("01_actual_wall_fourth", {"geometry_owner": "original Army male_live combat_shapes", "FootSource_preparation_scope": "resource availability only; not this case contact provider", "target_ids": original_ids.slice(3, 7), "wall_id": wall, "body_contacts": 3, "fourth_hp_loss": 0.0, "attack_id": edge_flight.attack_id})

func _focus() -> void:
	# Use the SAME original Camera2D. Original CloseVisual's window is1800x1100;
	# the x40.5 centre at zoom1 shows gun/crew x31..35 through the last body x52.5.
	# No original scene owner writes limits or offset; verify the actual canvas
	# transform at capture instead of assuming this requested position took effect.
	lab.camera.zoom = Vector2.ONE
	lab.camera.position = Vector2(40.5, 32.0) * TerrainRenderer.CELL_PIXELS - Vector2(0, 75)
	lab.camera.reset_smoothing()
	lab.camera.force_update_scroll()

func _mesh_points(geometry: Dictionary) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for name: String in ["body", "shield"]:
		for polygon: PackedVector2Array in geometry[name]:
			for point: Vector2 in polygon: points.append(point)
	return points

func _framed_subject(label: String, points: Array[Vector2], canvas: Transform2D, visible: Rect2) -> Dictionary:
	if not _expect(not points.is_empty(), "actual capture subject publishes original world points", label): return {}
	var world_min: Vector2 = points[0]
	var world_max: Vector2 = points[0]
	var viewport_min: Vector2 = canvas * points[0]
	var viewport_max: Vector2 = viewport_min
	for point: Vector2 in points:
		var projected: Vector2 = canvas * point
		if not _expect(visible.has_point(projected), "original camera places each real subject point inside the actual viewport margin",
			{"subject": label, "world": point, "viewport": projected, "allowed": visible}): return {}
		world_min = world_min.min(point)
		world_max = world_max.max(point)
		viewport_min = viewport_min.min(projected)
		viewport_max = viewport_max.max(projected)
	return {"subject": label, "original_world_point_count": points.size(),
		"world_bounds": [world_min.x, world_min.y, world_max.x, world_max.y],
		"viewport_bounds": [viewport_min.x, viewport_min.y, viewport_max.x, viewport_max.y]}

func _capture(label: String, detail: Dictionary = {}) -> bool:
	# Parent capture still owns original presenter readiness, real pixels and
	# the single settled capture. These are read-only framing oracles, not a
	# replacement renderer, overlay, pose or gameplay clock.
	_focus()
	team.advance_frame(0.0)
	ui.vehicle_view.refresh()
	ui.view.refresh()
	await process_frame
	lab.camera.force_update_scroll()
	var canvas: Transform2D = root.get_canvas_transform()
	var visible: Rect2 = root.get_visible_rect().grow(-16.0)
	var subjects := {}
	var vehicle_node: Node2D = ui.vehicle_view._siege_nodes.get(key)
	var body: Sprite2D = vehicle_node.get_node("Body") as Sprite2D if vehicle_node != null else null
	if not _expect(body != null and body.visible and body.texture != null, "actual original gun art remains a visible original Sprite"): return false
	var local: Rect2 = body.get_rect()
	var gun_points: Array[Vector2] = []
	for point: Vector2 in [local.position, local.position + Vector2(local.size.x, 0), local.end, local.position + Vector2(0, local.size.y)]:
		gun_points.append(body.to_global(point))
	subjects["original_gun"] = gun_points
	var indices: Array[int] = [1, 2] # The two actual original crew, not substitute rows.
	if contact_case == "shield_only": indices.append(3)
	elif contact_case == "wall_fourth": indices.append_array([3, 4, 5, 6])
	for index in indices:
		subjects["original_person_%d" % original_ids[index]] = _mesh_points(team.incoming_geometry(index))
	if contact_case == "late_friend":
		subjects["original_Actor_%d" % lab.character.person_id] = _mesh_points(lab.character.incoming_geometry(true))
	if detail.has("wall_id"):
		var wall: Dictionary = lab.terrain.site.features[str(detail.wall_id)]
		var wall_points: Array[Vector2] = []
		for cell_index: int in wall.cells:
			var cell: Vector2i = lab.terrain.cell_from_index(cell_index)
			var surface: Vector2 = lab.terrain.surface_visual_offset(cell)
			for corner: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
				var point: Vector2 = (Vector2(cell) + corner) * TerrainRenderer.CELL_PIXELS
				wall_points.append(point)
				wall_points.append(point + surface)
		subjects["original_paid_wall_" + str(detail.wall_id)] = wall_points
	var framed: Array[Dictionary] = []
	for subject: String in subjects:
		var fact: Dictionary = _framed_subject(subject, subjects[subject], canvas, visible)
		if fact.is_empty(): return false
		framed.append(fact)
	detail.framing = {"camera": "original TerrainLab Camera2D", "camera_position": [lab.camera.position.x, lab.camera.position.y],
		"zoom": [lab.camera.zoom.x, lab.camera.zoom.y], "limits": [lab.camera.limit_left, lab.camera.limit_top, lab.camera.limit_right, lab.camera.limit_bottom],
		"actual_viewport_size": [root.size.x, root.size.y], "safe_margin_pixels": 16,
		"canvas_transform": [canvas.x.x, canvas.x.y, canvas.y.x, canvas.y.y, canvas.origin.x, canvas.origin.y],
		"subjects": framed, "manual_visual_review": "PENDING"}
	return await super._capture(label, detail)

func _run() -> void:
	if not _expect(contact_case in ["late_friend", "shield_only", "wall_fourth"], "one bounded actual contact case", contact_case): return
	visual_case = "ram" # Use existing preflight's named GPU/save isolation.
	visual_kind = "ballista"
	visual_direction = "right"
	visual_mode = "gd"
	if not _preflight() or not _scene() or not _paid_vehicle("ballista"): return
	visual_case = "contact_" + contact_case
	var positions: Array[Vector2i] = [Vector2i(28, 30), Vector2i(31, 32), Vector2i(31, 33)]
	if contact_case == "wall_fourth": positions.append_array([Vector2i(40, 32), Vector2i(43, 32), Vector2i(46, 32), Vector2i(52, 32)])
	else: positions.append(Vector2i(46, 32) if contact_case == "shield_only" else Vector2i(50, 12))
	if not _army(positions): return
	if not _expect(await ui._prepare_siege_work_people([original_ids[1], original_ids[2]]), "explicit original Controller preparation admits true crew work assets"): return
	for slot in range(2):
		var assigned := ui.vehicles.assign_crew(key, original_ids[slot + 1], str(slot), original_ids[0], true)
		if not _expect(assigned.ok, "same original people occupy the actual engine work slots", assigned): return
	if not _seconds(0.1) or not _expect(ui.vehicles.crew_ready(lab.terrain.site.vehicles[key]), "true original crew is ready"): return
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var loaded := SiteRuntime.transfer_items(lab.terrain, lab.terrain.site.depot_items, lab.terrain.site.inventory, vehicle.holder, vehicle.cargo,
		{"siege_bolt": 1}, [], int(lab.terrain.site.depot_items.version), int(vehicle.holder.version), 20)
	if not _expect(loaded.ok and int(vehicle.cargo.siege_bolt) == 1, "one original paid Depot bolt is in the true original magazine", loaded): return
	_focus()
	var ok := false
	if contact_case == "late_friend": ok = await _late_friend()
	elif contact_case == "shield_only": ok = await _shield_only()
	else: ok = await _wall_fourth()
	if not ok or visual_failed: return
	if not _expect(captures.size() == 1 and shared_steps > 0 and lab.siege_shots == 1
		and lab.siege_projectiles.is_empty() and vehicle.action.is_empty() and int(vehicle.cargo.get("siege_bolt", 0)) == 0, "actual GPU edge case must settle its one original shot and capture real pixels"): return
	visual_finished = true
	_report()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_CONTACT_EDGES_GPU_PASS: ", contact_case, "; actual original live rig/Actor meshes, items/HP/movement + one real paid release on original shared clock; explicit FootSource preparation proves resource availability only, not this case contact provider; no Native/FPS or manual pixel-review claim")
	quit(0)
