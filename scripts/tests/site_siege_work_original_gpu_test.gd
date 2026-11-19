extends "res://scripts/tests/site_siege_close_visual_test.gd"
## Separate eight-case work proof; the existing 31 visual cases are unchanged.
const WorkClips = preload("res://scripts/terrain_lab/site_siege_work_clips.gd")
var work_mode := "gd_atlas"
var work_body := 0
var cache_only := false
var crew_ids: Array[int] = []
var work_id := 0
var commander_id := 0
var completed_work := 0
var asset_facts: Array[Dictionary] = []
var original_gear := {}
var original_items: Array = []
var original_cargo := {}
var reference_contact: RefCounted

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for name: String in ["--work-mode", "--work-body"]:
		var at := args.find(name)
		if at >= 0 and at + 1 < args.size():
			if name == "--work-mode": work_mode = args[at + 1]
			else: work_body = 1 if args[at + 1] == "female" else 0
	cache_only = args.has("--work-cache-only")
	visual_kind = "ram"
	visual_case = "ram"
	visual_direction = "right"
	visual_mode = "gd" # Original preflight has its own existing case contract.
	visual_deadline = Time.get_ticks_msec() + 600000
	_run.call_deferred()

func _report() -> void:
	if folder.is_empty(): return
	var file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"status": "FAIL" if visual_failed else ("PASS" if visual_finished else "INCOMPLETE"),
		"case": "original_work", "mode": work_mode, "body": work_body, "cache_only": cache_only,
		"checks": checks, "check_count": visual_checks, "completed_work": completed_work,
		"captures": captures, "asset_cache": asset_facts, "shared_steps": shared_steps,
		"crew_ids": crew_ids, "actual_work_person": work_id, "manual_visual_review": "PENDING",
		"scope": "Original PackedScene Army live/Atlas or original native soldier/Actor selected explicitly; actual compound push, real rotating rig pull, real loading, original contact mesh/material, dye/items, original reaction/KO/release, actual pending JSON load, persistent cache. Initial flat-map and body/live-role fixture metadata only. No FPS/export/full-release proof."}, "\t"))
	file.close()

func _fixture() -> TerrainData:
	# Reuse the original Store roundtrip's generated FOREST + persistent level delta.
	# Bare allocation/unsaved base-array fills cannot survive original seeded reload.
	var data := TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "building-runtime-contract")
	for y in range(5, 70):
		for x in range(5, 70):
			var index := data.index(Vector2i(x, y))
			data.site.terrain_changes[str(index)] = 0
			data.height_levels[index] = 0
	for source: String in data.resource_base:
		SiteEnvironment.change(data, source, {"cleared": true, "remaining": 0})
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	data.site.capacity = 100000
	data.site.depot_cell = data.index(Vector2i(3, 3))
	data.site.player_cell = data.index(Vector2i(4, 4))
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(4, 3))
	data.site.worker_enabled = false
	var initialized := SiteRuntime.initialize_item_storage(data.site)
	if not _expect(initialized.ok, "original generated persistent fixture initializes actual material holders", initialized): return null
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	return data

func _army(positions: Array[Vector2i]) -> bool:
	team = lab.army
	team.team_id = 1
	team.roster_size = positions.size()
	team.defer_captain_presenter = false
	if not _expect(team.deploy_at(lab.terrain, lab.character, lab.npc, positions) and team.enable_combat(false, positions.size() if work_body == 1 else 0), "original Army allocates same-body original roster"): return false
	team.set_process(false)
	team.tactical_ai_enabled = false
	# Stable initial role is an original admitted retained live-member role.
	# No renderer/person is created by the fixture; original rebuild handles it.
	if work_mode == "gd_live": team.combat_units[1].visual_role = "female_live" if work_body == 1 else "male_live"
	ui.initialize_team_items(team)
	# This fixture directly enables the original Army rather than consuming the
	# formal trial preflight. Prepare actual bodies once before any shared step.
	for index in range(positions.size()):
		if not _expect(TerrainArmy.prepare_contact_source_for(ui.person_appearance(team.combat_identity(index)), lab.character.editor), "explicit fixture preparation admits each actual original male/female contact body"): return false
	team._rebuild_visual_instances()
	lab.terrain.site.army_next_team = 2
	for index in range(positions.size()): original_ids.append(team.combat_identity(index))
	return _expect(team._sprites.size() == positions.size(), "original Army presenter retains every original row")

