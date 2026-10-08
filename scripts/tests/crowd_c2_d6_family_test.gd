extends SceneTree
## D6/D10: formal scene, original family modal, original outside NPC, immediate runtime append save.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const DT := 1.0 / 30.0
var lab: TerrainLab
var controller: SiteController
var site: Node
var out_dir := ""
var checks: Array[Dictionary] = []
var failed := false
var result: Dictionary = {}
var capture_dialog: AcceptDialog
var action_seconds := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "details": details})
	print("D6 ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		failed = true
		_write_result()
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _write_result() -> void:
	if out_dir.is_empty(): return
	var file := FileAccess.open(out_dir.path_join("d6_family.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not failed, "checks": checks, "action_seconds": action_seconds,
			"coverage": "Formal family modal; actor to outside NPC append before next native step; NPC to original roster and roster to roster; native and full Site roundtrips",
			"not_covered": ["GPU family modal appearance", "new-faction enemy contact", "one/four-thread append determinism", "clear after succession"]}, "\t", true, true))
		file.close()

func _capture_result(value: Dictionary) -> void:
	result = value.duplicate(true)

func _advance(ticks: int) -> void:
	for tick in range(ticks):
		lab._advance_action_time(DT)
		action_seconds += DT
		if tick % 30 == 0: await process_frame
		if paused: return

