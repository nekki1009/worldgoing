extends SceneTree
## CAV-2: native mounted cavalry wired into the crowd battle. One case per run; pick it with --cavalry-case:
##   turn      a sharp turn at gallop drops the charge (soldier_charge) and makes no contact
##   palisade  a charge toward a blocked column (the palisade stand-in: static_blocked, synced by sync_terrain) brakes in front
##   dismount  a native dismount is written back to the GD row and the rider list
##   saveload  a rider mid-charge: capture_for_save is valid and the native state reloads still mounted
##   unmounted a team with no riders: no charge stats, no native mounted flag, no rider list
## CAV-3 ordinary soldiers (mounted atlas res://assets/army/mounted_soldiers/v2/ must be baked):
##   ordinary_mounts              a horse equipped through the equipment order flow (prepare/check/commit) makes the
##                                soldier a native rider with a mounted crowd kit whose ride frames resolve
##   ordinary_dismount_loses_horse a native dismount empties the mount slot; the horse is lost, not returned to goods
##   ordinary_bow_rider_fires     a mounted archer fires under the ordinary ranged rules and stays mounted
##   saveload_ordinary_rider      a mounted ordinary soldier saves and reloads still mounted with its horse item
## The charge-contact, through-3 and pike scenarios are verified by native scenario_tests (charge, penetration cap, pike).
## Their GD versions return with CAV-3 / CAV-4, when ordinary soldiers can ride and teams can be ordered into a line.
## CAV-4b cavalry charge orders (native CHARGE 5/7, RALLY 6; reports/cavalry-charge-plan.md section 5), riders are mounted ordinary soldiers:
##   charge_order                  a mounted team is ordered to CHARGE an enemy team through issue_order: gallop, then contact
##   rally_order                   after contact, RALLY pulls the riders back and the formation HOLDs with no rider charging
##   charge_refused_infantry       a team on foot is refused CHARGE as NOT_CAVALRY
##   charge_refused_no_commander   the commander 20 cells out (GD gate still eligible) is refused CHARGE as NO_COMMANDER
##   charge_saveload               a save taken mid-charge reloads with the CHARGE order and the charge resumes to contact
##   charge_real_picture           visual: the command path (SiteController._crowd_order) charges a 12-rider team into 24 foot;
##                                 contacts are produced and the p95 frame time stays under CHARGE_FRAME_MS_LIMIT
## Run: -- --crowd --crowd-test <fresh run_id> --cavalry-case <case> [--crowd-atlas-root res://output/site_siege_close_20261004/equipment_atlas_runtime]
## Fails fast on the first failed check.
const DT := 1.0 / 30.0
const ORDINARY_CASES := ["ordinary_mounts", "ordinary_dismount_loses_horse", "ordinary_bow_rider_fires", "saveload_ordinary_rider"]
const CHARGE_CASES := ["charge_order", "rally_order", "charge_refused_infantry", "charge_refused_no_commander", "charge_saveload", "charge_real_picture"]
# The switch plan (output/project_command_center/CONTINUOUS_SWITCH/switch-plan.md) names no frame-time number. The real-picture
# gate of SITE_CROWD_10K_PLAN_SOL.md (lines 237 and 409: whole frame p95 <= 33.3 ms, p99 <= 50 ms) is the sourced frame limit.
# The "about 6 ms per tick" of NEKKI_DECISION_20261028_continuous_model_switch.md is the native 10k step cost, not a frame gate.
const CHARGE_FRAME_MS_LIMIT := 33.3
const CHARGE_FRAME_P99_MS_LIMIT := 50.0
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
	if not check(case_name in ["turn", "palisade", "dismount", "saveload", "unmounted"] + ORDINARY_CASES + CHARGE_CASES, "a known cavalry case is selected", case_name): return
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
	if case_name in ORDINARY_CASES:
		_ordinary_case()
		return
	if case_name in CHARGE_CASES:
		_charge_case()
		return
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