func _cache(identity: int) -> bool:
	var appearance: Dictionary = ui.person_appearance(identity)
	var directory: String = WorkAppend.directory(appearance)
	if not _expect(not directory.is_empty(), "exact original equipment has a deterministic optional cache namespace", identity): return false
	var manifest := directory + "/manifest.json"
	var prior := FileAccess.get_md5(manifest) if FileAccess.file_exists(manifest) else ""
	var timestamp := FileAccess.get_modified_time(manifest) if not prior.is_empty() else 0
	if cache_only and not _expect(not prior.is_empty(), "second Godot run requires an existing persistent work cache; baking is forbidden", directory): return false
	var accepted := false
	if cache_only: accepted = WorkAppend.admit(appearance, directory)
	else: accepted = await WorkAppend.ensure(ui, appearance)
	if not _expect(accepted and WorkAppend.ready(appearance), "original capture/cache admits all three real work clips", directory): return false
	var digest := FileAccess.get_md5(manifest)
	if not prior.is_empty() and not _expect(digest == prior and FileAccess.get_modified_time(manifest) == timestamp, "cache hit does not rewrite or recapture its original manifest", identity): return false
	if not _expect(await WorkAppend.ensure(ui, appearance) and FileAccess.get_md5(manifest) == digest, "explicit ensure uses already admitted cache without a second capture", identity): return false
	asset_facts.append({"person_id": identity, "directory": directory, "existing_before": not prior.is_empty(), "md5": digest, "modified_time": FileAccess.get_modified_time(manifest), "body": appearance.body})
	return true