func _native_position(identity: int) -> Vector2:
	var hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(identity)))
	return Vector2(float(hot.px), float(hot.py))

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var base := "res://output/crowd_c2_c3_20261001"
	var at := args.find("--crowd-output")
	if at >= 0 and at + 1 < args.size(): base = args[at + 1]
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out_dir = base.path_join("d6_family_%s_%d" % [stamp, Time.get_ticks_msec()])
	if not _check((base.begins_with("res://output/") or base.begins_with("res://native/crowd10k/out_c2/")) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(out_dir)), "new named evidence folder", out_dir): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ignore := FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(240.0).timeout.connect(func() -> void:
		failed = true
		_write_result()
		printerr("GATE FAIL: D6 script deadline 240 seconds")
		quit(3))
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new() # Explicit original actor fixture, authored before original scene setup.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	controller = lab.site_controller
	site = lab.crowd_site
	controller._auto_save_blocked = true
	if not _check(not controller.crowd_test_run_id.is_empty() and str(lab.terrain.site.id).begins_with("crowd_test_"), "Site and persistence isolated before fixture setup"): return
	capture_dialog = AcceptDialog.new()
	controller._equipment_dialog = capture_dialog
	controller._equipment_result = _capture_result
	var old_actor := lab.character
	var heir := lab.npc
	var old_id := old_actor.person_id
	var heir_id := heir.person_id
	heir.faction_id = 2 # A faction absent from the deployed native world.
	heir.hp = 73.0
	heir.stun = 11.0
	heir.fatigue = 17.0
	heir.fatigue_rest = 9.0
	heir.training = 68.0
	heir.exchange_cooldown = 0.7
	heir.ranged_cooldown = 0.4
	heir.exchange_skill_cooldown = 4.2
	heir.command_abilities = {"tactics": 37, "leadership": 48, "coach": 59}
	lab.terrain.site.manual.cargo = {"grain": 3}
	lab.terrain.site.worker.cargo = {"fish": 2}
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 8, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 8, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	if not _check(deployed.ok and site.active and site.contains_person(old_id) and not site.contains_person(heir_id), "formal deployment retains an existing outside NPC", deployed): return
	var first_member_id: int = site._team_by_id(int(site.command_teams()[0].team_id)).person_ids[1]
	var second_member_id: int = site._team_by_id(int(site.command_teams()[0].team_id)).person_ids[2]
	var family: Array = [
		{"site_id": str(lab.terrain.site.id), "person_id": heir_id, "path": "", "label": "Explicit existing NPC family fixture", "age_years": 14},
		{"site_id": str(lab.terrain.site.id), "person_id": first_member_id, "path": "", "label": "Explicit existing first roster family fixture", "age_years": -1},
		{"site_id": str(lab.terrain.site.id), "person_id": second_member_id, "path": "", "label": "Explicit existing second roster family fixture", "age_years": -1}]
	var registered: Dictionary = controller.family_continuity.register_members(family, true)
	if not _check(registered.ok, "register only explicit original NPC and roster people", registered): return
	var family_before: Dictionary = lab.terrain.site.family.duplicate(true)
	var native_before: Variant = site.crowd
	var scene_before := lab.terrain
	var corpse_holder: Dictionary = old_actor.item_state
	var corpse_items: Array = old_actor.item_state.item_ids.duplicate()
	var rosters_before: Array = []
	var person_ids_before: PackedInt64Array = site.crowd.person_ids()
	var commands_before: int = site.command_teams().size()
	var native_formations_before: int = site.crowd.formation_count()
	var victim: int = site._team_by_id(int(site.command_teams()[1].team_id)).person_ids[1]
	Runtime.mark_combat(lab.terrain, 12.0)
	if not _check(site.apply_environment_damage(old_id, 10000.0) == 0.0 and controller._pending_deaths.has(old_id), "controlled person dies through native event bridge"): return
	await _advance(30)
	if not _check(not paused and not is_instance_valid(controller._family_dialog) and controller._pending_deaths.has(old_id), "family waits for own original down and remains settlement"): return
	if not _check(site.apply_environment_damage(victim, 10000.0) == 0.0 and controller._pending_deaths.has(victim), "another person dies one second later"): return
	for tick in range(120):
		lab._advance_action_time(DT)
		action_seconds += DT
		if paused: break
		if tick % 30 == 0: await process_frame
	if not _check(paused and bool(lab.terrain.site.paused) and is_instance_valid(controller._family_dialog), "original FamilyDialog pauses immediately after own settlement", {"seconds": action_seconds, "pending": controller._pending_deaths}): return
	if not _check(not controller._pending_deaths.has(old_id) and controller._pending_deaths.has(victim) and float(controller._pending_deaths[victim]) > 0.0, "other person's pending death does not delay family selection", controller._pending_deaths): return
	if not _check(old_actor.loot_settled and not old_actor.remains_id.is_empty() and lab.terrain.site.ground_loot.has(old_actor.remains_id) and is_same(old_actor.item_state, corpse_holder) and old_actor.item_state.item_ids.is_empty(), "dead original actor owns settled cold state and original remains", old_actor.remains_id): return
	var remains_id := old_actor.remains_id
	var remains: Dictionary = lab.terrain.site.ground_loot[remains_id]
	if not _check(remains.item_ids == corpse_items and remains.cargo == {"grain": 3} and lab.terrain.site.manual.cargo.is_empty(), "dead person's real items and cargo settle before succession", {"items": remains.item_ids, "cargo": remains.get("cargo", {})}): return
	var modal: AcceptDialog = controller._family_dialog
	var list: ItemList = modal.find_child("FamilyMembers", true, false)
	var choose: Button = modal.find_child("ChooseFamilySuccessor", true, false)
	if not _check(list != null and choose != null and list.item_count == 3 and int(list.get_item_metadata(0).person_id) == heir_id and int(list.get_item_metadata(0).age_years) == 14, "original family controls reference the original minor NPC"): return
	var heir_holder: Dictionary = heir.item_state
	var heir_gear := heir.item_state.duplicate(true)
	var heir_cargo: Dictionary = lab.terrain.site.worker.cargo
	var heir_state := {"hp": heir.hp, "stun": heir.stun, "grace": heir.stun_grace, "ko": heir.knockout_left,
		"exch_cd": heir.exchange_cooldown, "ranged_cd": heir.ranged_cooldown, "skill_cd": heir.exchange_skill_cooldown,
		"fatigue": heir.fatigue, "fatigue_rest": heir.fatigue_rest, "training": heir.training, "position": heir.position / 64.0}
	var prior_states := {}
	for identity: int in person_ids_before: prior_states[identity] = site.soldier_state(int(site.crowd.soldier_index(identity)))
	var command_states := {}
	for entry: Dictionary in site.command_teams(): command_states[int(entry.team_id)] = site.formation_state(int(entry.formation))
	rosters_before = site.rosters.duplicate(true) # Snapshot after lawful death settlement, before control transfer.
	var steps_before: int = site._steps
	var clock_before: float = lab.terrain.site.combat_left
	list.select(0)
	choose.pressed.emit() # The production button calls family_continuity.choose and control_selected.
	if not _check(bool(result.get("ok", false)) and lab.controlled_person_id() == heir_id and not paused and not lab.terrain.site.paused, "original family button transfers control and resumes immediately", result): return
	if not _check(is_same(site.crowd, native_before) and is_same(lab.terrain, scene_before) and site.active and site._steps == steps_before and lab.terrain.site.combat_left == clock_before, "succession preserves the live world, clock and action step without rebuilding"): return
	if not _check(site.crowd.soldier_count() == person_ids_before.size() + 1 and site.crowd.formation_count() == native_formations_before + 1 and site.command_teams().size() == commands_before, "only new solo simulation person and formation are appended"): return
	for identity: int in person_ids_before:
		if not _check(site.soldier_state(int(site.crowd.soldier_index(identity))) == prior_states[identity], "existing hot soldier unchanged by append", identity): return
	for entry: Dictionary in site.command_teams():
		if not _check(site.formation_state(int(entry.formation)) == command_states[int(entry.team_id)], "ordinary command formation unchanged by succession", entry.team_id): return
	var index: int = site.crowd.soldier_index(heir_id)
	var owner: RefCounted = site.person_owner(heir_id)
	var hot: Dictionary = site.soldier_state(index)
	var formation: Dictionary = site.formation_state(owner.formation_index)
	var person: Dictionary = owner.person(index)
	if not _check(site.player_index == index and formation.host_center and formation.no_orders and not formation.ai_enabled and owner.faction_id == 2, "new-faction NPC is sole controlled solo formation without team orders", formation): return
	for field: String in ["hp", "stun", "grace", "ko", "exch_cd", "ranged_cd", "skill_cd"]:
		if not _check(float(hot[field]) == float(heir_state[field]), "NPC hot state preserved: " + field, {"before": heir_state[field], "after": hot[field]}): return
	for field: String in ["fatigue", "fatigue_rest", "training"]:
		if not _check(float(formation[field]) == float(heir_state[field]), "NPC shared state preserved: " + field): return
	if not _check(_native_position(heir_id) == heir_state.position and int(hot.tactics) == 37 and int(hot.leadership) == 48 and int(hot.coach) == 59, "NPC continuous position and original abilities imported"): return
	if not _check(is_same(site._actors[heir_id], heir) and is_same(person.holder, heir_holder) and is_same(person.cargo, heir_cargo) and heir.item_state == heir_gear and lab.terrain.site.family == family_before and site.rosters == rosters_before, "original NPC body, cold references, age and rosters unchanged"): return
	for roster: Dictionary in site.rosters:
		for row: Dictionary in roster.units:
			if not _check(int(row.person_id) != heir_id, "NPC is never placed in a roster", roster.team_id): return
	if not _check(site.crowd.validate(), "runtime append validates before its first step"): return
	var native_blob: PackedByteArray = site.crowd.save_state()
	var native_hash: int = site.crowd.state_hash()
	var copy: Variant = ClassDB.instantiate("ArmyCrowd")
	copy.setup(1, 9071)
	var copied_before_hash: int = copy.state_hash()
	var copied_loaded: bool = copy.load_state(native_blob)
	var copied_valid: bool = copy.validate()
	var copied_blob: PackedByteArray = copy.save_state()
	var copied_hash: int = copy.state_hash()
	var first_difference := -1
	for byte in range(mini(native_blob.size(), copied_blob.size())):
		if native_blob[byte] != copied_blob[byte]:
			first_difference = byte
			break
	if first_difference < 0 and native_blob.size() != copied_blob.size(): first_difference = mini(native_blob.size(), copied_blob.size())
	var source_blob_path := out_dir.path_join("immediate_append_native.bin")
	var copied_blob_path := out_dir.path_join("immediate_append_reloaded.bin")
	for evidence: Array in [[source_blob_path, native_blob], [copied_blob_path, copied_blob]]:
		var blob_file := FileAccess.open(str(evidence[0]), FileAccess.WRITE)
		if not _check(blob_file != null, "open native append blob evidence", evidence[0]): return
		blob_file.store_buffer(evidence[1])
		blob_file.close()
	var append_diagnostic := {"load_ok": copied_loaded, "copy_valid": copied_valid,
		"live_hash": str(native_hash), "copy_before_hash": str(copied_before_hash), "copy_after_hash": str(copied_hash),
		"source_bytes": native_blob.size(), "reloaded_bytes": copied_blob.size(), "first_byte_difference": first_difference,
		"source_blob": source_blob_path, "reloaded_blob": copied_blob_path,
		"source_sha256": FileAccess.get_sha256(source_blob_path), "reloaded_sha256": FileAccess.get_sha256(copied_blob_path)}
	if not _check(copied_loaded and copied_valid and copied_blob == native_blob and copied_hash == native_hash, "immediate append native save/load/hash is exact before first step", append_diagnostic): return
	var guard: Dictionary = controller.save_to(controller.save_path)
	if not _check(not guard.ok and guard.code == "BUSY" and controller._pending_deaths.has(victim) and not FileAccess.file_exists(controller.save_path), "full Site save honestly waits for the other pending remains", guard): return
	await _advance(90)
	if not _check(controller._pending_deaths.is_empty() and site._steps > steps_before and site.active and not paused and is_same(site.crowd, native_before), "same battle continues and remaining death settles naturally"): return
	# Use the original keyboard handler and common action clock for successor input.
	await process_frame # Finish disposing the family modal before keyboard dispatch.
	lab.movement_input_enabled = true
	var start_cell := Vector2i(_native_position(heir_id).floor())
	var direction := Vector2i.ZERO
	var key := KEY_NONE
	var keys := [KEY_D, KEY_A, KEY_S, KEY_W]
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	for candidate in range(directions.size()):
		var legal := true
		for distance in range(1, 4):
			if not lab.terrain.can_step(start_cell + directions[candidate] * (distance - 1), start_cell + directions[candidate] * distance): legal = false
		if legal:
			direction = directions[candidate]
			key = keys[candidate]
			break
	if not _check(direction != Vector2i.ZERO, "successor has a legal three-cell input path"): return
	var old_position := _native_position(old_id)
	var heir_position := _native_position(heir_id)
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	lab._unhandled_input(event)
	if not _check(lab._held_directions.has(key), "formal keyboard handler accepts successor movement"): return
	await _advance(30)
	event = InputEventKey.new()
	event.keycode = key
	event.pressed = false
	lab._unhandled_input(event)
	if not _check(_native_position(heir_id).distance_to(heir_position) > 0.1 and _native_position(old_id).distance_to(old_position) < 0.00001 and site.player_index == index and site.crowd.validate(), "input moves successor while old dead host stays still", {"from": heir_position, "to": _native_position(heir_id)}): return
	# Full Site saves retain the original out-of-combat rule; never reset the clock.
	for tick in range(900):
		if float(lab.terrain.site.combat_left) <= 0.0: break
		lab._advance_action_time(DT)
		action_seconds += DT
		if tick % 30 == 0: await process_frame
	if not _check(float(lab.terrain.site.combat_left) <= 0.0, "original combat grace expires naturally before full Site save", lab.terrain.site.combat_left): return
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _check(saved.ok, "full original Site save after natural settlement", saved): return
	var loaded: Dictionary = Store.load_site(controller.save_path)
	if not _check(loaded.ok, "saved Site passes original full validation", loaded.get("code", "OK")): return
	var saved_site: Dictionary = loaded.data.site
	if not _check(int(saved_site.controlled_person_id) == heir_id and int(saved_site.actors.npc.person_id) == heir_id and int(saved_site.actors.player.person_id) == old_id and float(saved_site.actors.player.hp) == 0.0 and bool(saved_site.actors.player.loot_settled) and str(saved_site.actors.player.remains_id) == remains_id, "saved original actor slots retain successor and dead actor cold settlement", saved_site.actors.player.remains_id): return
	if not _check(saved_site.ground_loot[remains_id] == lab.terrain.site.ground_loot[remains_id] and saved_site.actors.npc.item_state == heir_gear and saved_site.worker.cargo == heir_cargo and saved_site.family == family_before, "full Site roundtrip preserves corpse belongings, NPC items, cargo and age"): return
	if not _check(copy.load_state(Marshalls.base64_to_raw(saved_site.crowd.blob)) and copy.state_hash() == site.crowd.state_hash() and copy.validate(), "full Site native section retains live hash after continuation"): return
	var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(controller.save_path), ProjectSettings.globalize_path(out_dir.path_join("d6_site.json")))
	if not _check(copied == OK, "copy isolated passing save into named evidence", error_string(copied)): return
	if not await _continue_to_member(first_member_id, "npc_to_member" ): return
	if not await _continue_to_member(second_member_id, "member_to_member" ): return
	for saved_phase: String in ["d6", "npc_to_member", "member_to_member"]:
		if not await _reload_settled_remains(saved_phase): return
	_write_result()
	controller._equipment_dialog = null
	capture_dialog.free()
	lab.queue_free()
	await process_frame
	print("GATE OK: D6 family modal, outside NPC append and two existing roster successions ", checks.size())
	quit(0)