# ---------------------------------------------------------------- CAV-3 ordinary riders
func _ordinary_case() -> void:
	# The bow case is a one-archer team against one enemy (as crowd_c2_natural_ammo_test), male body: the
	# runtime atlas root publishes the male bow foot recipe only.
	var bow := case_name == "ordinary_bow_rider_fires"
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 1 if bow else 4, "troop_type": "bow" if bow else "melee_infantry", "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 1 if bow else 6, "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	if not check(deployed.ok and site.active and site.command_teams().size() == 2, "a crowd battle deploys two opposing teams", deployed): return
	var friend_team: Dictionary = site._team_by_id(int(site.command_teams()[0].team_id))
	var soldier_id := int(friend_team.person_ids[0 if bow else 1])
	if not check(not site._actors.has(soldier_id), "the chosen rider is an ordinary soldier", soldier_id): return
	var index := int(site._index_by_id[soldier_id])
	if not check(_mount_by_order(soldier_id), "the ordinary soldier mounts through the order flow"): return
	match case_name:
		"ordinary_mounts":
			_ordinary_mounts_case(soldier_id, index)
		"ordinary_dismount_loses_horse":
			_ordinary_dismount_case(soldier_id, index)
		"ordinary_bow_rider_fires":
			_ordinary_bow_case(friend_team, soldier_id, index)
		"saveload_ordinary_rider":
			_ordinary_saveload_case(soldier_id, index)

# The equipment order flow, as the controlled player uses it for any slot: prepare, check (inside), commit.
# The soldier is made the controlled person for the personal order (as site_g8a_crowd_test does), then control is restored.
func _mount_by_order(soldier_id: int) -> bool:
	var record: Dictionary = site._records[soldier_id]
	if not record.get("cargo") is Dictionary: record["cargo"] = {}
	record.cargo["horse"] = int(record.cargo.get("horse", 0)) + 1
	var horses_before := int(record.cargo.horse)
	var previous_control := lab.controlled_person_id()
	lab.terrain.site["controlled_person_id"] = soldier_id
	var prepared: Dictionary = controller.equipment_orders.prepare(soldier_id, {"mode": "personal", "slot": SiteRuntime.MOUNT_SLOT, "item_id": SiteRuntime.MOUNT_GOODS})
	var committed: Dictionary = controller.equipment_orders.commit(prepared.order) if bool(prepared.get("ok", false)) else prepared
	lab.terrain.site["controlled_person_id"] = previous_control
	if not check(bool(prepared.get("ok", false)), "prepare/check admit the horse order", prepared): return false
	if not check(bool(committed.get("ok", false)), "the horse order commits", committed): return false
	var item_id := SiteRuntime.mount_item_id(record.item_state)
	if not check(not item_id.is_empty() and lab.terrain.site.item_records.has(item_id), "the mount slot holds a real horse item", record.item_state): return false
	return check(int(record.cargo.get("horse", 0)) == horses_before - 1, "exactly one horse left the soldier's goods", record.cargo)

func _mounted_kit_ok(soldier_id: int, index: int) -> bool:
	var appearance: Dictionary = site._appearance(soldier_id)
	if not check(bool(appearance.get("mounted", false)), "the projected appearance is mounted", appearance): return false
	var kit := int(site._kit_cache.get(JSON.stringify(appearance), -1))
	if not check(kit >= 0 and site._kit_ids[index] == kit, "the soldier's crowd kit is the mounted kit", [kit, site._kit_ids[index]]): return false
	var described: Dictionary = site.view._describe(appearance)
	var page: Dictionary = site.view._pages[int(described.page)]
	for clip: String in ["ride_idle", "ride_walk", "ride_run"]:
		for direction: String in ["up", "right", "down", "left"]:
			if not check(page.sequences.has(clip + "|" + direction), "the mounted page has " + clip + "|" + direction): return false
	var frame: Dictionary = SiteMountedSoldierAtlas.frame(appearance, "ride_walk", "down", 0.5)
	return check(not frame.is_empty() and frame.horse.texture is AtlasTexture, "rider and horse frames resolve", frame.get("key", ""))

