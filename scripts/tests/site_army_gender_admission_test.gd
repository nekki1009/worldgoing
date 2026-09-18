extends SceneTree
## Real Site save/load boundaries; isolated bad saves/assets, never user data.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const OUT := "res://output/terrain_army_acceptance_20260918/admission"
const SAVE := OUT + "/valid.json"
const BAD := OUT + "/invalid.json"
const FIXTURE := OUT + "/female"

func _initialize() -> void:
	_run.call_deferred()

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value))
	file.close()

func _bad_state(state: Dictionary) -> void:
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	var payload: Dictionary = JSON.parse_string(envelope.payload)
	payload.state = state
	envelope.payload = JSON.stringify(payload, "", true, true)
	envelope.checksum = str(envelope.payload).sha256_text()
	_write(BAD, envelope)

func _run() -> void:
	create_timer(50.0).timeout.connect(func() -> void: push_error("Gender admission deadline"); quit(1))
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	assert(lab.start_melee_trial({"friendly_count": 3, "enemy_count": 1, "friendly_female_percent": 100,
		"enemy_female_percent": 0, "friendly_attack": false, "enemy_attack": false}).ok)
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, SAVE).ok)
	var original_hash := FileAccess.get_sha256(SAVE)
	var loaded := Store.load_site(SAVE)
	assert(loaded.ok)
	lab.bind_terrain(loaded.data)
	lab.site_controller._auto_save_blocked = true
	assert(lab.army.combat_units[1].visual_role == "female_atlas")
	assert(lab.site_controller.person_appearance(lab.army.combat_identity(1)).body == 1)
	var state: Dictionary = loaded.data.site.duplicate(true)
	state.armies[0].units[1].erase("appearance")
	_bad_state(state)
	assert(Store.load_site(BAD).code == "CORRUPT_SAVE", "Current female row cannot erase its appearance to bypass asset admission")
	state.armies[0].erase("visual_version")
	_bad_state(state)
	assert(Store.load_site(BAD).code == "CORRUPT_SAVE", "Unversioned female-atlas rows are not the historical male-only missing-template format")
	state = loaded.data.site.duplicate(true)
	state.armies[1].units[0].erase("appearance")
	_bad_state(state)
	assert(Store.load_site(BAD).code == "CORRUPT_SAVE", "Current male rows also require their explicit appearance")
	state = loaded.data.site.duplicate(true)
	state.armies[0].units[1].visual_role = "male_atlas"
	_bad_state(state)
	assert(not Store.load_site(BAD).ok, "Body/role mismatch must fail before scene replacement")
	state = loaded.data.site.duplicate(true)
	state.armies[0].units[1].appearance.parts.hair = "hair_female_02"
	_bad_state(state)
	assert(Store.load_site(BAD).code == "MISSING_ASSET")
	var prior: Dictionary = loaded.data.site
	loaded.data.site = state
	assert(Store.save(loaded.data, SAVE).code == "MISSING_ASSET")
	loaded.data.site = prior
	assert(FileAccess.get_sha256(SAVE) == original_hash, "Rejected save must preserve last good bytes")
	state = loaded.data.site.duplicate(true)
	state.armies[0].units[1].item_state.equipped.erase("shield")
	_bad_state(state)
	assert(Store.load_site(BAD).code == "MISSING_ASSET", "Admission must read actual gear, not the original full-loadout template")
	# The historical headless captain had female_live but a male body. Only
	# unversioned data migrates its label; current explicit data is strict.
	state = loaded.data.site.duplicate(true)
	state.armies[0].units[0].appearance = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	_bad_state(state)
	assert(not Store.load_site(BAD).ok)
	state.armies[0].erase("visual_version")
	_bad_state(state)
	var legacy := Store.load_site(BAD)
	assert(legacy.ok and legacy.data.site.armies[0].units[0].visual_role == "male_live")
	assert(legacy.data.site.armies[0].units[0].appearance.body == 0)
	# Actual private publication copy gives positive controls for missing/stale
	# assets without moving, deleting, or modifying any production resource.
	assert(DirAccess.make_dir_recursive_absolute(FIXTURE) == OK)
	var production_hashes := {}
	for name: String in ["page_000.png", "page_000.res", "dye.png"]:
		production_hashes[name] = FileAccess.get_sha256(Atlas.FEMALE_ROOT + "/" + name)
		assert(DirAccess.copy_absolute(Atlas.FEMALE_ROOT + "/" + name, FIXTURE + "/" + name) == OK)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Atlas.FEMALE_ROOT + "/manifest.json"))
	manifest.pages[0].path = FIXTURE + "/page_000.png"
	manifest.pages[0].resource_path = FIXTURE + "/page_000.res"
	_write(FIXTURE + "/manifest.json", manifest)
	var dye: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Atlas.FEMALE_ROOT + "/dye.json"))
	dye.source_manifest = FIXTURE + "/manifest.json"
	dye.source_manifest_md5 = FileAccess.get_md5(dye.source_manifest)
	dye.mask_path = FIXTURE + "/dye.png"
	_write(FIXTURE + "/dye.json", dye)
	Atlas._female_root = FIXTURE
	assert(Store.load_site(SAVE).ok, "Isolated unchanged resources must pass")
	Atlas._female_root = FIXTURE + "/missing"
	var current_data := lab.terrain
	var current_ids := lab.army.snapshot_person_ids(lab.army.capture_combat_state())
	lab.site_controller._load_path(SAVE)
	assert(lab.terrain == current_data and lab.army.snapshot_person_ids(lab.army.capture_combat_state()) == current_ids)
	assert(Store.load_site(SAVE).code == "MISSING_ASSET", "Even a warmed cache must recheck at load")
	Atlas._female_root = FIXTURE
	var broken := manifest.duplicate(true)
	broken.source_fingerprints[Atlas.FEMALE_BAKER] = "00000000000000000000000000000000"
	_write(FIXTURE + "/manifest.json", broken)
	assert(Store.load_site(SAVE).code == "MISSING_ASSET")
	broken = manifest.duplicate(true)
	broken.pages[0].resource_path = FIXTURE + "/absent.res"
	_write(FIXTURE + "/manifest.json", broken)
	assert(Store.load_site(SAVE).code == "MISSING_ASSET")
	_write(FIXTURE + "/manifest.json", manifest)
	broken = dye.duplicate(true)
	broken.source_manifest_md5 = "00000000000000000000000000000000"
	_write(FIXTURE + "/dye.json", broken)
	assert(Store.load_site(SAVE).code == "MISSING_ASSET")
	_write(FIXTURE + "/dye.json", dye)
	assert(Store.load_site(SAVE).ok)
	Atlas._female_root = Atlas.FEMALE_ROOT
	Atlas.refresh_female_sources()
	for name: String in production_hashes:
		assert(FileAccess.get_sha256(Atlas.FEMALE_ROOT + "/" + name) == production_hashes[name])
	# Female remains retain their actual equipment; unavailable missing-piece
	# visuals reject removal atomically instead of losing the real item.
	var row: Dictionary = lab.army.combat_units[1]
	var person_id := lab.army.combat_identity(1)
	var shield_id := str(row.item_state.equipped.shield)
	var items_before := JSON.stringify(lab.terrain.site.item_records)
	assert(not lab.site_controller.equipment_removal_guard(person_id, [shield_id]).ok)
	assert(JSON.stringify(lab.terrain.site.item_records) == items_before and row.item_state.equipped.shield == shield_id)
	lab.army.apply_unit_contact(1, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true})
	lab._process((ceilf(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) / TerrainLab.EXCHANGE_ACTION_STEP) + 1.0) * TerrainLab.EXCHANGE_ACTION_STEP)
	assert(row.loot_settled and row.item_state.item_ids.is_empty())
	assert(lab.terrain.site.ground_loot[row.remains_id].item_ids.has(shield_id))
	assert(lab.site_controller.person_appearance(person_id).parts.shield != "none")
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, OUT + "/female_remains.json").ok)
	assert(Store.load_site(OUT + "/female_remains.json").ok)
	print("GENDER ADMISSION PASS: strict roles, legacy live migration, actual gear, missing/stale atlas and dye, failed load/save atomicity, female remains and no lost equipment")
	lab.queue_free()
	await process_frame
	quit(0)