func _continue_to_member(next_id: int, phase: String) -> bool:
	# Repeat the real modal path for existing original roster bodies, without rebuilding a fixture.
	var old_id := lab.controlled_person_id()
	var old_person: Dictionary = controller.person_actions._person(old_id)
	var old_body: Variant = old_person.body
	var old_holder: Dictionary = old_person.holder
	var old_items: Array = old_holder.item_ids.duplicate()
	var old_cargo: Dictionary = old_person.cargo.duplicate(true)
	var native: Variant = site.crowd
	var data := lab.terrain
	var ids: PackedInt64Array = site.crowd.person_ids()
	var soldiers: int = site.crowd.soldier_count()
	var formations: int = site.crowd.formation_count()
	var roster_ref: Dictionary = site._records[next_id]
	var holder_ref: Dictionary = roster_ref.item_state
	var cargo_ref: Dictionary = roster_ref.cargo
	var next_hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(next_id)))
	if not _check(float(next_hot.hp) > 41.0 and site.apply_environment_damage(next_id, float(next_hot.hp) - 41.0) == 41.0, phase + " original living roster member receives real wound to 41 HP"): return false
	Runtime.mark_combat(lab.terrain, 12.0)
	if not _check(site.apply_environment_damage(old_id, 10000.0) == 0.0 and controller._pending_deaths.has(old_id), phase + " old controlled person dies through original native event"): return false
	for tick in range(120):
		lab._advance_action_time(DT)
		action_seconds += DT
		if paused: break
		if tick % 30 == 0: await process_frame
	if not _check(paused and is_instance_valid(controller._family_dialog) and not controller._pending_deaths.has(old_id) and bool(old_body.get("loot_settled")), phase + " original death settlement opens original family modal"): return false
	var remains_id := str(old_body.get("remains_id"))
	if not _check(not remains_id.is_empty() and lab.terrain.site.ground_loot.has(remains_id) and old_holder.item_ids.is_empty() and old_person.cargo.is_empty(), phase + " old original body owns actual settled remains", remains_id): return false
	var remains: Dictionary = lab.terrain.site.ground_loot[remains_id]
	if not _check(remains.item_ids == old_items and remains.cargo == old_cargo, phase + " original items and cargo exactly reach the corpse container"): return false
	var modal: AcceptDialog = controller._family_dialog
	var list: ItemList = modal.find_child("FamilyMembers", true, false)
	var button: Button = modal.find_child("ChooseFamilySuccessor", true, false)
	if not _check(list != null and button != null, phase + " original family UI is present"): return false
	var selected := -1
	for item in range(list.item_count):
		var member: Dictionary = list.get_item_metadata(item)
		if int(member.person_id) == next_id and str(member.site_id) == str(lab.terrain.site.id) and bool(member.selectable): selected = item
	if not _check(selected >= 0, phase + " family lists the explicit existing living roster member", next_id): return false
	var command_states := {}
	for entry: Dictionary in site.command_teams(): command_states[int(entry.team_id)] = site.formation_state(int(entry.formation))
	var roster_before: Array = site.rosters.duplicate(true)
	var steps_before: int = site._steps
	var clock_before: float = lab.terrain.site.combat_left
	list.select(selected)
	result.clear()
	button.pressed.emit()
	if not _check(bool(result.get("ok", false)) and lab.controlled_person_id() == next_id and not paused and not lab.terrain.site.paused, phase + " family button changes control to original roster member", result): return false
	if not _check(is_same(site.crowd, native) and is_same(lab.terrain, data) and site.active and site._steps == steps_before and lab.terrain.site.combat_left == clock_before and site.crowd.person_ids() == ids and site.crowd.soldier_count() == soldiers and site.crowd.formation_count() == formations, phase + " existing member succession does not append, rebuild, step or reset clocks"): return false
	var owner: RefCounted = site.person_owner(next_id)
	var index: int = site.crowd.soldier_index(next_id)
	var state: Dictionary = site.soldier_state(index)
	if not _check(site.player_index == index and float(state.hp) == 41.0 and not site.formation_state(owner.formation_index).host_center and not site.formation_state(owner.formation_index).no_orders and site.crowd.validate(), phase + " wounded member receives individual host control in original ordinary formation"): return false
	for entry: Dictionary in site.command_teams():
		if not _check(site.formation_state(int(entry.formation)) == command_states[int(entry.team_id)], phase + " all original command and AI state preserved", entry.team_id): return false
	if not _check(site.rosters == roster_before and is_same(site._records[next_id], roster_ref) and is_same(roster_ref.item_state, holder_ref) and is_same(roster_ref.cargo, cargo_ref), phase + " original row, holder, cargo and all roster values survive control transfer"): return false
	await process_frame
	lab.movement_input_enabled = true
	var position := _native_position(next_id)
	var old_position := _native_position(old_id)
	var start := Vector2i(position.floor())
	var keys := [KEY_D, KEY_A, KEY_S, KEY_W]
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	var key := KEY_NONE
	for candidate in range(directions.size()):
		var direction := directions[candidate]
		var legal := true
		for distance in range(1, 4):
			if not lab.terrain.can_step(start + direction * (distance - 1), start + direction * distance): legal = false
		for identity: int in ids:
			if identity == next_id: continue
			var other: Dictionary = site.soldier_state(int(site.crowd.soldier_index(identity)))
			if float(other.hp) <= 0.0: continue
			var offset := Vector2(float(other.px), float(other.py)) - position
			if offset.dot(Vector2(direction)) > 0.0 and offset.dot(Vector2(direction)) < 3.5 and absf(offset.cross(Vector2(direction))) < 0.8: legal = false
		if legal:
			key = keys[candidate]
			break
	if not _check(key != KEY_NONE, phase + " original member has a clear keyboard path"): return false
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	lab._unhandled_input(event)
	if not _check(lab._held_directions.has(key), phase + " original keyboard handler addresses current member"): return false
	await _advance(30)
	event = InputEventKey.new()
	event.keycode = key
	event.pressed = false
	lab._unhandled_input(event)
	if not _check(_native_position(next_id).distance_to(position) > 0.1 and _native_position(old_id).distance_to(old_position) < 0.00001 and not site.formation_state(owner.formation_index).host_center and site._steps > steps_before and site.crowd.validate(), phase + " keyboard moves only living successor without solo-centering the original formation", {"before": position, "after": _native_position(next_id)}): return false
	for tick in range(900):
		if float(lab.terrain.site.combat_left) <= 0.0 and controller._pending_deaths.is_empty(): break
		lab._advance_action_time(DT)
		action_seconds += DT
		if tick % 30 == 0: await process_frame
	if not _check(float(lab.terrain.site.combat_left) <= 0.0 and controller._pending_deaths.is_empty(), phase + " common clock naturally clears combat grace and death work"): return false
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _check(saved.ok, phase + " full original Site save", saved): return false
	var loaded: Dictionary = Store.load_site(controller.save_path)
	if not _check(loaded.ok, phase + " full Site reload validates", loaded.get("code", "OK")): return false
	var saved_site: Dictionary = loaded.data.site
	var living_rows: Array[Dictionary] = []
	var dead_rows: Array[Dictionary] = []
	for roster: Dictionary in saved_site.armies:
		for row: Dictionary in roster.units:
			if int(row.person_id) == next_id: living_rows.append(row)
			if int(row.person_id) == old_id: dead_rows.append(row)
	if not _check(int(saved_site.controlled_person_id) == next_id and int(saved_site.crowd.player.person_id) == next_id and living_rows.size() == 1 and float(living_rows[0].hp) == 41.0, phase + " wounded controlled person is stored exactly once in original armies units schema"): return false
	if not _check(int(saved_site.actors.player.person_id) == lab.character.person_id and float(saved_site.actors.player.hp) == 0.0 and bool(saved_site.actors.player.loot_settled) and int(saved_site.actors.npc.person_id) == lab.npc.person_id and float(saved_site.actors.npc.hp) == 0.0 and bool(saved_site.actors.npc.loot_settled) and not str(saved_site.actors.npc.remains_id).is_empty() and saved_site.ground_loot.has(str(saved_site.actors.npc.remains_id)), phase + " both original actor schema slots retain their settled dead bodies"): return false
	if old_id == lab.npc.person_id:
		if not _check(dead_rows.is_empty() and str(saved_site.actors.npc.remains_id) == remains_id, phase + " dead NPC remains only in original actors npc slot"): return false
	else:
		if not _check(dead_rows.size() == 1 and float(dead_rows[0].hp) == 0.0 and bool(dead_rows[0].loot_settled) and str(dead_rows[0].remains_id) == remains_id, phase + " dead controlled roster person stays settled in its original units row"): return false
	if not _check(saved_site.ground_loot[remains_id] == remains and saved_site.family == lab.terrain.site.family and living_rows[0].item_state == holder_ref and living_rows[0].cargo == cargo_ref, phase + " saved original remains, family, member equipment and cargo survive roundtrip"): return false
	var reloaded: Variant = ClassDB.instantiate("ArmyCrowd")
	reloaded.setup(1, 9072)
	if not _check(reloaded.load_state(Marshalls.base64_to_raw(saved_site.crowd.blob)) and reloaded.validate() and reloaded.state_hash() == site.crowd.state_hash(), phase + " saved native world hash continues unchanged"): return false
	var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(controller.save_path), ProjectSettings.globalize_path(out_dir.path_join(phase + "_site.json")))
	if not _check(copied == OK, phase + " original isolated save copied to named evidence", error_string(copied)): return false
	return true