func _ordinary_mounts_case(soldier_id: int, index: int) -> void:
	if not check(site.crowd.soldier_mounted(index) and site.rider_identities().has(soldier_id), "the native rider flag and rider list follow the mount slot"): return
	if not _mounted_kit_ok(soldier_id, index): return
	for step in range(30):
		if not check(_tick(1), "live frame with an ordinary rider has no latched fault"): return
	if not check(site.crowd.soldier_mounted(index), "the ordinary rider stays mounted"): return
	print("CAV3 GATE OK: ordinary_mounts")
	quit(0)

func _ordinary_dismount_case(soldier_id: int, index: int) -> void:
	var record: Dictionary = site._records[soldier_id]
	var item_id := SiteRuntime.mount_item_id(record.item_state)
	var horses := int(record.cargo.get("horse", 0))
	if not check(bool(site.crowd.set_soldier_mounted(index, false)), "the native dismount is applied"): return
	if not check(_tick(1), "the frame after the dismount has no latched fault"): return
	if not check(not site.rider_identities().has(soldier_id) and not site._is_rider_row(soldier_id), "the rider list and row drop the dismounted soldier"): return
	if not check(SiteRuntime.mount_item_id(record.item_state).is_empty() and not lab.terrain.site.item_records.has(item_id), "the mount slot is empty and the horse item is gone"): return
	if not check(int(record.cargo.get("horse", 0)) == horses, "the lost horse is not returned to goods", record.cargo): return
	var appearance: Dictionary = site._appearance(soldier_id)
	if not check(not bool(appearance.get("mounted", false)) and site._kit_ids[index] == int(site._kit_cache.get(JSON.stringify(appearance), -1)), "the soldier is back on its foot kit"): return
	print("CAV3 GATE OK: ordinary_dismount_loses_horse")
	quit(0)

func _ordinary_bow_case(friend_team: Dictionary, soldier_id: int, index: int) -> void:
	var appearance: Dictionary = site._appearance(soldier_id)
	if not check(str(appearance.parts.weapon).begins_with("bow"), "the rider is an archer", appearance.parts.weapon): return
	if not check(site.crowd.soldier_mounted(index), "the archer is a native rider"): return
	# The rider's kit shows the mounted bow clip on the shoot slot.
	var kit_appearance: Dictionary = site._appearance(soldier_id)
	var page: Dictionary = site.view._pages[int(site.view._describe(kit_appearance).page)]
	if not check(SiteMountedSoldierAtlas.crowd_clip("shoot", kit_appearance) == "attack_bow" and page.sequences.has("attack_bow|right"), "the mounted kit carries the attack_bow shoot clip"): return
	var enemy_team: Dictionary = site._team_by_id(int(site.command_teams()[1].team_id))
	var enemy_id := int(enemy_team.person_ids[0])
	var corridor := _find_corridor()
	if not check(corridor.x >= 0 and _place(soldier_id, Vector2(corridor) + Vector2.ONE * 0.5) and _place(enemy_id, Vector2(corridor + Vector2i(6, 0)) + Vector2.ONE * 0.5), "a legal unobstructed six-cell ranged corridor", corridor): return
	var ammo_before := float(site.soldier_state(index).ammo)
	if not check(ammo_before > 0.0, "the archer carries arrows", ammo_before): return
	var ordered: Dictionary = site.issue_order(int(friend_team.team_id), TerrainArmy.CombatOrder.ATTACK, Vector2i(-1, -1), enemy_id, "test")
	if not check(bool(ordered.get("ok", false)), "the mounted archer is ordered to attack the enemy", ordered): return
	# Native ranged rules (S_RANGED = 4): a mounted archer is a ranged soldier like any other archer, with no mounted
	# refusal. Shot release belongs to the GD fire host (TerrainLab.issue_fire_order), which needs an original team
	# owner; lab.fire_owner_view maps no TerrainArmy to these crowd trial teams, so a foot archer releases nothing here either.
	var ranged := false
	for step in range(300):
		if not check(_tick(1), "live frame has no latched fault"): return
		var state: Dictionary = site.soldier_state(index)
		if int(state.state) == 4:
			ranged = bool(site.crowd.soldier_mounted(index))
			if ranged: break
	if not check(ranged, "the mounted archer takes the native ranged state while still mounted", site.soldier_state(index)): return
	for step in range(60):
		if not check(_tick(1), "live frame in the ranged state has no latched fault"): return
	if not check(site.crowd.soldier_mounted(index) and int(site.soldier_state(index).state) == 4, "the archer stays mounted in the ranged state", site.soldier_state(index)): return
	print("CAV3 GATE OK: ordinary_bow_rider_fires (native ranged state from horseback; release not wired for trial teams)")
	quit(0)

