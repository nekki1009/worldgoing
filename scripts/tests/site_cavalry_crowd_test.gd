extends SceneTree
## CAV-2: native mounted cavalry wired into the crowd battle. One case per run; pick it with --cavalry-case:
##   turn      a sharp turn at gallop drops the charge (soldier_charge) and makes no contact
##   palisade  a charge toward a blocked column (the palisade stand-in: static_blocked, synced by sync_terrain) brakes in front
##   dismount  a native dismount is written back to the GD row and the rider list
##   saveload  a rider mid-charge: capture_for_save is valid and the native state reloads still mounted
##   unmounted a team with no riders: no charge stats, no native mounted flag, no rider list
## The charge-contact, through-3 and pike scenarios are verified by native scenario_tests (charge, penetration cap, pike).
## Their GD versions return with CAV-3 / CAV-4, when ordinary soldiers can ride and teams can be ordered into a line.
## Run: -- --crowd --crowd-test <fresh run_id> --cavalry-case <case> [--crowd-atlas-root res://output/site_siege_close_20261004/equipment_atlas_runtime]
## Fails fast on the first failed check. Not run in this change: Godot was not executed for this patch.
const DT := 1.0 / 30.0
var lab: TerrainLab
var controller: SiteController
var site: Node
var case_name := "turn"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("CAV2 ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

# One real frame of the live game step, as in site_g8a_crowd_test.gd.
func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("CAV2 latched frame fault: ", controller._original_step_fault)
			return false
	return true

func _deploy_two_teams(friend_count: int, enemy_count: int) -> Dictionary:
	return lab.deploy_trial_armies([
		{"faction": 0, "count": friend_count, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": enemy_count, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "east"}])

# Host-controls one rider index and drives it through the real key path. The controlled Actor's input is rewritten
# every frame by TerrainLab._advance_movement_input from the held keys, so a direct set_input is overwritten at once.
func _drive(rider_index: int, direction: Vector2, run: bool) -> void:
	site.player_index = rider_index
	site.crowd.set_host_control(rider_index, true)
	lab._held_directions.clear()
	if direction != Vector2.ZERO: lab._held_directions[1] = Vector2i(roundi(direction.x), roundi(direction.y))
	lab._run_held = run
	site.set_input(direction, run)

# Releases the held keys (the lab's own path then sends a zero wish).
func _release_drive() -> void:
	lab._held_directions.clear()
	lab._run_held = false
	site.set_input(Vector2.ZERO, false)

# Diagnostics: native position, velocity and mount of the rider.
func _rider_state(rider_index: int) -> Dictionary:
	var state: Dictionary = site.soldier_state(rider_index)
	return {"px": state.get("px"), "py": state.get("py"), "vx": state.get("vx"), "vy": state.get("vy"),
		"hp": state.get("hp"), "mounted": site.crowd.soldier_mounted(rider_index), "player_index": site.player_index,
		"actor_soldier_index": int(site.crowd.soldier_index(lab.character.person_id)), "rider_index": rider_index,
		"wish": site.wish, "wish_run": site.running, "held": lab._held_directions.size()}

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	var pick := args.find("--cavalry-case")
	if pick >= 0 and pick + 1 < args.size(): case_name = str(args[pick + 1])
	if not check(case_name in ["turn", "palisade", "dismount", "saveload", "unmounted"], "a known cavalry case is selected", case_name): return
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
	# Mounted riders are original Actors: only they have prepared riding contact visuals (_prepare_contact_appearance).
	# The controlled Actor is mounted before deploy, the way site_siege_native_mounted_contact_test.gd does it.
	var actor: TerrainTestCharacter = lab.character
	if case_name != "unmounted":
		var initial: Dictionary = actor.capture_state()
		initial.appearance = HumanCharacter3DEditor.default_appearance(0)
		initial.appearance.mounted = true
		initial.pose = "ride_idle"
		initial.pose_time = 0.0
		actor.restore_state(initial)
	var deployed: Dictionary = _deploy_two_teams(4, 6)
	if not check(deployed.ok and site.active and site.command_teams().size() == 2, "a crowd battle deploys two opposing teams", deployed): return
	var teams: Array = site.command_teams()
	var friend_team: Dictionary = site._team_by_id(int(teams[0].team_id))

	if case_name == "unmounted":
		_unmounted_case(friend_team)
		return
	# The deploy import set the native flag from the Actor's mounted appearance (import_mounted_riders).
	var rider_id := actor.person_id
	if not check(site.rider_identities().has(rider_id), "the deploy import lists the mounted Actor as a rider"): return
	var rider_index := int(site._index_by_id[rider_id])
	if not check(site.crowd.soldier_mounted(rider_index), "the native rider flag is set by the deploy import"): return

	match case_name:
		"dismount":
			_dismount_case(rider_id, rider_index)
		"saveload":
			_saveload_case(rider_id, rider_index)
		"turn":
			_turn_case(rider_index)
		"palisade":
			_palisade_case(rider_index)

# turn: charging east, then a sharp turn south at gallop. The charge must drop while the heading turns and no contact follows.
func _turn_case(rider_index: int) -> void:
	_drive(rider_index, Vector2.RIGHT, true)
	for step in range(60):
		if not check(_tick(1), "live frame before the turn has no latched fault"): return
	var charge: PackedFloat64Array = site.crowd.soldier_charge(rider_index)
	if not check(charge[0] == 1.0 and charge[1] >= 0.4, "charging straight east before the turn", [charge, _rider_state(rider_index)]): return
	var contacts0: float = float(site.crowd.cav_stats()[0])
	_drive(rider_index, Vector2(0.0, 1.0), true)
	var charged_while_turning := false
	for step in range(60):
		if not check(_tick(1), "live frame during the turn has no latched fault"): return
		charge = site.crowd.soldier_charge(rider_index)
		if step >= 10 and step < 30 and charge[0] == 1.0: charged_while_turning = true
	if not check(not charged_while_turning, "the charge is lost while the heading turns"): return
	var stats: PackedFloat64Array = site.crowd.cav_stats()
	if not check(stats[0] == contacts0 and stats[1] == 0.0, "a turned rider makes no contact and no penetration", stats): return
	print("CAV2 GATE OK: turn")
	quit(0)

# palisade: a blocked column ahead of the rider (static_blocked, the palisade stand-in) must stop the charge in front of it.
func _palisade_case(rider_index: int) -> void:
	var data: TerrainData = lab.terrain
	var start: Dictionary = site.soldier_state(rider_index)
	var wall_x := int(floor(float(start.px))) + 5
	if not check(wall_x < data.size.x - 1, "the wall column fits on the map", wall_x): return
	if data.static_blocked.is_empty():
		var blocked := PackedByteArray()
		blocked.resize(data.size.x * data.size.y)
		blocked.fill(0)
		data.static_blocked = blocked
	for y in range(data.size.y): data.static_blocked[data.index(Vector2i(wall_x, y))] = 1
	data.navigation_revision += 1
	if not check(site.sync_terrain(), "the blocked column syncs to native terrain"): return
	_drive(rider_index, Vector2.RIGHT, true)
	var furthest := 0.0
	for step in range(150):
		if not check(_tick(1), "live frame has no latched fault"): return
		furthest = maxf(furthest, float(site.soldier_state(rider_index).px))
	var state: Dictionary = site.soldier_state(rider_index)
	_release_drive()
	if not check(furthest < float(wall_x), "the rider never crosses the palisade column (furthest %.3f, wall %d)" % [furthest, wall_x]): return
	if not check(Vector2(float(state.vx), float(state.vy)).length() < 4.5, "the rider brakes in front of the palisade", state): return
	print("CAV2 GATE OK: palisade")
	quit(0)

func _dismount_case(rider_id: int, rider_index: int) -> void:
	# The native dismount of a lost charge is simulated by clearing the native flag; the write-back is what is under test.
	if not check(bool(site.crowd.set_soldier_mounted(rider_index, false)), "the native dismount is applied"): return
	if not check(_tick(1), "the frame after the dismount has no latched fault"): return
	if not check(not site.rider_identities().has(rider_id), "the rider list drops the dismounted person"): return
	if not check(not site._is_rider_row(rider_id), "the GD row (the Actor's saved appearance) is written back as dismounted"): return
	print("CAV2 GATE OK: dismount")
	quit(0)

func _saveload_case(rider_id: int, rider_index: int) -> void:
	_drive(rider_index, Vector2.RIGHT, true)
	for step in range(60):
		if not check(_tick(1), "live frame before the save has no latched fault"): return
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid mid-charge", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	site.crowd.render_set_kits(site._kit_ids)
	site._rebuild_rider_ids()
	if not check(site.crowd.soldier_mounted(rider_index), "the reloaded native rider stays mounted"): return
	if not check(site.rider_identities().has(rider_id) and site._is_rider_row(rider_id), "the reloaded GD rider list and row keep the rider"): return
	if not check(_tick(1), "the frame after the reload has no latched fault"): return
	print("CAV2 GATE OK: saveload")
	quit(0)

func _unmounted_case(friend_team: Dictionary) -> void:
	for index in range(int(site.crowd.soldier_count())):
		if not check(not site.crowd.soldier_mounted(index), "no native soldier starts mounted", index): return
	if not check(site.rider_identities().is_empty(), "no rider is listed for a team with no riders"): return
	_drive(int(site._index_by_id[int(friend_team.person_ids[1])]), Vector2.RIGHT, true)
	for step in range(300):
		if not check(_tick(1), "live frame has no latched fault"): return
	var stats: PackedFloat64Array = site.crowd.cav_stats()
	if not check(stats[0] == 0.0 and stats[1] == 0.0 and stats[2] == 0.0 and stats[4] == 0.0, "an unmounted team records no charge outcomes", stats): return
	if not check(site.rider_identities().is_empty(), "the unmounted team stays unlisted"): return
	print("CAV2 GATE OK: unmounted")
	quit(0)
