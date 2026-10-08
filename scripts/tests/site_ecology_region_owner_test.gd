extends "res://scripts/tests/region_controlled_death_restriction_test.gd"
## Bounded E1 migration checks on actual original PackedScene / Slot / Store.
## Reuses the pinned manifest and cleanup fixture, not its death acceptance.
const EcologyCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	out = "res://.godot-temp/site_ecology_region_owner/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	_run.call_deferred()

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(false); return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "Original formal scene exists"): _finish(false); return
	lab = packed.instantiate() as TerrainLab
	lab.restore_only = true
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	controller = lab.site_controller
	_freeze(lab)
	var archived := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archived, "ecology-owner:archive")
	lab.bind_terrain(archived)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "ecology_owner_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened := controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Original fixed-world publication", opened): _finish(false); return
	_freeze(lab)
	slot = controller.region_slot
	var wired := lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "Actual Slot adapters", wired): _finish(false); return
	cold_id = Grid.site_id(str(slot.pin.atlas_id), Vector2i(1, 0))
	var owner := lab._region_gameplay_owner_lab(cold_id, "cold_exact")
	if not _check(owner.ok and owner.lab is TerrainLab, "Actual original cold owner", owner): _finish(false); return
	cold = owner.lab
	_freeze(cold)
	# Author a legacy fixture on the actual owner before its first checkpoint.
	# Existing biological stock/base and all people/items remain unchanged.
	cold.terrain.site.erase("ecology_version")
	for fields: Dictionary in cold.terrain.site.changes.values():
		fields.erase("eco_mode")
		fields.erase("eco_resting")
	var committed := controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(committed.ok, "Actual owner captures a legacy selected source", committed): _finish(false); return
	var source_path := slot.site_path(Vector2i(1, 0))
	var loaded := slot._load_checked(source_path, Vector2i(1, 0))
	if not _check(loaded.ok, "Selected legacy source readback", loaded): _finish(false); return
	var source: TerrainData = loaded.data
	if not _check(not source.site.has("ecology_version") and source.site.has("region_snapshot"), "Region readback retains original unmarked source"): _finish(false); return
	var source_sha := FileAccess.get_sha256(source_path)
	var source_bytes := var_to_bytes([source.site, source.resource_base, source.parameters, source.fingerprint()])
	var active_before := var_to_bytes(lab.terrain.site)
	var world_before := float(slot.control.logical_game_seconds)
	var generation_before := int(slot._marker.generation)
	var original_metadata := SiteStore.validate_region_snapshot(source, {})
	if not _check(original_metadata.ok, "Legacy validation remains a pure source proof", original_metadata): _finish(false); return
	var prepared := lab.prepare_region_owner_bind(source, "cold_exact", slot)
	if not _check(prepared.ok, "Original selected-source bind prepares E1 candidate", prepared): _finish(false); return
	if not _check(prepared.data != source and int(prepared.data.site.ecology_version) == 1, "E1 is admitted only on detached candidate"):
		prepared.discard.call(); _finish(false); return
	var migrated_metadata := SiteStore.validate_region_snapshot(prepared.data, {})
	if not _check(migrated_metadata.ok and prepared.data.site.has("region_snapshot"), "Migrated bind captured actual original owner graph", migrated_metadata):
		prepared.discard.call(); _finish(false); return
	var candidate_path := out.path_join("ecology_bind_candidate.json")
	var saved: Dictionary = prepared.save_candidate.call(prepared.data, candidate_path)
	if not _check(saved.ok, "Original candidate save plus exact Slot readback", saved):
		prepared.discard.call(); _finish(false); return
	var roundtrip := slot._load_checked(candidate_path, Vector2i(1, 0))
	if not _check(roundtrip.ok and int(roundtrip.data.site.ecology_version) == 1, "E1 owner snapshot survives real file roundtrip", roundtrip):
		prepared.discard.call(); _finish(false); return
	# The selected source proof does not certify arbitrary target ecology.
	# Submit actual transformed candidates through the real original wrapper.
	var population := ""
	for key: String in prepared.data.resource_base:
		if int(prepared.data.resource_base[key].kind) in [Env.Kind.FISH, Env.Kind.WILDLIFE] and int(Env.ecology_info(prepared.data, key).capacity) >= 2:
			population = key
			break
	if not _check(not population.is_empty(), "Pinned fixture supplies an original population with K at least two"):
		prepared.discard.call(); _finish(false); return
	var population_capacity := int(Env.ecology_info(prepared.data, population).capacity)
	var cold_data_before: TerrainData = cold.terrain
	var cold_body_before: TerrainTestCharacter = cold.character
	var original_owner_before := var_to_bytes([cold.terrain.site, cold.character.capture_state(), cold._region_bind_receipt_value])
	var children_before := lab.get_child_count()
	for tamper: Dictionary in [{"remaining": 0, "eco_resting": false}, {"remaining": population_capacity, "eco_resting": true}, {"remaining": 0, "eco_resting": "false"}]:
		var invalid_target := Env.navigation_for_state(prepared.data, prepared.data.site.duplicate(true))
		invalid_target.site.changes[population] = {"remaining": tamper.remaining, "next_recovery": -1, "eco_resting": tamper.eco_resting}
		invalid_target.set_meta(&"region_bind_source", source)
		var invalid_bytes := var_to_bytes([invalid_target.site, invalid_target.resource_base, invalid_target.parameters])
		var denied := lab.prepare_region_owner_bind(invalid_target, "cold_exact", slot)
		if denied.ok and denied.get("discard") is Callable: denied.discard.call()
		if not _check(not denied.ok, "Actual bind rejects a corrupt target even with a legal selected source", {"tamper": tamper, "result": denied}):
			prepared.discard.call(); _finish(false); return
		if not _check(var_to_bytes([invalid_target.site, invalid_target.resource_base, invalid_target.parameters]) == invalid_bytes, "Rejected target is not repaired in place"):
			prepared.discard.call(); _finish(false); return
		if not _check(var_to_bytes([source.site, source.resource_base, source.parameters, source.fingerprint()]) == source_bytes and FileAccess.get_sha256(source_path) == source_sha, "Rejected target keeps legal raw source and file hash"):
			prepared.discard.call(); _finish(false); return
		if not _check(cold.terrain == cold_data_before and cold.character == cold_body_before and var_to_bytes([cold.terrain.site, cold.character.capture_state(), cold._region_bind_receipt_value]) == original_owner_before and lab.get_child_count() == children_before, "Rejected target leaves original owner and retained scene set unchanged"):
			prepared.discard.call(); _finish(false); return
		if not _check(var_to_bytes(lab.terrain.site) == active_before and float(slot.control.logical_game_seconds) == world_before and int(slot._marker.generation) == generation_before, "Rejected target cannot mutate active owner or publish time/generation"):
			prepared.discard.call(); _finish(false); return
	prepared.discard.call()
	if not _check(var_to_bytes([source.site, source.resource_base, source.parameters, source.fingerprint()]) == source_bytes and FileAccess.get_sha256(source_path) == source_sha, "Preparing/saving never edits selected legacy source"):
		_finish(false); return
	if not _check(var_to_bytes(lab.terrain.site) == active_before and float(slot.control.logical_game_seconds) == world_before and int(slot._marker.generation) == generation_before, "Private preparation cannot publish world/people/time"):
		_finish(false); return
	# The direct original cold restore entry is separate from prepared binding.
	var created := lab._region_new_bind_child(source)
	if not _check(created.ok, "Original retained cold shell", created): _finish(false); return
	var replay: TerrainLab = created.child
	var restored := replay.restore_original_site(source)
	if not _check(restored.ok and restored.get("owners_restored") == true and int(replay.terrain.site.get("ecology_version", 0)) == 1, "Cold source migrates through original graph projection", restored):
		replay.free(); _finish(false); return
	var biological := ""
	for key: String in replay.terrain.resource_base:
		if int(replay.terrain.resource_base[key].kind) in [Env.Kind.TIMBER, Env.Kind.FOOD, Env.Kind.HERB]:
			biological = key
			break
	if not _check(not biological.is_empty(), "Fixed fixture has an original biological source"):
		replay.free(); _finish(false); return
	var mode := SiteRuntime.ecology_set_modes(replay.terrain, [biological], "protected")
	if not _check(mode.ok, "Original ecology mode mutation on restored child", mode):
		replay.free(); _finish(false); return
	var context: Dictionary = original_metadata.context
	var owners := replay.capture_region_owner_state(context)
	if not _check(owners.ok, "Original cold child captures its actual owners", owners):
		replay.free(); _finish(false); return
	var captured := SiteStore.capture_region_snapshot(replay.terrain, context, owners.owner_states)
	if not _check(captured.ok, "Original Region capture accepts E1 state", captured):
		replay.free(); _finish(false); return
	var cold_path := out.path_join("ecology_cold_candidate.json")
	var cold_saved := SiteStore.save_region_snapshot(replay.terrain, cold_path, context, owners.owner_states)
	if not _check(cold_saved.ok, "Original cold owner writes real Store file", cold_saved):
		replay.free(); _finish(false); return
	var cold_loaded := slot._load_checked(cold_path, Vector2i(1, 0))
	if not _check(cold_loaded.ok and cold_loaded.data.site.changes[biological].eco_mode == "protected", "Cold E1 mode and actual owner snapshot survive load", cold_loaded):
		replay.free(); _finish(false); return
	# A correct checksum cannot hide invalid E1 schema in a bare snapshot.
	var tampered: Dictionary = captured.state.duplicate(true)
	tampered.ecology_version = 2
	var forged := EcologyCheckpoint.make(tampered, context, owners.owner_states)
	if not _check(forged.ok, "Tamper fixture contains a self-consistent metadata hash", forged):
		replay.free(); _finish(false); return
	tampered.region_snapshot = forged.snapshot
	var tampered_before := var_to_bytes(tampered)
	var rejected := SiteStore.validate_region_snapshot(replay.terrain, {"state": tampered})
	if not _check(not rejected.ok and var_to_bytes(tampered) == tampered_before, "Bare owner snapshot rejects invalid ecology schema without repair", rejected):
		replay.free(); _finish(false); return
	replay.free()
	if not _check(var_to_bytes([source.site, source.resource_base, source.parameters, source.fingerprint()]) == source_bytes and FileAccess.get_sha256(source_path) == source_sha, "Cold migration keeps legacy file and source immutable"):
		_finish(false); return
	report = {"legacy_source_sha256": source_sha, "prepared_file": candidate_path, "cold_file": cold_path,
		"checks": checks, "scope": "original_owner_region_prepare_and_cold_restore_migration_file_roundtrip"}
	_finish(true)

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): print(message)
	paused = false
	if is_instance_valid(lab): lab.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and current.get("world_id") == world_id:
		if last_world_exists:
			var file := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE)
			file.store_buffer(last_world_bytes)
			file.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var evidence := {"checks": checks, "failed": failed, "report": report, "artifact_root": out,
		"scope": "original_owner_region_prepare_and_cold_restore_migration_file_roundtrip"}
	var output := FileAccess.open(out.path_join("receipt.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(evidence, "\t", true, true))
		output.close()
	print("SITE_ECOLOGY_REGION_OWNER_", "FAIL" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)