func _reload_settled_remains(phase: String) -> bool:
	var source := out_dir.path_join(phase + "_site.json")
	var destination := controller.save_root.path_join("reload_" + phase + ".json")
	var source_sha := FileAccess.get_sha256(source)
	if not _check(controller._save_path_guard(destination).ok and DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination)) == OK, phase + " settled save copied into isolated live reload path"): return false
	var loaded: Dictionary = controller.load_from(destination)
	if not _check(loaded.ok and lab.crowd_site != null and lab.crowd_site.active, phase + " settled save rebound through original load_from and live scene", loaded): return false
	site = lab.crowd_site
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	var remains: Dictionary = lab.terrain.site.ground_loot.duplicate(true)
	var item_count: int = lab.terrain.site.item_records.size()
	var next_loot: int = lab.terrain.site.next_loot
	var dead_ids: Array[int] = []
	for owner in site.person_owners():
		for index: int in owner.combat_units:
			if float(owner.combat_hot_get(index, &"hp")) > 0.0: continue
			var identity: int = owner.combat_identity(index)
			var remains_id := str(owner.combat_hot_get(index, &"remains_id", ""))
			if not _check(bool(owner.combat_hot_get(index, &"loot_settled", false)) and not remains_id.is_empty() and remains.has(remains_id), phase + " rebound original corpse retains settled remains", identity): return false
			dead_ids.append(identity)
	# Live action path invokes settle_person_deaths again for longer than down pose.
	await _advance(150)
	controller.settle_person_deaths(DT)
	if not _check(not paused and not dead_ids.is_empty() and controller._pending_deaths.is_empty() and lab.terrain.site.ground_loot == remains and int(lab.terrain.site.next_loot) == next_loot and lab.terrain.site.item_records.size() == item_count,
		phase + " live post-load settlement creates no second corpse or items", {"dead_ids": dead_ids, "containers": remains.size(), "next_loot": next_loot, "items": item_count}): return false
	return _check(FileAccess.get_sha256(source) == source_sha, phase + " immutable corpse evidence remains unchanged")
