extends SceneTree
## Formal published assets + actual original holders. Dedicated GPU helper 120 s,
## internal 100 s. Static pose fixtures are NOT timed looting or battle/FPS proof.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Reader = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const OUTPUT := "res://output/site_army_equipment_formal"
var started_us := 0
var deadline_us := 0
var title: Label
var measurements := {"scope": "Formal 32-mask metadata, 32 original ordinary rows, actual inventory and save/load, selected static GPU poses; not timed looting, full animation visual review or FPS"}

func _initialize() -> void:
	started_us = Time.get_ticks_usec()
	deadline_us = started_us + 100000000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_usec() >= deadline_us:
		push_error("SITE ARMY EQUIPMENT FORMAL exceeded its dedicated 100-second deadline")
		quit(1)
	return false

func _formal_catalog() -> Dictionary:
	# Never accept a staging/output catalog or bypass Reader.validate_batches.
	assert(Reader.set_catalog_path(Reader.CATALOG))
	assert(FileAccess.file_exists(Reader.CATALOG), "Formal atomic publication has not happened; staging is not acceptance")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.CATALOG))
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST)).appearance
	var fingerprints := Plan.fingerprints()
	assert(fingerprints.size() == Plan.SOURCE_PATHS.size() and catalog.source_fingerprints == fingerprints)
	assert(int(catalog.schema_version) == 1 and catalog.recipes.size() >= 32)
	assert(catalog.source_manifest_md5 == FileAccess.get_md5(Reader.BASE_MANIFEST))
	var total_keys := 0
	for mask in range(32):
		var paths: Array = catalog.recipes[Plan.recipe_key(mask)]
		assert(paths.size() == 5)
		for path: String in paths:
			assert(path.begins_with(Reader.CATALOG.get_base_dir() + "/") and FileAccess.file_exists(path))
		var appearance := Plan.appearance_for(mask, baseline)
		assert(Reader.supports(appearance), "Every published mask must pass all timing, page, source and coverage guards")
		var recipe := Reader._recipe(mask)
		assert(recipe.sequences.size() == 72)
		var keys := {}
		for sequence: Array in recipe.sequences.values():
			for frame: Dictionary in sequence:
				var key := "%s|%s|%d" % [frame.clip, frame.direction, int(frame.frame)]
				assert(not keys.has(key))
				keys[key] = true
		assert(keys.size() == 536)
		total_keys += keys.size()
	assert(total_keys == 17152)
	measurements.merge({"catalog": Reader.CATALOG, "recipes": 32, "batches": 160,
		"keys_per_recipe": 536, "total_keys": total_keys, "source_fingerprints": fingerprints})
	return baseline

func _take_cell(data: TerrainData, desired: Vector2i, used: Dictionary) -> Vector2i:
	# Keep actual generated walkability so a real Store reconstruction is legal.
	# The overview is a spaced grid, adjusted only when its desired cell is blocked.
	for radius in range(8):
		for y in range(desired.y - radius, desired.y + radius + 1):
			for x in range(desired.x - radius, desired.x + radius + 1):
				var cell := Vector2i(x, y)
				if data.is_walkable(cell) and not used.has(cell):
					used[cell] = true
					return cell
	assert(false, "No legal fixture cell near requested overview position")
	return TerrainArmy.INVALID_CELL

func _inventory(lab: TerrainLab) -> Dictionary:
	var data: TerrainData = lab.terrain
	var holders: Array[Dictionary] = [data.site.depot_items, lab.character.item_state, lab.npc.item_state]
	var cargoes: Array[Dictionary] = [data.site.inventory, data.site.manual.cargo, data.site.worker.cargo]
	for team: TerrainArmy in lab.combat_armies:
		for body: Dictionary in team.combat_units:
			holders.append(body.item_state)
			cargoes.append(body.cargo)
	var items := {}
	var resources := {}
	for holder: Dictionary in holders:
		for id: String in holder.item_ids:
			assert(not items.has(id) and data.site.item_records.has(id))
			var record: Dictionary = data.site.item_records[id]
			assert(record.holder == holder.holder)
			items[id] = {"definition": record.definition, "original_owner": record.original_owner}
		for id: String in holder.equipped.values():
			assert(id in holder.item_ids)
	for cargo: Dictionary in cargoes:
		for resource: String in cargo:
			resources[resource] = int(resources.get(resource, 0)) + int(cargo[resource])
	assert(items.size() == data.site.item_records.size() and data.site.ground_loot.is_empty())
	return {"items": items, "resources": resources}