func _make_people() -> bool:
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var side := Vector2i(-facing.y, facing.x)
	var positions: Array[Vector2i] = [anchor - facing * 4 - side]
	if work_mode == "native_actor": positions.append(SiteRuntime.siege_crew_cell(lab.terrain, vehicle, "1"))
	else:
		positions.append(SiteRuntime.siege_crew_cell(lab.terrain, vehicle, "0"))
		positions.append(SiteRuntime.siege_crew_cell(lab.terrain, vehicle, "1"))
	if not _army(positions): return false
	commander_id = original_ids[0]
	if work_mode == "native_actor":
		var actor: TerrainTestCharacter = lab.character
		var appearance: Dictionary = ui.person_appearance(actor.person_id).duplicate(true)
		appearance.body = float(work_body) # Explicit initial original Actor body fixture.
		actor._saved_appearance = appearance.duplicate(true)
		if not _expect(actor.editor != null and actor.editor.restore_appearance(appearance), "original Actor editor restores its actual male/female body"): return false
		ui.equipment_changed(actor.person_id)
		var colors := {}
		for slot: String in SiteRuntime.EquipmentDye.SLOTS:
			if actor.item_state.equipped.has(slot): colors[slot] = "386cbfff"
		if not _expect(not colors.is_empty() and SiteRuntime.dye_equipment(lab.terrain, actor.item_state, colors, int(actor.item_state.version)).ok, "original Actor actual equipped item IDs receive initial real dye"): return false
		ui.equipment_changed(actor.person_id)
		actor.terrain_cell = SiteRuntime.siege_crew_cell(lab.terrain, vehicle, "0")
		actor.position = (Vector2(actor.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		actor.movement_from_cell = actor.terrain_cell
		actor._movement_start = actor.position # Initial fixture, before membership/native admission.
		actor.play_pose(&"idle")
		if not _expect(team.join_player(actor).ok, "original Actor joins the original team through its existing membership owner"): return false
		crew_ids = [actor.person_id, original_ids[1]]
		work_id = actor.person_id
		original_ids.append(work_id)
	else:
		crew_ids = [original_ids[1], original_ids[2]]
		work_id = original_ids[1]
	if work_mode.begins_with("native_"):
		if not _expect(OS.get_cmdline_user_args().has("--crowd") and lab.crowd_site != null, "native work uses actual original World and paired ABI"): return false
		var parsed: Dictionary = lab._trial_side_settings({"friendly_count": 1, "friendly_training": 0, "friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
		if not _expect(parsed.ok, "native work side settings accepted", parsed): return false
		var settings: Dictionary = parsed.side
		settings.faction = 2
		var entered: Dictionary = lab.crowd_site.deploy([settings], [[Vector2i(65, 65)]])
		if not _expect(entered.ok and lab.crowd_site.active and lab.crowd_site.contains_person(work_id), "native import retains exact original people and items", entered): return false
		if work_mode == "native_actor" and not _expect(is_same(lab.crowd_site._actors.get(work_id), lab.character), "native work Actor is the same original live Actor object"): return false
		# Same original parity fixture: control the actual commander before any
		# shared step, so his native HOLD slot cannot walk into the real turn sweep.
		var original_commander: Dictionary = ui.person_actions._person(commander_id)
		if not _expect(not original_commander.is_empty(), "native work retains its original commander before control"): return false
		var original_native_ids: Dictionary = lab.crowd_site._index_by_id.duplicate()
		var switched: Dictionary = ui._control_family_person(null, commander_id)
		var controlled_commander: Dictionary = ui.person_actions._person(commander_id)
		if not _expect(switched.ok and lab.controlled_person_id() == commander_id and not controlled_commander.is_empty()
			and lab.crowd_site._index_by_id == original_native_ids and controlled_commander.cell == original_commander.cell
			and not bool(controlled_commander.moving) and is_same(controlled_commander.owner, original_commander.owner)
			and is_same(controlled_commander.body, original_commander.body) and is_same(controlled_commander.holder, original_commander.holder)
			and is_same(controlled_commander.cargo, original_commander.cargo),
			"original public control keeps the same native commander, cell, people, body, items and cargo", switched): return false
	for identity: int in crew_ids:
		if not await _cache(identity): return false
	if not _expect(await ui._prepare_siege_work_people(crew_ids), "original explicit Controller prepares actual crew work recipes before assignment"): return false
	for fact: Dictionary in asset_facts:
		if not _expect(FileAccess.get_md5(str(fact.directory) + "/manifest.json") == fact.md5 and FileAccess.get_modified_time(str(fact.directory) + "/manifest.json") == fact.modified_time, "original UI preparation reuses admitted persistent work cache"): return false
	var person: Dictionary = ui.person_actions._person(work_id)
	original_gear = ui.person_appearance(work_id).duplicate(true)
	original_items = person.holder.item_ids.duplicate()
	original_cargo = person.cargo.duplicate(true)
	if not _expect(int(original_gear.body) == work_body and not original_gear.get("equipment_dyes", {}).is_empty(), "actual original body, equipment and item dye are present", original_gear): return false
	return await _assign_all()

func _assign_all() -> bool:
	for slot in range(crew_ids.size()):
		var assigned := ui.vehicles.assign_crew(key, crew_ids[slot], str(slot), commander_id, true)
		if not _expect(assigned.ok, "original transaction assigns same crew ID", assigned): return false
	return await _until_work(func() -> bool: return ui.vehicles.crew_ready(lab.terrain.site.vehicles[key]), 30.0, "all original crew reach their true work stations")

func _until_work(predicate: Callable, seconds: float, label: String) -> bool:
	for index in range(ceili(seconds / DT)):
		if bool(predicate.call()): return true
		if not _step(): return false
		if index % 120 == 0: await process_frame
	return _expect(bool(predicate.call()), label)

func _mesh_equal(left: Array, right: Array, offset: Vector2) -> bool:
	if left.size() != right.size() or left.is_empty(): return false
	for part in range(left.size()):
		if left[part].size() != right[part].size(): return false
		for point in range(left[part].size()):
			if (left[part][point] - right[part][point]).distance_to(offset) > 0.02: return false
	return true

func _check_work(clip: String, label: String) -> bool:
	if lab.crowd_site != null and lab.crowd_site.active: lab.crowd_site.render(0.0)
	else: team.advance_frame(0.0)
	var work: Dictionary = ui.vehicles.siege_work_pose(work_id)
	if not _expect(str(work.get("clip", "")) == clip, "original action projects the expected work clip", {"work": work, "label": label}): return false
	var person: Dictionary = ui.person_actions._person(work_id)
	var owner: Variant = person.owner
	var index := int(person.unit)
	var appearance: Dictionary = ui.person_appearance(work_id)
	if not _expect(appearance == original_gear and person.holder.item_ids == original_items and person.cargo == original_cargo, "work preserves exact original equipment/dye/item IDs and cargo"): return false
	var native := owner is CrowdPersonOwner
	var editor: Variant = lab.crowd_site._actors[work_id].editor if native and work_mode == "native_actor" else (team._unit_editor(index) if not native and work_mode == "gd_live" else null)
	if editor != null:
		var expected_yaw: float = PI + deg_to_rad({Vector2i.DOWN: 0.0, Vector2i.LEFT: -90.0, Vector2i.UP: 180.0, Vector2i.RIGHT: 90.0}[Vector2i(work.facing)])
		if not _expect(is_equal_approx(editor.preview_pivot.rotation.y, expected_yaw), "original live pivot faces the same real work contact direction", label): return false
		if not _expect(JSON.parse_string(JSON.stringify(editor.capture_appearance(), "", true, true)) == JSON.parse_string(JSON.stringify(appearance, "", true, true)) and str(editor.selected_animation) == clip and absf(editor.animation_player.current_animation_position - fposmod(float(work.time), float(WorkClips.DURATIONS[clip]))) < 0.0001, "original live editor samples identical work clip/time/body/equipment", label): return false
	else:
		var sprite: Sprite2D = lab.crowd_site._siege_work_sprites.get(work_id) if native else team._sprites[index]
		if not _expect(sprite != null and sprite.texture != null and sprite.has_meta("siege_work_frame") and sprite.material is ShaderMaterial, "original Atlas/native actor-row sprite uses real work appendix and dye shader", label): return false
		if native and not _expect(lab.crowd_site._draw_actors.has(sprite) and not lab.crowd_site._actors.has(work_id), "original native soldier appears once through the existing insertion row"): return false
		var direction: String = {Vector2i.DOWN: "down", Vector2i.LEFT: "left", Vector2i.UP: "up", Vector2i.RIGHT: "right"}[Vector2i(work.facing)]
		var expected_frame: Dictionary = WorkAppend.frame(appearance, clip, direction, float(work.time))
		if not _expect(not expected_frame.is_empty() and sprite.texture is AtlasTexture and (sprite.texture as AtlasTexture).region == (expected_frame.texture as AtlasTexture).region, "original work sprite uses the same actual clip/time/face atlas region", label): return false
		var dye_slot: String = str(appearance.equipment_dyes.keys()[0])
		if not _expect(sprite.get_instance_shader_parameter(dye_slot + "_dye") == TerrainArmy.EquipmentAtlas.DyeAtlas.canvas_color(appearance.equipment_dyes[dye_slot]), "work mask shader uses the actual original item dye"): return false
	if not _expect(TerrainArmy.load_contact_source(lab.character.editor), "original continuous contact source is available"): return false
	var actual_source: RefCounted = TerrainArmy.contact_source_for(appearance)
	if (native or work_mode == "gd_atlas") and not _expect(actual_source != null and actual_source.supports_appearance(appearance), "production contact owner must admit this actual body; do not replace a woman with male mesh", {"body": work_body, "native": native}): return false
	var geometry: Dictionary = owner.incoming_geometry(index)
	# An independent original same-body ContactSource is a test oracle only;
	# never installed on a person/Lab or allowed to drive accepted hits.
	if reference_contact == null:
		reference_contact = TerrainArmy.ContactSource.new()
		if not _expect(reference_contact.initialize(root, appearance, editor), "original same-body raw contact oracle initializes without body coercion"): return false
	var raw: Dictionary = reference_contact.sample(StringName(clip), fposmod(float(work.time), float(WorkClips.DURATIONS[clip])), Vector2i(work.facing), Vector2.ZERO, 0.0, appearance, false)
	var ground: Vector2 = person.position if native else owner.combat_ground(index)
	var offset: Vector2 = ground + lab.terrain.surface_visual_offset_at(ground) if native else ground + owner.combat_offset(index)
	if not _expect(_mesh_equal(geometry.body, raw.get("body", []), offset), "actual incoming body mesh equals the identical original work clip/time/face/equipment projection", label): return false
	var profile: Dictionary = SiteCombatRules.siege_hit_profile("ballista")
	var point: Vector2 = geometry.body[0][0]
	var actual: Vector2 = owner.contact_protection(index, {"point": point, "body": 0, "shield": false}, profile)
	var expected: Vector2 = reference_contact.armor_at(StringName(clip), fposmod(float(work.time), float(WorkClips.DURATIONS[clip])), Vector2i(work.facing), point - offset, str(profile.kind), Vector2.ZERO, 0.0, appearance)
	return _expect(actual.distance_to(expected) < 0.00001, "original armor material samples the actual same work mesh", label)

func _work_capture(clip: String, label: String) -> bool:
	if not _check_work(clip, label): return false
	_focus()
	return await _capture(label, {"person_id": work_id, "work": ui.vehicles.siege_work_pose(work_id), "mode": work_mode, "body": work_body, "actual_contact_mesh": true})

func _check_no_work(label: String) -> bool:
	if lab.crowd_site != null and lab.crowd_site.active: lab.crowd_site.render(0.0)
	else: team.advance_frame(0.0)
	if not _expect(ui.vehicles.siege_work_pose(work_id).is_empty(), "original work query yields to reaction/KO/release", label): return false
	if work_mode == "native_soldier":
		return _expect(not lab.crowd_site._siege_work_sprites.has(work_id), "reaction/KO/release removes only the optional row and restores original native kit", label)
	var editor: Variant = lab.character.editor if work_mode == "native_actor" else team._unit_editor(team.index_for_identity(work_id))
	if editor != null: return _expect(not WorkClips.DURATIONS.has(str(editor.selected_animation)), "original live reaction/KO/ordinary animation replaces work", label)
	var sprite: Sprite2D = team._sprites[team.index_for_identity(work_id)]
	return _expect(sprite != null and sprite.texture != null and not sprite.has_meta("siege_work_frame"), "original ordinary/KO atlas replaces work without blanking the original person", label)

func _release_engine() -> bool:
	var stopped := ui.vehicles.order_siege(key, "stop", {}, commander_id, true)
	if not _expect(stopped.ok, "original stop preserves committed movement/action safety", stopped): return false
	if not await _until_work(func() -> bool: return lab.terrain.site.vehicles[key].move.is_empty() and lab.terrain.site.vehicles[key].action.is_empty(), 20.0, "original stop safely settles without second clock"): return false
	var released := ui.vehicles.unassign_crew(key, 0, commander_id, true)
	if not _expect(released.ok, "original crew release transaction", released): return false
	return await _until_work(func() -> bool: return lab.terrain.site.vehicles[key].crew_slots.is_empty(), 20.0, "same crew safely leave original vehicle")

func _push_and_pull() -> bool:
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var goal := anchor + facing
	if not _expect(ui.vehicles.order_siege(key, "move", {"type": "ground", "cell": [goal.x, goal.y]}, commander_id, true).ok, "actual RAM whole-group movement command"): return false
	if not await _until_work(func() -> bool: return str(ui.vehicles.siege_work_pose(work_id).get("clip", "")) == "siege_push" and float(ui.vehicles.siege_work_pose(work_id).get("time", 0.0)) >= 0.20, 15.0, "actual committed compound reaches work sample"): return false
	if not await _work_capture("siege_push", "01_actual_push"): return false
	if not await _until_work(func() -> bool: return vehicle.move.is_empty() and int(vehicle.cell) == lab.terrain.index(goal), 20.0, "whole original group completes the same source/target barrier"): return false
	if lab.crowd_site != null and lab.crowd_site.active:
		# Original pose acknowledgment can precede velocity decay. Observe the
		# same original crew through shared steps; keep the real turn BUSY guard.
		if not await _until_work(func() -> bool:
			for identity: int in crew_ids:
				var person: Dictionary = ui.person_actions._person(identity)
				if person.is_empty() or bool(person.moving): return false
			return true, 20.0, "original native crew naturally settles after compound pose acknowledgment"): return false
	anchor = goal
	completed_work += 1
	if not _expect(ui.vehicles.order_siege(key, "turn", {"facing": [0, 1]}, commander_id, true).ok, "actual crew paths and visible rig turn command"): return false
	if not await _until_work(func() -> bool: return str(vehicle.action.get("stage", "")) == "rotate" and float(vehicle.action.get("elapsed", 0.0)) >= 0.25, 40.0, "all original crew arrive at real rig contacts before rotating"): return false
	if not await _work_capture("siege_pull", "02_actual_turn_pull"): return false
	completed_work += 1
	if not await _release_engine(): return false
	if not _check_no_work("released"): return false
	if not await _capture("03_original_release", {"original_person_preserved": true}): return false
	completed_work += 1
	var removed := SiteRuntime.remove_siege_vehicle(lab.terrain, key, 1, ui.vehicles._siege_people_except.bind({}))
	if not _expect(removed.ok, "original empty idle engine removal permits next paid fixture", removed): return false
	facing = Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	visual_direction = "down" if facing == Vector2i.DOWN else "right"
	visual_kind = "ballista"
	return _paid_vehicle("ballista")

func _pending_load_and_reactions() -> bool:
	if not await _assign_all(): return false
	# Finish the prior committed turn grace before adding ammo or a pending attack.
	if not await _until_work(func() -> bool: return float(lab.terrain.site.combat_left) <= 0.0, 12.0, "original turn combat grace naturally ends before pending attack"): return false
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	vehicle.cargo.siege_bolt = 1 # Explicit initial fixture round; real attack owns its debit.
	vehicle.holder.version = int(vehicle.holder.version) + 1
	var target := {"type": "ground", "cell": [anchor.x + facing.x * 12, anchor.y + facing.y * 12]}
	if not _expect(ui.vehicles.order_siege(key, "attack", target, commander_id, true).ok and vehicle.action.is_empty(), "real stable pending attack exists before its first shared step"): return false
	if not _expect(float(lab.terrain.site.combat_left) == 0.0, "pending load begins outside original combat save guard"): return false
	var saved: Dictionary = ui.save_to(ui.save_path)
	if not _expect(saved.ok, "actual original JSON saves pending command/crew/appearance", saved): return false
	WorkAppend._directories.clear() # No person state: simulate a fresh process admission cache.
	var before_load: TerrainData = lab.terrain
	await ui._load_path(ui.save_path)
	if not _expect(not is_same(lab.terrain, before_load) and lab.terrain.site.vehicles.has(key), "actual original GUI JSON load commits a fresh validated terrain and preserves pending engine ID"): return false
	team = lab.army
	team.set_process(false)
	ui._auto_save_blocked = true
	vehicle = lab.terrain.site.vehicles[key]
	if not _expect(str(vehicle.command.get("type", "")) == "attack" and vehicle.command.target == target and vehicle.crew_slots.values().has(work_id), "actual JSON load restores identical typed pending target and original crew ID"): return false
	for fact: Dictionary in asset_facts:
		if not _expect(FileAccess.get_md5(str(fact.directory) + "/manifest.json") == fact.md5 and FileAccess.get_modified_time(str(fact.directory) + "/manifest.json") == fact.modified_time, "loaded pending crew re-admits existing persistent cache without baking"): return false
	completed_work += 1
	if not await _until_work(func() -> bool: return str(vehicle.action.get("stage", "")) == "loading" and float(vehicle.action.get("elapsed", 0.0)) >= 0.25, 20.0, "loaded command resumes genuine original loading action"): return false
	if not await _work_capture("siege_load", "04_loaded_actual_loading"): return false
	completed_work += 1
	var person: Dictionary = ui.person_actions._person(work_id)
	var owner: Variant = person.owner
	var index := int(person.unit)
	owner.ranged_apply_hit(index, anchor - facing * 2, {"siege": true, "shield": false, "result": {"hp": 1.0, "stun": 1.0, "stagger": 0.35, "guard_break": false}})
	if not _check_no_work("real hit"): return false
	if not await _capture("05_original_hit_reaction", {"original_damage_owner": true}): return false
	completed_work += 1
	if not await _until_work(func() -> bool: return float(owner.combat_hot_get(index, &"exchange_stagger", 0.0)) <= 0.0, 2.0, "original owner advances its existing reaction clock"): return false
	owner.ranged_apply_hit(index, anchor - facing * 2, {"siege": true, "shield": false, "result": {"hp": 1.0, "stun": SiteCombatRules.STUN_LIMIT, "stagger": 0.35, "guard_break": false}})
	if not _expect(float(owner.combat_hot_get(index, &"ko", 0.0)) > 0.0 and ui.vehicles.siege_work_pose(work_id).is_empty(), "original actual knockout suppresses work without overwriting HP/KO pose"): return false
	var knockout_hp_before_wait := float(owner.combat_hot_get(index, &"hp", 0.0))
	var knockout_ko_before_wait := float(owner.combat_hot_get(index, &"ko", 0.0))
	if not _seconds(3.0) or not _check_no_work("real KO"): return false
	if not _expect(owner.combat_identity(index) == work_id and float(owner.combat_hot_get(index, &"ko", 0.0)) > 0.0, "same original person remains knocked out after its natural down animation"): return false
	if not await _capture("06_original_knockout", {"original_person_id": work_id, "original_ko_owner": true,
		"elapsed_ko_action_seconds": 3.0, "hp_before_wait": knockout_hp_before_wait, "hp_after_wait": float(owner.combat_hot_get(index, &"hp", 0.0)),
		"ko_before_wait": knockout_ko_before_wait, "ko_after_wait": float(owner.combat_hot_get(index, &"ko", 0.0)),
		"health_scope": "Original owner advances health; native unbandaged KO bleeding remains enabled, no HP equality override."}): return false
	completed_work += 1
	if not _expect(ui.vehicles.order_siege(key, "stop", {}, commander_id, true).ok and ui.vehicles.unassign_crew(key, 0, commander_id, true).ok, "remaining original crew can stop and safely release after KO"): return false
	if not await _until_work(func() -> bool: return vehicle.crew_slots.is_empty() and vehicle.action.is_empty(), 12.0, "final original recovery and release settle"): return false
	if not _expect(ui.vehicles.siege_work_pose(work_id).is_empty() and ui.person_actions._person(work_id).holder.item_ids == original_items, "final release preserves knocked-out original person's actual equipment IDs"): return false
	completed_work += 1
	return await _capture("07_ko_safe_release", {"original_knocked_out_person_preserved": true})

func _run() -> void:
	if not _expect(work_mode in ["gd_atlas", "gd_live", "native_soldier", "native_actor"], "known original work presenter case", work_mode): return
	if not _preflight() or not _scene() or not _paid_vehicle("ram"): return
	visual_case = "original_work"
	if not await _make_people(): return
	if not await _push_and_pull(): return
	if not await _pending_load_and_reactions(): return
	if not _expect(completed_work == 8 and captures.size() == 7, "all eight actual work/control/persistence scopes and seven real images complete", {"completed": completed_work, "captures": captures.size()}): return
	visual_finished = true
	_report()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	if reference_contact != null: reference_contact.dispose()
	print("SITE_SIEGE_WORK_ORIGINAL_GPU_PASS: ", work_mode, " body=", work_body, " cache_only=", cache_only, " actual original work/contact/dye/reaction/KO/release/JSON pending load; manual pixel review remains separate")
	quit(0)