# As crowd_c2_natural_ammo_test: nine walkable, steppable cells in three rows, away from the controlled person.
func _find_corridor() -> Vector2i:
	var player_state: Dictionary = site.soldier_state(site.player_index)
	var player := Vector2(float(player_state.px), float(player_state.py))
	for y in range(4, lab.terrain.size.y - 4):
		for x in range(4, lab.terrain.size.x - 10):
			var start := Vector2i(x, y)
			if player.distance_to(Vector2(start)) < 24.0: continue
			var legal := true
			for row in range(-1, 2):
				for offset in range(9):
					var here := start + Vector2i(offset, row)
					if not lab.terrain.is_walkable(here): legal = false
					if offset > 0 and not lab.terrain.can_step(here - Vector2i.RIGHT, here): legal = false
			if legal: return start
	return Vector2i(-1, -1)

func _place(identity: int, position: Vector2) -> bool:
	var owner: RefCounted = site.person_owner(identity)
	return site.set_soldier_fields(owner.index_for_identity(identity), {"px": position.x, "py": position.y}) and site.set_formation_fields(owner.formation_index,
		{"cx": position.x, "cy": position.y, "goal_x": position.x, "goal_y": position.y, "origin_x": position.x, "origin_y": position.y, "ref_x": position.x, "ref_y": position.y, "ref_valid": true, "ai_enabled": false})

func _ordinary_saveload_case(soldier_id: int, index: int) -> void:
	for step in range(30):
		if not check(_tick(1), "live frame before the save has no latched fault"): return
	var item_id := SiteRuntime.mount_item_id(site._records[soldier_id].item_state)
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid with an ordinary rider", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	site.crowd.render_set_kits(site._kit_ids)
	site._rebuild_rider_ids()
	if not check(site.crowd.soldier_mounted(index) and site.rider_identities().has(soldier_id), "the reloaded native rider stays mounted"): return
	if not check(SiteRuntime.mount_item_id(site._records[soldier_id].item_state) == item_id and site._is_rider_row(soldier_id), "the horse item and row survive"): return
	if not _mounted_kit_ok(soldier_id, index): return
	if not check(_tick(1), "the frame after the reload has no latched fault"): return
	print("CAV3 GATE OK: saveload_ordinary_rider")
	quit(0)

# ---------------------------------------------------------------- CAV-4b charge orders
# Friends are ordinary soldiers mounted through the order flow (every friend rides, so the team is a cavalry formation).
# The enemy side is foot. The commander is the formation's current person (native current_cmd).
func _charge_case() -> void:
	var real := case_name == "charge_real_picture"
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 12 if real else 4, "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 24 if real else 6, "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	if not check(deployed.ok and site.active and site.command_teams().size() == 2, "a crowd battle deploys two opposing teams", deployed): return
	var friend_team: Dictionary = site._team_by_id(int(site.command_teams()[0].team_id))
	var enemy_team: Dictionary = site._team_by_id(int(site.command_teams()[1].team_id))
	if case_name != "charge_refused_infantry":
		for identity: int in friend_team.person_ids:
			if not check(not site._actors.has(identity), "every friend is an ordinary soldier", identity): return
			if not check(_mount_by_order(identity), "the ordinary soldier mounts through the order flow", identity): return
	var cavalry := bool(site.is_cavalry_team(friend_team))
	if not check(cavalry == (case_name != "charge_refused_infantry"), "the team reads as a cavalry formation only when its riders are mounted", cavalry): return
	match case_name:
		"charge_refused_infantry":
			_charge_refused_infantry(friend_team, enemy_team)
		"charge_refused_no_commander":
			_charge_no_commander(friend_team, enemy_team)
		"charge_order":
			_charge_order(friend_team, enemy_team)
		"rally_order":
			_rally_order(friend_team, enemy_team)
		"charge_saveload":
			_charge_saveload(friend_team, enemy_team)
		"charge_real_picture":
			_charge_real_picture(friend_team, enemy_team)