func _fixture_pose(team: TerrainArmy, index: int, pose: String, age: float, attacking: bool = false) -> void:
	# Pose/age fixture only: do not report these as gameplay commands or hits.
	var body: Dictionary = team.combat_units[index]
	body.pose = pose
	body.age = age
	body.attack = attacking
	body.attack_reduction = 0.0
	body.attack_fatigue = 0.0
	body.aim = []
	team.facing[index] = Vector2i.DOWN
	team._visual_dirty = true

func _assert_frame(team: TerrainArmy, index: int, mask: int) -> void:
	var appearance := team.equipment_appearance(index)
	var raw := team.contact_sample(index)
	var frame := Reader.frame(appearance, team._combat_clip(index), "down", float(raw[1]))
	assert(not frame.is_empty() and frame.texture is AtlasTexture)
	# Same actual recipe/frame must share the actual texture, not copy images.
	assert(Reader.frame(appearance, team._combat_clip(index), "down", float(raw[1])).texture == frame.texture)
	var sprite: Sprite2D = team._sprites[index]
	assert(sprite.visible and sprite.texture != null and sprite.scale.is_equal_approx(Vector2.ONE * float(frame.map_scale)))
	var anchor := Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * float(frame.map_scale)
	if mask == 31:
		# The original full-kit baseline intentionally retains its original atlas.
		var original := team.combat_frame(index)
		var key := team._soldier_frame_key(str(original.clip), str(original.direction), int(original.frame))
		assert(sprite.texture == team._soldier_frame_textures[key])
		anchor = team._soldier_frame_anchors[key]
	else:
		assert(sprite.texture == frame.texture, "The actual Sprite must use this person's missing-equipment recipe")
		var expected_key := "equipment|%s|%s|%s|%d" % [str(appearance.parts), frame.clip, frame.direction, int(frame.frame)]
		assert(team._soldier_current_keys[index] == expected_key)
	assert(team._soldier_sprite_anchors[index].distance_to(anchor) < 0.0001, "Raw bake anchors must be scaled to map pixels")
	assert(sprite.position.distance_to(team.combat_ground(index) + team.combat_offset(index) - anchor) < 0.0001)
	var texture := frame.texture as AtlasTexture
	assert(texture.region == Rect2(float(frame.rect.x), float(frame.rect.y), float(frame.rect.w), float(frame.rect.h)))

func _assert_query(team: TerrainArmy, index: int, mask: int, guard: bool) -> void:
	var pose := team._continuous_pose(index)
	assert(not pose.body.is_empty() and pose.shield.is_empty() == ((mask & 2) == 0))
	if guard:
		assert(pose.parry.is_empty() == ((mask & 3) != 1), "Only actual unshielded melee weapons provide parry")
	else:
		assert(not pose.weapon.is_empty())
		if (mask & 1) == 0:
			assert(team.attack_clip(index) == &"attack_unarmed" and pose.weapon.size() == 1, "Empty weapon slot uses original kicking-leg geometry, never a phantom sword")
		else:
			assert(team.attack_clip(index) == &"walk_slash")
	var origin := team.combat_ground(index) + team.combat_offset(index)
	for kind: String in ["body", "weapon", "shield", "parry"]:
		var actual := team.combat_shapes(index, kind)
		assert(actual.size() == pose[kind].size())
		for polygon in range(actual.size()):
			assert(actual[polygon].size() == pose[kind][polygon].size())
			for vertex in range(actual[polygon].size()):
				assert(actual[polygon][vertex].distance_to(pose[kind][polygon][vertex] + origin) < 0.0001)
	if mask == 0:
		var raw := team.contact_sample(index)
		for polygon: PackedVector2Array in pose.body:
			var point := Vector2.ZERO
			for vertex: Vector2 in polygon:
				point += vertex
			point /= polygon.size()
			assert(TerrainArmy._contact_source.armor_at(raw[0], raw[1], raw[2], point, "slash", raw[3], raw[4], team.equipment_appearance(index)) == Vector2.ZERO)

