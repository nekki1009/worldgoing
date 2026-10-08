extends SceneTree
## D10: an original outside NPC joins through the real family button and receives enemy melee damage.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const DT := 1.0 / 30.0
var lab: TerrainLab
var controller: SiteController
var site: Node
var out_dir := ""
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var failed := false
var result: Dictionary = {}
var capture_dialog: AcceptDialog
var action_seconds := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "details": details})
	print("D10 ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		failed = true
		_write_result()
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _write_result() -> void:
	if out_dir.is_empty(): return
	var file := FileAccess.open(out_dir.path_join("d10_enemy.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not failed, "checks": checks, "samples": samples,
			"action_seconds": action_seconds,
			"coverage": "Original FamilyDialog appends the original outside NPC with a new faction; original enemy ATTACK closes distance, selects that NPC, resolves a melee pair and reduces NPC HP while host engage is false",
			"not_covered": ["GPU modal appearance", "clear after succession", "large battle performance"]}, "\t", true, true))
		file.close()

func _capture_result(value: Dictionary) -> void:
	result = value.duplicate(true)

func _position(index: int) -> Vector2:
	var state: Dictionary = site.soldier_state(index)
	return Vector2(float(state.px), float(state.py))

func _sample(tick: int, enemy: int, heir: int) -> void:
	var stats: PackedFloat64Array = site.crowd.stats()
	var enemy_view: PackedFloat32Array = site.crowd.soldier_view(enemy)
	var heir_hot: Dictionary = site.soldier_state(heir)
	samples.append({"tick": tick, "action_seconds": action_seconds, "enemy_position": _position(enemy),
		"heir_position": _position(heir), "enemy_target": int(enemy_view[12]), "heir_hp": heir_hot.hp,
		"heir_stun": heir_hot.stun, "heir_ko": heir_hot.ko, "pairs": int(stats[10]),
		"shots": int(stats[11]), "host_engage": site.engage, "combat_left": stats[33]})

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var base := "res://output/crowd_c2_c3_20261001"
	var at := args.find("--crowd-output")
	if at >= 0 and at + 1 < args.size(): base = args[at + 1]
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out_dir = base.path_join("d10_enemy_%s_%d" % [stamp, Time.get_ticks_msec()])
	if not _check(base.begins_with("res://output/") and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(out_dir)), "new named evidence folder", out_dir): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ignore := FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(180.0).timeout.connect(func() -> void:
		failed = true
		_write_result()
		printerr("GATE FAIL: D10 script deadline 180 seconds")
		quit(3))
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
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
	var heir_id := heir.person_id
	heir.faction_id = 2
	heir.training = 0.0
	heir.hp = 100.0
	heir.combat_driven_by_lab = false
	heir.issue_command(TerrainTestNPC.Command.STOP)
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 1, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 1, "training": 100.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	if not _check(deployed.ok and site.active and not site.contains_person(heir_id), "original NPC remains outside the deployed native battle", deployed): return
	var command_teams: Array = site.command_teams()
	var enemy_team: Dictionary = site._team_by_id(int(command_teams[1].team_id))
	var enemy_id: int = enemy_team.person_ids[0]
	var enemy: int = site.crowd.soldier_index(enemy_id)
	var friend_id: int = site._team_by_id(int(command_teams[0].team_id)).person_ids[0]
	var friend: int = site.crowd.soldier_index(friend_id)
	var enemy_cell := Vector2i(_position(enemy).floor())
	var heir_cell := Vector2i(-1, -1)
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
		var legal := true
		for distance in range(1, 4):
			if not lab.terrain.can_step(enemy_cell + direction * (distance - 1), enemy_cell + direction * distance): legal = false
		var candidate := enemy_cell + direction * 3
		if legal and heir.can_enter_cell(candidate) and _position(friend).distance_to(Vector2(candidate) + Vector2.ONE * 0.5) > 10.0:
			heir_cell = candidate
			break
	if not _check(heir_cell != Vector2i(-1, -1) and heir.place(heir_cell, true), "author outside NPC on a legal three-cell route before succession", {"enemy_cell": enemy_cell, "heir_cell": heir_cell}): return
	var positioned := heir.position / TerrainRenderer.CELL_PIXELS
	var holder: Dictionary = heir.item_state
	var equipment: Dictionary = heir.item_state.duplicate(true)
	var native: Variant = site.crowd
	var soldiers: int = site.crowd.soldier_count()
	var formations: int = site.crowd.formation_count()
	var registered: Dictionary = controller.family_continuity.register_members([
		{"site_id": str(lab.terrain.site.id), "person_id": heir_id, "path": "", "label": "Explicit original outside NPC", "age_years": 24}], true)
	if not _check(registered.ok, "register original outside NPC as the sole family successor", registered): return
	Runtime.mark_combat(lab.terrain, 12.0)
	# Environment damage is used only to enter the existing family flow, never as enemy-contact evidence.
	if not _check(site.apply_environment_damage(old_actor.person_id, 10000.0) == 0.0, "old controlled actor dies to trigger original succession"): return
	for tick in range(120):
		lab._advance_action_time(DT)
		action_seconds += DT
		if paused: break
		if tick % 30 == 0: await process_frame
	if not _check(paused and is_instance_valid(controller._family_dialog) and old_actor.loot_settled, "original death settlement opens original FamilyDialog"): return
	var modal: AcceptDialog = controller._family_dialog
	var list: ItemList = modal.find_child("FamilyMembers", true, false)
	var choose: Button = modal.find_child("ChooseFamilySuccessor", true, false)
	if not _check(list != null and choose != null and list.item_count == 1 and int(list.get_item_metadata(0).person_id) == heir_id, "original family button selects the existing NPC"): return
	var rosters: Array = site.rosters.duplicate(true)
	var step_before: int = site._steps
	list.select(0)
	choose.pressed.emit()
	if not _check(bool(result.get("ok", false)) and lab.controlled_person_id() == heir_id and not paused and site.active, "original family button appends NPC and resumes the live battle", result): return
	var heir_index: int = site.crowd.soldier_index(heir_id)
	var owner: RefCounted = site.person_owner(heir_id)
	var state: Dictionary = site.formation_state(owner.formation_index)
	if not _check(is_same(site.crowd, native) and site._steps == step_before and site.crowd.soldier_count() == soldiers + 1 and site.crowd.formation_count() == formations + 1 and site.command_teams().size() == 2, "append changes only the new solo simulation person and formation"): return
	if not _check(owner.faction_id == 2 and state.no_orders and state.host_center and not state.ai_enabled and _position(heir_index) == positioned and site.player_index == heir_index, "new faction retains authored position and solo individual control", state): return
	if not _check(is_same(site._actors[heir_id], heir) and is_same(heir.item_state, holder) and heir.item_state == equipment and site.rosters == rosters and site.crowd.validate(), "original NPC body, items and original rosters are preserved"): return
	for roster: Dictionary in site.rosters:
		for row: Dictionary in roster.units:
			if not _check(int(row.person_id) != heir_id, "successor remains outside every roster", roster.team_id): return
	if not _check(int(site.crowd.nearest_enemy(enemy, 20.0)) == heir_index, "existing enemy spatial query recognizes the newly added hostile faction"): return
	site.wish = Vector2.ZERO
	site.engage = false
	var ordered: Dictionary = site.issue_order(int(enemy_team.team_id), TerrainArmy.CombatOrder.ATTACK, Vector2i(-1, -1), heir_id, "test")
	if not _check(ordered.ok, "existing enemy receives ordinary ATTACK against the original NPC", ordered): return
	var before: PackedFloat64Array = site.crowd.stats()
	var hp_before: float = site.soldier_state(heir_index).hp
	var enemy_start := _position(enemy)
	var targeted := false
	var host_passive := true
	var min_distance := enemy_start.distance_to(_position(heir_index))
	_sample(0, enemy, heir_index)
	for tick in range(900):
		lab._advance_action_time(DT)
		action_seconds += DT
		var view: PackedFloat32Array = site.crowd.soldier_view(enemy)
		targeted = targeted or int(view[12]) == heir_index
		host_passive = host_passive and not site.engage
		min_distance = minf(min_distance, _position(enemy).distance_to(_position(heir_index)))
		if tick % 10 == 0: _sample(tick + 1, enemy, heir_index)
		if float(site.soldier_state(heir_index).hp) < hp_before: break
		if tick % 30 == 0: await process_frame
	var after: PackedFloat64Array = site.crowd.stats()
	var final_hot: Dictionary = site.soldier_state(heir_index)
	_sample(int(after[36] - before[36]), enemy, heir_index)
	if not _check(targeted and enemy_start.distance_to(_position(enemy)) > 0.5 and min_distance < 1.5, "ordinary enemy moves into contact and selects the appended NPC", {"targeted": targeted, "start": enemy_start, "end": _position(enemy), "min_distance": min_distance}): return
	if not _check(host_passive and int(after[10]) > int(before[10]) and int(after[11]) == int(before[11]) and float(final_hot.hp) < hp_before, "enemy melee exchange naturally damages the passive appended NPC", {"hp_before": hp_before, "hp_after": final_hot.hp, "stun_after": final_hot.stun, "pairs_before": before[10], "pairs_after": after[10], "shots_before": before[11], "shots_after": after[11], "host_passive": host_passive}): return
	if not _check(site.crowd.validate() and is_same(site.crowd, native) and is_same(site._actors[heir_id], heir) and is_same(heir.item_state, holder) and site.command_teams().size() == 2, "same world and original NPC ownership remain valid after enemy contact"): return
	_write_result()
	controller._equipment_dialog = null
	capture_dialog.free()
	lab.queue_free()
	await process_frame
	print("GATE OK: D10 original outside successor receives real enemy melee damage ", checks.size())
	quit(0)