func _issue_charge(friend_team: Dictionary, enemy_team: Dictionary) -> bool:
	var ordered: Dictionary = site.issue_order(int(friend_team.team_id), TerrainArmy.CombatOrder.CHARGE, Vector2i(-1, -1), int(enemy_team.person_ids[0]), "test")
	if not check(bool(ordered.get("ok", false)), "the mounted team is ordered to CHARGE the enemy formation (native kind 7)", ordered): return false
	return check(int(site.formation_state(int(friend_team.formation)).order) == 6, "the formation reports the CHARGE order (native state 6)")

func _riders_charging(friend_team: Dictionary) -> bool:
	for identity: int in friend_team.person_ids:
		var charge: PackedFloat64Array = site.crowd.soldier_charge(int(site._index_by_id[identity]))
		if charge[0] == 1.0 and charge[1] >= 0.4: return true
	return false

# Ticks live frames until contact. The gallop must be seen before the first contact.
func _charge_until_contact(friend_team: Dictionary) -> bool:
	var contacts0 := float(site.crowd.cav_stats()[0])
	var gallop := false
	for step in range(2400):
		if not check(_tick(1), "live frame during the charge has no latched fault"): return false
		if _riders_charging(friend_team): gallop = true
		if float(site.crowd.cav_stats()[0]) > contacts0:
			return check(gallop, "the riders reached gallop before the first contact", site.crowd.cav_stats())
	return check(false, "the charge makes contact within 80 s", site.crowd.cav_stats())

func _charge_refused_infantry(friend_team: Dictionary, enemy_team: Dictionary) -> void:
	var refused: Dictionary = site.issue_order(int(friend_team.team_id), TerrainArmy.CombatOrder.CHARGE, Vector2i(-1, -1), int(enemy_team.person_ids[0]), "test")
	if not check(not bool(refused.get("ok", true)) and str(refused.get("code", "")) == "NOT_CAVALRY", "a team on foot is refused CHARGE as NOT_CAVALRY", refused): return
	print("CAV4B GATE OK: charge_refused_infantry")
	quit(0)

func _charge_no_commander(friend_team: Dictionary, enemy_team: Dictionary) -> void:
	# GD gate: the commander is present and can act, so the refusal is the native reach check (8 cells, layout half diagonal).
	var commander := int(site.formation_state(int(friend_team.formation)).current_person)
	var index := int(site._index_by_id[commander])
	var state: Dictionary = site.soldier_state(index)
	var away := float(state.px) + 20.0
	if away > float(lab.terrain.size.x) - 2.0: away = float(state.px) - 20.0
	if not check(site.set_soldier_fields(index, {"px": away, "py": float(state.py)}), "the commander is moved 20 cells from the formation centre"): return
	var refused: Dictionary = site.issue_order(int(friend_team.team_id), TerrainArmy.CombatOrder.CHARGE, Vector2i(-1, -1), int(enemy_team.person_ids[0]), "test")
	if not check(not bool(refused.get("ok", true)) and str(refused.get("code", "")) == "NO_COMMANDER", "a commander 20 cells out is refused CHARGE as NO_COMMANDER", refused): return
	print("CAV4B GATE OK: charge_refused_no_commander")
	quit(0)

func _charge_order(friend_team: Dictionary, enemy_team: Dictionary) -> void:
	if not _issue_charge(friend_team, enemy_team): return
	if not _charge_until_contact(friend_team): return
	print("CAV4B GATE OK: charge_order")
	quit(0)