func _capture(lab: TerrainLab, filename: String, heading: String, location: Vector2, zoom: float) -> void:
	title.text = heading
	lab.camera.position = location
	lab.camera.zoom = Vector2.ONE * zoom
	lab.camera.reset_smoothing()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT.path_join(filename)) == OK)

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Formal sprite acceptance needs the GPU runner, not an unavailable headless PASS")
	var baseline := _formal_catalog()
	root.size = Vector2i(1500, 1000)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	for owner: Node in [lab, lab.character, lab.npc, lab.site_controller, lab.army, lab.opposing_army]:
		owner.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	Env.initialize(data, "formal-army-equipment-fixture")
	# Explicit terrain-only fixture cleanup is a saved original sparse delta.
	for key: String in data.resource_base:
		Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	var used := {}
	assert(lab.character.place(_take_cell(data, Vector2i(80, 80), used), true))
	assert(lab.npc.place(_take_cell(data, Vector2i(82, 80), used), true))
	var cells: Array[Vector2i] = [_take_cell(data, Vector2i(70, 70), used)]
	for mask in range(32):
		cells.append(_take_cell(data, Vector2i(30 + (mask % 8) * 3, 30 + (mask >> 3) * 4), used))
	for index in range(33, 100):
		cells.append(_take_cell(data, Vector2i(65 + (index % 10), 65 + floori(float(index) / 10.0)), used))
	var team: TerrainArmy = lab.army
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	assert(team.combat_units.size() == 100 and team.visual_mode() == "baked_atlas" and team.active_3d_source_count() == 1)
	var female_appearance: Dictionary = team._unit_editor(0).capture_appearance()
	var before := _inventory(lab)
	var original_records: Dictionary = data.site.item_records.duplicate(true)
	var retained := {}
	var identities: Array[int] = []
	var moved := 0
	for mask in range(32):
		var index := mask + 1
		var body: Dictionary = team.combat_units[index]
		var identity := team.combat_identity(index)
		identities.append(identity)
		assert(not team._uses_live_presenter(index) and team._unit_editor(index) == null)
		assert(body.appearance == baseline and body.item_state.equipped.size() == 5)
		var appearance := Plan.appearance_for(mask, baseline)
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		var admitted: Dictionary = lab.site_controller._equipment_recipe_guard(person, appearance)
		assert(admitted.ok, str(admitted))
		var items: Array = []
		for bit in range(Plan.SLOTS.size()):
			if (mask & (1 << bit)) == 0:
				items.append(body.item_state.equipped[Plan.SLOTS[bit]])
		if not items.is_empty():
			var transfer := Runtime.transfer_items(data, body.item_state, body.cargo, data.site.depot_items,
				data.site.inventory, {}, items, int(body.item_state.version), int(data.site.depot_items.version), int(data.site.capacity))
			assert(transfer.ok, str(transfer))
			moved += items.size()
		lab.site_controller.equipment_changed(identity)
		assert(team.equipment_appearance(index) == appearance and Reader._appearance_mask(team.equipment_appearance(index)) == mask)
		assert(float(body.hp) == 100.0 and float(body.fatigue) == 0.0 and body.appearance == baseline)
		retained[identity] = {"item_state": body.item_state.duplicate(true), "cargo": body.cargo.duplicate(true)}
	assert(moved == 80 and data.site.depot_items.item_ids.size() == 80 and _inventory(lab) == before)
	assert(data.site.item_records.size() == original_records.size())
	# Save and genuinely reconstruct the same Site before any static attack pose.
	lab.site_controller._capture_positions()
	var saved := Store.save(data, OUTPUT + "/actual_equipment.json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(OUTPUT + "/actual_equipment.json")
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	team = lab.army
	assert(team.combat_units.size() == 100 and _inventory(lab) == before)
	assert(team._unit_editor(0).capture_appearance() == female_appearance)
	for mask in range(32):
		var index := team.index_for_identity(identities[mask])
		assert(index == mask + 1)
		var body: Dictionary = team.combat_units[index]
		assert(body.item_state == retained[identities[mask]].item_state and body.cargo == retained[identities[mask]].cargo)
		assert(float(body.hp) == 100.0 and float(body.fatigue) == 0.0)
		assert(team.equipment_appearance(index) == Plan.appearance_for(mask, baseline), "Initialized empty slots must not refill on read/bind")
		_fixture_pose(team, index, "idle", 0.0)
	# Rebinding releases the lazy shared query; ask the actual owner for geometry
	# before observing its identity. Rendering alone does not need this skeleton.
	assert(not team.combat_shapes(1, "body").is_empty())
	var source: Variant = TerrainArmy._contact_source
	var editor_id: int = source.editor.get_instance_id()
	var skeleton_id: int = source.skeleton.get_instance_id()
	var animation: Animation = source.editor.animation_player.get_animation(&"down")
	var mesh_count: int = source.editor.model_root.find_children("*", "MeshInstance3D", true, false).size()
	lab.get_node("SiteUI").hide()
	lab.get_node("TerrainLabUI").hide()
	var overlay := CanvasLayer.new()
	lab.add_child(overlay)
	title = Label.new()
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 24)
	overlay.add_child(title)
	for mask in range(32):
		var label := Label.new()
		label.text = "m%02d  %s" % [mask, _slot_label(mask)]
		label.position = team.combat_ground(mask + 1) + Vector2(-65, 12)
		label.z_index = 100
		label.add_theme_font_size_override("font_size", 18)
		lab.add_child(label)
	team.advance_frame(0.0)
	for mask in range(32):
		_assert_frame(team, mask + 1, mask)
	assert(team._sprites[32].texture == team._sprites[99].texture, "Unchanged original soldiers share the existing baseline frame")
	await _capture(lab, "01_32_masks.png", "FORMAL 32 MASKS | W weapon / S shield / A armor / O outfit / B boots | -- absent", Vector2(41, 35.5) * 64.0, 0.92)
	await _capture(lab, "02_no_armor.png", "m27 | Original armor transferred to depot; weapon, shield, outfit and boots retained", team.combat_ground(28) + Vector2(0, -25), 4.0)
	for mask in range(32):
		_fixture_pose(team, mask + 1, "guard", 0.073)
	team.advance_frame(0.0)
	for mask in range(32):
		_assert_frame(team, mask + 1, mask)
		_assert_query(team, mask + 1, mask, true)
	await _capture(lab, "03_no_shield_guard.png", "m29 | Actual unshielded melee guard; original sword parry, no shield collision", team.combat_ground(30) + Vector2(0, -25), 4.0)
	for mask in range(32):
		_fixture_pose(team, mask + 1, "walk_slash" if (mask & 1) else "attack_unarmed", 0.537, true)
	team.advance_frame(0.0)
	for mask in range(32):
		_assert_frame(team, mask + 1, mask)
		_assert_query(team, mask + 1, mask, false)
	await _capture(lab, "04_no_weapon.png", "m30 | Actual weapon transferred; original unarmed attack and kicking-leg collision", team.combat_ground(31) + Vector2(0, -25), 4.0)
	var cached_full := team._continuous_pose(32).duplicate(true)
	team._continuous_pose(1)
	assert(team._continuous_pose(32) == cached_full, "Stripped B must not change cached equipped A")
	assert(source.editor.get_instance_id() == editor_id and source.skeleton.get_instance_id() == skeleton_id)
	assert(source.editor.animation_player.get_animation(&"down") == animation)
	assert(source.editor.model_root.find_children("*", "MeshInstance3D", true, false).size() == mesh_count)
	assert(source.editor.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	assert(team.active_3d_source_count() == 1 and team._sprites.size() == 100 and _inventory(lab) == before)
	assert(Plan.fingerprints() == measurements.source_fingerprints, "No source model, animation, timing or baker modification")
	measurements.merge({"actual_rows": 100, "ordinary_masks": 32, "original_items": before.items.size(),
		"items_moved_not_created": moved, "inventory_conserved": true, "save_load_no_refill": true,
		"sprite_states_checked": 96, "query_states_checked": 64, "live_female_presenters": 1,
		"ordinary_query_editors": 1, "query_viewport_render_disabled": true,
		"wall_ms": (Time.get_ticks_usec() - started_us) / 1000.0,
		"static_memory_bytes": OS.get_static_memory_usage(), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))})
	var report := FileAccess.open(OUTPUT + "/measurements.json", FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify(measurements, "\t"))
	report.close()
	print("SITE_ARMY_EQUIPMENT_FORMAL_VISUAL_PASS ", JSON.stringify(measurements))
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)

func _slot_label(mask: int) -> String:
	var result := ""
	for bit in range(5):
		result += ["W", "S", "A", "O", "B"][bit] if (mask & (1 << bit)) else "-"
	return result
