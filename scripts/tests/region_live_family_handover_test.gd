extends "res://scripts/tests/region_controlled_death_restriction_test.gd"
## Actual pinned World / live and cold original owners / one Slot publication.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const LiveFamily = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const LiveCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
var live_target := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	out = "res://.godot-temp/region_live_family_handover/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	_run.call_deferred()

func _live_region_facts() -> PackedByteArray:
	var owners := {}
	for owner: String in slot._region_original_labs:
		var actual: TerrainLab = slot._region_original_labs[owner]
		var state: Dictionary = actual.terrain.site.duplicate(true)
		actual.site_controller._capture_positions(state, true)
		var appearances: Array = []
		for actor: TerrainTestCharacter in actual.combat_actors: appearances.append(actor._saved_appearance.duplicate(true))
		var offices: Array = []
		for team: TerrainArmy in actual.combat_armies: offices.append(team.offices.duplicate(true))
		owners[owner] = {"site": actual.terrain.site, "body": state, "appearance": appearances, "offices": offices}
	return var_to_bytes({"marker": slot._marker, "control": slot.control, "owners": owners, "paused": paused})

func _live_family_ref(identity: int) -> Dictionary:
	return {"site_id": str(lab.terrain.site.id), "person_id": identity, "path": "", "label": "原家人", "age_years": -1}

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(); return
	var packed: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "Original formal scene exists"): _finish(); return
	lab = packed.instantiate() as TerrainLab
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	controller = lab.site_controller
	_freeze(lab)
	var bootstrap: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(bootstrap, "live-family:archive")
	lab.bind_terrain(bootstrap)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "live_family_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened["ok"], "Original Controller creates and binds one actual pinned World", opened): _finish(); return
	_freeze(lab)
	slot = controller.region_slot
	var wired: Dictionary = lab._wire_region_gameplay_adapters(slot)
	if not _check(wired["ok"], "Original same-Slot owners wire", wired): _finish(); return
	# Explicit finite TEST genesis uses the original allocator, Army and holders.
	var side: Dictionary = {"prefix": "friendly", "count": 2, "slot_count": 2, "female_count": 0, "faction": lab.character.faction_id, "training": 0.0,
		"role": "combat", "troop_type": "melee_infantry", "attack": false, "cart_count": 0, "wagon_count": 0, "abilities": {}, "ai_enabled": false}
	var sides: Array[Dictionary] = [side]
	var cells: Array[Vector2i] = [Vector2i(20, 20), Vector2i(21, 20)]
	# Slot 0 holds the new-game player team (unit 0, captain); the friendly side goes to slot 1.
	var born: Dictionary = lab._deploy_trial_teams(sides, [cells], 1)
	if not _check(born["ok"], "Original named genesis creates real rows without control reassignment", born): _finish(); return
	var team: TerrainArmy = lab.combat_armies[1]
	live_target = team.combat_identity(team.formal_commander)
	var head: int = lab.controlled_person_id()
	var family: LiveFamily = controller.family_continuity
	var registered: Dictionary = family.register_members([_live_family_ref(head), _live_family_ref(live_target)], true)
	if not _check(registered["ok"], "Original family explicitly registers both actual people", registered): _finish(); return
	var appointed: Dictionary = family.appoint_head(head, head)
	if not _check(appointed["ok"], "Original head appointment grants actual authority", appointed): _finish(); return
	cold_id = Grid.site_id(str(slot.pin.atlas_id), Vector2i(1, 0))
	var other: Dictionary = lab._region_gameplay_owner_lab(cold_id, "cold_exact")
	if not _check(other["ok"] and other.get("lab") is TerrainLab, "Original cold factory creates the other full owner", other): _finish(); return
	cold = other["lab"]
	_freeze(cold)
	var due: Dictionary = slot.consume_due_region_events()
	if not _check(due["ok"] and bool(due.get("complete", false)), "Original due endpoints finish before handover", due): _finish(); return
	var initial: Dictionary = controller.checkpoint_region_internal("region_checkpoint")
	if not _check(initial["ok"], "Original complete checkpoint selects both actual owners", initial): _finish(); return
	var generation: int = int(slot._marker["generation"])
	var before: PackedByteArray = _live_region_facts()
	var refused: Dictionary = family.handover(head, cold_id, live_target)
	if not _check(not refused["ok"] and str(refused["code"]) == "LOCAL_REQUIRED" and before == _live_region_facts(), "Remote selection refuses without moving a person or changing either graph/generation", refused): _finish(); return
	# Site generation filenames carry a usec timestamp, so they cannot be obstructed in advance;
	# the deterministic next commit document below is the real IO obstruction.
	var removed: Error = OK
	var made: Error = OK
	var blocked_commit: String = slot.folder.path_join("commits/%020d.json" % (generation + 1))
	made = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_commit))
	if not _check(made == OK, "The next commit document is obstructed after all owner captures", made): _finish(); return
	before = _live_region_facts()
	var commit_failure: Dictionary = family.handover(head, str(lab.terrain.site.id), live_target)
	removed = DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_commit))
	if not _check(not commit_failure["ok"] and removed == OK and before == _live_region_facts(), "Late original commit failure leaves active/cold body graphs, marker and control exact", commit_failure): _finish(); return
	var old_actor: TerrainTestCharacter = lab.character
	var old_body: PackedByteArray = var_to_bytes(old_actor.capture_state(true))
	var old_family: PackedByteArray = var_to_bytes(lab.terrain.site["family"])
	var cold_body: Dictionary = cold.terrain.site.duplicate(true)
	cold.site_controller._capture_positions(cold_body, true)
	var context: Dictionary = controller._live_family_ui_context()
	var changed: Dictionary = family.handover(head, str(lab.terrain.site.id), live_target)
	if not _check(changed["ok"] and int(slot._marker["generation"]) == generation + 1, "Living handover uses exactly one original Slot publication", changed): _finish(); return
	if not _check(lab.character == old_actor and old_body == var_to_bytes(old_actor.capture_state(true)) and old_family == var_to_bytes(lab.terrain.site["family"]), "Old living head remains same body, items, position and family office"): _finish(); return
	var cold_after: Dictionary = cold.terrain.site.duplicate(true)
	cold.site_controller._capture_positions(cold_after, true)
	if not _check(var_to_bytes(cold_body) == var_to_bytes(cold_after), "Joint publication preserves the complete other cold owner"): _finish(); return
	before = _live_region_facts()
	var stale: Dictionary = controller._submit_live_family_handover(context, str(lab.terrain.site.id), live_target)
	if not _check(not stale["ok"] and str(stale["code"]) == "STALE_CONTEXT" and before == _live_region_facts(), "Old UI context cannot reuse the previous controller/generation", stale): _finish(); return
	for coordinate: Vector2i in [Vector2i.ZERO, Vector2i(1, 0)]:
		var loaded: Dictionary = slot._load_checked(slot.site_path(coordinate), coordinate)
		if not _check(loaded["ok"], "Original Slot reads a selected active/cold generation", loaded): _finish(); return
		var validated: Dictionary = Store.validate_region_snapshot(loaded["data"], {})
		if not _check(validated["ok"], "Each selected body retains an authenticated full original owner graph", validated): _finish(); return
		if coordinate == Vector2i.ZERO:
			if not _check(int(loaded["data"].site["controlled_person_id"]) == live_target, "Selected active save contains new control"): _finish(); return
	# Actual original departure makes the old head's Site cold; it is not a control-only teleport.
	lab.terrain.site["paused"] = false
	paused = false
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed["ok"], "New controlled Captain departs through the original Region travel transaction", departed): _finish(); return
	var source: Dictionary = slot.open_site(Vector2i.ZERO)
	if not _check(source["ok"], "Original Slot reopens the former hot Site as a saved cold source", source): _finish(); return
	var old_saved: Dictionary = LiveFamily._saved_person(source["data"], head)
	var moved_saved: Dictionary = LiveFamily._saved_person(source["data"], live_target)
	if not _check(not old_saved.is_empty() and float(old_saved["hp"]) > 0.0 and moved_saved.is_empty(), "Former head stays alive in cold source; actual departing person is not duplicated"): _finish(); return
	var restored: TerrainLab = packed.instantiate() as TerrainLab
	restored.restore_only = true
	restored.pause_when_unfocused = false
	restored.visible = false
	root.add_child(restored)
	var rebound: Dictionary = restored.restore_original_site(source["data"])
	# Neutral part 2: the old head may be a roster person of the start team (crowd or GD roster), not an actor body.
	var head_in_roster: bool = restored.crowd_site != null and restored.crowd_site.active and restored.crowd_site.contains_person(head)
	for restored_team: TerrainArmy in restored.combat_armies:
		if restored_team.has_army() and restored_team.index_for_identity(head) >= 0: head_in_roster = true
	_check(rebound["ok"] and (restored.actor_present(restored.character) and restored.character.person_id == head or head_in_roster),
		"Original full owner restore reconstitutes the same old head in the now-cold Site", rebound)
	restored.free()
	report = {"generation_before": generation, "generation_after_handover": generation + 1, "target": live_target,
		"old_head": head, "scope": "actual_live_handover_joint_cold_graph_io_refusal_save_and_original_departure_cold_restore"}
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): print(message)
	paused = false
	if is_instance_valid(lab): lab.free()
	if is_instance_valid(cold): cold.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and current.get("world_id") == world_id:
		if last_world_exists:
			var file: FileAccess = FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE)
			file.store_buffer(last_world_bytes)
			file.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var evidence: Dictionary = {"checks": checks, "failed": failed, "report": report}
	var output: FileAccess = FileAccess.open(out.path_join("receipt.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(evidence, "\t", true, true))
		output.close()
	print("REGION_LIVE_FAMILY_HANDOVER_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)
