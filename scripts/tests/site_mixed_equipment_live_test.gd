extends SceneTree
## Real main-scene person, original issued items, async atlas, saved identity.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
var OUT := "res://output/equipment_limits_20260919/integration"
var lab: TerrainLab
var controller: SiteController
var team: TerrainArmy
var identity := 0
var captain := 0
var folder := ""
var checks := 0
var started := 0
var stage := "setup"
var body := 0
var culture := ""
var progress_at := 0

func _initialize() -> void:
	started = Time.get_ticks_msec()
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - progress_at >= 10000:
		progress_at = Time.get_ticks_msec()
		var capture := Atlas._preparation
		print("MIXED LIVE PROGRESS ", stage, " ", str(capture.get("phase")) + " " + str(capture.get("captured_frames")) + "/" + str(capture.get("total_frames")) if is_instance_valid(capture) else "")
	if Time.get_ticks_msec() - started > 420000:
		push_error("MIXED LIVE deadline at " + stage)
		quit(1)
	return false

func check(ok: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if not ok:
		push_error("MIXED LIVE " + stage + ": " + message + "; " + str(detail))
		quit(1)
	return ok

func freeze_simulation() -> void:
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)

func choose(slot_id: String, material: String) -> String:
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		if str(slot.id) != slot_id: continue
		for part: Dictionary in slot.options:
			if part.get("material") == material and part.get("culture") == culture: return str(part.id)
	return ""

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var steel_walk := "--steel-mingguang" in args
	if steel_walk:
		args.remove_at(args.find("--steel-mingguang"))
		OUT = "res://output/steel_mingguang_walk_20260919/integration"
	var walk_repair := "--equipment-walk" in args
	if walk_repair:
		args.remove_at(args.find("--equipment-walk"))
		OUT = "res://output/equipment_walk_fix_20260919/integration"
	if not check(DisplayServer.get_name() != "headless" and args.size() == 2, "GPU, culture and body required"): return
	culture = args[0]
	body = int(args[1])
	if not check(culture in ["chinese", "japanese", "western"] and body in [0, 1], "known culture/body"): return
	folder = OUT + "/%s_%d_%d" % [culture, body, Time.get_ticks_usec()]
	if not check(not DirAccess.dir_exists_absolute(folder), "fresh evidence folder; never replace an earlier run"): return
	DirAccess.make_dir_recursive_absolute(folder)
	Atlas._mixed_root = OUT + "/cache"
	Atlas.refresh_female_sources()
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	freeze_simulation()
	controller = lab.site_controller
	var cells: Array[Vector2i] = []
	for index in range(lab.terrain.size.x * lab.terrain.size.y):
		var depot := lab.terrain.cell_from_index(index)
		if not lab.terrain.is_walkable(depot) or lab.character.occupies_cell(depot) or (is_instance_valid(lab.npc) and lab.npc.occupies_cell(depot)): continue
		cells.clear()
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var cell := depot + direction
			if lab.terrain.can_step(depot, cell) and not lab.character.occupies_cell(cell) and not (is_instance_valid(lab.npc) and lab.npc.occupies_cell(cell)): cells.append(cell)
		if cells.size() >= 2:
			lab.terrain.site.depot_cell = index
			break
	if not check(cells.size() >= 2, "real legal adjacent cells"): return
	var settings := lab._trial_side_settings({"friendly_count": 2, "friendly_female_percent": body * 100, "friendly_attack": false,
		"friendly_troop_type": "crossbow" if culture == "japanese" else "melee_infantry"}, "friendly")
	if not check(settings.ok, "trial settings", settings): return
	var positions: Array[Vector2i] = [cells[0], cells[1]]
	var deployed := lab._deploy_trial_teams([settings.side], [positions], 0)
	if not check(deployed.ok, "original deployment", deployed): return
	freeze_simulation()
	team = lab.combat_armies[0]
	captain = team.combat_identity(0)
	identity = team.combat_identity(1)
	if not check(not team._uses_live_presenter(1) and team._unit_editor(1) == null, "ordinary person is atlas-only"): return
	var source_count := team.active_3d_source_count()
	lab.terrain.site.equipment_nations = {"mixed": {"military_head": captain, "members": [captain, identity], "standards": {}}}
	if not check(controller.equipment_orders.set_nation_culture(captain, "mixed", culture).ok, "fix actual nation culture"): return
	var materials: Array = {"chinese": ["cloth", "steel", "leather", "wood"], "japanese": ["steel", "cloth", "iron", "stone"], "western": ["iron", "leather", "cloth", "steel"]}[culture]
	if walk_repair:
		materials = {"chinese":["leather","iron","steel","wood"],"japanese":["steel","cloth","iron","stone"],"western":["iron","iron","steel","steel"]}[culture]
	if steel_walk:
		materials = ["leather", "steel", "iron", "wood"]
	var parts := {}
	for index in range(4):
		var slot: String = ["helmet", "armor", "boots", "shield"][index]
		parts[slot] = choose(slot, materials[index])
	parts.weapon = {"chinese": "spear_01_stone", "japanese": "crossbow_01_steel", "western": "longsword_01_steel"}[culture]
	var slots := {}
	var items := {}
	lab.terrain.site.capacity = maxi(int(lab.terrain.site.capacity), SiteRuntime.inventory_size(lab.terrain.site.inventory) + 40)
	for slot: String in parts:
		var asset := str(parts[slot])
		var made := SiteRuntime.create_equipment(lab.terrain, lab.terrain.site.depot_items, slot + ":" + asset, {"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, captain)
		if not check(made.ok, "real depot stock", made): return
		items[slot] = made.item_id
		slots[slot] = {"definition": slot + ":" + asset}
	if not check(controller.equipment_orders.set_standard(captain, "mixed", "line", "Mixed materials", slots, "blue").ok, "same culture independent materials"): return
	var person := controller.person_actions._person(identity)
	var before: Dictionary = person.holder.duplicate(true)
	var records: Dictionary = lab.terrain.site.item_records.duplicate(true)
	# The original issue rule retains an already matching worn item. Derive IDs
	# independently from the untouched holder/records, never from the order result.
	var expected_items := items.duplicate()
	for slot: String in items:
		var worn := str(before.equipped.get(slot, ""))
		if not worn.is_empty() and str(records[worn].definition) == slot + ":" + str(parts[slot]):
			expected_items[slot] = worn
	var result := controller.equipment_orders.begin_issue(identity, "mixed", "line")
	if not check(result.ok, "original begin issue", result): return
	stage = "prepare exact shared atlas"
	var was_preparing: bool = result.get("preparing", false)
	while controller.person_actions.is_busy(identity) and bool(controller.person_actions.job_for(identity).get("preparing", false)):
		controller.person_actions.advance(1.0)
		if not check(controller.person_actions.settle_after_contacts().is_empty(), "no commit during atlas preparation"): return
		if not check(person.holder == before and lab.terrain.site.item_records == records, "all actual items unchanged while waiting"): return
		await process_frame
	if not check(controller.person_actions.is_busy(identity), "preparation completed without cancel", controller.person_actions._results): return
	if not check(controller.person_actions.job_for(identity).elapsed == 0.0, "preparation is not work time"): return
	stage = "original five-second commit"
	controller.person_actions.advance(4.999)
	if not check(controller.person_actions.settle_after_contacts().is_empty() and person.holder == before, "not early"): return
	controller.person_actions.advance(0.001)
	var settled := controller.person_actions.settle_after_contacts()
	if not check(settled.size() == 1 and bool(settled[0].ok), "post-contact real commit", settled): return
	if not check(int(person.holder.version) == int(before.version) + 1 and team.active_3d_source_count() == source_count and team._unit_editor(1) == null, "same original holder, no per-person skeleton"): return
	for slot: String in items:
		if not check(person.holder.equipped.get(slot) == expected_items[slot], "exact original retained or stocked item ID: " + slot, person.holder.equipped): return
		if expected_items[slot] != items[slot]:
			if not check(lab.terrain.site.depot_items.item_ids.has(items[slot]) and lab.terrain.site.item_records[items[slot]] == records[items[slot]], "unneeded duplicate remains unchanged in depot: " + slot): return
		elif before.equipped.has(slot):
			var returned := str(before.equipped[slot])
			if not check(lab.terrain.site.depot_items.item_ids.has(returned) and lab.terrain.site.item_records[returned].holder == "depot", "replaced original item returned intact: " + slot): return
	if not check(lab.terrain.site.item_records.size() == records.size(), "issue neither creates nor deletes original item records"): return
	if not check(controller.equipment_orders.apply_standard_dyes(captain, identity, "mixed", "line").ok, "real NPC color transaction"): return
	var appearance := controller.person_appearance(identity).duplicate(true)
	if not check(Atlas.supports(appearance) and not Atlas.dye_entry(appearance).is_empty(), "strict complete recipe and dye admitted"): return
	var record := Atlas.mixed_recipe(appearance)
	if not check(not record.is_empty(), "actual custom recipe"): return
	var unchanged_count: int = lab.terrain.site.item_records.size()
	if not check(await Atlas.prepare_recipe(lab, appearance), "warm recipe reuse"): return
	if not check(team.active_3d_source_count() == source_count and lab.terrain.site.item_records.size() == unchanged_count, "reuse neither model nor item creation"): return
	stage = "Sprite and original MultiMesh pixels"
	if not await pixels(appearance): return
	stage = "real save load rebind"
	controller._capture_positions()
	var saved_holder: Dictionary = person.holder.duplicate(true)
	var saved := SiteStore.save(lab.terrain, folder + "/site.json")
	if not check(saved.ok, "SiteStore save", saved): return
	var loaded := SiteStore.load_site(folder + "/site.json")
	if not check(loaded.ok, "SiteStore validates persisted shared cache", loaded): return
	lab.bind_terrain(loaded.data)
	freeze_simulation()
	person = controller.person_actions._person(identity)
	if not check(person.holder == saved_holder and controller.person_appearance(identity) == appearance, "same identity exact gear and colors restored"): return
	if not check(not person.owner._uses_live_presenter(int(person.unit)) and person.owner._unit_editor(int(person.unit)) == null, "restored ordinary person still no skeleton"): return
	controller._capture_positions()
	if not check(SiteStore.save(lab.terrain, folder + "/restored.json").ok, "re-save restored person"): return
	var report := {"status": "PASS", "culture": culture, "body": body, "person_id": identity, "parts": parts,
		"cold_preparation": was_preparing, "manifest": record.source_manifest, "checks": checks, "elapsed_msec": Time.get_ticks_msec() - started}
	FileAccess.open(folder + "/result.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_MIXED_EQUIPMENT_LIVE_PASS ", JSON.stringify(report))
	quit()

func pixels(appearance: Dictionary) -> bool:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var batch := Batch.new()
	viewport.add_child(batch)
	batch.setup(team, 2)
	var sprite := Sprite2D.new()
	viewport.add_child(sprite)
	sprite.texture_filter = CharacterRenderContract.TEXTURE_FILTER
	var ground := Vector2(256, 400)
	var count := 0
	var plan := Atlas.mixed_plan(appearance)
	for clip: Dictionary in plan.clips:
		for direction: String in ["down", "left", "up", "right"]:
			for time: float in [0.0, 0.371]:
				var frame := Atlas.frame(appearance, str(clip.id), direction, time)
				if not check(not frame.is_empty(), "actual full-clip frame"): return false
				sprite.texture = frame.texture
				sprite.scale = Vector2.ONE * float(frame.map_scale)
				sprite.position = ground - Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * float(frame.map_scale)
				if not check(Atlas.apply_dye(sprite, appearance), "original sprite mask"): return false
				batch.hide()
				sprite.show()
				await process_frame
				await RenderingServer.frame_post_draw
				var reference := viewport.get_texture().get_image()
				sprite.hide()
				batch.begin()
				if not check(batch.submit(0, ground, appearance, str(clip.id), direction, time), "original batch admits mixed recipe"): return false
				batch.flush()
				batch.show()
				await process_frame
				await RenderingServer.frame_post_draw
				var actual := viewport.get_texture().get_image()
				if not check(reference.get_data() == actual.get_data(), "Sprite/MultiMesh exact RGBA", [clip.id, direction, time]):
					reference.save_png(folder + "/failed_sprite.png")
					actual.save_png(folder + "/failed_batch.png")
					return false
				if time == 0.371 and clip.id in ["idle", "walk", "attack_jump_heavy"]:
					actual.save_png(folder + "/%s_%s.png" % [clip.id, direction])
				count += 1
	# A separate 2x nearest-filter GPU preview makes the same admitted palette
	# readable; it is not part of, or a replacement for, the map-scale comparison.
	viewport.size = Vector2i(640, 640)
	batch.hide()
	sprite.show()
	for direction: String in ["down", "left", "up", "right"]:
		var frame := Atlas.frame(appearance, "idle", direction, 0.371)
		sprite.texture = frame.texture
		sprite.scale = Vector2.ONE * 2.0
		sprite.position = Vector2(320, 580) - Vector2(frame.anchor_offset.x, frame.anchor_offset.y) * 2.0
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		var used := picture.get_used_rect()
		if not check(used.has_area() and used.position.x > 0 and used.position.y > 0 and used.end.x < 640 and used.end.y < 640, "native preview fully in bounds", direction): return false
		picture.save_png(folder + "/preview_idle_" + direction + ".png")
	viewport.queue_free()
	await process_frame
	print("MIXED_BATCH_PIXEL_PAIRS ", count)
	return true