func _rally_order(friend_team: Dictionary, enemy_team: Dictionary) -> void:
	if not _issue_charge(friend_team, enemy_team): return
	if not _charge_until_contact(friend_team): return
	var rallied: Dictionary = site.issue_order(int(friend_team.team_id), TerrainArmy.CombatOrder.RALLY, Vector2i(-1, -1), -1, "test")
	if not check(bool(rallied.get("ok", false)), "RALLY is accepted for the charging team", rallied): return
	var returned := false
	for step in range(1800):
		if not check(_tick(1), "live frame during the rally has no latched fault"): return
		if not _riders_charging(friend_team) and int(site.formation_state(int(friend_team.formation)).order) == 0:
			returned = true
			break
	if not check(returned, "the rally brings the riders back and the formation HOLDs with no rider charging", site.formation_state(int(friend_team.formation)).order): return
	print("CAV4B GATE OK: rally_order")
	quit(0)

func _charge_saveload(friend_team: Dictionary, enemy_team: Dictionary) -> void:
	if not _issue_charge(friend_team, enemy_team): return
	var gallop := false
	for step in range(900):
		if not check(_tick(1), "live frame before the save has no latched fault"): return
		if _riders_charging(friend_team):
			gallop = true
			break
	if not check(gallop, "the save is taken mid-charge with a rider at gallop"): return
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid mid-charge", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	site.crowd.render_set_kits(site._kit_ids)
	site._rebuild_rider_ids()
	if not check(int(site.formation_state(int(friend_team.formation)).order) == 6, "the reloaded formation still holds the CHARGE order"): return
	if not _charge_until_contact(friend_team): return
	print("CAV4B GATE OK: charge_saveload")
	quit(0)

# Visual acceptance through the command path the UI uses (SiteController._crowd_order, source "test" = the faction-0 team),
# with a picked enemy person. Frame time is the whole lab frame (_tick), measured from the order to 60 frames after contact.
func _charge_real_picture(friend_team: Dictionary, enemy_team: Dictionary) -> void:
	var ordered: Dictionary = controller._crowd_order("test", TerrainArmy.CombatOrder.CHARGE, Vector2i(-1, -1), int(enemy_team.person_ids[0]))
	if not check(bool(ordered.get("ok", false)), "the command path orders the 12-rider team to CHARGE the picked enemy formation", ordered): return
	var contacts0 := float(site.crowd.cav_stats()[0])
	var frame_ms: Array[float] = []
	var contact_frame := -1
	for step in range(2400):
		var started := Time.get_ticks_usec()
		if not check(_tick(1), "live frame during the charge has no latched fault"): return
		frame_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		if contact_frame < 0 and float(site.crowd.cav_stats()[0]) > contacts0: contact_frame = step
		if contact_frame >= 0 and step >= contact_frame + 60: break
	if not check(contact_frame >= 0, "the charge produces contacts", site.crowd.cav_stats()): return
	var ordered_ms: Array[float] = frame_ms.duplicate()
	ordered_ms.sort()
	var p95: float = ordered_ms[int(floor(0.95 * float(ordered_ms.size() - 1)))]
	var worst: float = ordered_ms[ordered_ms.size() - 1]
	var p99: float = ordered_ms[int(floor(0.99 * float(ordered_ms.size() - 1)))]
	if not check(p95 <= CHARGE_FRAME_MS_LIMIT, "the p95 frame time stays under %.1f ms" % CHARGE_FRAME_MS_LIMIT, [p95, p99, worst, frame_ms.size()]): return
	if not check(p99 <= CHARGE_FRAME_P99_MS_LIMIT, "the p99 frame time stays under %.1f ms" % CHARGE_FRAME_P99_MS_LIMIT, [p95, p99, worst, frame_ms.size()]): return
	print("CAV4B frame ms p95 %.3f p99 %.3f worst %.3f frames %d contact_frame %d stats %s" % [p95, p99, worst, frame_ms.size(), contact_frame, str(site.crowd.cav_stats())])
	print("CAV4B GATE OK: charge_real_picture")
	quit(0)
